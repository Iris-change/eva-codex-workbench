import AppKit

@MainActor
extension NativeWorkbench {
    func buildInspector() {
        inspector.orientation = .vertical; inspector.alignment = .leading; inspector.spacing = 10
        inspector.edgeInsets = NSEdgeInsets(top: 20, left: 15, bottom: 20, right: 15)
        inspector.surfaceColor = EVATheme.panel
        inspector.addArrangedSubview(EVATheme.label("SYSTEM MONITOR / 工作区", size: 12, color: EVATheme.orange, weight: .semibold))
        inspectorTabs.selectedSegment = 0; inspectorTabs.target = self; inspectorTabs.action = #selector(inspectorChanged)
        inspector.addArrangedSubview(inspectorTabs); inspectorTabs.widthAnchor.constraint(equalToConstant: 350).isActive = true
        inspectorPath.lineBreakMode = .byTruncatingMiddle; inspector.addArrangedSubview(inspectorPath); inspectorPath.widthAnchor.constraint(equalToConstant: 350).isActive = true
        inspectorActions.orientation = .horizontal; inspectorActions.spacing = 5; inspector.addArrangedSubview(inspectorActions)
        inspectorTableScroll.documentView = inspectorTable
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("tool")); column.width = 330; inspectorTable.addTableColumn(column)
        inspectorTable.headerView = nil; inspectorTable.delegate = self; inspectorTable.dataSource = self; inspectorTable.rowHeight = 26; inspectorTable.backgroundColor = EVATheme.panel
        inspectorTableScroll.hasVerticalScroller = true; inspectorTableScroll.drawsBackground = false
        inspector.addArrangedSubview(inspectorTableScroll); inspectorTableScroll.widthAnchor.constraint(equalToConstant: 350).isActive = true; inspectorTableScroll.heightAnchor.constraint(equalToConstant: 150).isActive = true
        inspectorText.isEditable = false; inspectorText.isSelectable = true; inspectorText.font = .monospacedSystemFont(ofSize: 11, weight: .regular); inspectorText.textColor = EVATheme.cream; inspectorText.backgroundColor = EVATheme.panel
        inspectorText.autoresizingMask = [.width]; inspectorText.isVerticallyResizable = true
        inspectorTextScroll.documentView = inspectorText; inspectorTextScroll.hasVerticalScroller = true; inspectorTextScroll.hasHorizontalScroller = false
        inspector.addArrangedSubview(inspectorTextScroll); inspectorTextScroll.widthAnchor.constraint(equalToConstant: 350).isActive = true; inspectorTextScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 100).isActive = true
        terminalInput.placeholderString = "输入命令后回车（文本模式）"; terminalInput.delegate = self
        inspector.addArrangedSubview(terminalInput); terminalInput.widthAnchor.constraint(equalToConstant: 350).isActive = true
        inspectorChanged()
    }
    @objc func toggleInspector() {
        inspectorVisible.toggle(); inspector.isHidden = !inspectorVisible
        window.minSize = NSSize(width: inspectorVisible ? 1450 : 1080, height: 720)
        if inspectorVisible && window.frame.width < 1450 { var frame = window.frame; frame.size.width = min(1500, NSScreen.main?.visibleFrame.width ?? 1500); window.setFrame(frame, display: true) }
        if inspectorVisible { refreshInspector() }
    }
    @objc func inspectorChanged() {
        for view in inspectorActions.arrangedSubviews { inspectorActions.removeArrangedSubview(view); view.removeFromSuperview() }
        let tab = inspectorTabs.selectedSegment
        inspectorTableScroll.isHidden = tab == 0; terminalInput.isHidden = tab != 3
        func button(_ name: String, _ action: Selector, tag: Int = 0) { let b = EVATheme.button(name, target: self, action: action); b.tag = tag; inspectorActions.addArrangedSubview(b) }
        button("刷新", #selector(refreshInspector))
        switch tab {
        case 1: button("上级", #selector(fileUp))
        case 2: button("暂存", #selector(gitAction), tag: 0); button("撤暂存", #selector(gitAction), tag: 1); button("提交…", #selector(gitCommit)); button("更多…", #selector(gitMore))
        case 3: button("新建", #selector(terminalCreate)); button("Ctrl+C", #selector(terminalInterrupt)); button("关闭", #selector(terminalClose))
        case 4: button("安装", #selector(pluginChange), tag: 0); button("卸载", #selector(pluginChange), tag: 1)
        default: break
        }
        inspectorText.string = ""; inspectorTable.reloadData()
        if inspectorVisible { refreshInspector() }
    }
    func renderTools() {
        guard inspectorVisible else { return }
        if inspectorProjectID != workingProjectID { inspectorProjectID = workingProjectID; fileDirectory = ""; fileEntries = []; gitEntries = []; terminalEntries = []; selectedTerminal = ""; terminalBuffer = ""; refreshInspector() }
        guard inspectorTabs.selectedSegment == 0 else { return }
        let t = selectedThread ?? [:], key = pretty(t["tools"]) + pretty(t["plan"]) + string(t["diff"])
        if key == toolSignature { return }; toolSignature = key
        var parts: [String] = []
        let plan = objects(t["plan"])
        if !plan.isEmpty { parts.append("PLAN\n" + plan.map { "\(string($0["status"]))  \(string($0["step"]))" }.joined(separator: "\n")) }
        for tool in objects(t["tools"]) {
            let name = string(tool["name"]).isEmpty ? string(tool["type"]) : string(tool["name"])
            let text = [name + "  ·  " + string(tool["status"]), string(tool["command"]), string(tool["aggregatedOutput"]), string(tool["output"]), pretty(tool["input"]), pretty(tool["changes"])].filter { !$0.isEmpty }.joined(separator: "\n")
            parts.append(text)
        }
        if !string(t["diff"]).isEmpty { parts.append("DIFF\n" + string(t["diff"])) }
        inspectorPath.stringValue = "执行记录 / 当前会话"; inspectorText.string = parts.isEmpty ? "任务开始后，这里显示工具执行、计划和变更。" : parts.joined(separator: "\n\n────────────────\n\n")
    }
    @objc func refreshInspector() {
        guard !workingProjectID.isEmpty else { inspectorText.string = "请先选择项目。"; return }
        let projectID = workingProjectID, tab = inspectorTabs.selectedSegment
        if tab == 0 { toolSignature = ""; renderTools(); return }
        if tab == 1 {
            let directory = fileDirectory; inspectorPath.stringValue = directory.isEmpty ? "/" : directory
            perform("/api/files", query: ["projectId": projectID, "path": directory]) { value in
                guard self.workingProjectID == projectID, self.inspectorTabs.selectedSegment == tab, self.fileDirectory == directory else { return }
                self.fileEntries = objects(value).sorted { flag($0["directory"]) != flag($1["directory"]) ? flag($0["directory"]) : string($0["name"]) < string($1["name"]) }; self.reloadInspector()
            }; return
        }
        let route = tab == 2 ? "git-status" : tab == 3 ? "terminal-list" : "plugins-list"
        inspectorPath.stringValue = tab == 4 ? "Codex 插件 · 账号连接在官方客户端完成" : tab == 3 ? "本机 Shell · 文本模式，非完整终端模拟器" : "读取 Git 状态…"
        perform("/api/dev/" + route, body: ["projectId": projectID]) { value in
            guard self.workingProjectID == projectID, self.inspectorTabs.selectedSegment == tab else { return }; let data = object(value)
            if tab == 2 { self.gitEntries = objects(data["files"]); self.inspectorPath.stringValue = "BRANCH / " + string(data["branch"]); self.inspectorText.string = "最近提交\n" + string(data["log"]) }
            else if tab == 3 { self.terminalEntries = objects(data["terminals"]); if self.selectedTerminal.isEmpty, let first = self.terminalEntries.first { self.selectTerminal(string(first["id"])) } }
            else { self.pluginEntries = objects(data["plugins"]); self.inspectorText.string = "选择插件查看安装和授权状态。" }
            self.reloadInspector()
        }
    }
    func reloadInspector() { suppressInspectorSelection = true; inspectorTable.reloadData(); suppressInspectorSelection = false }
    func inspectorSelected() {
        guard !suppressInspectorSelection else { return }; let row = inspectorTable.selectedRow
        guard row >= 0 else { return }
        let projectID = workingProjectID, tab = inspectorTabs.selectedSegment
        switch tab {
        case 1:
            guard fileEntries.indices.contains(row) else { return }; let entry = fileEntries[row]
            let path = fileDirectory.isEmpty ? string(entry["name"]) : fileDirectory + "/" + string(entry["name"])
            if flag(entry["directory"]) { fileDirectory = path; refreshInspector() }
            else { perform("/api/file", query: ["projectId": projectID, "path": path]) { value in guard self.workingProjectID == projectID, self.inspectorTabs.selectedSegment == tab else { return }; self.inspectorPath.stringValue = path; self.inspectorText.string = string(object(value)["text"]) } }
        case 2:
            guard gitEntries.indices.contains(row) else { return }; let entry = gitEntries[row]
            perform("/api/dev/git-diff", body: ["projectId": projectID, "path": string(entry["path"]), "staged": string(entry["worktree"]) == " "]) { value in guard self.workingProjectID == projectID, self.inspectorTabs.selectedSegment == tab else { return }; self.inspectorText.string = string(object(value)["text"]) }
        case 3: if terminalEntries.indices.contains(row) { selectTerminal(string(terminalEntries[row]["id"])) }
        case 4: if pluginEntries.indices.contains(row) { inspectorText.string = pretty(pluginEntries[row]) }
        default: break
        }
    }
    @objc func fileUp() { fileDirectory = (fileDirectory as NSString).deletingLastPathComponent; refreshInspector() }
    @objc func gitAction(_ sender: NSButton) {
        let row = inspectorTable.selectedRow; guard gitEntries.indices.contains(row) else { notice("请先选择一个 Git 文件。"); return }
        perform("/api/dev/git-action", body: ["projectId": workingProjectID, "operation": sender.tag == 0 ? "stage" : "unstage", "path": string(gitEntries[row]["path"])]) { _ in self.refreshInspector() }
    }
    @objc func gitCommit() {
        let project = workingProjectID, alert = NSAlert(); alert.messageText = "提交已暂存的更改"
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 400, height: 26)); input.placeholderString = "提交说明"; alert.accessoryView = input
        alert.addButton(withTitle: "提交"); alert.addButton(withTitle: "取消")
        alert.beginSheetModal(for: window) { [weak self] response in if response == .alertFirstButtonReturn { self?.perform("/api/dev/git-action", body: ["projectId": project, "operation": "commit", "message": input.stringValue]) { _ in self?.refreshInspector() } } }
    }
    @objc func gitMore(_ sender: NSButton) {
        let menu = NSMenu()
        for (i, name) in ["获取远程 / fetch", "快进拉取 / pull", "推送 / push", "切换分支…", "新建分支…"].enumerated() { let item = NSMenuItem(title: name, action: #selector(gitMoreSelected), keyEquivalent: ""); item.tag = i; item.target = self; menu.addItem(item) }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
    }
    @objc func gitMoreSelected(_ sender: NSMenuItem) {
        let operations = ["fetch", "pull", "push", "switch", "branch"], project = workingProjectID, operation = operations[sender.tag]
        if sender.tag < 3 { perform("/api/dev/git-action", body: ["projectId": project, "operation": operation]) { _ in self.refreshInspector() }; return }
        let alert = NSAlert(); alert.messageText = sender.tag == 3 ? "切换分支" : "新建分支"
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 350, height: 26)); input.placeholderString = "分支名称"; alert.accessoryView = input
        alert.addButton(withTitle: "确定"); alert.addButton(withTitle: "取消")
        alert.beginSheetModal(for: window) { [weak self] response in if response == .alertFirstButtonReturn { self?.perform("/api/dev/git-action", body: ["projectId": project, "operation": operation, "branch": input.stringValue]) { _ in self?.refreshInspector() } } }
    }
    func selectTerminal(_ id: String) { selectedTerminal = id; terminalBuffer = ""; inspectorText.string = ""; api.startTerminal(id) }
    @objc func terminalCreate() { perform("/api/dev/terminal-create", body: ["projectId": workingProjectID]) { value in self.selectTerminal(string(object(value)["id"])); self.refreshInspector() } }
    @objc func terminalSend() {
        guard !selectedTerminal.isEmpty else { notice("请先新建或选择一个终端。"); return }
        let input = terminalInput.stringValue; guard !input.isEmpty else { return }; terminalInput.stringValue = ""
        perform("/api/dev/terminal-input", body: ["id": selectedTerminal, "data": input + "\r"])
    }
    @objc func terminalInterrupt() { if !selectedTerminal.isEmpty { perform("/api/dev/terminal-input", body: ["id": selectedTerminal, "data": "\u{03}"]) } }
    @objc func terminalClose() {
        guard !selectedTerminal.isEmpty else { return }; let id = selectedTerminal
        perform("/api/dev/terminal-close", body: ["id": id]) { _ in self.selectedTerminal = ""; self.terminalBuffer = ""; self.inspectorText.string = ""; self.refreshInspector() }
    }
    func receiveTerminal(_ value: JSON) {
        if flag(value["reset"]) { terminalBuffer = "" }
        terminalBuffer += string(value["data"])
        if terminalBuffer.count > 200_000 { terminalBuffer = String(terminalBuffer.suffix(200_000)) }
        if inspectorTabs.selectedSegment == 3 {
            inspectorText.string = terminalBuffer.replacingOccurrences(of: "\u{1B}\\][^\u{07}]*(?:\u{07}|\u{1B}\\\\)", with: "", options: .regularExpression).replacingOccurrences(of: "\u{1B}\\[[0-?]*[ -/]*[@-~]", with: "", options: .regularExpression).replacingOccurrences(of: "\r", with: "")
            inspectorText.scrollToEndOfDocument(nil)
        }
    }
    @objc func pluginChange(_ sender: NSButton) {
        let row = inspectorTable.selectedRow; guard pluginEntries.indices.contains(row) else { notice("请先选择插件。"); return }
        perform("/api/dev/plugins-change", body: ["projectId": workingProjectID, "id": string(pluginEntries[row]["id"]), "operation": sender.tag == 0 ? "install" : "remove"]) { value in self.notice(string(object(value)["message"])); self.refreshInspector() }
    }
}
