import AppKit
import CoreImage

// Visual system ported from the web workbench (style.css / unit02.css): flat 2–3 px radii, red primary,
// gold system accents, hazard stripes and Mincho titles. Every colour has a red/black and a red/white variant.

func hexColor(_ value: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((value >> 16) & 0xff) / 255, green: CGFloat((value >> 8) & 0xff) / 255, blue: CGFloat(value & 0xff) / 255, alpha: alpha)
}

enum EVAStyle {
    static func dyn(_ name: String, _ dark: UInt32, _ light: UInt32, _ darkAlpha: CGFloat = 1, _ lightAlpha: CGFloat = 1) -> NSColor {
        EVATheme.color("style." + name, dark: hexColor(dark, darkAlpha), light: hexColor(light, lightAlpha))
    }
    static let base = dyn("base", 0x0a0b0d, 0xf7f3ee)
    static let header = dyn("header", 0x101113, 0xfcf9f5)
    static let sessionBar = dyn("session", 0x0d0e10, 0xfaf6f1)
    static let headerRule = dyn("headerRule", 0x3c3029, 0xe3d2c8)
    static let sessionRule = dyn("sessionRule", 0x252526, 0xebdfd8)
    static let ink = dyn("ink", 0xe8e2d7, 0x2b1a1a)
    static let sub = dyn("sub", 0xb9a69c, 0x7f655a)
    static let faint = dyn("faint", 0x8e877e, 0x9c8a80)
    static let crumb = dyn("crumb", 0xb39c84, 0x9a7a66)
    static let red = hexColor(0xb62026)
    static let redEdge = dyn("redEdge", 0xd14935, 0xc43a2c)
    static let onRed = hexColor(0xfff4e6)
    static let orange = dyn("orange", 0xf06a22, 0xc4461a)
    static let gold = dyn("gold", 0xe7bc35, 0x8f650a)
    static let goldBackground = dyn("goldBg", 0x211a0e, 0xfaf0d6)
    static let goldLine = dyn("goldLine", 0x65501f, 0xdcbf72)
    static let selected = dyn("selected", 0x35161b, 0xf6dcd8)
    static let outline = dyn("outline", 0x33312e, 0xdcc8c0)
    static let control = dyn("control", 0x18191b, 0xfffdfb)
    static let controlLine = dyn("controlLine", 0x39332d, 0xdfcbc2)
    static let controlText = dyn("controlText", 0xc5bbb0, 0x4a3a36)
    static let field = dyn("field", 0x0a0b0d, 0xfffdfb)
    static let fieldLine = dyn("fieldLine", 0x48312f, 0xe0c3bd)
    static let card = dyn("card", 0x171412, 0xfffaf6)
    static let cardLine = dyn("cardLine", 0x4b352b, 0xe6cfc4)
    static let cardText = dyn("cardText", 0xdbcec0, 0x3a2824)
    static let sidebarTop = dyn("sidebarTop", 0x51161c, 0xf2d2ce)
    static let sidebarMid = dyn("sidebarMid", 0x241215, 0xf8e8e5)
    static let sidebarBottom = dyn("sidebarBottom", 0x101113, 0xfcf8f5)
    static let accountRule = dyn("accountRule", 0x49312c, 0xe6d2cb)
    static let stripeGap = dyn("stripeGap", 0x0a0b0d, 0xf7f3ee)
    static let backdropInk = dyn("backdropInk", 0xa88470, 0x7a4a3a)
    static let yellow = dyn("yellow", 0xe7bc35, 0xd9a520)

    static func mono(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont { .monospacedSystemFont(ofSize: size, weight: weight) }
    static func ui(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont { NSFont(name: weight.rawValue >= NSFont.Weight.semibold.rawValue ? "PingFangSC-Semibold" : weight.rawValue >= NSFont.Weight.medium.rawValue ? "PingFangSC-Medium" : "PingFangSC-Regular", size: size) ?? .systemFont(ofSize: size, weight: weight) }
    static func title(_ size: CGFloat) -> NSFont { IntroFonts.mincho(size) }
    static func label(_ text: String, _ font: NSFont, _ color: NSColor, kern: CGFloat = 0) -> NSTextField {
        let label = NSTextField(labelWithString: text); label.font = font; label.textColor = color
        if kern != 0 { label.attributedStringValue = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .kern: kern]) }
        return label
    }
    static func set(_ label: NSTextField, _ text: String, kern: CGFloat) {
        label.attributedStringValue = NSAttributedString(string: text, attributes: [.font: label.font ?? mono(9), .foregroundColor: label.textColor ?? ink, .kern: kern])
    }
}

private func stroke(_ rect: NSRect, _ color: NSColor, radius: CGFloat, width: CGFloat = 1) {
    let path = NSBezierPath(roundedRect: rect.insetBy(dx: width / 2, dy: width / 2), xRadius: radius, yRadius: radius); path.lineWidth = width; color.setStroke(); path.stroke()
}
private func fill(_ rect: NSRect, _ color: NSColor, radius: CGFloat) { color.setFill(); NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill() }

// MARK: Buttons

final class EVAButton: NSButton {
    enum Kind { case primary, selected, outline, ghost, gold, card, chip }
    var kind: Kind = .outline { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    var trailing: String? { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    var caption: String? { didSet { needsDisplay = true } }
    var leftAligned = false { didSet { needsDisplay = true } }
    private var hovering = false
    convenience init() { self.init(frame: .zero); setUp() }
    convenience init(_ title: String, kind: Kind, target: AnyObject?, action: Selector?) {
        self.init(frame: .zero); setUp(); self.title = title; self.kind = kind; self.target = target; self.action = action
    }
    private func setUp() { isBordered = false; bezelStyle = .regularSquare; setButtonType(.momentaryPushIn); focusRingType = .none; imagePosition = .noImage }
    override var title: String { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    override var isEnabled: Bool { didSet { needsDisplay = true } }
    var titleFont: NSFont {
        switch kind {
        case .primary: return EVAStyle.ui(13, .medium)
        case .gold, .ghost, .chip: return EVAStyle.ui(11)
        case .card: return EVAStyle.ui(12.5, .medium)
        default: return EVAStyle.ui(12)
        }
    }
    override var intrinsicContentSize: NSSize {
        if kind == .card { return NSSize(width: 122, height: 64) }
        let width = (title as NSString).size(withAttributes: [.font: titleFont]).width + (trailing == nil ? 0 : 22)
        let pad: CGFloat = kind == .ghost ? 8 : kind == .chip ? 9 : 14
        return NSSize(width: ceil(width + pad * 2), height: kind == .primary ? 34 : kind == .chip ? 24 : 30)
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas(); trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        let r = bounds, hot = hovering && isEnabled, pressed = isHighlighted
        var background: NSColor = .clear, line: NSColor = .clear, text = EVAStyle.ink, radius: CGFloat = 2
        switch kind {
        case .primary: background = pressed ? EVAStyle.red.blended(withFraction: 0.2, of: .black)! : hot ? EVAStyle.red.blended(withFraction: 0.12, of: .white)! : EVAStyle.red; line = EVAStyle.redEdge; text = EVAStyle.onRed
        case .selected: background = EVAStyle.selected; line = EVAStyle.red; radius = 3
        case .outline: background = hot ? EVAStyle.selected.withAlphaComponent(0.55) : .clear; line = hot ? EVAStyle.redEdge : EVAStyle.outline; text = EVAStyle.controlText; radius = 2
        case .ghost: background = hot ? EVAStyle.outline.withAlphaComponent(0.35) : .clear; text = hot ? EVAStyle.ink : EVAStyle.faint; radius = 3
        case .gold: background = hot ? EVAStyle.goldBackground.blended(withFraction: 0.15, of: EVAStyle.gold)! : EVAStyle.goldBackground; line = hot ? EVAStyle.goldLine : .clear; text = EVAStyle.gold; radius = 3
        case .chip: background = EVAStyle.gold.withAlphaComponent(0.04); line = EVAStyle.goldLine; text = EVAStyle.gold; radius = 4
        case .card: background = hot ? EVAStyle.card.blended(withFraction: 0.25, of: EVAStyle.red)! : EVAStyle.card; line = hot ? EVAStyle.redEdge : EVAStyle.cardLine; text = EVAStyle.cardText
        }
        NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
        if !isEnabled { NSGraphicsContext.current?.cgContext.setAlpha(0.42) }
        if background != .clear { fill(r, background, radius: radius) }
        if line != .clear { stroke(r, line, radius: radius) }
        if kind == .card {
            (caption ?? "").draw(at: NSPoint(x: 18, y: 14), withAttributes: [.font: EVAStyle.mono(8), .foregroundColor: EVAStyle.orange, .kern: 0.8])
            title.draw(at: NSPoint(x: 18, y: 32), withAttributes: [.font: titleFont, .foregroundColor: text])
            return
        }
        let attributes: [NSAttributedString.Key: Any] = [.font: titleFont, .foregroundColor: text]
        let size = (title as NSString).size(withAttributes: attributes)
        let x = leftAligned ? 15 : (r.width - size.width - (trailing == nil ? 0 : 22)) / 2
        title.draw(at: NSPoint(x: x, y: (r.height - size.height) / 2), withAttributes: attributes)
        if let trailing {
            let mark = NSAttributedString(string: trailing, attributes: [.font: EVAStyle.ui(15), .foregroundColor: kind == .primary ? EVAStyle.onRed.withAlphaComponent(0.85) : text])
            let markSize = mark.size(); mark.draw(at: NSPoint(x: leftAligned ? r.width - markSize.width - 14 : x + size.width + 8, y: (r.height - markSize.height) / 2))
        }
    }
    override var isFlipped: Bool { true }
}

final class EVAPopUp: NSPopUpButton {
    private var hovering = false
    override init(frame: NSRect, pullsDown: Bool) { super.init(frame: frame, pullsDown: pullsDown); isBordered = false; focusRingType = .none; font = EVAStyle.ui(11) }
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsetsZero }
    required init?(coder: NSCoder) { fatalError() }
    override var intrinsicContentSize: NSSize {
        let width = ((titleOfSelectedItem ?? "") as NSString).size(withAttributes: [.font: EVAStyle.ui(11)]).width
        return NSSize(width: min(260, ceil(width + 36)), height: 30)
    }
    override func select(_ item: NSMenuItem?) { super.select(item); invalidateIntrinsicContentSize(); needsDisplay = true }
    override func selectItem(at index: Int) { super.selectItem(at: index); invalidateIntrinsicContentSize(); needsDisplay = true }
    override var isEnabled: Bool { didSet { needsDisplay = true } }
    override func updateTrackingAreas() {
        super.updateTrackingAreas(); trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
        if !isEnabled { NSGraphicsContext.current?.cgContext.setAlpha(0.45) }
        fill(bounds, EVAStyle.control, radius: 2); stroke(bounds, hovering && isEnabled ? EVAStyle.redEdge : EVAStyle.controlLine, radius: 2)
        let attributes: [NSAttributedString.Key: Any] = [.font: EVAStyle.ui(11), .foregroundColor: EVAStyle.controlText]
        let title = NSAttributedString(string: titleOfSelectedItem ?? "", attributes: attributes), size = title.size()
        NSGraphicsContext.current?.cgContext.saveGState(); NSBezierPath(rect: NSRect(x: 8, y: 0, width: max(0, bounds.width - 30), height: bounds.height)).addClip()
        title.draw(at: NSPoint(x: 10, y: (bounds.height - size.height) / 2)); NSGraphicsContext.current?.cgContext.restoreGState()
        let chevron = NSBezierPath(), cx = bounds.width - 14, cy = bounds.height / 2
        chevron.move(to: NSPoint(x: cx - 4, y: cy - 2)); chevron.line(to: NSPoint(x: cx, y: cy + 2)); chevron.line(to: NSPoint(x: cx + 4, y: cy - 2))
        chevron.lineWidth = 1.4; EVAStyle.controlText.setStroke(); chevron.stroke()
    }
    override var isFlipped: Bool { true }
}

final class EVASegmented: NSSegmentedControl {
    override var isFlipped: Bool { true }
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsetsZero }
    override var intrinsicContentSize: NSSize {
        var width: CGFloat = 0
        for index in 0..<segmentCount { width += ((label(forSegment: index) ?? "") as NSString).size(withAttributes: [.font: EVAStyle.ui(11)]).width + 24 }
        return NSSize(width: ceil(width), height: 30)
    }
    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
        if !isEnabled { NSGraphicsContext.current?.cgContext.setAlpha(0.55) }
        fill(bounds, EVAStyle.control, radius: 2)
        let total = max(1, intrinsicContentSize.width), scale = bounds.width / total; var x: CGFloat = 0
        for index in 0..<segmentCount {
            let text = label(forSegment: index) ?? "", width = (((text as NSString).size(withAttributes: [.font: EVAStyle.ui(11)]).width + 24) * scale)
            let rect = NSRect(x: x, y: 0, width: width, height: bounds.height), on = isSelected(forSegment: index)
            if on { fill(rect.insetBy(dx: 1, dy: 1), EVAStyle.selected, radius: 2); EVAStyle.red.setFill(); NSRect(x: rect.minX + 1, y: rect.maxY - 3, width: rect.width - 2, height: 2).fill() }
            let string = NSAttributedString(string: text, attributes: [.font: EVAStyle.ui(11, on ? .medium : .regular), .foregroundColor: on ? EVAStyle.ink : EVAStyle.faint]), size = string.size()
            string.draw(at: NSPoint(x: rect.midX - size.width / 2, y: (rect.height - size.height) / 2))
            x += width
        }
        stroke(bounds, EVAStyle.controlLine, radius: 2)
    }
}

// MARK: Surfaces

final class FieldBox: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) { fill(bounds, EVAStyle.field, radius: 2); stroke(bounds, EVAStyle.fieldLine, radius: 2) }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}

/// Flat bar with optional bottom/top rules (header, session bar, composer frame).
final class BarSurface: NSView {
    var color: NSColor = .clear, bottomRule: NSColor?, topRule: NSColor?, topWeight: CGFloat = 1, hazardTop = false
    override var isFlipped: Bool { true }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        if color != .clear { color.setFill(); bounds.fill() }
        if let bottomRule { bottomRule.setFill(); NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill() }
        if let topRule { topRule.setFill(); NSRect(x: 0, y: 0, width: bounds.width, height: topWeight).fill() }
        if hazardTop { Hazard.draw(in: NSRect(x: 0, y: 0, width: bounds.width, height: 4), colors: (EVAStyle.yellow, EVAStyle.stripeGap), band: 9, slant: 6) }
    }
}

enum Hazard {
    static func draw(in rect: NSRect, colors: (NSColor, NSColor), band: CGFloat, slant: CGFloat, vertical: Bool = false) {
        NSGraphicsContext.saveGraphicsState(); NSBezierPath(rect: rect).addClip()
        colors.1.setFill(); rect.fill(); colors.0.setFill()
        if vertical {
            var y = rect.minY - rect.width - band * 2
            while y < rect.maxY + band { let p = NSBezierPath(); p.move(to: NSPoint(x: rect.minX, y: y)); p.line(to: NSPoint(x: rect.maxX, y: y + slant)); p.line(to: NSPoint(x: rect.maxX, y: y + slant + band * 0.48)); p.line(to: NSPoint(x: rect.minX, y: y + band * 0.48)); p.close(); p.fill(); y += band }
        } else {
            var x = rect.minX - rect.height - band * 2
            while x < rect.maxX + band { let p = NSBezierPath(); p.move(to: NSPoint(x: x, y: rect.maxY)); p.line(to: NSPoint(x: x + slant, y: rect.minY)); p.line(to: NSPoint(x: x + slant + band * 0.5, y: rect.minY)); p.line(to: NSPoint(x: x + band * 0.5, y: rect.maxY)); p.close(); p.fill(); x += band }
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}

/// Red/black chevron armour strip along the window edges (body::before in the web version).
final class EdgeStripe: NSView {
    override var isFlipped: Bool { true }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) { Hazard.draw(in: bounds, colors: (EVAStyle.red, EVAStyle.stripeGap), band: 13, slant: 7, vertical: true) }
}

final class SidebarSurface: NSView {
    override var isFlipped: Bool { true }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        let h = max(bounds.height, 360)
        let gradient = NSGradient(colorsAndLocations: (EVAStyle.sidebarTop, 0), (EVAStyle.sidebarMid, 170 / h), (EVAStyle.sidebarBottom, 350 / h), (EVAStyle.sidebarBottom, 1))
        gradient?.draw(in: bounds, angle: 90 + 12)
        EVAStyle.headerRule.setFill(); NSRect(x: bounds.width - 1, y: 0, width: 1, height: bounds.height).fill()
    }
}

/// Small "02 LOCAL SYSTEM" mark used in the sidebar identity (same placeholder as the public SVG).
final class MarkView: NSView {
    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 46, height: 46) }
    override func draw(_ dirtyRect: NSRect) {
        guard let c = NSGraphicsContext.current?.cgContext else { return }
        let palette = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .aqua ? IntroPalette.light : IntroPalette.dark
        IntroScene(size: bounds.size, palette: palette, connected: true).nervMark(c, x: 0, y: 0, size: min(bounds.width, bounds.height))
    }
}

final class StatusFooter: NSView {
    let status = EVAStyle.label("", EVAStyle.mono(9), EVAStyle.faint)
    override var isFlipped: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        let center = EVAStyle.label("EVANGELION-02", EVAStyle.mono(8.5), EVAStyle.orange, kern: 1.2)
        for view in [center, status] as [NSView] { view.translatesAutoresizingMaskIntoConstraints = false; addSubview(view) }
        status.lineBreakMode = .byTruncatingTail; status.alignment = .right
        NSLayoutConstraint.activate([center.centerXAnchor.constraint(equalTo: centerXAnchor, constant: 8), center.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -1),
            status.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -32), status.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -1), status.widthAnchor.constraint(lessThanOrEqualToConstant: 420)])
    }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        EVAStyle.header.setFill(); bounds.fill()
        EVAStyle.sessionRule.setFill(); NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
        EVAStyle.red.setFill(); NSRect(x: 0, y: bounds.height - 3, width: bounds.width, height: 3).fill()
        Hazard.draw(in: NSRect(x: 32, y: bounds.height / 2 - 4, width: 42, height: 5), colors: (EVAStyle.yellow, EVAStyle.header), band: 10, slant: 3)
        EVAStyle.orange.setFill(); NSRect(x: bounds.width / 2 - 66, y: bounds.height / 2 - 3.5, width: 4, height: 4).fill()
    }
}

// MARK: Backdrop

/// Background art behind the conversation: the user's own image (kept local, never bundled) or an original
/// procedural pencil-linework texture; drawn right-aligned and faded towards the conversation column.
final class Backdrop: NSView {
    enum Mode: String { case linework, custom, none }
    static var mode: Mode { Mode(rawValue: UserDefaults.standard.string(forKey: "native.backdrop") ?? "linework") ?? .linework }
    static var customPath: String? { UserDefaults.standard.string(forKey: "native.backdropImage") }
    private var cacheKey = "", cached: CGImage?
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); cacheKey = ""; needsDisplay = true }
    func reload() { cacheKey = ""; needsDisplay = true }
    var isLight: Bool { effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .aqua }

    override func draw(_ dirtyRect: NSRect) {
        guard Backdrop.mode != .none, bounds.width > 200, bounds.height > 200, let c = NSGraphicsContext.current?.cgContext else { return }
        let artHeight = bounds.height, artWidth = min(bounds.width * 0.62, artHeight * 0.95)
        let key = "\(Backdrop.mode.rawValue)|\(Backdrop.customPath ?? "")|\(Int(artWidth))x\(Int(artHeight))|\(isLight)"
        if key != cacheKey { cacheKey = key; cached = Backdrop.mode == .custom ? customImage(size: CGSize(width: artWidth, height: artHeight)) : linework(size: CGSize(width: artWidth, height: artHeight)) }
        guard let image = cached else { return }
        let rect = CGRect(x: bounds.width - artWidth, y: 0, width: artWidth, height: artHeight)
        c.saveGState(); c.translateBy(x: 0, y: bounds.height); c.scaleBy(x: 1, y: -1)
        let flipped = CGRect(x: rect.minX, y: bounds.height - rect.maxY, width: rect.width, height: rect.height)
        // Fade in from the left edge of the art so text in the conversation column stays readable.
        if let mask = Backdrop.fadeMask(width: Int(artWidth)) { c.clip(to: flipped, mask: mask) }
        c.setAlpha(Backdrop.mode == .custom ? (isLight ? 0.18 : 0.24) : 1); c.draw(image, in: flipped); c.restoreGState()
    }

    static func fadeMask(width: Int) -> CGImage? {
        let w = max(2, width), space = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(data: nil, width: w, height: 1, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        guard let gradient = CGGradient(colorsSpace: space, colors: [CGColor(gray: 0, alpha: 1), CGColor(gray: 1, alpha: 1), CGColor(gray: 1, alpha: 1)] as CFArray, locations: [0, 0.45, 1]) else { return nil }
        ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: w, y: 0), options: []); return ctx.makeImage()
    }

    // Original abstract study: loose graphite strands sweeping down and across, plus construction lines.
    func linework(size: CGSize) -> CGImage? {
        let scale = window?.backingScaleFactor ?? 2, w = Int(size.width * scale), h = Int(size.height * scale)
        guard w > 0, h > 0, let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        c.scaleBy(x: scale, y: scale); c.setLineCap(.round)
        var seed: UInt64 = 0x02E0A0230
        func rnd() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat((seed >> 33) & 0xffffff) / CGFloat(0xffffff) }
        let ink = (isLight ? hexColor(0x6a3a2e) : hexColor(0xb08a74)).usingColorSpace(.sRGB)!
        let W = size.width, H = size.height
        // Construction lines.
        c.setStrokeColor(ink.withAlphaComponent(isLight ? 0.10 : 0.12).cgColor); c.setLineWidth(0.8)
        for i in 0..<5 { let x = W * (0.25 + CGFloat(i) * 0.17); c.move(to: CGPoint(x: x, y: H)); c.addLine(to: CGPoint(x: x + W * 0.32, y: H * 0.62)); c.addLine(to: CGPoint(x: x - W * 0.05, y: H * 0.18)); c.addLine(to: CGPoint(x: x + W * 0.28, y: -10)); c.strokePath() }
        // Strand clusters: each cluster flows from an origin near the top-right towards the lower left.
        for cluster in 0..<9 {
            let ox = W * (0.42 + rnd() * 0.6), oy = H * (1.02 - rnd() * 0.12), sweep = 0.55 + rnd() * 0.5, bend = (rnd() - 0.5) * W * 0.5
            let count = 34 + Int(rnd() * 26)
            for s in 0..<count {
                let spread = (CGFloat(s) / CGFloat(count) - 0.5) * W * 0.28, jitter = (rnd() - 0.5) * 18
                let start = CGPoint(x: ox + spread * 0.35 + jitter, y: oy + jitter * 0.3)
                let end = CGPoint(x: ox - W * sweep * 0.55 + spread + jitter * 2, y: oy - H * (0.45 + rnd() * 0.45))
                let c1 = CGPoint(x: start.x - W * 0.08 + bend * 0.4, y: start.y - H * 0.18), c2 = CGPoint(x: end.x + bend + spread * 0.6, y: end.y + H * 0.22)
                c.setStrokeColor(ink.withAlphaComponent((isLight ? 0.05 : 0.06) + rnd() * (isLight ? 0.14 : 0.18)).cgColor)
                c.setLineWidth(0.45 + rnd() * 1.1); c.move(to: start); c.addCurve(to: end, control1: c1, control2: c2); c.strokePath()
            }
            if cluster % 3 == 0 {   // short cross-hatching on the darkest cluster areas
                c.setStrokeColor(ink.withAlphaComponent(isLight ? 0.08 : 0.1).cgColor); c.setLineWidth(0.5)
                for _ in 0..<40 { let x = ox - rnd() * W * 0.4, y = oy - rnd() * H * 0.5; c.move(to: CGPoint(x: x, y: y)); c.addLine(to: CGPoint(x: x + 9 + rnd() * 8, y: y - 6 - rnd() * 6)); c.strokePath() }
            }
        }
        return c.makeImage()
    }

    // User-supplied image: aspect-fill, desaturated, inverted when needed so lines read on the current theme.
    func customImage(size: CGSize) -> CGImage? {
        guard let path = Backdrop.customPath, let ns = NSImage(contentsOfFile: path), let cg = ns.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return linework(size: size) }
        var image = CIImage(cgImage: cg).applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.15])
        let average = image.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: image.extent)])
        var pixel = [UInt8](repeating: 0, count: 4), context = CIContext()
        context.render(average, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        let luminance = (0.3 * Double(pixel[0]) + 0.59 * Double(pixel[1]) + 0.11 * Double(pixel[2])) / 255
        if isLight ? luminance < 0.5 : luminance > 0.5 { image = image.applyingFilter("CIColorInvert") }
        let scale = (window?.backingScaleFactor ?? 2), target = CGSize(width: size.width * scale, height: size.height * scale)
        let factor = max(target.width / image.extent.width, target.height / image.extent.height)
        image = image.transformed(by: CGAffineTransform(scaleX: factor, y: factor))
        let crop = CGRect(x: image.extent.maxX - target.width, y: image.extent.midY - target.height / 2, width: target.width, height: target.height)
        context = CIContext(); return context.createCGImage(image, from: crop)
    }
}
