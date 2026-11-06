import AppKit
import UniformTypeIdentifiers

@MainActor
extension NativeWorkbench {
    func installMenus() {
        let bar = NSMenu(), application = NSMenuItem(), appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于 EVA Workbench", action: #selector(showAbout), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 EVA Workbench", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "退出 EVA Workbench", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        application.submenu = appMenu; bar.addItem(application)
        let file = NSMenuItem(), fileMenu = NSMenu(title: "文件")
        fileMenu.addItem(withTitle: "新对话", action: #selector(newConversation), keyEquivalent: "n")
        fileMenu.addItem(withTitle: "添加项目…", action: #selector(addProject), keyEquivalent: "o")
        fileMenu.addItem(withTitle: "同步本机会话", action: #selector(syncHistory), keyEquivalent: "r")
        file.submenu = fileMenu; bar.addItem(file)
        let edit = NSMenuItem(), editMenu = NSMenu(title: "编辑")
        for (name, action, key) in [("撤销", #selector(UndoManager.undo), "z"), ("剪切", #selector(NSText.cut(_:)), "x"), ("复制", #selector(NSText.copy(_:)), "c"), ("粘贴", #selector(NSText.paste(_:)), "v"), ("全选", #selector(NSText.selectAll(_:)), "a")] { editMenu.addItem(withTitle: name, action: action, keyEquivalent: key) }
        edit.submenu = editMenu; bar.addItem(edit)
        let view = NSMenuItem(), viewMenu = NSMenu(title: "显示")
        viewMenu.addItem(withTitle: "工具面板", action: #selector(toggleInspector), keyEquivalent: "i")
        viewMenu.addItem(withTitle: "重播启动序列", action: #selector(replayStartup), keyEquivalent: "")
        let introOnLaunch = viewMenu.addItem(withTitle: "启动时播放开场", action: #selector(toggleIntroOnLaunch(_:)), keyEquivalent: "")
        introOnLaunch.state = (UserDefaults.standard.object(forKey: "native.introEnabled") as? Bool ?? true) ? .on : .off
        let introSound = viewMenu.addItem(withTitle: "开场日文播报", action: #selector(toggleIntroSound(_:)), keyEquivalent: "")
        introSound.state = (UserDefaults.standard.object(forKey: "native.introSound") as? Bool ?? true) ? .on : .off
        view.submenu = viewMenu; bar.addItem(view)
        NSApp.mainMenu = bar
    }
    @objc func showAbout() {
        let alert = NSAlert(); alert.messageText = "EVA Workbench 0.9.1"
        alert.informativeText = "Swift / AppKit 原生界面\nCodex 与 Claude Code 双后端\n本机历史按需读取，继续时创建独立分支。\n基于 EVA Codex Workbench（MIT）。"
        alert.beginSheetModal(for: window)
    }
    func saveDraft() { drafts[selectedThreadID] = (composer.string, draftAttachments) }
    func restoreDraft() {
        draftEpoch += 1
        let draft = drafts[selectedThreadID]
        composer.string = draft?.0 ?? ""; composer.needsDisplay = true
        draftAttachments = draft?.1 ?? []; renderAttachments()
    }
    func chooseThread(_ thread: JSON) {
        let id = string(thread["id"])
        guard id != selectedThreadID else { return }
        saveDraft(); selectedThreadID = id; workingProjectID = string(thread["projectId"])
        preferredProvider = string(thread["provider"]) == "claude" ? "claude" : "codex"
        selectedModel = string(thread["model"]); selectedEffort = string(thread["effort"]); catalogSignature = ""
        mode = ["workspace-write", "full-access"].contains(string(thread["mode"])) ? string(thread["mode"]) : "read-only"; fullAccessAcknowledged = mode == "full-access"
        UserDefaults.standard.set(id, forKey: "native.selectedThread"); UserDefaults.standard.set(workingProjectID, forKey: "native.selectedProject")
        restoreDraft(); notice(""); applyState(state)
    }
    func useThread(_ thread: JSON) {
        let id = string(thread["id"])
        if !threads.contains(where: { string($0["id"]) == id }) { state["threads"] = threads + [thread] }
        chooseThread(thread)
    }
    @objc func newConversation() {
        guard !sending else { return }
        saveDraft(); selectedThreadID = ""; selectedModel = ""; selectedEffort = ""; mode = "read-only"; fullAccessAcknowledged = false; catalogSignature = ""
        UserDefaults.standard.removeObject(forKey: "native.selectedThread")
        restoreDraft(); notice(""); applyState(state); window.makeFirstResponder(composer)
    }
    @objc func projectChanged() {
        filterProjectID = projectPicker.selectedItem?.representedObject as? String ?? ""
        if !filterProjectID.isEmpty { workingProjectID = filterProjectID; newConversation() }
        updateSidebar()
    }
    @objc func addProject() {
        let panel = NSOpenPanel(); panel.title = "选择项目文件夹"; panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            self.perform("/api/project", body: ["path": url.path]) { value in
                let project = object(value), id = string(project["id"])
                if !self.projects.contains(where: { string($0["id"]) == id }) { self.state["projects"] = self.projects + [project] }
                self.workingProjectID = id; self.filterProjectID = id; self.projectListSignature = ""; self.newConversation()
            }
        }
    }
    @objc func toggleArchive() { showArchived.toggle(); updateSidebar() }
    @objc func syncHistory() { perform("/api/history/sync", body: [:]) }
    func loadHistory(_ id: String, older: Bool = false) {
        guard !loadingHistory.contains(id) else { return }; loadingHistory.insert(id); updateControls()
        api.request("/api/history/read", body: ["threadId": id, "older": older], timeout: 90) { [weak self] result in
            guard let self else { return }; self.loadingHistory.remove(id)
            switch result {
            case .success(let value):
                let thread = object(object(value)["thread"])
                if !thread.isEmpty { self.state["threads"] = self.threads.map { string($0["id"]) == id ? thread : $0 }; self.applyState(self.state) }
            case .failure(let error): self.notice(error.localizedDescription); self.updateControls()
            }
        }
    }
    @objc func earlierHistory() { loadHistory(selectedThreadID, older: true) }
    @objc func continueHistory() {
        let id = selectedThreadID
        guard !id.isEmpty, !sending else { return }; sending = true; updateControls()
        api.request("/api/history/continue", body: ["threadId": id, "mode": mode, "model": selectedModel, "effort": selectedEffort, "confirmFullAccess": fullAccessAcknowledged], timeout: 90) { [weak self] result in
            guard let self else { return }; self.sending = false
            switch result { case .success(let value): self.useThread(object(value)); case .failure(let error): self.notice(error.localizedDescription) }
            self.updateControls()
        }
    }
    @objc func openContinuation() {
        // Follow the chain to the newest conversation (A → B → C).
        var current = selectedThread, seen = Set<String>()
        while let t = current, let id = object(t["continuedIn"])["threadId"] as? String, !seen.contains(id), let next = threads.first(where: { string($0["id"]) == id }) { seen.insert(id); current = next }
        if let t = current, string(t["id"]) != selectedThreadID { chooseThread(t) } else { notice("找不到切换后的对话，可在侧栏中查看。") }
    }
    @objc func unmergeConversation() {
        guard let t = selectedThread else { return }
        perform("/api/thread/merge", body: ["threadId": string(t["id"]), "intoThreadId": NSNull()]) { [weak self] value in self?.useThread(object(object(value)["thread"])) }
    }
    @objc func undoTransfer() {
        guard let t = selectedThread, !sending else { return }
        sending = true; updateControls()
        api.request("/api/thread/transfer/undo", body: ["threadId": string(t["id"])], timeout: 60) { [weak self] result in
            guard let self else { return }; self.sending = false
            switch result { case .success(let value): self.notice(""); self.useThread(object(object(value)["thread"])); case .failure(let error): self.notice(error.localizedDescription) }
            self.updateControls()
        }
    }
    @objc func openOriginal() {
        guard let t = selectedThread else { return }; let source = object(t["forkedFrom"])
        if let id = object(t["transfer"])["sourceThreadId"] as? String, let original = threads.first(where: { string($0["id"]) == id }) { chooseThread(original); return }
        if let original = threads.first(where: { string(object($0["localHistory"])["id"]) == string(source["id"]) && string(object($0["localHistory"])["provider"]) == string(source["provider"]) }) { chooseThread(original) }
    }
    @objc func providerChanged() {
        if selectedThread != nil {
            let target = providerPicker.selectedSegment == 1 ? "claude" : "codex"
            providerPicker.selectedSegment = provider == "claude" ? 1 : 0
            if target != provider { startTransfer(recent: false) }
            return
        }
        preferredProvider = providerPicker.selectedSegment == 1 ? "claude" : "codex"
        UserDefaults.standard.set(preferredProvider, forKey: "native.provider"); selectedModel = ""; selectedEffort = ""; mode = "read-only"; fullAccessAcknowledged = false; catalogSignature = ""; updateControls(); updateUsageWidget()
    }
    @objc func modelChanged() { selectedModel = modelPicker.selectedItem?.representedObject as? String ?? ""; selectedEffort = ""; rebuildEfforts() }
    @objc func effortChanged() { selectedEffort = effortPicker.selectedItem?.representedObject as? String ?? "" }
    @objc func modeChanged() {
        let requested = modePicker.selectedItem?.representedObject as? String ?? "read-only"
        guard requested != mode else { return }
        if requested != "full-access" { applyPermissionMode(requested, confirmed: false); return }
        let alert = NSAlert(); alert.messageText = "为此会话启用完全访问？"
        alert.informativeText = "Claude Code 将以当前系统用户权限读取、修改本机文件并执行命令，普通工具不再逐次确认，范围不限于所选项目。\n\nmacOS 系统权限继续生效；官方仍可能要求确认少数特殊操作。你可以在任务停止后随时切回只读。"
        alert.addButton(withTitle: "取消"); alert.addButton(withTitle: "启用完全访问")
        alert.beginSheetModal(for: window) { [weak self] result in guard let self else { return }; if result == .alertSecondButtonReturn { self.applyPermissionMode(requested, confirmed: true) } else { self.updateControls() } }
    }
    @objc func suggestion(_ sender: NSButton) {
        composer.string = ["请分析这个项目的结构，说明主要模块和运行方法。", "请审查当前项目，优先找出真实的缺陷和风险。", "请先了解项目，并帮我制定实现方案。具体需求是："][min(sender.tag, 2)]
        composer.needsDisplay = true; window.makeFirstResponder(composer)
    }
    @objc func sendMessage() {
        guard sendButton.isEnabled, !sending else { return }
        let text = composer.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !draftAttachments.isEmpty else { return }
        guard currentProject != nil else { notice("请先添加或选择一个项目文件夹。"); addProject(); return }
        let epoch = draftEpoch, initialID = selectedThreadID, attachments = draftAttachments, files = draftAttachments.map { string($0["id"]) }, model = selectedModel, effort = selectedEffort
        sending = true; notice(""); updateControls()
        let submit: (String) -> Void = { [weak self] id in
            guard let self else { return }
            self.api.request("/api/send", body: ["threadId": id, "text": text, "attachments": files, "model": model, "effort": effort], timeout: 90) { [weak self] result in
                guard let self else { return }; self.sending = false
                switch result {
                case .success:
                    for key in [initialID, id] where self.drafts[key]?.0.trimmingCharacters(in: .whitespacesAndNewlines) == text { self.drafts.removeValue(forKey: key) }
                    if self.selectedThreadID == id && self.composer.string.trimmingCharacters(in: .whitespacesAndNewlines) == text { self.composer.string = ""; self.composer.needsDisplay = true; self.draftAttachments.removeAll(); self.renderAttachments() }
                case .failure(let error): self.notice(error.localizedDescription)
                }
                self.updateControls()
            }
        }
        if !initialID.isEmpty { submit(initialID); return }
        api.request("/api/thread", body: ["provider": provider, "projectId": workingProjectID, "mode": mode, "model": model, "effort": effort, "confirmFullAccess": fullAccessAcknowledged], timeout: 90) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let value):
                let t = object(value)
                if self.draftEpoch == epoch { self.useThread(t); self.composer.string = text; self.draftAttachments = attachments; self.renderAttachments() }
                submit(string(t["id"]))
            case .failure(let error): self.sending = false; self.notice(error.localizedDescription); self.updateControls()
            }
        }
    }
    @objc func stopMessage() { perform("/api/cancel", body: ["threadId": selectedThreadID]) }
    @objc func retryMessage() {
        guard let message = objects(selectedThread?["messages"]).last(where: { string($0["role"]) == "user" }) else { return }
        composer.string = string(message["text"]); draftAttachments = objects(message["attachments"]); renderAttachments(); composer.needsDisplay = true
        window.makeFirstResponder(composer)
    }
    @objc func renameConversation() {
        let id = selectedThreadID, alert = NSAlert(); alert.messageText = "重命名对话"
        let input = NSTextField(string: string(selectedThread?["title"])); input.frame = NSRect(x: 0, y: 0, width: 350, height: 26); alert.accessoryView = input
        alert.addButton(withTitle: "保存"); alert.addButton(withTitle: "取消")
        alert.beginSheetModal(for: window) { [weak self] response in if response == .alertFirstButtonReturn { self?.perform("/api/thread/rename", body: ["threadId": id, "title": input.stringValue]) } }
    }
    @objc func archiveConversation() { perform("/api/thread/archive", body: ["threadId": selectedThreadID, "archived": !flag(selectedThread?["archived"])]) }
    @objc func accountAction() {
        let p = providerState, selectedProvider = provider
        let route = string(p["connection"]) != "connected" ? "/api/reconnect" : flag(object(p["account"])["signedIn"]) ? "/api/refresh-account" : "/api/login"
        perform(route, body: ["provider": selectedProvider]) { value in
            if selectedProvider == "codex", let url = URL(string: string(object(value)["authUrl"])), url.scheme == "https", ["auth.openai.com", "auth0.openai.com", "chatgpt.com"].contains(url.host ?? "") { NSWorkspace.shared.open(url) }
            else if selectedProvider == "claude" && route == "/api/login" { self.notice("已打开 Claude Code 官方登录终端，完成后点击“刷新”。") }
        }
    }
    @objc func addImages() {
        let panel = NSOpenPanel(); panel.title = "添加文件"; panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowsMultipleSelection = true
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK else { return }
            self.uploadFiles(panel.urls)
        }
    }
    func renderAttachments() {
        for view in attachmentBar.arrangedSubviews { attachmentBar.removeArrangedSubview(view); view.removeFromSuperview() }
        for (index, file) in draftAttachments.enumerated() {
            let button = EVATheme.button((string(file["mime"]).hasPrefix("image/") ? "▧ " : "▤ ") + string(file["name"]), target: self, action: #selector(previewDraftFile)); button.identifier = NSUserInterfaceItemIdentifier(string(file["id"])); button.cell?.lineBreakMode = .byTruncatingMiddle; button.widthAnchor.constraint(lessThanOrEqualToConstant: 350).isActive = true
            let label = EVATheme.label(string(file["readability"]) + (flag(file["truncated"]) ? " · 部分文字" : ""), size: 10, color: EVATheme.muted); label.lineBreakMode = .byTruncatingTail; label.toolTip = string(file["warning"])
            let remove = EVATheme.button("×", target: self, action: #selector(removeImage)); remove.tag = index; remove.toolTip = "移除此附件"
            let row = EVATheme.horizontal([button, label, EVATheme.spacer(), remove], spacing: 5); attachmentBar.addArrangedSubview(row); row.widthAnchor.constraint(equalTo: attachmentBar.widthAnchor).isActive = true
        }
        attachmentScroll.isHidden = draftAttachments.isEmpty; attachmentHeight?.constant = min(104, CGFloat(draftAttachments.count) * 28)
    }
    @objc func removeImage(_ sender: NSButton) { guard draftAttachments.indices.contains(sender.tag) else { return }; draftAttachments.remove(at: sender.tag); renderAttachments(); updateControls() }
    func openImage(_ file: JSON) {
        if !string(file["mime"]).hasPrefix("image/") { previewAttachment(file); return }
        api.download(string(file["url"])) { [weak self] data in
            guard let self, let data, let image = NSImage(data: data) else { return }
            let preview = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 600), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            preview.title = string(file["name"]); preview.isReleasedWhenClosed = false; preview.delegate = self
            preview.appearance = nil; preview.backgroundColor = EVATheme.background
            let view = NSImageView(); view.image = image; view.imageScaling = .scaleProportionallyUpOrDown; preview.contentView = view; preview.center(); preview.makeKeyAndOrderFront(nil); self.imageWindows.append(preview)
        }
    }
    func presentApprovalIfNeeded() {
        guard shownApproval.isEmpty, introView == nil, window.attachedSheet == nil, let approval = objects(state["approvals"]).first else { return }
        let id = string(approval["id"]), params = object(approval["params"]), questions = objects(params["questions"])
        shownApproval = id; approvalFields.removeAll()
        let alert = NSAlert(); alert.messageText = questions.isEmpty ? "确认助手的执行请求" : "助手需要你的回答"
        alert.informativeText = string(approval["provider"]) == "claude" ? "Claude Code · 仅对这一次请求生效" : "Codex · 请核对以下操作"
        let content = EVATheme.vertical([], spacing: 10)
        let description = questions.isEmpty ? pretty(params) : ""
        if !description.isEmpty {
            let text = NSTextView(); text.isEditable = false; text.isSelectable = true; text.font = .monospacedSystemFont(ofSize: 11, weight: .regular); text.string = description
            let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 520, height: 220)); scroll.documentView = text; scroll.hasVerticalScroller = true
            content.addArrangedSubview(scroll); scroll.widthAnchor.constraint(equalToConstant: 520).isActive = true; scroll.heightAnchor.constraint(equalToConstant: 220).isActive = true
        }
        for q in questions {
            let label = NSTextField(wrappingLabelWithString: string(q["question"]) + "\n" + objects(q["options"]).map { string($0["label"]) + "：" + string($0["description"]) }.joined(separator: "\n"))
            content.addArrangedSubview(label); label.widthAnchor.constraint(equalToConstant: 520).isActive = true
            let input = NSTextField(); input.placeholderString = "请输入你的选择或回答"; approvalFields[string(q["id"])] = input; content.addArrangedSubview(input); input.widthAnchor.constraint(equalToConstant: 520).isActive = true
        }
        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: questions.isEmpty ? 220 : CGFloat(questions.count * 110)))
        accessory.addSubview(content); content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([content.leadingAnchor.constraint(equalTo: accessory.leadingAnchor), content.trailingAnchor.constraint(equalTo: accessory.trailingAnchor), content.topAnchor.constraint(equalTo: accessory.topAnchor), content.bottomAnchor.constraint(equalTo: accessory.bottomAnchor)])
        alert.accessoryView = accessory; alert.window.appearance = nil; alert.layout()
        alert.addButton(withTitle: questions.isEmpty ? "允许本次" : "提交回答"); alert.addButton(withTitle: questions.isEmpty ? "拒绝" : "暂不回答")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            let accept = response == .alertFirstButtonReturn, answers = self.approvalFields.mapValues { $0.stringValue }
            self.shownApproval = ""
            if !questions.isEmpty && (!accept || answers.values.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })) { self.notice("请求仍在等待完整回答。可停止任务取消请求。"); return }
            self.api.request("/api/approval", body: ["id": id, "accept": accept, "answers": answers]) { result in
                if case .failure(let error) = result { self.notice(error.localizedDescription) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.presentApprovalIfNeeded() }
            }
        }
    }
    @objc func replayStartup() { showStartupSequence(force: true) }
    // Full-window native port of the web boot sequence; holds at 99.2 % until the pilot confirms.
    func showStartupSequence(force: Bool = false) {
        guard introView == nil, let root = window.contentView else { return }
        if !force && (UserDefaults.standard.object(forKey: "native.introEnabled") as? Bool ?? true) == false { return }
        if !force && NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { return }
        let intro = IntroView(frame: root.bounds); intro.autoresizingMask = [.width, .height]
        intro.isConnected = { [weak self] in string(self?.state["connection"]) == "connected" }
        intro.onFinish = { [weak self] in guard let self else { return }; self.introView = nil; self.window.makeFirstResponder(self.composer); self.presentApprovalIfNeeded() }
        root.addSubview(intro, positioned: .above, relativeTo: nil); introView = intro; intro.start(interactive: true)
    }
    @objc func toggleIntroOnLaunch(_ sender: NSMenuItem) {
        let enabled = !(UserDefaults.standard.object(forKey: "native.introEnabled") as? Bool ?? true)
        UserDefaults.standard.set(enabled, forKey: "native.introEnabled"); sender.state = enabled ? .on : .off
    }
    @objc func toggleIntroSound(_ sender: NSMenuItem) {
        let enabled = !(UserDefaults.standard.object(forKey: "native.introSound") as? Bool ?? true)
        UserDefaults.standard.set(enabled, forKey: "native.introSound"); sender.state = enabled ? .on : .off
    }
}
