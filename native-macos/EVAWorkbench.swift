import AppKit

func scheduleGracefulExitFallback(child: Process? = nil, after seconds: Double = 5) {
    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + seconds) {
        if child?.isRunning == true { child?.terminate() }
        exit(0)
    }
}

@MainActor
final class NativeWorkbench: NSObject, NSApplicationDelegate, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    let environment = ProcessInfo.processInfo.environment
    let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/EVA-Workbench")
    lazy var port = Int(environment["EVA_DESKTOP_PORT"] ?? "43137") ?? 43137
    lazy var api = NativeAPI(port: port)
    var window: NSWindow!
    var backend: Process?
    var ownedService = false
    var logHandle: FileHandle?
    var ready = false, stopping = false, checking = false, presentingError = false
    var monitor: Timer?
    var launchDate = Date()
    var failures = 0
    var state: JSON = ["projects": [], "threads": [], "models": [], "approvals": []]
    var selectedThreadID = UserDefaults.standard.string(forKey: "native.selectedThread") ?? ""
    var workingProjectID = UserDefaults.standard.string(forKey: "native.selectedProject") ?? ""
    var filterProjectID = ""
    var preferredProvider = UserDefaults.standard.string(forKey: "native.provider") ?? "codex"
    var showArchived = false
    var displayedThreads: [JSON] = []
    var suppressSidebarSelection = false
    var suppressInspectorSelection = false
    var drafts: [String: (String, [JSON])] = [:]
    var inspectorProjectID = ""
    var sending = false
    var loadingHistory = Set<String>()
    var draftEpoch = 0
    var draftAttachments: [JSON] = []
    var pendingUploads = 0
    var pendingImageUploads = 0
    var selectedModel = "", selectedEffort = "", mode = "read-only"
    var catalogSignature = "", renderedThread = "", messageSignature = "__unrendered__", toolSignature = ""
    var cards: [String: MessageCard] = [:]
    var imageWindows: [NSWindow] = []
    var shownApproval = ""
    var approvalFields: [String: NSTextField] = [:]
    var fileDirectory = ""
    var fileEntries: [JSON] = [], gitEntries: [JSON] = [], pluginEntries: [JSON] = [], terminalEntries: [JSON] = []
    var selectedTerminal = "", terminalBuffer = ""
    var introView: IntroView?
    var startupTimer: Timer?
    var inspectorVisible = false
    var controlSignature = "", sidebarSignature = ""
    var projectListSignature = ""
    var didRestoreSelection = false
    var fullAccessAcknowledged = false, changingMode = false
    var usageTimer: Timer?, usageRefreshing = false
    var usageErrors: [String: String] = [:]
    let usagePopover = NSPopover()
    let usageButton = EVAButton()
    let contextMetric = UsageMetric(), fiveHourMetric = UsageMetric(), weekMetric = UsageMetric()
    let usageSourceLabel = NSTextField(wrappingLabelWithString: "")
    let usageRefreshButton = EVAButton()
    let themePicker = EVAPopUp(frame: .zero, pullsDown: false)

    let sidebarTable = NSTableView()
    let search = NSSearchField()
    let projectPicker = EVAPopUp(frame: .zero, pullsDown: false)
    let syncButton = EVAButton(), archiveButton = EVAButton(), accountButton = EVAButton()
    let sessionCountLabel = EVAStyle.label("00", EVAStyle.mono(10), EVAStyle.sub)
    let modeBadge = EVAButton(), footer = StatusFooter(), backdrop = Backdrop()
    let syncLabel = EVATheme.label("正在连接本机服务…", size: 10, color: EVATheme.muted)
    let accountLabel = EVATheme.label("", size: 11, color: EVATheme.muted)
    let providerPicker = EVASegmented(labels: ["Codex", "Claude Code"], trackingMode: .selectOne, target: nil, action: nil)
    let projectLabel = EVATheme.label("PROJECT / 未选择项目", size: 11, color: EVATheme.muted)
    let titleLabel = EVATheme.label("新对话", size: 24, weight: .semibold)
    let connectionLabel = EVATheme.label("● CONNECTING", size: 11, color: EVATheme.orange)
    let taskLabel = EVATheme.label("准备中…", size: 11, color: EVATheme.muted)
    let noticeLabel = EVATheme.label("", size: 12, color: EVATheme.orange)
    let historyLabel = NSTextField(wrappingLabelWithString: "")
    let historyContinue = EVAButton(), historyEarlier = EVAButton(), historyOriginal = EVAButton(), historyUndo = EVAButton(), historyNext = EVAButton(), historyUnmerge = EVAButton()
    let transferButton = EVAButton(), transferPreviewButton = EVAButton()
    let historyBox = NSStackView()
    let chatScroll = NSScrollView()
    let chatStack = FlippedStack()
    let composer = ComposerView()
    let modelPicker = EVAPopUp(frame: .zero, pullsDown: false)
    let modelDetailsLabel = EVATheme.label("", size: 10, color: EVATheme.muted)
    let networkScopeLabel = EVATheme.label("Claude Code 与 Codex 均使用官方 CLI 直接连接", size: 10, color: EVATheme.orange)
    let effortPicker = EVAPopUp(frame: .zero, pullsDown: false)
    let modePicker = EVAPopUp(frame: .zero, pullsDown: false)
    let sendButton = EVAButton(), stopButton = EVAButton(), retryButton = EVAButton(), attachButton = EVAButton()
    let attachmentBar = FlippedStack()
    let attachmentScroll = NSScrollView()
    var attachmentHeight: NSLayoutConstraint?
    let renameButton = EVAButton(), archiveThreadButton = EVAButton()
    let inspector = ThemedStack()
    let inspectorTabs = EVASegmented(labels: ["执行", "文件", "Git", "终端", "插件"], trackingMode: .selectOne, target: nil, action: nil)
    let inspectorText = NSTextView()
    let inspectorTextScroll = NSScrollView()
    let inspectorActions = NSStackView()
    let inspectorTable = NSTableView()
    let inspectorTableScroll = NSScrollView()
    let inspectorPath = EVATheme.label("", size: 10, color: EVATheme.muted)
    let terminalInput = NSTextField(), commitInput = NSTextField()

    var projects: [JSON] { objects(state["projects"]) }
    var threads: [JSON] { objects(state["threads"]) }
    var selectedThread: JSON? { threads.first { string($0["id"]) == selectedThreadID } }
    var currentProject: JSON? { projects.first { string($0["id"]) == workingProjectID } }
    var provider: String { if let thread = selectedThread { return string(thread["provider"]) == "claude" ? "claude" : "codex" }; return preferredProvider }
    var providerName: String { provider == "claude" ? "Claude Code" : "Codex" }
    var providerState: JSON { provider == "claude" ? object(object(state["providers"])["claude"]) : state }
    var models: [JSON] { objects(providerState["models"]) }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let identifier = Bundle.main.bundleIdentifier, let other = NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first(where: { $0.processIdentifier != getpid() }) {
            other.activate(options: [.activateAllWindows]); NSApp.terminate(nil); return
        }
        NSApp.setActivationPolicy(.regular)
        setThemeAppearance()
        installMenus()
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1500, height: 1000)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: min(1500, screen.width - 48), height: min(950, screen.height - 64)), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "EVA Workbench"
        window.appearance = nil
        window.backgroundColor = EVATheme.background
        window.titlebarAppearsTransparent = true; window.titleVisibility = .hidden
        window.minSize = NSSize(width: 1080, height: 720)
        window.setFrameAutosaveName("EVANativeMainWindow")
        window.isReleasedWhenClosed = false; window.delegate = self
        if !window.setFrameUsingName("EVANativeMainWindow") { window.center() }
        window.contentView = buildInterface()
        api.onState = { [weak self] value in self?.applyState(value) }
        api.onDisconnect = { [weak self] in if self?.stopping == false { self?.connectionLabel.stringValue = "○ 本机连接中断，正在重连…" } }
        api.onTerminal = { [weak self] value in self?.receiveTerminal(value) }
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        probe(initial: true)
    }
    func probe(initial: Bool = false) {
        guard !stopping && !checking else { return }; checking = true
        api.request("/health", timeout: 1.5) { [weak self] result in
            guard let self else { return }; self.checking = false; guard !self.stopping else { return }
            switch result {
            case .success(let value):
                guard string(object(value)["app"]) == "EVA-UNIT02" else { self.showError("本地端口已被其他程序占用，未连接该程序。"); return }
                self.failures = 0; if !self.ready { self.connectNativeClient() }
            case .failure:
                if initial { self.startBackend() }
                else if self.ready { self.failures += 1; if self.failures >= 2 { NSApp.terminate(nil) } }
                else if Date().timeIntervalSince(self.launchDate) > 25 { self.showError("本地工作台未能启动，请检查本机安装文件。") }
            }
        }
    }
    func connectNativeClient() {
        guard !ready else { return }; ready = true
        api.bootstrap { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                self.api.startEvents()
                self.api.request("/api/state") { [weak self] result in if case .success(let value) = result { self?.applyState(object(value)) } }
                self.showStartupSequence()
                self.usageTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in DispatchQueue.main.async { self?.refreshUsage() } }
            case .failure(let error): self.showError("原生客户端连接失败：" + error.localizedDescription)
            }
        }
        monitor?.invalidate()
        monitor = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in DispatchQueue.main.async { self?.probe() } }
    }
    func startBackend() {
        let server = support.appendingPathComponent("workbench/server.cjs")
        guard let node = ["/usr/local/bin/node", "/opt/homebrew/bin/node"].first(where: { FileManager.default.isExecutableFile(atPath: $0) }), FileManager.default.fileExists(atPath: server.path) else { showError("缺少 Node.js 或本机工作台支持目录。"); return }
        do {
            let logs = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs")
            try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
            let log = logs.appendingPathComponent("EVA-Workbench.log")
            if !FileManager.default.fileExists(atPath: log.path) { FileManager.default.createFile(atPath: log.path, contents: nil) }
            logHandle = try FileHandle(forWritingTo: log); try logHandle?.seekToEnd()
            let process = Process(); process.executableURL = URL(fileURLWithPath: node); process.arguments = [server.path]; process.currentDirectoryURL = support.appendingPathComponent("workbench")
            var env = environment; env["PATH"] = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"; env["HACKCLAW_PORT"] = String(port)
            if let directory = environment["EVA_DESKTOP_DATA_DIR"] { env["HACKCLAW_DATA_DIR"] = directory }
            let codex = "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"
            if FileManager.default.isExecutableFile(atPath: codex) { env["HACKCLAW_CODEX"] = codex }
            process.environment = env; process.standardInput = FileHandle.nullDevice; process.standardOutput = logHandle; process.standardError = logHandle
            process.terminationHandler = { [weak self] child in
                if child.terminationStatus == 0 { scheduleGracefulExitFallback() }
                DispatchQueue.main.async {
                    guard let self, !self.stopping else { return }
                    if child.terminationStatus == 0 { NSApp.terminate(nil) } else { self.showError("本地服务已停止，请重新打开 EVA Workbench。") }
                }
            }
            backend = process; ownedService = true; launchDate = Date(); try process.run()
            monitor = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in DispatchQueue.main.async { self?.probe() } }
        } catch { showError("启动失败：" + error.localizedDescription) }
    }
    func perform(_ route: String, body: JSON? = nil, query: [String: String] = [:], completion: ((Any) -> Void)? = nil) {
        api.request(route, query: query, body: body) { [weak self] result in
            switch result { case .success(let value): completion?(value); case .failure(let error): self?.notice(error.localizedDescription) }
        }
    }
    func notice(_ message: String) { noticeLabel.stringValue = message; noticeLabel.isHidden = message.isEmpty }
    func showError(_ message: String) {
        guard !presentingError && !stopping else { return }; presentingError = true
        let alert = NSAlert(); alert.messageText = "EVA Workbench 无法继续"; alert.informativeText = message; alert.addButton(withTitle: "退出")
        alert.beginSheetModal(for: window) { _ in NSApp.terminate(nil) }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { window?.makeKeyAndOrderFront(nil); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func windowWillClose(_ notification: Notification) { if let closed = notification.object as? NSWindow { imageWindows.removeAll { $0 === closed } } }
    func windowDidResize(_ notification: Notification) { renderMessages(force: false) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if stopping { return .terminateNow }; stopping = true; monitor?.invalidate(); startupTimer?.invalidate(); usageTimer?.invalidate()
        scheduleGracefulExitFallback(child: ownedService ? backend : nil)
        guard ready else { backend?.terminate(); return .terminateNow }
        api.request("/api/shutdown", body: [:], timeout: 1.5) { [weak self] _ in DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.finishTermination() } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in self?.finishTermination() }
        return .terminateLater
    }
    func finishTermination() { if ownedService && backend?.isRunning == true { backend?.terminate() }; api.stop(); NSApp.reply(toApplicationShouldTerminate: true) }
}

@main
struct Entry {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--self-test-exit-fallback") { scheduleGracefulExitFallback(after: 0.1); RunLoop.current.run(until: Date().addingTimeInterval(2)); exit(1) }
        if let index = CommandLine.arguments.firstIndex(of: "--render-intro"), index + 1 < CommandLine.arguments.count {
            let times = [0.3, 1.2, 2.2, 3.5, 5, 6.6, 8, 9.5, 11.5, 13.3, 14.6, 15.0, 15.2, 16.5, 18.9, 19.5]
            do { try IntroView.renderFrames(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]), times: times); print("intro frames written") } catch { print("render failed:", error); exit(1) }
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--render-markdown"), index + 2 < CommandLine.arguments.count {
            // Offscreen check of message rendering: --render-markdown <input.md> <output-prefix>
            let source = (try? String(contentsOfFile: CommandLine.arguments[index + 1], encoding: .utf8)) ?? ""
            for (name, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", .aqua)] {
                let card = MessageCard(message: ["role": "assistant", "text": source, "model": "claude-opus-5-5"], provider: "claude"); card.appearance = NSAppearance(named: appearance)
                let host = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 10)); host.appearance = card.appearance; host.wantsLayer = true
                card.translatesAutoresizingMaskIntoConstraints = false; host.addSubview(card)
                NSLayoutConstraint.activate([card.leadingAnchor.constraint(equalTo: host.leadingAnchor), card.trailingAnchor.constraint(equalTo: host.trailingAnchor), card.topAnchor.constraint(equalTo: host.topAnchor)])
                card.update(message: ["role": "assistant", "text": source, "model": "claude-opus-5-5"], provider: "claude", width: 900); host.layoutSubtreeIfNeeded()
                host.setFrameSize(NSSize(width: 900, height: card.fittingSize.height)); host.layoutSubtreeIfNeeded()
                host.appearance!.performAsCurrentDrawingAppearance {
                    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
                    let base = NSImage(size: host.bounds.size); base.lockFocus(); EVAStyle.base.setFill(); host.bounds.fill(); base.unlockFocus()
                    host.cacheDisplay(in: host.bounds, to: rep)
                    let out = NSImage(size: host.bounds.size); out.lockFocus(); EVAStyle.base.setFill(); host.bounds.fill(); rep.draw(in: host.bounds); out.unlockFocus()
                    if let tiff = out.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) { try? png.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 2] + "-" + name + ".png")) }
                }
            }
            return
        }
        if CommandLine.arguments.contains("--self-test") {
            let composer = ComposerView(); var sent = 0; composer.onSend = { sent += 1 }; composer.string = "hi"
            func key(_ flags: NSEvent.ModifierFlags) -> NSEvent { NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)! }
            composer.setSelectedRange(NSRange(location: 2, length: 0)); composer.keyDown(with: key(.shift)); precondition(sent == 0 && composer.string == "hi\n", "Shift+Return must insert a newline")
            composer.keyDown(with: key([])); precondition(sent == 1 && composer.string == "hi\n", "Return must send")
            precondition(introCurve(0) == 0 && introCurve(1) == 1 && abs(introStage(IntroTiming.hold, IntroTiming.syncStart, IntroTiming.hold) - 1) < 1e-9)
            precondition(string(object(["id": "a"])["id"]) == "a")
            precondition(messageText("# Heading\n```swift\nlet x = 1\n```\nBody").string.contains("let x = 1"))
            precondition(!messageText("<script>example</script>").string.isEmpty)
            let withFiles = MessageCard(message: ["role": "user", "text": "看看这张照片", "attachments": [["id": "a", "name": "IMG_0001-a-very-long-photo-name.HEIC", "mime": "image/png"], ["id": "b", "name": "report.pdf", "mime": "application/octet-stream"]]], provider: "claude")
            precondition(withFiles.attachments.arrangedSubviews.count == 2, "messages with attachments must render")
            let md = messageText("## 标题\n**粗体** 与 `code` 和 [链接](https://example.com)\n- 列表项\n1. 第一\n> 引用\n| A | B |\n|---|---|\n| 1 | 2 |").string
            precondition(!md.contains("**") && !md.contains("`") && !md.contains("](") && !md.contains("## ") && !md.contains("|---") && md.contains("•") && md.contains("1.") && md.contains("A\tB"), "Markdown must render, not show source: \(md)")
            let client = NativeAPI(port: 43137); precondition(client.origin == "http://127.0.0.1:43137")
            print("Native AppKit controls, local API and text renderer checks passed; no WebKit host")
            return
        }
        let application = NSApplication.shared, delegate = NativeWorkbench()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
