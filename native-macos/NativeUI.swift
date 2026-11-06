import AppKit

@MainActor
extension NativeWorkbench {
    func configure(_ button: NSButton, _ title: String, _ action: Selector, primary: Bool = false, kind: EVAButton.Kind? = nil) {
        button.title = title; button.target = self; button.action = action
        if let styled = button as? EVAButton { styled.kind = kind ?? (primary ? .primary : .outline); return }
        button.bezelStyle = .rounded; button.font = .systemFont(ofSize: 12, weight: primary ? .semibold : .regular)
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
    func fill(_ view: NSView, in parent: NSView, insets: NSEdgeInsets = NSEdgeInsets()) {
        view.translatesAutoresizingMaskIntoConstraints = false; parent.addSubview(view)
        NSLayoutConstraint.activate([view.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: insets.left), view.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -insets.right), view.topAnchor.constraint(equalTo: parent.topAnchor, constant: insets.top), view.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -insets.bottom)])
    }
    func fullWidth(_ views: [NSView], in stack: NSStackView) { for view in views { stack.addArrangedSubview(view); view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -(stack.edgeInsets.left + stack.edgeInsets.right)).isActive = true } }

    // Layout follows the web workbench: gradient sidebar · system header · session bar · centred column · status footer.
    func buildInterface() -> NSView {
        let root = EVAFrame(); root.showGrid = false

        // Sidebar
        let sidebarSurface = SidebarSurface()
        let sidebar = EVATheme.vertical([], spacing: 10); sidebar.edgeInsets = NSEdgeInsets(top: 46, left: 18, bottom: 14, right: 18)
        let mark = MarkView(); mark.widthAnchor.constraint(equalToConstant: 44).isActive = true; mark.heightAnchor.constraint(equalToConstant: 44).isActive = true
        let identity = EVATheme.horizontal([mark, EVATheme.vertical([EVAStyle.label("EVANGELION-02", EVAStyle.title(16), EVAStyle.ink, kern: 0.6), EVAStyle.label("私人工作台", EVAStyle.mono(8), hexColor(0xd6aaa0), kern: 1)], spacing: 6)], spacing: 14)
        sidebar.addArrangedSubview(identity); sidebar.setCustomSpacing(30, after: identity)
        let newButton = EVAButton("新对话", kind: .primary, target: self, action: #selector(newConversation)); newButton.trailing = "＋"; newButton.leftAligned = true
        fullWidth([newButton], in: sidebar); newButton.heightAnchor.constraint(equalToConstant: 46).isActive = true
        configure(syncButton, "同步本机会话", #selector(syncHistory)); fullWidth([syncButton], in: sidebar); syncButton.heightAnchor.constraint(equalToConstant: 38).isActive = true
        syncLabel.font = EVAStyle.mono(9); syncLabel.textColor = EVAStyle.faint; syncLabel.maximumNumberOfLines = 2; fullWidth([syncLabel], in: sidebar)
        sidebar.setCustomSpacing(22, after: syncLabel)
        let addProjectButton = EVAButton("＋", kind: .ghost, target: self, action: #selector(addProject)); addProjectButton.toolTip = "添加项目文件夹"
        let projects = EVATheme.horizontal([EVAStyle.label("项目", EVAStyle.ui(10), EVAStyle.sub), EVATheme.spacer(), addProjectButton]); fullWidth([projects], in: sidebar)
        projectPicker.target = self; projectPicker.action = #selector(projectChanged); fullWidth([projectPicker], in: sidebar); projectPicker.heightAnchor.constraint(equalToConstant: 36).isActive = true
        sidebar.setCustomSpacing(22, after: projectPicker)
        configure(archiveButton, "归档", #selector(toggleArchive), kind: .ghost)
        let recent = EVATheme.horizontal([EVAStyle.label("最近对话", EVAStyle.ui(10), EVAStyle.sub), EVATheme.spacer(), archiveButton, sessionCountLabel], spacing: 10); fullWidth([recent], in: sidebar)
        search.placeholderString = "搜索对话…"; search.delegate = self; (search.cell as? NSSearchFieldCell)?.searchButtonCell = nil; search.isBezeled = false; search.drawsBackground = false; search.focusRingType = .none; search.font = EVAStyle.ui(12); search.textColor = EVAStyle.ink
        let searchBox = FieldBox(); fill(search, in: searchBox, insets: NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8))
        fullWidth([searchBox], in: sidebar); searchBox.heightAnchor.constraint(equalToConstant: 36).isActive = true
        let conversationList = table(sidebarTable); sidebarTable.rowHeight = 46; sidebarTable.intercellSpacing = NSSize(width: 0, height: 2); sidebarTable.style = .plain
        fullWidth([conversationList], in: sidebar); conversationList.heightAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
        conversationList.setContentHuggingPriority(.defaultLow, for: .vertical)
        let pilot = EVAStyle.label("02", NSFont(name: "DINAlternate-Bold", size: 36) ?? .systemFont(ofSize: 36, weight: .semibold), EVAStyle.orange)
        let patch = EVATheme.horizontal([pilot, EVATheme.vertical([EVAStyle.label("ASUKA / EVANGELION-02", EVAStyle.ui(10), EVAStyle.ink), EVAStyle.label("驾驶员专属 · 私人工作台", EVAStyle.mono(8), EVAStyle.faint)], spacing: 4)], spacing: 12)
        fullWidth([patch], in: sidebar)
        configure(accountButton, "登录", #selector(accountAction), kind: .outline)
        accountLabel.font = EVAStyle.ui(10); accountLabel.textColor = EVAStyle.sub; accountLabel.lineBreakMode = .byTruncatingTail
        let accountRow = EVATheme.horizontal([accountLabel, EVATheme.spacer(), accountButton]); accountRow.edgeInsets = NSEdgeInsets(top: 12, left: 8, bottom: 0, right: 0)
        let accountBar = BarSurface(); accountBar.topRule = EVAStyle.accountRule; fill(accountRow, in: accountBar)
        fullWidth([accountBar], in: sidebar)
        fill(sidebar, in: sidebarSurface); sidebarSurface.widthAnchor.constraint(equalToConstant: 248).isActive = true

        // Header
        buildUsagePopover(); configure(usageButton, "上下文 — · 5h — · 周 —", #selector(showUsage), kind: .ghost)
        themePicker.addItems(withTitles: ["跟随系统", "红黑", "红白"]); themePicker.target = self; themePicker.action = #selector(themeChanged)
        themePicker.selectItem(at: ["system", "dark", "light"].firstIndex(of: UserDefaults.standard.string(forKey: "native.theme") ?? "system") ?? 0)
        connectionLabel.font = EVAStyle.mono(9); connectionLabel.textColor = hexColor(0xd4b18e)
        let replay = EVAButton("↻ 重播开机动画", kind: .gold, target: self, action: #selector(replayStartup))
        let exit = EVAButton("退出 ↗", kind: .ghost, target: NSApp, action: #selector(NSApplication.terminate(_:)))
        let headerRow = EVATheme.horizontal([EVAStyle.label("EVANGELION-02", EVAStyle.ui(16, .semibold), EVAStyle.ink, kern: 2), EVAStyle.label("私人工作台", EVAStyle.mono(8), hexColor(0xa28d7b), kern: 2.1), EVATheme.spacer(), usageButton, connectionLabel, themePicker, replay, exit], spacing: 12)
        headerRow.edgeInsets = NSEdgeInsets(top: 4, left: 32, bottom: 0, right: 26)
        let header = BarSurface(); header.color = EVAStyle.header; header.bottomRule = EVAStyle.headerRule; header.hazardTop = true; fill(headerRow, in: header)
        header.heightAnchor.constraint(equalToConstant: 64).isActive = true

        // Session bar
        projectLabel.font = EVAStyle.ui(10); projectLabel.textColor = EVAStyle.crumb
        titleLabel.font = EVAStyle.title(21); titleLabel.textColor = EVAStyle.ink
        let sessionHeading = EVATheme.vertical([projectLabel, titleLabel], spacing: 6)
        configure(renameButton, "重命名", #selector(renameConversation)); configure(archiveThreadButton, "归档", #selector(archiveConversation))
        configure(transferButton, "切换助手继续", #selector(transferConversation))
        transferButton.toolTip = "在当前对话里换另一助手继续：历史正文和工具摘要作为参考交给它，权限重置为只读；发送前可撤销。原助手的记录保留。"
        modeBadge.kind = .chip; modeBadge.title = "只读模式"; modeBadge.isEnabled = true; modeBadge.toolTip = "当前会话的权限"
        let tools = EVAButton("工具与文件", kind: .outline, target: self, action: #selector(toggleInspector))
        let contextRow = EVATheme.horizontal([sessionHeading, EVATheme.spacer(), modeBadge, transferButton, renameButton, archiveThreadButton, tools], spacing: 8)
        contextRow.edgeInsets = NSEdgeInsets(top: 0, left: 32, bottom: 0, right: 26)
        titleLabel.lineBreakMode = .byTruncatingTail; projectLabel.lineBreakMode = .byTruncatingMiddle
        for view in [titleLabel, projectLabel, sessionHeading] as [NSView] { view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal) }
        let sessionBar = BarSurface(); sessionBar.color = EVAStyle.sessionBar; sessionBar.bottomRule = EVAStyle.sessionRule; fill(contextRow, in: sessionBar)
        sessionBar.heightAnchor.constraint(equalToConstant: 88).isActive = true

        // Centre column (max 920 wide), over the backdrop
        let center = EVATheme.vertical([], spacing: 12)
        noticeLabel.isHidden = true; noticeLabel.lineBreakMode = .byTruncatingTail; noticeLabel.font = EVAStyle.ui(12); noticeLabel.textColor = EVAStyle.orange; fullWidth([noticeLabel], in: center)
        historyLabel.font = EVAStyle.ui(11); historyLabel.textColor = EVAStyle.ink
        configure(historyContinue, "继续此会话", #selector(continueHistory), primary: true)
        configure(historyEarlier, "加载更早记录", #selector(earlierHistory)); configure(historyOriginal, "查看原会话", #selector(openOriginal))
        configure(historyUndo, "撤销切换", #selector(undoTransfer)); configure(historyNext, "前往当前对话", #selector(openContinuation), primary: true); configure(historyUnmerge, "取消合并", #selector(unmergeConversation))
        configure(transferPreviewButton, "预览导入转录", #selector(previewTransfer))
        historyBox.orientation = .vertical; historyBox.alignment = .leading; historyBox.spacing = 8; historyBox.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        historyBox.wantsLayer = true; historyBox.layer?.borderWidth = 1; historyBox.layer?.cornerRadius = 2
        historyBox.addArrangedSubview(historyLabel); historyBox.addArrangedSubview(EVATheme.horizontal([historyContinue, historyNext, historyEarlier, historyOriginal, historyUndo, historyUnmerge, transferPreviewButton]))
        historyLabel.widthAnchor.constraint(equalTo: historyBox.widthAnchor, constant: -28).isActive = true; historyLabel.maximumNumberOfLines = 3
        historyBox.isHidden = true; fullWidth([historyBox], in: center)

        chatScroll.hasVerticalScroller = true; chatScroll.drawsBackground = false; chatScroll.borderType = .noBorder; chatScroll.scrollerStyle = .overlay
        chatStack.orientation = .vertical; chatStack.alignment = .leading; chatStack.spacing = 14
        chatStack.edgeInsets = NSEdgeInsets(top: 16, left: 0, bottom: 20, right: 0)
        chatStack.translatesAutoresizingMaskIntoConstraints = false; chatScroll.documentView = chatStack
        NSLayoutConstraint.activate([chatStack.widthAnchor.constraint(equalTo: chatScroll.contentView.widthAnchor), chatStack.leadingAnchor.constraint(equalTo: chatScroll.contentView.leadingAnchor), chatStack.topAnchor.constraint(equalTo: chatScroll.contentView.topAnchor)])
        fullWidth([chatScroll], in: center); chatScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
        chatScroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        attachmentBar.orientation = .vertical; attachmentBar.alignment = .leading; attachmentBar.spacing = 4; attachmentBar.translatesAutoresizingMaskIntoConstraints = false
        attachmentScroll.documentView = attachmentBar; attachmentScroll.hasVerticalScroller = true; attachmentScroll.drawsBackground = false; attachmentScroll.isHidden = true
        fullWidth([attachmentScroll], in: center)
        attachmentHeight = attachmentScroll.heightAnchor.constraint(equalToConstant: 0); attachmentHeight?.isActive = true
        attachmentBar.widthAnchor.constraint(equalTo: attachmentScroll.contentView.widthAnchor).isActive = true

        // Composer: red top rule, transparent field, flat controls
        let composerScroll = NSScrollView(); composerScroll.hasVerticalScroller = true; composerScroll.borderType = .noBorder; composerScroll.drawsBackground = false; composerScroll.scrollerStyle = .overlay
        composer.isRichText = false; composer.font = EVAStyle.ui(14); composer.textColor = EVAStyle.ink; composer.backgroundColor = .clear; composer.drawsBackground = false
        composer.insertionPointColor = EVAStyle.orange
        composer.isAutomaticQuoteSubstitutionEnabled = false; composer.isAutomaticDashSubstitutionEnabled = false; composer.allowsUndo = true
        composer.textContainerInset = NSSize(width: 0, height: 4); composer.isVerticallyResizable = true
        composer.onSend = { [weak self] in self?.sendMessage() }; composerScroll.documentView = composer
        composer.onFiles = { [weak self] urls in self?.uploadFiles(urls) }; composer.registerForDraggedTypes([.fileURL])
        providerPicker.target = self; providerPicker.action = #selector(providerChanged)
        configure(attachButton, "＋ 文件", #selector(addImages)); attachButton.toolTip = "支持任意单个文件，可选择、拖入或粘贴文件；最多 8 个，图片最多 4 张，单文件 32 MB。"
        modelPicker.target = self; modelPicker.action = #selector(modelChanged)
        effortPicker.target = self; effortPicker.action = #selector(effortChanged)
        modePicker.target = self; modePicker.action = #selector(modeChanged)
        configure(sendButton, "发送 ↑", #selector(sendMessage), primary: true)
        configure(stopButton, "停止", #selector(stopMessage)); configure(retryButton, "重试", #selector(retryMessage), kind: .ghost)
        modelPicker.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let controls = EVATheme.horizontal([providerPicker, attachButton, modelPicker, effortPicker, modePicker, EVATheme.spacer(), retryButton, stopButton, sendButton], spacing: 8)
        let hint = EVAStyle.label("回车发送 · Shift + 回车换行 · 支持粘贴或拖入文件 · 额外权限由你确认", EVAStyle.ui(10.5), EVAStyle.faint)
        modelDetailsLabel.font = EVAStyle.mono(9); modelDetailsLabel.textColor = EVAStyle.faint; modelDetailsLabel.lineBreakMode = .byTruncatingMiddle
        networkScopeLabel.font = EVAStyle.mono(9); networkScopeLabel.textColor = EVAStyle.orange; networkScopeLabel.lineBreakMode = .byTruncatingTail
        networkScopeLabel.toolTip = "Claude Code 通过随附的官方 CLI 直接连接，沿用系统与环境变量中的代理设置（HTTPS_PROXY / NO_PROXY）。"
        let composerStack = EVATheme.vertical([], spacing: 12); composerStack.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 4, right: 20)
        fullWidth([composerScroll, controls], in: composerStack); composerScroll.heightAnchor.constraint(equalToConstant: 66).isActive = true
        let composerFrame = BarSurface(); composerFrame.topRule = EVAStyle.red; fill(composerStack, in: composerFrame)
        fullWidth([composerFrame], in: center)
        let notes = EVATheme.vertical([hint, modelDetailsLabel, networkScopeLabel], spacing: 4); notes.edgeInsets = NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
        fullWidth([notes], in: center)

        let content = NSView()
        fill(backdrop, in: content)
        center.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(center)
        // The column follows the window width (no fixed cap), keeping 32 pt margins on both sides.
        NSLayoutConstraint.activate([center.centerXAnchor.constraint(equalTo: content.centerXAnchor), center.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -64),
            center.topAnchor.constraint(equalTo: content.topAnchor, constant: 14), center.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16)])

        // Footer status
        taskLabel.font = EVAStyle.mono(9); taskLabel.textColor = EVAStyle.faint; taskLabel.lineBreakMode = .byTruncatingTail; taskLabel.alignment = .right
        footer.status.removeFromSuperview(); taskLabel.translatesAutoresizingMaskIntoConstraints = false; footer.addSubview(taskLabel)
        NSLayoutConstraint.activate([taskLabel.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -32), taskLabel.centerYAnchor.constraint(equalTo: footer.centerYAnchor, constant: -1), taskLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 460)])
        footer.heightAnchor.constraint(equalToConstant: 30).isActive = true

        let main = EVATheme.vertical([], spacing: 0); fullWidth([header, sessionBar, content, footer], in: main)
        content.setContentHuggingPriority(.defaultLow, for: .vertical)

        buildInspector()
        inspector.widthAnchor.constraint(equalToConstant: 380).isActive = true; inspector.isHidden = true
        let body = EVATheme.horizontal([sidebarSurface, main, inspector], spacing: 0)
        body.alignment = .top; body.distribution = .fill
        fill(body, in: root)
        NSLayoutConstraint.activate([sidebarSurface.heightAnchor.constraint(equalTo: body.heightAnchor), main.heightAnchor.constraint(equalTo: body.heightAnchor), inspector.heightAnchor.constraint(equalTo: body.heightAnchor)])
        // Armour stripes on both window edges.
        let left = EdgeStripe(), right = EdgeStripe()
        for (stripe, leading) in [(left, true), (right, false)] {
            stripe.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(stripe)
            NSLayoutConstraint.activate([stripe.widthAnchor.constraint(equalToConstant: 7), stripe.topAnchor.constraint(equalTo: root.topAnchor, constant: 160), stripe.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: leading ? 0 : -30),
                leading ? stripe.leadingAnchor.constraint(equalTo: root.leadingAnchor) : stripe.trailingAnchor.constraint(equalTo: root.trailingAnchor)])
        }
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
        displayedThreads = rows; sessionCountLabel.stringValue = String(format: "%02d", rows.count)
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
        projectLabel.stringValue = "项目   /   " + (string(currentProject?["name"]).isEmpty ? "未选择项目" : string(currentProject?["name"]))
        modeBadge.title = mode == "full-access" ? "完全访问" : mode == "workspace-write" ? "写入模式" : "只读模式"
        modeBadge.isHidden = selectedThread == nil && !object(selectedThread?["localHistory"]).isEmpty
        historyBox.effectiveAppearance.performAsCurrentDrawingAppearance { historyBox.layer?.borderColor = EVAStyle.cardLine.cgColor; historyBox.layer?.backgroundColor = EVAStyle.card.withAlphaComponent(0.9).cgColor }
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
            let signedIn = flag(object(providerState["account"])["signedIn"])
            let welcome = EVATheme.vertical([EVAStyle.label("ASUKA / EVANGELION-02 · PRIVATE WORKSTATION", EVAStyle.mono(11, .medium), EVAStyle.orange, kern: 2.4), EVAStyle.label("准备好了，就开始。", EVAStyle.title(52), EVAStyle.ink), EVAStyle.label(signedIn ? "项目已待命。把下一步交给 \(providerName)。" : "登录 \(providerName)，开始你的工作。", EVAStyle.ui(14), EVAStyle.sub)], spacing: 18)
            welcome.edgeInsets = NSEdgeInsets(top: max(30, chatScroll.contentView.bounds.height * 0.16), left: 0, bottom: 0, right: 0)
            let suggestions = EVATheme.horizontal([], spacing: 10)
            for (index, name) in ["分析项目", "审查代码", "开始构建"].enumerated() { let button = EVAButton(name, kind: .card, target: self, action: #selector(suggestion)); button.caption = String(format: "%02d  /  OPERATION", index + 1); button.tag = index; suggestions.addArrangedSubview(button) }
            welcome.addArrangedSubview(suggestions); welcome.setCustomSpacing(30, after: welcome.arrangedSubviews[2]); chatStack.addArrangedSubview(welcome)
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
            let title = EVAStyle.label(string(t["title"]), EVAStyle.ui(12, .medium), EVAStyle.ink); title.lineBreakMode = .byTruncatingTail
            let subtitle = EVAStyle.label(provider + "  /  " + kind + (string(t["status"]) == "inProgress" ? "  ◌ 运行中" : ""), EVAStyle.mono(8.5), EVAStyle.orange, kern: 0.6)
            let box = pinned(EVATheme.vertical([title, subtitle], spacing: 5), padding: 6); box.subviews.first.map { ($0 as? NSStackView)?.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 0) }
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
