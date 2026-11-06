import AppKit

@MainActor
extension NativeWorkbench {
    func configure(_ button: NSButton, _ title: String, _ action: Selector, primary: Bool = false) {
        button.title = title; button.target = self; button.action = action; button.bezelStyle = .rounded
        button.font = .systemFont(ofSize: 12, weight: primary ? .semibold : .regular)
        if primary { button.bezelColor = EVATheme.red; button.contentTintColor = .white }
    }
    func pinned(_ view: NSView, padding: CGFloat = 16, color: NSColor? = nil) -> NSView {
        let box = ThemedSurface(); if let color { box.surfaceColor = color } else { box.surfaceColor = .clear }
        view.translatesAutoresizingMaskIntoConstraints = false; box.addSubview(view)
        NSLayoutConstraint.activate([view.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: padding), view.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -padding), view.topAnchor.constraint(equalTo: box.topAnchor, constant: padding), view.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -padding)])
        return box
    }
    func table(_ table: NSTableView) -> NSScrollView {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main")); column.width = 220; column.resizingMask = .autoresizingMask
        table.addTableColumn(column); table.headerView = nil; table.delegate = self; table.dataSource = self
        table.backgroundColor = .clear; table.rowHeight = 53; table.intercellSpacing = NSSize(width: 0, height: 4)
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle; table.selectionHighlightStyle = .regular
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.drawsBackground = false; scroll.borderType = .noBorder
        return scroll
    }
    func buildInterface() -> NSView {
        let root = EVAFrame(); root.showGrid = false
        let sidebar = EVATheme.vertical([], spacing: 10)
        let brand = EVATheme.horizontal([EVATheme.label("02", size: 44, color: EVATheme.orange, weight: .medium), EVATheme.vertical([EVATheme.label("EVANGELION", size: 15, weight: .bold), EVATheme.label("PRIVATE WORKSTATION", size: 9, color: EVATheme.muted)], spacing: 4)])
        sidebar.addArrangedSubview(brand)
        let newButton = EVATheme.button("新对话  ＋", target: self, action: #selector(newConversation), primary: true)
        sidebar.addArrangedSubview(newButton)
        newButton.widthAnchor.constraint(equalTo: sidebar.widthAnchor).isActive = true
        let projects = EVATheme.horizontal([EVATheme.label("PROJECT / 项目", size: 10, color: EVATheme.orange), EVATheme.spacer(), EVATheme.button("＋", target: self, action: #selector(addProject))])
        sidebar.addArrangedSubview(projects); projects.widthAnchor.constraint(equalTo: sidebar.widthAnchor).isActive = true
        projectPicker.target = self; projectPicker.action = #selector(projectChanged)
        sidebar.addArrangedSubview(projectPicker); projectPicker.widthAnchor.constraint(equalTo: sidebar.widthAnchor).isActive = true
        configure(syncButton, "同步本机会话", #selector(syncHistory)); sidebar.addArrangedSubview(syncButton)
        syncLabel.maximumNumberOfLines = 2; sidebar.addArrangedSubview(syncLabel)
        configure(archiveButton, "归档", #selector(toggleArchive))
        let recent = EVATheme.horizontal([EVATheme.label("SESSIONS / 会话", size: 10, color: EVATheme.orange), EVATheme.spacer(), archiveButton])
        sidebar.addArrangedSubview(recent); recent.widthAnchor.constraint(equalTo: sidebar.widthAnchor).isActive = true
        search.placeholderString = "搜索会话标题"; search.delegate = self
        sidebar.addArrangedSubview(search); search.widthAnchor.constraint(equalTo: sidebar.widthAnchor).isActive = true
        let conversationList = table(sidebarTable); sidebar.addArrangedSubview(conversationList)
        conversationList.widthAnchor.constraint(equalTo: sidebar.widthAnchor).isActive = true
        conversationList.heightAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
        sidebar.addArrangedSubview(EVATheme.label("NATIVE / APPKIT  •  02", size: 9, color: EVATheme.orange))
        configure(accountButton, "登录", #selector(accountAction))
        let account = EVATheme.horizontal([accountLabel, EVATheme.spacer(), accountButton])
        sidebar.addArrangedSubview(account); account.widthAnchor.constraint(equalTo: sidebar.widthAnchor).isActive = true
        accountLabel.lineBreakMode = .byTruncatingTail
        let sidebarBox = pinned(sidebar, color: EVATheme.sidebar)
        sidebarBox.widthAnchor.constraint(equalToConstant: 255).isActive = true

        let center = EVATheme.vertical([], spacing: 12)
        buildUsagePopover(); configure(usageButton, "上下文 — · 5h — · 周 —", #selector(showUsage))
        themePicker.addItems(withTitles: ["跟随系统", "红黑", "红白"]); themePicker.target = self; themePicker.action = #selector(themeChanged)
        themePicker.selectItem(at: ["system", "dark", "light"].firstIndex(of: UserDefaults.standard.string(forKey: "native.theme") ?? "system") ?? 0)
        let heading = EVATheme.horizontal([EVATheme.label("EVANGELION–02", size: 17, weight: .semibold), EVATheme.spacer(), usageButton, themePicker, connectionLabel, EVATheme.button("重播", target: self, action: #selector(replayStartup)), EVATheme.button("退出", target: NSApp, action: #selector(NSApplication.terminate(_:)))])
        center.addArrangedSubview(heading); heading.widthAnchor.constraint(equalTo: center.widthAnchor).isActive = true
        let sessionHeading = EVATheme.vertical([projectLabel, titleLabel], spacing: 5)
        configure(renameButton, "重命名", #selector(renameConversation)); configure(archiveThreadButton, "归档", #selector(archiveConversation))
        configure(transferButton, "切换助手继续", #selector(transferConversation))
        transferButton.toolTip = "在当前对话里换另一助手继续：历史正文和工具摘要作为参考交给它，权限重置为只读；发送前可撤销。原助手的记录保留。"
        let contextRow = EVATheme.horizontal([sessionHeading, EVATheme.spacer(), transferButton, renameButton, archiveThreadButton, EVATheme.button("工具与文件", target: self, action: #selector(toggleInspector))])
        titleLabel.lineBreakMode = .byTruncatingTail; projectLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        projectLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.widthAnchor.constraint(lessThanOrEqualTo: sessionHeading.widthAnchor).isActive = true
        projectLabel.widthAnchor.constraint(lessThanOrEqualTo: sessionHeading.widthAnchor).isActive = true
        sessionHeading.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        center.addArrangedSubview(contextRow); contextRow.widthAnchor.constraint(equalTo: center.widthAnchor).isActive = true
        noticeLabel.isHidden = true; noticeLabel.lineBreakMode = .byTruncatingTail; center.addArrangedSubview(noticeLabel)
        noticeLabel.widthAnchor.constraint(equalTo: center.widthAnchor).isActive = true
        historyLabel.font = .systemFont(ofSize: 11); historyLabel.textColor = EVATheme.cream
        configure(historyContinue, "继续此会话", #selector(continueHistory), primary: true)
        configure(historyEarlier, "加载更早记录", #selector(earlierHistory)); configure(historyOriginal, "查看原会话", #selector(openOriginal))
        configure(historyUndo, "撤销切换", #selector(undoTransfer)); configure(historyNext, "前往当前对话", #selector(openContinuation), primary: true); configure(historyUnmerge, "取消合并", #selector(unmergeConversation))
        configure(transferPreviewButton, "预览导入转录", #selector(previewTransfer))
        historyBox.orientation = .vertical; historyBox.alignment = .leading; historyBox.spacing = 7
        historyBox.addArrangedSubview(historyLabel); historyBox.addArrangedSubview(EVATheme.horizontal([historyContinue, historyNext, historyEarlier, historyOriginal, historyUndo, historyUnmerge, transferPreviewButton]))
        historyLabel.widthAnchor.constraint(equalTo: historyBox.widthAnchor).isActive = true; historyLabel.maximumNumberOfLines = 3
        historyBox.isHidden = true; center.addArrangedSubview(historyBox); historyBox.widthAnchor.constraint(equalTo: center.widthAnchor).isActive = true

        chatScroll.hasVerticalScroller = true; chatScroll.drawsBackground = false; chatScroll.borderType = .noBorder
        chatStack.orientation = .vertical; chatStack.alignment = .leading; chatStack.spacing = 14
        chatStack.edgeInsets = NSEdgeInsets(top: 16, left: 0, bottom: 20, right: 0)
        chatStack.translatesAutoresizingMaskIntoConstraints = false; chatScroll.documentView = chatStack
        NSLayoutConstraint.activate([chatStack.widthAnchor.constraint(equalTo: chatScroll.contentView.widthAnchor), chatStack.leadingAnchor.constraint(equalTo: chatScroll.contentView.leadingAnchor), chatStack.topAnchor.constraint(equalTo: chatScroll.contentView.topAnchor)])
        center.addArrangedSubview(chatScroll); chatScroll.widthAnchor.constraint(equalTo: center.widthAnchor).isActive = true
        chatScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
        center.addArrangedSubview(taskLabel); taskLabel.lineBreakMode = .byTruncatingTail; taskLabel.widthAnchor.constraint(equalTo: center.widthAnchor).isActive = true
        attachmentBar.orientation = .vertical; attachmentBar.alignment = .leading; attachmentBar.spacing = 4; attachmentBar.translatesAutoresizingMaskIntoConstraints = false
        attachmentScroll.documentView = attachmentBar; attachmentScroll.hasVerticalScroller = true; attachmentScroll.drawsBackground = false; attachmentScroll.isHidden = true
        center.addArrangedSubview(attachmentScroll); attachmentScroll.widthAnchor.constraint(equalTo: center.widthAnchor).isActive = true
        attachmentHeight = attachmentScroll.heightAnchor.constraint(equalToConstant: 0); attachmentHeight?.isActive = true
        attachmentBar.widthAnchor.constraint(equalTo: attachmentScroll.contentView.widthAnchor).isActive = true
        let composerScroll = NSScrollView(); composerScroll.hasVerticalScroller = true; composerScroll.borderType = .bezelBorder
        composer.isRichText = false; composer.font = .systemFont(ofSize: 14); composer.textColor = EVATheme.cream; composer.backgroundColor = EVATheme.panel
        composer.isAutomaticQuoteSubstitutionEnabled = false; composer.isAutomaticDashSubstitutionEnabled = false; composer.allowsUndo = true
        composer.textContainerInset = NSSize(width: 9, height: 9); composer.isVerticallyResizable = true
        composer.onSend = { [weak self] in self?.sendMessage() }; composerScroll.documentView = composer
        composer.onFiles = { [weak self] urls in self?.uploadFiles(urls) }; composer.registerForDraggedTypes([.fileURL])
        center.addArrangedSubview(composerScroll); composerScroll.widthAnchor.constraint(equalTo: center.widthAnchor).isActive = true; composerScroll.heightAnchor.constraint(equalToConstant: 92).isActive = true
        providerPicker.target = self; providerPicker.action = #selector(providerChanged)
        configure(attachButton, "＋ 文件", #selector(addImages)); attachButton.toolTip = "支持任意单个文件，可选择、拖入或粘贴文件；最多 8 个，图片最多 4 张，单文件 32 MB。"
        modelPicker.target = self; modelPicker.action = #selector(modelChanged)
        effortPicker.target = self; effortPicker.action = #selector(effortChanged)
        modePicker.target = self; modePicker.action = #selector(modeChanged)
        configure(sendButton, "发送 ↑", #selector(sendMessage), primary: true)
        configure(stopButton, "停止", #selector(stopMessage)); configure(retryButton, "重试", #selector(retryMessage))
        let options = EVATheme.horizontal([providerPicker, attachButton, modelPicker, effortPicker, modePicker])
        center.addArrangedSubview(options); options.widthAnchor.constraint(equalTo: center.widthAnchor).isActive = true
        modelDetailsLabel.lineBreakMode = .byTruncatingMiddle
        center.addArrangedSubview(modelDetailsLabel); modelDetailsLabel.widthAnchor.constraint(equalTo: center.widthAnchor).isActive = true
        networkScopeLabel.lineBreakMode = .byTruncatingTail
        networkScopeLabel.toolTip = "Claude Code 通过随附的官方 CLI 直接连接，沿用系统与环境变量中的代理设置（HTTPS_PROXY / NO_PROXY）。"
        center.addArrangedSubview(networkScopeLabel); networkScopeLabel.widthAnchor.constraint(equalTo: center.widthAnchor).isActive = true
        modelPicker.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let sendRow = EVATheme.horizontal([EVATheme.label("⌘ / Ctrl + Enter 发送  ·  权限由你确认", size: 10, color: EVATheme.muted), EVATheme.spacer(), retryButton, stopButton, sendButton])
        center.addArrangedSubview(sendRow); sendRow.widthAnchor.constraint(equalTo: center.widthAnchor).isActive = true
        let centerBox = pinned(center, padding: 22)

        buildInspector()
        inspector.widthAnchor.constraint(equalToConstant: 380).isActive = true; inspector.isHidden = true
        let body = EVATheme.horizontal([sidebarBox, centerBox, inspector], spacing: 0)
        body.alignment = .top; body.distribution = .fill; body.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(body)
        NSLayoutConstraint.activate([body.leadingAnchor.constraint(equalTo: root.leadingAnchor), body.trailingAnchor.constraint(equalTo: root.trailingAnchor), body.topAnchor.constraint(equalTo: root.topAnchor, constant: 5), body.bottomAnchor.constraint(equalTo: root.bottomAnchor), sidebarBox.heightAnchor.constraint(equalTo: body.heightAnchor), centerBox.heightAnchor.constraint(equalTo: body.heightAnchor), inspector.heightAnchor.constraint(equalTo: body.heightAnchor)])
        return root
    }

    func applyState(_ value: JSON) {
        guard !stopping else { return }; state = value
        if !didRestoreSelection, let t = selectedThread { selectedModel = string(t["model"]); selectedEffort = string(t["effort"]); didRestoreSelection = true }
        if !selectedThreadID.isEmpty && selectedThread == nil { selectedThreadID = "" }
        if let t = selectedThread { workingProjectID = string(t["projectId"]) }
        if !projects.contains(where: { string($0["id"]) == workingProjectID }) { workingProjectID = string(projects.first?["id"]) }
        updateSidebar()
        updateControls()
        renderMessages(force: false)
        renderTools()
        updateUsageWidget()
        presentApprovalIfNeeded()
        if let t = selectedThread, !object(t["localHistory"]).isEmpty, !flag(t["historyLoaded"]), string(t["historyError"]).isEmpty {
            if provider == "claude" || string(state["connection"]) == "connected" { loadHistory(string(t["id"])) }
        }
    }
    func updateSidebar() {
        let selected = projectPicker.selectedItem?.representedObject as? String ?? filterProjectID
        let projectKey = projects.map { string($0["id"]) + string($0["name"]) }.joined(separator: "|")
        if projectListSignature != projectKey {
            projectPicker.removeAllItems(); projectPicker.addItem(withTitle: "全部会话 / 所有项目"); projectPicker.lastItem?.representedObject = ""
            for project in projects { projectPicker.addItem(withTitle: string(project["name"])); projectPicker.lastItem?.representedObject = string(project["id"]); projectPicker.lastItem?.toolTip = string(project["path"]) }
            if let index = projectPicker.itemArray.firstIndex(where: { ($0.representedObject as? String) == selected }) { projectPicker.selectItem(at: index) }
            projectListSignature = projectKey
        }
        let query = search.stringValue.lowercased()
        let rows = threads.filter { t in (filterProjectID.isEmpty || string(t["projectId"]) == filterProjectID) && flag(t["archived"]) == showArchived && object(t["continuedIn"]).isEmpty && !flag(t["discarded"]) && (query.isEmpty || string(t["title"]).lowercased().contains(query)) }.sorted { a, b in
            ((a["updatedAt"] as? Double) ?? (a["createdAt"] as? Double) ?? 0) > ((b["updatedAt"] as? Double) ?? (b["createdAt"] as? Double) ?? 0)
        }
        let key = rows.map { string($0["id"]) + string($0["title"]) + string($0["status"]) }.joined(separator: "|") + "::" + selectedThreadID
        displayedThreads = rows
        if key != sidebarSignature {
            sidebarSignature = key; suppressSidebarSelection = true; sidebarTable.reloadData()
            if let index = rows.firstIndex(where: { string($0["id"]) == selectedThreadID }) { sidebarTable.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false) } else { sidebarTable.deselectAll(nil) }
            suppressSidebarSelection = false
        }
        archiveButton.title = showArchived ? "返回" : "归档"
        let summary = object(state["localHistory"]), counts = object(summary["counts"])
        syncButton.isEnabled = ready && !flag(summary["loading"])
        syncButton.title = flag(summary["loading"]) ? "同步中…" : "同步本机会话"
        let total = ["codex", "claudeDesktop", "claudeCli"].reduce(0) { $0 + ((counts[$1] as? Int) ?? 0) }
        syncLabel.stringValue = string(summary["error"]).isEmpty ? "已发现 \(total) 条本机记录" : "部分同步失败，可点击重试"
        syncLabel.toolTip = string(summary["error"])
    }
    func updateControls() {
        let t = selectedThread ?? [:], historical = !object(t["localHistory"]).isEmpty, archived = flag(t["archived"]), continued = object(t["continuedIn"])
        let busy = sending || changingMode || string(t["status"]) == "inProgress" || !string(t["activeTurn"]).isEmpty
        let p = providerState, connected = string(p["connection"]) == "connected", signedIn = flag(object(p["account"])["signedIn"])
        providerPicker.selectedSegment = provider == "claude" ? 1 : 0; providerPicker.isEnabled = !busy && (selectedThread == nil || (!archived && continued.isEmpty))
        providerPicker.toolTip = selectedThread == nil ? nil : "在当前对话中切换到另一助手继续"
        connectionLabel.stringValue = connected ? "● \(providerName) 已连接" : "○ \(providerName) " + (string(p["connection"]) == "disconnected" ? "已断开" : "连接中")
        connectionLabel.toolTip = string(p["connectionError"])
        accountLabel.stringValue = signedIn ? (provider == "claude" ? (connected ? "Claude Code 已登录" : "Claude Code 已登录 · 连接中") : "Codex 已登录") : "尚未登录"
        accountButton.title = connected ? (signedIn ? "刷新" : "登录") : "重连"
        accountButton.isEnabled = ready
        projectLabel.stringValue = "PROJECT / " + string(currentProject?["name"])
        projectLabel.toolTip = string(currentProject?["path"])
        titleLabel.stringValue = selectedThread == nil ? "新对话" : string(t["title"])
        titleLabel.toolTip = titleLabel.stringValue
        renameButton.isHidden = selectedThread == nil || historical; archiveThreadButton.isHidden = selectedThread == nil
        archiveThreadButton.toolTip = historical ? "只在 EVA 中收起，不改变官方应用里的记录" : nil
        transferButton.isHidden = selectedThread == nil || !continued.isEmpty; transferButton.isEnabled = !busy && !archived
        transferButton.title = provider == "claude" ? "切换到 Codex 继续" : "切换到 Claude Code 继续"
        renameButton.isEnabled = !busy; archiveThreadButton.isEnabled = !busy; archiveThreadButton.title = archived ? "恢复" : "归档"
        let closed = historical || archived || !continued.isEmpty
        composer.isEditable = !closed
        composer.placeholder = !continued.isEmpty ? "这段对话已切换到 \(string(continued["provider"]) == "claude" ? "Claude Code" : "Codex") 继续，请前往当前对话。" : historical ? "本机历史只读。点击“继续此会话”创建独立分支。" : "告诉 \(providerName)，你想在这个项目里完成什么…"
        sendButton.isEnabled = !closed && !busy && pendingUploads == 0 && connected && signedIn
        attachButton.isEnabled = !closed && !busy && draftAttachments.count + pendingUploads < 8
        retryButton.isEnabled = !closed && !busy && objects(t["messages"]).contains { string($0["role"]) == "user" }
        stopButton.isHidden = !busy; stopButton.isEnabled = !string(t["activeTurn"]).isEmpty
        let status = string(t["status"])
        taskLabel.stringValue = !string(t["error"]).isEmpty ? string(t["error"]) : busy ? (status == "completed" ? "正在更新上下文…" : "\(providerName) 正在执行…") : status == "completed" ? "任务完成" : status == "interrupted" ? "任务已停止" : "系统就绪 / LOCAL LINK"
        taskLabel.toolTip = taskLabel.stringValue
        let source = object(t["localHistory"]), fork = object(t["forkedFrom"]), transfer = object(t["transfer"])
        historyBox.isHidden = !historical && fork.isEmpty && transfer.isEmpty && continued.isEmpty
        let inPlace = flag(transfer["inPlace"]), unused = !objects(t["messages"]).contains { !flag($0["imported"]) }
        historyNext.isHidden = continued.isEmpty; historyUnmerge.isHidden = !flag(continued["merged"]); historyUndo.isHidden = !inPlace || !flag(transfer["pending"]) || !unused || archived; historyUndo.isEnabled = !busy
        historyContinue.isHidden = !historical || !continued.isEmpty; historyEarlier.isHidden = !historical || t["historyCursor"] == nil || t["historyCursor"] is NSNull
        historyContinue.isEnabled = flag(source["canContinue"]) && !loadingHistory.contains(selectedThreadID)
        historyEarlier.isEnabled = !loadingHistory.contains(selectedThreadID)
        historyOriginal.isHidden = (fork.isEmpty && transfer.isEmpty) || inPlace
        transferPreviewButton.isHidden = transfer.isEmpty
        historyLabel.stringValue = historical ? (!string(t["historyError"]).isEmpty ? string(t["historyError"]) : !flag(t["historyLoaded"]) ? "正在读取本机历史…" : flag(source["canContinue"]) ? "本机历史 · 原会话保留，继续时创建独立分支。" : "原项目目录已移动，当前可查看历史。") : "从“\(string(fork["title"]))”继续的 EVA 分支"
        if !transfer.isEmpty { historyLabel.stringValue = "已从 \(string(transfer["sourceProvider"]) == "claude" ? "Claude Code" : "Codex") 导入 \(string(transfer["messageCount"])) 条消息和工具摘要；界面预览最近 \(string(transfer["visibleMessages"])) 条，完整转录可预览。" + (flag(transfer["pending"]) ? "下一次发送时交给 \(providerName) 参考。" : "已交给 \(providerName) 参考。") }
        if inPlace {
            let from = string(transfer["sourceProvider"]) == "claude" ? "Claude Code" : "Codex"
            historyLabel.stringValue = "本对话已从 \(from) 切换到 \(providerName)：上方是切换前的 \(string(transfer["messageCount"])) 条消息（界面显示最近 \(string(transfer["visibleMessages"])) 条，完整转录可预览）。权限已重置为只读。" + (flag(transfer["pending"]) ? "发送下一条消息时一并交给 \(providerName) 参考。" : "")
        }
        if flag(continued["merged"]) { let kept = threads.first { string($0["id"]) == string(continued["threadId"]) }; historyLabel.stringValue = "这条会话与“\(string(kept?["title"]))”重复，已合并收起；原记录未改动。" }
        else if !continued.isEmpty { historyLabel.stringValue = "这段对话已切换到 \(string(continued["provider"]) == "claude" ? "Claude Code" : "Codex") 继续。这里保留切换前的原始记录。" }
        let modelKey = provider + pretty(models)
        if modelKey != catalogSignature {
            let defaultModel = models.first { flag($0["isDefault"]) } ?? models.first ?? [:]
            catalogSignature = modelKey; modelPicker.removeAllItems(); modelPicker.addItem(withTitle: provider == "claude" ? string(defaultModel["name"]) : "官方默认模型"); modelPicker.lastItem?.representedObject = ""
            for model in models where provider != "claude" || string(model["id"]) != "default" { modelPicker.addItem(withTitle: string(model["name"])); modelPicker.lastItem?.representedObject = string(model["id"]); modelPicker.lastItem?.toolTip = string(model["resolvedModel"]) + "\n" + string(model["description"]) }
            select(modelPicker, value: selectedModel); rebuildEfforts()
        }
        updateModelDetails()
        modelPicker.isEnabled = !busy && !archived; effortPicker.isEnabled = !busy && !archived && effortPicker.numberOfItems > 1
        modePicker.removeAllItems()
        for (id, name) in [("read-only", "只读 · 分析与建议"), ("workspace-write", provider == "claude" ? "写入 / 命令逐次确认" : "允许项目写入")] { modePicker.addItem(withTitle: name); modePicker.lastItem?.representedObject = id }
        if provider == "claude" { modePicker.addItem(withTitle: "完全访问 · 本机免逐次确认"); modePicker.lastItem?.representedObject = "full-access" }
        if !t.isEmpty && !historical { mode = string(t["mode"]) }
        select(modePicker, value: mode); modePicker.isEnabled = !busy && !archived
        modePicker.toolTip = "空闲会话可直接切换，下一次发送生效。完全访问使用当前系统用户的本机权限，不逐次确认普通工具。"
    }
    func select(_ picker: NSPopUpButton, value: String) { if let index = picker.itemArray.firstIndex(where: { ($0.representedObject as? String) == value }) { picker.selectItem(at: index) } else { picker.selectItem(at: 0) } }
    func rebuildEfforts() {
        let chosen = models.first { string($0["id"]) == selectedModel } ?? models.first { flag($0["isDefault"]) } ?? models.first ?? [:]
        effortPicker.removeAllItems(); effortPicker.addItem(withTitle: "默认思考强度"); effortPicker.lastItem?.representedObject = ""
        for value in objects(chosen["supportedReasoningEfforts"]) { let name = string(value["reasoningEffort"]); effortPicker.addItem(withTitle: ["low": "轻量", "medium": "标准", "high": "深入", "xhigh": "更深入", "max": "最高", "ultra": "超强"][name] ?? name); effortPicker.lastItem?.representedObject = name }
        select(effortPicker, value: selectedEffort)
        updateModelDetails()
    }
    func updateModelDetails() {
        guard provider == "claude" else { modelDetailsLabel.isHidden = true; modelPicker.toolTip = nil; return }
        modelDetailsLabel.isHidden = false
        let chosen = models.first { string($0["id"]) == selectedModel } ?? models.first { flag($0["isDefault"]) } ?? [:]
        let resolved = string(chosen["resolvedModel"]), actual = string(selectedThread?["lastResponseModel"])
        var text = resolved.isEmpty ? "官方尚未返回具体模型版本" : "当前映射：" + resolved + (flag(chosen["followsOfficial"]) ? " · 随官方更新" : "")
        if !actual.isEmpty { text += "  /  最近回复：" + actual }
        modelDetailsLabel.stringValue = text
        modelDetailsLabel.toolTip = text + "\n" + string(chosen["description"]) + "\n模型列表来自当前 Claude Code SDK；未列出的旧版本尚未接入。"
        modelPicker.toolTip = modelDetailsLabel.toolTip
    }

    func renderMessages(force: Bool) {
        let t = selectedThread ?? [:], messages = objects(t["messages"])
        let signature = selectedThreadID + messages.map { string($0["id"]) + string($0["text"]) + string($0["model"]) + objects($0["attachments"]).map { string($0["id"]) }.joined() }.joined(separator: "|")
        let width = max(280, chatScroll.contentView.bounds.width)
        if signature == messageSignature && !force { for view in cards.values { view.body.preferredMaxLayoutWidth = width - 34 }; return }
        let atBottom = chatStack.bounds.height - chatScroll.contentView.bounds.maxY < 100
        let changed = renderedThread != selectedThreadID
        if changed { cards.removeAll(); renderedThread = selectedThreadID }
        messageSignature = signature
        for view in chatStack.arrangedSubviews { chatStack.removeArrangedSubview(view); view.removeFromSuperview() }
        if messages.isEmpty {
            let welcome = EVATheme.vertical([EVATheme.label("ASUKA / EVANGELION–02 · PRIVATE WORKSTATION", size: 10, color: EVATheme.orange), EVATheme.label("准备好了，就开始。", size: 34, weight: .semibold), EVATheme.label("选择本机会话，或在项目中开始新的任务。", size: 13, color: EVATheme.muted)], spacing: 20)
            let suggestions = EVATheme.horizontal()
            for (index, name) in ["分析项目", "审查代码", "开始构建"].enumerated() { let button = EVATheme.button(name, target: self, action: #selector(suggestion)); button.tag = index; suggestions.addArrangedSubview(button) }
            welcome.addArrangedSubview(suggestions); chatStack.addArrangedSubview(welcome)
            welcome.widthAnchor.constraint(equalTo: chatStack.widthAnchor).isActive = true
        } else {
            var previousImported = false
            for message in messages {
                if previousImported && !flag(message["imported"]) {
                    let divider = EVATheme.label("—— 以下由 \(providerName) 继续 ——", size: 10, color: EVATheme.orange); divider.alignment = .center
                    chatStack.addArrangedSubview(divider); divider.widthAnchor.constraint(equalTo: chatStack.widthAnchor).isActive = true
                }
                previousImported = flag(message["imported"])
                let id = string(message["id"]), card = cards[id] ?? MessageCard(message: message, provider: provider)
                cards[id] = card; card.onImage = { [weak self] file in self?.openImage(file) }; card.update(message: message, provider: provider, width: width)
                chatStack.addArrangedSubview(card); card.widthAnchor.constraint(equalTo: chatStack.widthAnchor).isActive = true
            }
        }
        window?.contentView?.layoutSubtreeIfNeeded()
        if changed || atBottom { chatStack.scroll(NSPoint(x: 0, y: max(0, chatStack.bounds.height - chatScroll.contentView.bounds.height))) }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView === sidebarTable { return displayedThreads.count }
        switch inspectorTabs.selectedSegment { case 1: return fileEntries.count; case 2: return gitEntries.count; case 3: return terminalEntries.count; case 4: return pluginEntries.count; default: return 0 }
    }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { EVARow() }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView === sidebarTable {
            guard row < displayedThreads.count else { return nil }; let t = displayedThreads[row]
            let provider = string(t["provider"]) == "claude" ? "CLAUDE" : "CODEX"
            let kind = object(t["localHistory"]).isEmpty ? "EVA" : "本机"
            let title = EVATheme.label(string(t["title"]), size: 12); title.lineBreakMode = .byTruncatingTail
            let subtitle = EVATheme.label(provider + "  /  " + kind + (string(t["status"]) == "inProgress" ? "  ◌" : ""), size: 9, color: EVATheme.orange)
            let box = pinned(EVATheme.vertical([title, subtitle], spacing: 5), padding: 5)
            box.toolTip = string(t["title"]); return box
        }
        let title: String
        switch inspectorTabs.selectedSegment {
        case 1: guard row < fileEntries.count else { return nil }; title = (flag(fileEntries[row]["directory"]) ? "▱ " : "· ") + string(fileEntries[row]["name"])
        case 2: guard row < gitEntries.count else { return nil }; title = string(gitEntries[row]["path"])
        case 3: guard row < terminalEntries.count else { return nil }; title = string(terminalEntries[row]["title"])
        case 4: guard row < pluginEntries.count else { return nil }; title = string(pluginEntries[row]["name"]).isEmpty ? string(pluginEntries[row]["id"]) : string(pluginEntries[row]["name"])
        default: title = ""
        }
        let label = EVATheme.label(title, size: 11); label.lineBreakMode = .byTruncatingMiddle; return label
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let table = notification.object as? NSTableView else { return }
        if table === sidebarTable {
            guard !suppressSidebarSelection, table.selectedRow >= 0, table.selectedRow < displayedThreads.count else { return }
            chooseThread(displayedThreads[table.selectedRow])
        } else { inspectorSelected() }
    }
    func controlTextDidChange(_ notification: Notification) { if notification.object as? NSSearchField === search { updateSidebar() } }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if control === terminalInput && commandSelector == #selector(NSResponder.insertNewline(_:)) { terminalSend(); return true }; return false
    }
}
