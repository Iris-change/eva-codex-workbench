import AppKit
import UniformTypeIdentifiers
import ImageIO

typealias JSON = [String: Any]
func object(_ value: Any?) -> JSON { value as? JSON ?? [:] }
func objects(_ value: Any?) -> [JSON] { value as? [JSON] ?? [] }
func string(_ value: Any?) -> String { if let value = value as? String { return value }; return (value as? NSNumber)?.stringValue ?? "" }
func flag(_ value: Any?) -> Bool { (value as? NSNumber)?.boolValue ?? false }
func pretty(_ value: Any?) -> String {
    guard let value, JSONSerialization.isValidJSONObject(value), let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]), let text = String(data: data, encoding: .utf8) else { return "" }
    return text
}

enum EVATheme {
    static func color(_ name: String, dark: NSColor, light: NSColor) -> NSColor { NSColor(name: NSColor.Name("EVA." + name)) { appearance in appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light } }
    static let background = color("background", dark: NSColor(calibratedRed: 0.035, green: 0.04, blue: 0.052, alpha: 1), light: NSColor(calibratedRed: 0.99, green: 0.975, blue: 0.97, alpha: 1))
    static let panel = color("panel", dark: NSColor(calibratedRed: 0.065, green: 0.065, blue: 0.076, alpha: 1), light: .white)
    static let sidebar = color("sidebar", dark: NSColor(calibratedRed: 0.09, green: 0.045, blue: 0.06, alpha: 1), light: NSColor(calibratedRed: 0.97, green: 0.9, blue: 0.9, alpha: 1))
    static let red = NSColor(calibratedRed: 0.76, green: 0.075, blue: 0.12, alpha: 1)
    static let orange = color("accent", dark: NSColor(calibratedRed: 0.96, green: 0.37, blue: 0.15, alpha: 1), light: NSColor(calibratedRed: 0.7, green: 0.13, blue: 0.1, alpha: 1))
    static let cream = color("text", dark: NSColor(calibratedRed: 0.88, green: 0.83, blue: 0.74, alpha: 1), light: NSColor(calibratedRed: 0.19, green: 0.1, blue: 0.12, alpha: 1))
    static let muted = color("muted", dark: NSColor(calibratedRed: 0.59, green: 0.56, blue: 0.53, alpha: 1), light: NSColor(calibratedRed: 0.46, green: 0.39, blue: 0.4, alpha: 1))
    static let border = color("border", dark: NSColor(calibratedWhite: 0.17, alpha: 1), light: NSColor(calibratedRed: 0.86, green: 0.75, blue: 0.76, alpha: 1))
    static let userBubble = color("userBubble", dark: NSColor(calibratedWhite: 0.075, alpha: 1), light: NSColor(calibratedRed: 0.99, green: 0.93, blue: 0.92, alpha: 1))
    static let assistantBubble = color("assistantBubble", dark: NSColor(calibratedWhite: 0.045, alpha: 1), light: .white)
    static let codeBackground = color("codeBackground", dark: NSColor(calibratedWhite: 0.11, alpha: 1), light: NSColor(calibratedRed: 0.95, green: 0.91, blue: 0.9, alpha: 1))
    static let codeText = color("codeText", dark: NSColor(calibratedRed: 0.91, green: 0.79, blue: 0.66, alpha: 1), light: NSColor(calibratedRed: 0.4, green: 0.12, blue: 0.12, alpha: 1))
    static func label(_ text: String, size: CGFloat = 12, color: NSColor = cream, weight: NSFont.Weight = .regular) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        return label
    }
    static func button(_ title: String, target: AnyObject?, action: Selector?, primary: Bool = false) -> NSButton {
        EVAButton(title, kind: primary ? .primary : .outline, target: target, action: action)
    }
    static func vertical(_ views: [NSView] = [], spacing: CGFloat = 10) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.spacing = spacing
        stack.alignment = .leading
        return stack
    }
    static func horizontal(_ views: [NSView] = [], spacing: CGFloat = 8) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.spacing = spacing
        stack.alignment = .centerY
        return stack
    }
    static func spacer() -> NSView {
        let view = NSView()
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return view
    }
}

final class NativeAPI: NSObject, URLSessionDataDelegate {
    let origin: String
    let port: Int
    var onState: ((JSON) -> Void)?
    var onDisconnect: (() -> Void)?
    var onTerminal: ((JSON) -> Void)?
    private var cookie = ""
    private let lock = NSLock()
    private var streams: [Int: (kind: String, data: Data)] = [:]
    private var stateTask: URLSessionDataTask?
    private var terminalTask: URLSessionDataTask?
    private var stopped = false
    lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [:]
        config.timeoutIntervalForRequest = 65
        config.timeoutIntervalForResource = 43200
        return URLSession(configuration: config, delegate: self, delegateQueue: OperationQueue())
    }()
    init(port: Int) { self.port = port; self.origin = "http://127.0.0.1:\(port)" }
    func request(_ route: String, query: [String: String] = [:], body: JSON? = nil, timeout: Double = 65, completion: @escaping (Result<Any, Error>) -> Void) {
        guard route.hasPrefix("/"), !route.hasPrefix("//"), !route.contains("://") else { completion(.failure(NSError(domain: "EVA", code: 1, userInfo: [NSLocalizedDescriptionKey: "无效的本机接口"]))); return }
        var components = URLComponents(string: origin + route)!
        if !query.isEmpty { components.queryItems = query.sorted(by: { $0.key < $1.key }).map { URLQueryItem(name: $0.key, value: $0.value) } }
        var request = URLRequest(url: components.url!)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = timeout
        lock.lock(); let auth = cookie; lock.unlock()
        if !auth.isEmpty { request.setValue(auth, forHTTPHeaderField: "Cookie") }
        if let body {
            request.httpMethod = "POST"
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(origin, forHTTPHeaderField: "Origin")
        }
        session.dataTask(with: request) { data, response, error in
            let result: Result<Any, Error>
            if let error { result = .failure(error) }
            else if let data, let response = response as? HTTPURLResponse {
                if route == "/native-session", let headers = response.allHeaderFields as? [String: String] {
                    let cookies = HTTPCookie.cookies(withResponseHeaderFields: headers, for: request.url!)
                    if let cookie = cookies.first(where: { $0.name == "unit02_session" && $0.domain == "127.0.0.1" }) {
                        self.lock.lock(); self.cookie = "unit02_session=" + cookie.value; self.lock.unlock()
                    }
                }
                let value = (try? JSONSerialization.jsonObject(with: data)) ?? [:]
                if (200..<300).contains(response.statusCode) { result = .success(value) }
                else { result = .failure(NSError(domain: "EVA", code: response.statusCode, userInfo: [NSLocalizedDescriptionKey: string(object(value)["error"]).isEmpty ? "本机服务返回 \(response.statusCode)" : string(object(value)["error"])])) }
            } else { result = .failure(NSError(domain: "EVA", code: 2, userInfo: [NSLocalizedDescriptionKey: "本机服务未响应"])) }
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }
    func bootstrap(_ completion: @escaping (Result<Any, Error>) -> Void) { request("/native-session", completion: completion) }
    func download(_ route: String, completion: @escaping (Data?) -> Void) {
        guard route.hasPrefix("/api/attachment/"), !route.contains("..") else { completion(nil); return }
        var request = URLRequest(url: URL(string: origin + route)!)
        lock.lock(); request.setValue(cookie, forHTTPHeaderField: "Cookie"); lock.unlock()
        session.dataTask(with: request) { data, response, _ in
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            DispatchQueue.main.async { completion(ok ? data : nil) }
        }.resume()
    }
    func startEvents() { stopped = false; startStream(kind: "state", route: "/api/events") }
    func startTerminal(_ id: String) {
        terminalTask?.cancel()
        var components = URLComponents(string: origin + "/api/dev/terminal-events")!
        components.queryItems = [URLQueryItem(name: "id", value: id)]
        startStream(kind: "terminal", route: components.url!.path + "?" + components.percentEncodedQuery!)
    }
    private func startStream(kind: String, route: String) {
        var request = URLRequest(url: URL(string: origin + route)!)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        lock.lock(); request.setValue(cookie, forHTTPHeaderField: "Cookie"); lock.unlock()
        let task = session.dataTask(with: request)
        lock.lock(); streams[task.taskIdentifier] = (kind, Data()); lock.unlock()
        if kind == "state" { stateTask = task } else { terminalTask = task }
        task.resume()
    }
    func stop() { stopped = true; stateTask?.cancel(); terminalTask?.cancel(); session.invalidateAndCancel() }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        guard var entry = streams[dataTask.taskIdentifier] else { lock.unlock(); return }
        entry.data.append(data)
        if entry.data.count > 32 * 1024 * 1024 { entry.data.removeAll(); streams[dataTask.taskIdentifier] = entry; lock.unlock(); return }
        var events: [JSON] = []
        while let range = entry.data.range(of: Data("\n\n".utf8)) {
            let packet = entry.data.subdata(in: 0..<range.lowerBound); entry.data.removeSubrange(0..<range.upperBound)
            for line in String(decoding: packet, as: UTF8.self).split(separator: "\n") where line.hasPrefix("data: ") {
                if let decoded = try? JSONSerialization.jsonObject(with: Data(line.dropFirst(6).utf8)) as? JSON { events.append(decoded) }
            }
        }
        streams[dataTask.taskIdentifier] = entry
        lock.unlock()
        for value in events { DispatchQueue.main.async { if entry.kind == "state" { self.onState?(value) } else { self.onTerminal?(value) } } }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock(); let entry = streams.removeValue(forKey: task.taskIdentifier); let isStopped = stopped; lock.unlock()
        if entry?.kind == "state" && !isStopped {
            DispatchQueue.main.async {
                self.onDisconnect?()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { if !self.stopped { self.startEvents() } }
            }
        }
    }
}

final class ComposerView: NSTextView {
    var onSend: (() -> Void)?
    var onFiles: (([URL]) -> Void)?
    func fileURLs(_ pasteboard: NSPasteboard) -> [URL] { guard pasteboard.types?.contains(.fileURL) == true else { return [] }; return pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? [] }
    override func paste(_ sender: Any?) { let urls = fileURLs(.general); if !urls.isEmpty { onFiles?(urls) } else { super.paste(sender) } }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { fileURLs(sender.draggingPasteboard).isEmpty ? super.draggingEntered(sender) : .copy }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { fileURLs(sender.draggingPasteboard).isEmpty ? super.prepareForDragOperation(sender) : true }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool { let urls = fileURLs(sender.draggingPasteboard); if urls.isEmpty { return super.performDragOperation(sender) }; onFiles?(urls); return true }
    var placeholder = "告诉助手，你想完成什么…" { didSet { needsDisplay = true } }
    override func keyDown(with event: NSEvent) {
        // Return / keypad Enter sends; Shift or Option + Return inserts a line break. While an input method is
        // composing (marked text), Return only confirms the candidate and never sends.
        if (event.keyCode == 36 || event.keyCode == 76) && !hasMarkedText() {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags.contains(.shift) || flags.contains(.option) { insertNewlineIgnoringFieldEditor(nil); needsDisplay = true; return }
            onSend?(); return
        }
        super.keyDown(with: event)
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty { (placeholder as NSString).draw(at: NSPoint(x: textContainerInset.width + (textContainer?.lineFragmentPadding ?? 5), y: textContainerInset.height), withAttributes: [.font: font ?? NSFont.systemFont(ofSize: 14), .foregroundColor: EVAStyle.faint]) }
    }
    override func didChangeText() { super.didChangeText(); needsDisplay = true }
}

final class EVAFrame: NSView {
    var showGrid = false
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        EVAStyle.base.setFill(); bounds.fill()
        if showGrid {
            NSColor(calibratedWhite: 0.16, alpha: 0.22).setStroke()
            let grid = NSBezierPath(); grid.lineWidth = 0.5
            for x in stride(from: CGFloat(0), through: bounds.width, by: 42) { grid.move(to: NSPoint(x: x, y: 0)); grid.line(to: NSPoint(x: x, y: bounds.height)) }
            for y in stride(from: CGFloat(0), through: bounds.height, by: 42) { grid.move(to: NSPoint(x: 0, y: y)); grid.line(to: NSPoint(x: bounds.width, y: y)) }
            grid.stroke()
        }
    }
}

final class FlippedStack: NSStackView { override var isFlipped: Bool { true } }

final class ThemedSurface: NSView {
    var surfaceColor: NSColor = EVATheme.panel { didSet { updateSurface() } }
    func updateSurface() { wantsLayer = true; effectiveAppearance.performAsCurrentDrawingAppearance { layer?.backgroundColor = surfaceColor.cgColor } }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateSurface() }
}
final class ThemedStack: NSStackView {
    var surfaceColor: NSColor = EVATheme.panel { didSet { updateSurface() } }
    func updateSurface() { wantsLayer = true; effectiveAppearance.performAsCurrentDrawingAppearance { layer?.backgroundColor = surfaceColor.cgColor } }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateSurface() }
}

final class EVARow: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        EVAStyle.selected.setFill(); bounds.insetBy(dx: 0, dy: 1).fill()
        EVAStyle.red.setFill(); NSRect(x: 0, y: 1, width: 3, height: bounds.height - 2).fill()
        EVAStyle.red.withAlphaComponent(0.55).setStroke(); let edge = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 1.5)); edge.lineWidth = 1; edge.stroke()
    }
}

final class MessageCard: NSView {
    var bubbleColor: NSColor = EVATheme.assistantBubble
    var isUser = false
    override func draw(_ dirtyRect: NSRect) { EVAStyle.sessionRule.setFill(); NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill(); if isUser { EVAStyle.red.withAlphaComponent(0.8).setFill(); NSRect(x: 0, y: 20, width: 2, height: max(0, bounds.height - 40)).fill() } }
    let body = NSTextField(wrappingLabelWithString: "")
    let role = EVATheme.label("", size: 10, color: EVATheme.orange, weight: .semibold)
    let attachments = NSStackView()
    var text = ""
    var attachmentKey = ""
    var onImage: ((JSON) -> Void)?
    var images: [String: JSON] = [:]
    init(message: JSON, provider: String) {
        super.init(frame: .zero)
        wantsLayer = true
        // Flat transcript rows as in the web workbench: translucent base, small mono role line, hairline separator.
        isUser = string(message["role"]) == "user"
        bubbleColor = EVAStyle.base.withAlphaComponent(0.86)
        role.font = EVAStyle.mono(9, .medium); role.textColor = isUser ? EVAStyle.dyn("userRole", 0xb0bbc0, 0x5f7079) : EVAStyle.orange
        updateAppearance()
        body.isSelectable = true; body.allowsEditingTextAttributes = true
        body.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        attachments.orientation = .vertical; attachments.alignment = .leading; attachments.spacing = 7
        let stack = EVATheme.vertical([role, body, attachments], spacing: 8)
        attachments.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18), stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18), stack.topAnchor.constraint(equalTo: topAnchor, constant: 22), stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -22), body.widthAnchor.constraint(equalTo: stack.widthAnchor)])
        update(message: message, provider: provider, width: 700)
    }
    required init?(coder: NSCoder) { fatalError() }
    func updateAppearance() { effectiveAppearance.performAsCurrentDrawingAppearance { layer?.backgroundColor = bubbleColor.cgColor; layer?.borderWidth = 0; layer?.cornerRadius = 0 }; needsDisplay = true; body.needsDisplay = true }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateAppearance() }
    func update(message: JSON, provider: String, width: CGFloat) {
        let source = string(message["sourceProvider"]).isEmpty ? provider : string(message["sourceProvider"])
        role.stringValue = string(message["role"]) == "user" ? "YOU / 驾驶员" : source == "claude" ? "CLAUDE CODE / RESPONSE" : "CODEX / RESPONSE"
        if flag(message["imported"]) { role.stringValue += " · 导入历史" }
        if string(message["role"]) != "user", !string(message["model"]).isEmpty { role.stringValue += " · " + string(message["model"]) }
        let value = string(message["text"])
        if value != text { text = value; body.attributedStringValue = messageText(value) }
        body.preferredMaxLayoutWidth = max(200, width - 34)
        body.invalidateIntrinsicContentSize()
        let files = objects(message["attachments"]), key = files.map { string($0["id"]) }.joined(separator: ",")
        if key != attachmentKey {
            attachmentKey = key
            for view in attachments.arrangedSubviews { attachments.removeArrangedSubview(view); view.removeFromSuperview() }
            images.removeAll()
            for file in files {
                let id = string(file["id"]); images[id] = file
                let button = EVATheme.button((string(file["mime"]).hasPrefix("image/") ? "▧ " : "▤ ") + string(file["name"]), target: self, action: #selector(openImage))
                button.cell?.lineBreakMode = .byTruncatingMiddle; button.identifier = NSUserInterfaceItemIdentifier(id)
                // Add to the stack before constraining against it: a constraint between views without a common
                // ancestor throws and terminated the app whenever a message with attachments was shown.
                attachments.addArrangedSubview(button)
                button.widthAnchor.constraint(lessThanOrEqualTo: attachments.widthAnchor).isActive = true
            }
        }
        attachments.isHidden = files.isEmpty
    }
    @objc func openImage(_ sender: NSButton) { if let id = sender.identifier?.rawValue, let file = images[id] { onImage?(file) } }
}

func imageUpload(_ url: URL) throws -> JSON {
    let data = try Data(contentsOf: url)
    guard data.count <= 32 * 1024 * 1024, let image = NSImage(data: data), let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw NSError(domain: "EVA", code: 4, userInfo: [NSLocalizedDescriptionKey: "请选择不超过 32 MB 的可读取图片"]) }
    let scale = min(1.0, 4096.0 / Double(max(source.width, source.height)))
    let width = max(1, Int(Double(source.width) * scale)), height = max(1, Int(Double(source.height) * scale))
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
    image.draw(in: NSRect(x: 0, y: 0, width: width, height: height), from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    var encoded = bitmap.representation(using: .png, properties: [:])!, mime = "image/png"
    if encoded.count > 8 * 1024 * 1024 { encoded = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.88])!; mime = "image/jpeg" }
    guard encoded.count <= 8 * 1024 * 1024 else { throw NSError(domain: "EVA", code: 5, userInfo: [NSLocalizedDescriptionKey: "图片压缩后仍超过 8 MB，请缩小后再添加"]) }
    // Only the first frame/page is drawn above; report the total so the label can say what was left out.
    let frames = CGImageSourceCreateWithData(data as CFData, nil).map { CGImageSourceGetCount($0) } ?? 1
    return ["name": url.lastPathComponent, "dataUrl": "data:" + mime + ";base64," + encoded.base64EncodedString(), "frames": frames]
}
