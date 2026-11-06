import AppKit
import AVFoundation
import CoreText

// Native port of the web workbench's 20-second boot sequence (unified-sequence.js / intro-cg.js):
// NERV boot → LCL fill → pilot synchronisation (holds at 99.2 % for confirmation) → partition
// rewrite into "connecting" → hand-off to the real workbench. Drawn with CoreGraphics; no WebKit.

/// Reads a boolean preference that defaults to on; accepts YES/NO/1/0 from the command-line argument domain too.
func introFlag(_ key: String) -> Bool { UserDefaults.standard.object(forKey: key) == nil ? true : UserDefaults.standard.bool(forKey: key) }

enum IntroTiming {
    static let duration = 20.0, lclStart = 3.0, lclEnd = 6.4, lclClearStart = 6.8, lclClearEnd = 9.2
    static let syncStart = 8.8, syncFull = 14.1, hold = 13.3, transferStart = 14.35, transferEnd = 15.45
    static let handoffStart = 18.6, handoffEnd = 19.85, fadeStart = 19.85
}
func introCurve(_ x: Double) -> Double { let x = min(1, max(0, x)); return x * x * x * (x * (x * 6 - 15) + 10) }
func introStage(_ t: Double, _ a: Double, _ b: Double) -> Double { introCurve((t - a) / (b - a)) }
private func loopTime(_ t: Double, _ period: Double) -> Double { let p = t / period, lap = floor(p); return lap + introCurve(p - lap) }
private func breathe(_ t: Double, _ period: Double) -> Double { (1 - cos(loopTime(t, period) * .pi * 2)) / 2 }
private func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double { let t = min(1, max(0, (x - a) / (b - a))); return t * t * (3 - 2 * t) }
private func hash(_ x: Double, _ y: Double) -> Double { let v = sin(x * 127.1 + y * 311.7) * 43758.5453; return v - floor(v) }
private func hex(_ value: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((value >> 16) & 0xff) / 255, green: CGFloat((value >> 8) & 0xff) / 255, blue: CGFloat(value & 0xff) / 255, alpha: alpha)
}

struct IntroPalette {
    let light: Bool
    let background, ink, red, orange, yellow, grid, rule, hexInk, hexLabel, hexLiquid, hexLabelLiquid, track, highlight: NSColor
    let subtle, brandSub, ringLabel, linkText, stripe, lclTop, lclMid, lclBottom, lclLight, bubble, surface, caption: NSColor
    let linkOn, linkOff, linkArcOn, linkArcOff, linkAccent, cardBackground, cardText, cardMuted, cardRule: NSColor
    let lclAlpha: CGFloat
    // The original web sequence (black / red).
    static let dark = IntroPalette(light: false, background: hex(0x090b0c), ink: hex(0xe8e2d7), red: hex(0xb62026), orange: hex(0xf06a22), yellow: hex(0xe7bc35),
        grid: hex(0xe8e2d7, 0.022), rule: hex(0x5a2527), hexInk: hex(0xc52b2e), hexLabel: hex(0xf07864), hexLiquid: hex(0xffb05c), hexLabelLiquid: hex(0x582115),
        track: hex(0x452126), highlight: hex(0xfff0d4), subtle: hex(0xb39b8a), brandSub: hex(0xd6aaa0), ringLabel: hex(0xbaa18d), linkText: hex(0xc69a73), stripe: hex(0x9a1c25),
        lclTop: hex(0xf6a343), lclMid: hex(0xc76523), lclBottom: hex(0x8c321a), lclLight: hex(0xffd195), bubble: hex(0xffdbad), surface: hex(0xffd49a), caption: hex(0xeee6dc),
        linkOn: hex(0xaa795d, 0.63), linkOff: hex(0x6c5957, 0.5), linkArcOn: hex(0xceab97), linkArcOff: hex(0x907775), linkAccent: hex(0x68beda, 0.44),
        cardBackground: hex(0x111315, 0.96), cardText: hex(0xeee6dc), cardMuted: hex(0xc59d86), cardRule: hex(0x6d392c), lclAlpha: 0.72)
    // Red / white variant for the light theme: paper background, dark ink, deeper accents for contrast.
    static let light = IntroPalette(light: true, background: hex(0xf5f0e9), ink: hex(0x2b1a1a), red: hex(0xb62026), orange: hex(0xc4461a), yellow: hex(0xb8860b),
        grid: hex(0x2b1a1a, 0.05), rule: hex(0xd8b4ae), hexInk: hex(0xc52b2e), hexLabel: hex(0xa3202a), hexLiquid: hex(0x8c2a10), hexLabelLiquid: hex(0xfff3e4),
        track: hex(0xead0ca), highlight: hex(0xffffff), subtle: hex(0x8c6f63), brandSub: hex(0xa0645a), ringLabel: hex(0x8c6f63), linkText: hex(0x9a6a48), stripe: hex(0xd23a40),
        lclTop: hex(0xffc47e), lclMid: hex(0xf08c3e), lclBottom: hex(0xc8521f), lclLight: hex(0xfff1d6), bubble: hex(0xffffff), surface: hex(0xffe2b8), caption: hex(0x3a2422),
        linkOn: hex(0xb07a5c, 0.7), linkOff: hex(0x9c8784, 0.6), linkArcOn: hex(0x9a5c3c), linkArcOff: hex(0xa48d8a), linkAccent: hex(0x2f8fb0, 0.5),
        cardBackground: hex(0xffffff, 0.97), cardText: hex(0x2b1a1a), cardMuted: hex(0x8c6f63), cardRule: hex(0xe3c3bd), lclAlpha: 0.62)
}

enum IntroFonts {
    static let registered: Bool = {
        guard let url = Bundle.main.url(forResource: "unit02-mincho-black", withExtension: "woff2") else { return false }
        return CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }()
    static func mincho(_ size: CGFloat) -> NSFont { _ = registered; return NSFont(name: "Unit02Mincho-Black", size: size) ?? NSFont(name: "STSongti-SC-Black", size: size) ?? .boldSystemFont(ofSize: size) }
    static func sans(_ size: CGFloat, weight: NSFont.Weight = .medium) -> NSFont { NSFont(name: weight == .bold ? "PingFangSC-Semibold" : "PingFangSC-Medium", size: size) ?? .systemFont(ofSize: size, weight: weight) }
    static func display(_ size: CGFloat) -> NSFont { NSFont(name: "DINAlternate-Bold", size: size) ?? .boldSystemFont(ofSize: size) }
    static func serif(_ size: CGFloat) -> NSFont { NSFont(name: "Times New Roman", size: size) ?? NSFont(name: "Times", size: size) ?? .systemFont(ofSize: size) }
}

struct IntroCue { let start, end: Double; let ja, zh: String }
enum IntroMedia {
    static let cues: [IntroCue] = {
        guard let url = Bundle.main.url(forResource: "intro-timeline", withExtension: "json"), let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let cues = root["cues"] as? [[String: Any]] else { return [] }
        return cues.compactMap { c in guard let s = c["start"] as? Double, let e = c["end"] as? Double else { return nil }; return IntroCue(start: s, end: e, ja: c["ja"] as? String ?? "", zh: c["zh"] as? String ?? "") }
    }()
    static var voiceURL: URL? { Bundle.main.url(forResource: "intro-voice", withExtension: "wav") }
}

// MARK: - Scene drawing (flipped coordinates, origin top-left, units = points)

struct IntroScene {
    let size: CGSize, palette: IntroPalette, connected: Bool
    var w: CGFloat { size.width }
    var h: CGFloat { size.height }
    var mobile: Bool { w < 900 }
    var pad: CGFloat { mobile ? 25 : max(45, w * 0.045) }
    var cx: CGFloat { w / 2 }
    var cy: CGFloat { h * 0.45 }
    var ringRadius: CGFloat { min(w * (mobile ? 0.27 : 0.14), h * (h < 650 ? 0.15 : 0.19), mobile ? 150 : 195) }
    var linkSize: CGFloat { mobile ? 58 : 68 }
    var cardBottom: CGFloat { h < 600 ? 28 : h < 700 ? 40 : h < 800 ? 54 : h < 1050 ? 64 : 144 }

    // Canvas-style text: y is the alphabetic baseline.
    func text(_ s: String, _ x: CGFloat, _ y: CGFloat, _ font: NSFont, _ color: NSColor, align: NSTextAlignment = .left, alpha: CGFloat = 1) {
        let string = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color.withAlphaComponent(color.alphaComponent * alpha)])
        let width = string.size().width, left = align == .center ? x - width / 2 : align == .right ? x - width : x
        string.draw(at: NSPoint(x: left, y: y - font.ascender))
    }
    func line(_ c: CGContext, _ x: CGFloat, _ y: CGFloat, _ x2: CGFloat, _ y2: CGFloat, _ color: NSColor, width: CGFloat = 1) {
        c.setStrokeColor(color.cgColor); c.setLineWidth(width); c.beginPath(); c.move(to: CGPoint(x: x, y: y)); c.addLine(to: CGPoint(x: x2, y: y2)); c.strokePath()
    }

    func nervMark(_ c: CGContext, x: CGFloat, y: CGFloat, size s: CGFloat) {
        let k = s / 400; c.saveGState(); c.translateBy(x: x, y: y)
        c.setStrokeColor(palette.red.cgColor); c.setLineWidth(12 * k); c.setLineJoin(.miter)
        c.beginPath(); c.move(to: CGPoint(x: 45 * k, y: 50 * k)); c.addLine(to: CGPoint(x: 355 * k, y: 50 * k)); c.addLine(to: CGPoint(x: 355 * k, y: 300 * k))
        c.addLine(to: CGPoint(x: 305 * k, y: 350 * k)); c.addLine(to: CGPoint(x: 45 * k, y: 350 * k)); c.closePath(); c.strokePath()
        text("02", 200 * k, 235 * k, IntroFonts.serif(144 * k), palette.red, align: .center)
        text("LOCAL SYSTEM", 200 * k, 310 * k, .systemFont(ofSize: 23 * k), palette.red, align: .center)
        c.restoreGState()
    }

    func atmosphere(_ c: CGContext, _ t: Double, liquid: Bool, base: CGFloat = 1) {
        let fade = base * CGFloat(introStage(t, 0.3, 1.8) * (1 - introStage(t, 18.2, 19.4))); guard fade > 0 else { return }
        let size = min(w * (mobile ? 0.09 : 0.065), h * 0.095, max(12, (h * 0.5 - 110) / 4.1)), ink = liquid ? palette.hexLiquid : palette.hexInk
        func hexagon(_ r: CGFloat) { c.beginPath(); for i in 0..<6 { let a = CGFloat.pi / 3 * CGFloat(i), p = CGPoint(x: cos(a) * r, y: sin(a) * r * 0.72); i == 0 ? c.move(to: p) : c.addLine(to: p) }; c.closePath() }
        for side in 0..<2 { for row in 0..<5 {
            let x = w * (side == 1 ? 0.87 : 0.13), y = h * 0.5 + CGFloat(row - 2) * size * 1.65
            let phase = t / (2.7 + Double(row) * 0.3) + Double(row) * 0.29 + Double(side) * 0.43
            let pulse = CGFloat(pow((1 + sin(phase * .pi * 2)) / 2, 5)), a = (liquid ? 0.045 : 0.035) + pulse * (liquid ? 0.20 : 0.22)
            c.saveGState(); c.translateBy(x: x, y: y)
            c.setAlpha(fade * a); c.setFillColor(ink.cgColor); hexagon(size); c.fillPath()
            c.setAlpha(min(1, fade * a * 1.5)); c.setStrokeColor(ink.cgColor); c.setLineWidth(0.9); hexagon(size + 5); c.strokePath()
            c.setAlpha(min(1, a * 0.5 * fade)); c.setStrokeColor(palette.background.cgColor)
            var yy = -size * 0.55; while yy < size * 0.56 { let half = size * (1 - abs(yy) / (size * 1.45)); line(c, -half, yy, half, yy, palette.background, width: 0.9); yy += 4 }
            c.setFillColor(ink.cgColor)
            for j in 0..<5 { let lit = (j + row + side) % 3 == Int(floor(t * 0.8)) % 3; c.setAlpha(fade * a * (0.35 + (lit ? 0.65 : 0))); c.fill(CGRect(x: -size + CGFloat(j) * size * 0.43, y: size * 0.78, width: size * 0.30, height: 2)) }
            let label = (Int(floor(t / 1.4)) + row + side) % 2 == 0 ? "WARNING" : "EMERGENCY"
            c.setAlpha(1); let labelAlpha = fade * (liquid ? 0.35 + pulse * 0.45 : 0.15 + pulse * 0.5)
            var font = IntroFonts.display(max(9, min(25, size * 0.26)))
            while NSAttributedString(string: label, attributes: [.font: font]).size().width > size * 1.65 && font.pointSize > 7 { font = IntroFonts.display(font.pointSize - 1) }
            text(label, 0, font.capHeight / 2, font, liquid ? palette.hexLabelLiquid : palette.hexLabel, align: .center, alpha: labelAlpha)
            c.restoreGState()
        } }
    }

    func codexLink(_ c: CGContext, x: CGFloat, y: CGFloat, size: CGFloat, t: Double) {
        c.saveGState(); c.translateBy(x: x, y: y)
        let radius = size * 0.77, angle = CGFloat(loopTime(t, 6) * .pi * 2), pulse = CGFloat(1 + 0.022 * breathe(t, 3.8))
        c.setLineWidth(max(1, size / 90))
        c.setStrokeColor((connected ? palette.linkOn : palette.linkOff).cgColor); c.strokeEllipse(in: CGRect(x: -radius * pulse, y: -radius * pulse, width: radius * pulse * 2, height: radius * pulse * 2))
        c.setStrokeColor((connected ? palette.linkArcOn : palette.linkArcOff).cgColor); c.beginPath(); c.addArc(center: .zero, radius: radius + size * 0.10, startAngle: angle, endAngle: angle + .pi * 2 * 0.7, clockwise: false); c.strokePath()
        c.setStrokeColor(palette.linkAccent.cgColor); c.beginPath(); c.addArc(center: .zero, radius: radius + size * 0.17, startAngle: -angle + 0.3, endAngle: -angle + 0.8, clockwise: false); c.strokePath()
        // Codex node: ring with </> chevrons, drawn as in media/official/codex-node.svg.
        let k = size / 400; c.translateBy(x: -size / 2, y: -size / 2); c.setStrokeColor(palette.ink.cgColor)
        c.setLineWidth(14 * k); c.strokeEllipse(in: CGRect(x: 60 * k, y: 60 * k, width: 280 * k, height: 280 * k))
        c.setLineWidth(16 * k); c.beginPath()
        c.move(to: CGPoint(x: 160 * k, y: 140 * k)); c.addLine(to: CGPoint(x: 105 * k, y: 200 * k)); c.addLine(to: CGPoint(x: 160 * k, y: 260 * k))
        c.move(to: CGPoint(x: 240 * k, y: 140 * k)); c.addLine(to: CGPoint(x: 295 * k, y: 200 * k)); c.addLine(to: CGPoint(x: 240 * k, y: 260 * k)); c.strokePath()
        c.restoreGState()
    }

    // Port of drawUnit02Scene. `closing` renders the "connecting / ready" target frame.
    func draw(_ c: CGContext, t: Double, closing: Bool) {
        let p = palette
        c.setFillColor(p.background.cgColor); c.fill(CGRect(origin: .zero, size: size))
        var x = pad; while x < w - pad { line(c, x, 92, x, h - 70, p.grid); x += 46 }
        var y: CGFloat = 92; while y < h - 70 { line(c, pad, y, w - pad, y, p.grid); y += 46 }
        atmosphere(c, t, liquid: false)

        let wake = CGFloat(introStage(t, 0, 1.8) * (1 - introStage(t, IntroTiming.lclStart, IntroTiming.lclEnd)))
        if wake > 0 {
            c.saveGState(); c.setAlpha(wake); c.beginTransparencyLayer(auxiliaryInfo: nil)
            let s = min(w * (mobile ? 0.46 : 0.27), h * 0.36, mobile ? 210 : 390), top = (h - s - (mobile ? 132 : 168)) / 2
            nervMark(c, x: cx - s / 2, y: top, size: s)
            text("系统唤醒", cx, top + s + (mobile ? 78 : 108), IntroFonts.mincho(mobile ? 46 : 76), p.ink, align: .center)
            text("EVANGELION-02 / ASUKA PRIVATE WORKSTATION", cx, top + s + (mobile ? 117 : 155), IntroFonts.sans(mobile ? 11 : 17), p.orange, align: .center)
            c.endTransparencyLayer(); c.restoreGState()
        }

        let syncAlpha = CGFloat(introStage(t, IntroTiming.syncStart, IntroTiming.syncStart + 0.7) * (closing ? 1 - introStage(t, IntroTiming.transferStart, IntroTiming.transferEnd) : 1))
        if syncAlpha > 0 {
            c.saveGState(); c.setAlpha(syncAlpha)
            let metric = 99.2 * introStage(t, IntroTiming.syncStart, IntroTiming.hold) + 0.8 * introStage(t, IntroTiming.hold, IntroTiming.syncFull)
            let r = ringRadius, color = metric / 100 > 0.98 ? p.yellow : p.orange, start = -CGFloat.pi / 2, end = start + .pi * 2 * CGFloat(metric / 100)
            c.setLineWidth(mobile ? 5 : 7); c.setStrokeColor(p.track.cgColor); c.strokeEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
            c.setLineCap(.round); c.setStrokeColor(color.cgColor)
            for (blur, width, alpha) in [(32.0, 15.0, 0.24), (16.0, 9.0, 0.5), (8.0, 4.0, 1.0)] as [(CGFloat, CGFloat, CGFloat)] {
                c.saveGState(); c.setAlpha(syncAlpha * alpha); c.setShadow(offset: .zero, blur: blur, color: color.cgColor); c.setLineWidth(width)
                c.beginPath(); c.addArc(center: CGPoint(x: cx, y: cy), radius: r, startAngle: start, endAngle: end, clockwise: false); c.strokePath(); c.restoreGState()
            }
            c.setStrokeColor(p.highlight.cgColor); c.setLineWidth(1.2); c.beginPath(); c.addArc(center: CGPoint(x: cx, y: cy), radius: r - 1, startAngle: start, endAngle: end, clockwise: false); c.strokePath(); c.setLineCap(.butt)
            if metric > 0 { c.saveGState(); c.setShadow(offset: .zero, blur: 18, color: color.cgColor); c.setFillColor(p.highlight.cgColor); c.fillEllipse(in: CGRect(x: cx + cos(end) * r - 2.8, y: cy + sin(end) * r - 2.8, width: 5.6, height: 5.6)); c.restoreGState() }
            text(String(format: "%.1f%%", metric), cx, cy + 10, IntroFonts.mincho(mobile ? 35 : 53), p.ink, align: .center)
            text("同步率", cx, cy + (mobile ? 58 : 68), IntroFonts.mincho(mobile ? 14 : 18), p.ringLabel, align: .center)
            c.restoreGState()
        }

        if closing {
            let a = CGFloat(introStage(t, IntroTiming.transferStart, IntroTiming.transferEnd))
            c.saveGState(); c.setAlpha(a)
            text("EVANGELION-02", cx, cy - 45, IntroFonts.mincho(mobile ? 30 : 52), p.red, align: .center)
            text(t < 16 ? "正在连接工作台" : "工作台已就绪", cx, cy + 58, IntroFonts.mincho(mobile ? 43 : 80), p.ink, align: .center)
            text(connected ? "CODEX / 本地连接已建立" : "CODEX / 等待连接", cx, cy + 112, IntroFonts.sans(mobile ? 11 : 14), p.linkText, align: .center)
            let k = CGFloat(introStage(t, IntroTiming.handoffStart, IntroTiming.handoffEnd))
            let lx = cx * (1 - k) + (w - pad) * k, ly = min(h - 90, cy + 215) * (1 - k) + 45 * k, ls = linkSize * (1 - k) + 16 * k
            codexLink(c, x: lx, y: ly, size: ls, t: t)
            c.restoreGState()
        }

        // LCL covers the whole viewport, including the typography, then clears.
        let fill = introStage(t, IntroTiming.lclStart, IntroTiming.lclEnd), liquid = CGFloat(fill > 0 ? 1 - introStage(t, IntroTiming.lclClearStart, IntroTiming.lclClearEnd) : 0)
        if liquid > 0 {
            let level = h * CGFloat(1 - fill), surface = CGMutablePath()
            for i in 0...100 { let px = w * CGFloat(i) / 100, py = level + CGFloat(sin(Double(i) * 0.115 + t * 0.65) * 5 + sin(Double(i) * 0.26 - t * 0.4) * 2); i == 0 ? surface.move(to: CGPoint(x: px, y: py)) : surface.addLine(to: CGPoint(x: px, y: py)) }
            let body = surface.mutableCopy()!; body.addLine(to: CGPoint(x: w, y: h)); body.addLine(to: CGPoint(x: 0, y: h)); body.closeSubpath()
            c.saveGState(); c.addPath(body); c.clip()
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            if let tint = CGGradient(colorsSpace: space, colors: [p.lclTop.cgColor, p.lclMid.cgColor, p.lclBottom.cgColor] as CFArray, locations: [0, 0.35, 1]) {
                c.setAlpha(p.lclAlpha * liquid); c.drawLinearGradient(tint, start: CGPoint(x: 0, y: max(0, level)), end: CGPoint(x: 0, y: h), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            }
            if let light = CGGradient(colorsSpace: space, colors: [p.lclLight.withAlphaComponent(0).cgColor, p.lclLight.cgColor, p.lclLight.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 0.45, 0.65]) {
                c.setAlpha(0.12 * liquid); c.drawLinearGradient(light, start: .zero, end: CGPoint(x: w, y: h), options: [])
            }
            c.setAlpha(0.27 * liquid); c.setStrokeColor(p.bubble.cgColor); c.setLineWidth(1)
            for i in 0..<17 { let bx = w * CGFloat((Double(i) * 0.137 + 0.08).truncatingRemainder(dividingBy: 1)), by = h - CGFloat((t * 0.045 + Double(i) * 0.161).truncatingRemainder(dividingBy: 1)) * h, r = 1.5 + CGFloat(i % 4); c.strokeEllipse(in: CGRect(x: bx - r, y: by - r, width: r * 2, height: r * 2)) }
            atmosphere(c, t, liquid: true, base: liquid)
            c.restoreGState()
            c.saveGState(); c.setAlpha(0.65 * liquid); c.addPath(surface); c.setStrokeColor(p.surface.cgColor); c.setLineWidth(1.4); c.strokePath(); c.restoreGState()
        }

        // Shared armour perimeter and header, repeated from the workbench frame.
        let brand: CGFloat = mobile ? 43 : 58, brandX = pad + brand + (mobile ? 10 : 16)
        nervMark(c, x: pad, y: 19, size: brand)
        text("EVANGELION-02", brandX, mobile ? 44 : 46, IntroFonts.mincho(mobile ? 16 : 22), p.ink)
        text("私人工作台", brandX, mobile ? 63 : 66, IntroFonts.sans(mobile ? 9 : 10), p.brandSub)
        text("二号机", w - pad, 47, IntroFonts.sans(19), p.orange, align: .right)
        text("ASUKA / 明日香", w - pad, 67, IntroFonts.sans(10), p.subtle, align: .right)
        line(c, pad, 85, w - pad, 85, p.rule)
        let phase = t < IntroTiming.lclStart ? "系统唤醒" : t < IntroTiming.syncStart ? "环境准备" : t < IntroTiming.transferStart ? "驾驶员同步" : "进入工作台"
        text(phase, pad, h - 30, IntroFonts.sans(11), p.subtle); text("本地私人界面", w - pad, h - 30, IntroFonts.sans(10), p.subtle, align: .right)
        for right in [false, true] {
            c.saveGState(); if right { c.translateBy(x: w, y: 0); c.scaleBy(x: -1, y: 1) }
            c.setFillColor(p.red.cgColor); c.fill(CGRect(x: 0, y: 0, width: mobile ? 6 : 10, height: h))
            c.clip(to: CGRect(x: mobile ? 10 : 16, y: 106, width: mobile ? 7 : 11, height: h - 185)); c.setFillColor(p.stripe.cgColor)
            var sy: CGFloat = 70; while sy < h { c.beginPath(); c.move(to: CGPoint(x: 5, y: sy)); c.addLine(to: CGPoint(x: 33, y: sy - 20)); c.addLine(to: CGPoint(x: 33, y: sy - 9)); c.addLine(to: CGPoint(x: 5, y: sy + 11)); c.fillPath(); sy += 28 }
            c.restoreGState()
        }
        for bottom in [false, true] {
            c.saveGState(); if bottom { c.translateBy(x: 0, y: h); c.scaleBy(x: 1, y: -1) }
            for i in 0..<(mobile ? 6 : 14) { c.saveGState(); c.translateBy(x: pad + CGFloat(i) * 14, y: 9); c.concatenate(CGAffineTransform(a: 1, b: 0, c: -0.65, d: 1, tx: 0, ty: 0)); c.setFillColor((i % 4 == 0 ? p.orange : p.yellow).cgColor); c.fill(CGRect(x: 0, y: 0, width: 7, height: 5)); c.restoreGState() }
            line(c, pad + (mobile ? 94 : 206), 12, w - pad, 12, p.rule)
            c.restoreGState()
        }
    }

    // Renders one scene into an upright CGImage at the given backing scale.
    func image(t: Double, closing: Bool, scale: CGFloat) -> CGImage? {
        let pw = max(1, Int(w * scale)), ph = max(1, Int(h * scale))
        guard let c = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        c.scaleBy(x: scale, y: scale); c.translateBy(x: 0, y: h); c.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: c, flipped: true)
        draw(c, t: t, closing: closing); NSGraphicsContext.restoreGraphicsState()
        return c.makeImage()
    }

    // CPU approximation of the partition-rewrite shader: cells travel outward from (0.68, 0.5), slide sideways while
    // the front passes, then show the target; short packet tears add horizontal offsets of real image strips.
    func composeTransfer(_ c: CGContext, source: CGImage, target: CGImage, progress p: Double, t: Double) {
        func put(_ image: CGImage, clip: CGRect, dx: CGFloat = 0, alpha: CGFloat = 1) {
            c.saveGState(); c.clip(to: clip); c.setAlpha(alpha); c.translateBy(x: dx, y: h); c.scaleBy(x: 1, y: -1); c.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h)); c.restoreGState()
        }
        let full = CGRect(origin: .zero, size: size)
        if p >= 1 { put(target, clip: full); return }
        put(source, clip: full); guard p > 0 else { return }
        let rows = 60, tick = floor(t * 13); var done: [CGRect] = [], seams: [(CGRect, CGFloat)] = []
        for row in 0..<rows {
            let grouping = 1 + floor(hash(Double(row), 3) * 3), cols = Int(max(8, 24 / grouping)), ch = h / CGFloat(rows), cw = w / CGFloat(cols)
            for col in 0..<cols {
                let u = (Double(col) + 0.5) / Double(cols), v = (Double(row) + 0.5) / Double(rows)
                let travel = hypot((u - 0.68) * 1.2, (v - 0.5) * 0.78), local = introCurve((p * 1.55 - travel * 0.9) / 0.42)
                guard local > 0 else { continue }
                let rect = CGRect(x: CGFloat(col) * cw, y: CGFloat(row) * ch, width: cw + 0.5, height: ch + 0.5), rewritten = smoothstep(0.48, 0.8, local)
                if local >= 1 { done.append(rect); continue }
                let front = sin(local * .pi), seed = hash(Double(col), Double(row) + 7)
                let shift = ((u < 0.68 ? -1 : 1) * (0.003 + seed * 0.012) * front + (floor(hash(Double(row), tick) * 3) - 1) * 0.001 * front) * Double(w)
                put(source, clip: rect, dx: CGFloat(shift))
                if rewritten > 0 { put(target, clip: rect, dx: CGFloat(shift), alpha: CGFloat(rewritten)) }
                if seed > 0.75 { seams.append((CGRect(x: rect.minX, y: rect.maxY - 1.2, width: rect.width, height: 1.2), CGFloat(front * 0.45))) }
            }
        }
        if !done.isEmpty { c.saveGState(); c.clip(to: done); c.translateBy(x: 0, y: h); c.scaleBy(x: 1, y: -1); c.draw(target, in: CGRect(x: 0, y: 0, width: w, height: h)); c.restoreGState() }
        for (rect, alpha) in seams { c.setFillColor(palette.orange.withAlphaComponent(alpha).cgColor); c.fill(rect) }
        // Packet tears: sparse strips of real image content, offset horizontally, strongest mid-transition.
        let envelope = sin(p * .pi) * 0.44, packet = floor(p * 18), stripH = h / 240
        guard envelope > 0.02 else { return }
        for scan in 0..<240 where hash(Double(scan), packet) > 0.91 {
            let columns = 8 + Int(hash(Double(scan), 4) * 8), segW = w / CGFloat(columns), offset = CGFloat((hash(Double(scan), packet + 31) - 0.5) * 0.03) * w
            for seg in 0..<columns where hash(Double(seg), Double(scan) + packet) > 0.4 {
                let rect = CGRect(x: CGFloat(seg) * segW + segW * 0.06, y: CGFloat(scan) * stripH, width: segW * 0.8, height: stripH * 0.6)
                let radius = hypot(rect.midX / w - 0.5, (rect.midY / h - 0.5) * h / w); guard radius > 0.05 else { continue }
                put(p > 0.5 ? target : source, clip: rect, dx: offset, alpha: CGFloat(envelope * 0.9))
                c.setFillColor(palette.orange.withAlphaComponent(CGFloat(envelope * 0.3)).cgColor); c.fill(rect)
            }
        }
    }
}

// MARK: - Overlay view

final class IntroButton: NSButton {
    var fill = NSColor.clear, ink = NSColor.white
    override func draw(_ dirtyRect: NSRect) {
        fill.withAlphaComponent(isHighlighted ? fill.alphaComponent * 0.8 : fill.alphaComponent).setFill(); bounds.fill()
        let string = NSAttributedString(string: title, attributes: [.font: font ?? IntroFonts.sans(12), .foregroundColor: ink]), size = string.size()
        string.draw(at: NSPoint(x: alignment == .left ? 14 : (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
        if alignment == .left { NSAttributedString(string: "→", attributes: [.font: IntroFonts.sans(15), .foregroundColor: ink]).draw(at: NSPoint(x: bounds.width - 28, y: (bounds.height - size.height) / 2)) }
    }
}

final class IntroConfirmCard: NSView {
    var palette = IntroPalette.dark { didSet { needsDisplay = true; button.fill = palette.light ? hex(0xd9a520) : palette.yellow; button.ink = hex(0x151515); button.needsDisplay = true } }
    let button = IntroButton()
    override var isFlipped: Bool { true }
    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 400, height: 196))
        button.title = "驾驶员已确认，开始同步"; button.font = IntroFonts.mincho(15); button.alignment = .left; button.isBordered = false; button.setButtonType(.momentaryChange)
        button.frame = NSRect(x: 26, y: 140, width: 354, height: 42); addSubview(button)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        let p = palette, scene = IntroScene(size: bounds.size, palette: p, connected: true)
        p.cardBackground.setFill(); bounds.fill(); p.red.setFill(); NSRect(x: 0, y: 0, width: 6, height: bounds.height).fill(); p.cardRule.setFill(); NSRect(x: 6, y: 0, width: bounds.width - 6, height: 1).fill()
        p.orange.setFill(); NSBezierPath(ovalIn: NSRect(x: 26, y: 18, width: 7, height: 7)).fill()
        scene.text("驾驶员验证完成", 40, 26, IntroFonts.sans(11), p.cardMuted); scene.text("02.03", bounds.width - 20, 26, IntroFonts.display(11), p.orange, align: .right)
        p.red.setStroke(); let badge = NSBezierPath(rect: NSRect(x: 26.5, y: 40.5, width: 46, height: 46)); badge.lineWidth = 1; badge.stroke()
        scene.text("02", 49.5, 73, IntroFonts.serif(24), p.red, align: .center)
        scene.text("驾驶员已确认", 86, 64, IntroFonts.mincho(21), p.cardText); scene.text("明日香  / ASUKA · 二号机", 86, 84, IntroFonts.sans(12), p.cardMuted)
        p.cardRule.setFill(); NSRect(x: 26, y: 100, width: bounds.width - 46, height: 1).fill()
        scene.text("同步状态", 26, 124, IntroFonts.sans(11), p.cardMuted); scene.text("已确认", bounds.width - 20, 124, IntroFonts.sans(12, weight: .bold), p.orange, align: .right)
    }
}

final class IntroView: NSView {
    var onFinish: (() -> Void)?
    var isConnected: () -> Bool = { false }
    var soundEnabled: Bool { introFlag("native.introSound") }
    private var timer: Timer?, player: AVAudioPlayer?, clockStart = CACurrentMediaTime(), time = 0.0, held = false, interactive = true, finished = false
    private var workbench: CGImage?, cachedScale: CGFloat = 2
    private let card = IntroConfirmCard(), skip = IntroButton(), sound = IntroButton()
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    var palette: IntroPalette { effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .aqua ? .light : .dark }

    override init(frame: NSRect) {
        super.init(frame: frame); wantsLayer = true
        card.isHidden = true; card.button.target = self; card.button.action = #selector(confirm); addSubview(card)
        for (button, action) in [(skip, #selector(skipIntro)), (sound, #selector(toggleSound))] { button.isBordered = false; button.font = IntroFonts.sans(11); button.target = self; button.action = action; addSubview(button) }
        skip.title = "跳过开场 ↗"; updateSoundTitle()
    }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); styleControls(); needsDisplay = true }
    private func styleControls() {
        let p = palette; card.palette = p
        for button in [skip, sound] { button.fill = p.background.withAlphaComponent(0.001); button.ink = p.subtle; button.needsDisplay = true }
    }
    private func updateSoundTitle() { sound.title = soundEnabled ? "日文播报 · 开" : "日文播报 · 关"; sound.needsDisplay = true }
    override func layout() {
        super.layout(); let scene = IntroScene(size: bounds.size, palette: palette, connected: false)
        card.frame = NSRect(x: (bounds.width - 400) / 2, y: bounds.height - scene.cardBottom - 196, width: 400, height: 196)
        skip.frame = NSRect(x: bounds.width - scene.pad - 110, y: bounds.height - 62, width: 110, height: 24)
        sound.frame = NSRect(x: bounds.width - scene.pad - 230, y: bounds.height - 62, width: 112, height: 24)
    }

    func start(interactive: Bool) {
        self.interactive = interactive; styleControls(); cachedScale = window?.backingScaleFactor ?? 2
        if soundEnabled, let url = IntroMedia.voiceURL, let audio = try? AVAudioPlayer(contentsOf: url) { player = audio; audio.prepareToPlay(); audio.play() }
        clockStart = CACurrentMediaTime(); window?.makeFirstResponder(self)
        timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }; RunLoop.main.add(timer!, forMode: .common)
    }
    private func currentTime() -> Double { if let player, player.isPlaying { return player.currentTime }; return CACurrentMediaTime() - clockStart }
    private func tick() {
        guard !finished else { return }
        if held { return }
        var t = currentTime()
        if interactive && t >= IntroTiming.hold { held = true; t = IntroTiming.hold; player?.pause(); player?.currentTime = IntroTiming.hold; card.isHidden = false; card.alphaValue = 0; NSAnimationContext.runAnimationGroup { $0.duration = 0.5; card.animator().alphaValue = 1 } }
        if t >= IntroTiming.handoffStart && workbench == nil { workbench = snapshotWorkbench() }
        time = min(t, IntroTiming.duration)
        alphaValue = CGFloat(1 - introStage(time, IntroTiming.fadeStart, IntroTiming.duration))
        needsDisplay = true
        if time >= IntroTiming.duration - 0.02 { finish() }
    }
    @objc func confirm() {
        guard held else { return }; held = false; interactive = false
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; card.animator().alphaValue = 0 }) { [weak self] in self?.card.isHidden = true }
        clockStart = CACurrentMediaTime() - IntroTiming.hold
        if let player { player.currentTime = IntroTiming.hold; player.play() }
    }
    @objc func skipIntro() { finish() }
    @objc func toggleSound() {
        UserDefaults.standard.set(!soundEnabled, forKey: "native.introSound"); updateSoundTitle()
        if !soundEnabled { if let player { clockStart = CACurrentMediaTime() - player.currentTime; player.stop() }; player = nil }
        else if player == nil, let url = IntroMedia.voiceURL, let audio = try? AVAudioPlayer(contentsOf: url) { player = audio; audio.currentTime = time; if !held { audio.play() } }
    }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode { case 53: finish(); case 36, 49, 76: if held { confirm() } else { super.keyDown(with: event) }; default: super.keyDown(with: event) }
    }
    override func mouseDown(with event: NSEvent) {}
    func finish() {
        guard !finished else { return }; finished = true; timer?.invalidate(); player?.stop(); player = nil
        NSAnimationContext.runAnimationGroup({ $0.duration = time < IntroTiming.fadeStart ? 0.3 : 0.05; animator().alphaValue = 0 }) { [weak self] in self?.removeFromSuperview(); self?.onFinish?() }
    }
    private func snapshotWorkbench() -> CGImage? {
        guard let root = superview else { return nil }
        isHidden = true; defer { isHidden = false }
        guard let rep = root.bitmapImageRepForCachingDisplay(in: root.bounds) else { return nil }
        root.cacheDisplay(in: root.bounds, to: rep); return rep.cgImage
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let c = NSGraphicsContext.current?.cgContext else { return }
        let scene = IntroScene(size: bounds.size, palette: palette, connected: isConnected()), t = time
        if t >= IntroTiming.handoffStart, let workbench, let source = scene.image(t: t, closing: true, scale: cachedScale) {
            scene.composeTransfer(c, source: source, target: workbench, progress: introStage(t, IntroTiming.handoffStart, IntroTiming.handoffEnd), t: t)
        } else if t >= IntroTiming.transferStart && t < IntroTiming.transferEnd, let source = scene.image(t: t, closing: false, scale: cachedScale), let target = scene.image(t: t, closing: true, scale: cachedScale) {
            scene.composeTransfer(c, source: source, target: target, progress: introStage(t, IntroTiming.transferStart, IntroTiming.transferEnd), t: t)
        } else {
            scene.draw(c, t: t, closing: t >= IntroTiming.transferEnd)
        }
        IntroView.drawCaption(scene: scene, t: t)
    }
    static func drawCaption(scene: IntroScene, t: Double) {
        guard let cue = IntroMedia.cues.first(where: { t >= $0.start && t < $0.end }) else { return }
        let p = scene.palette, y = scene.h - 118, zh = NSAttributedString(string: cue.zh, attributes: [.font: IntroFonts.sans(15), .foregroundColor: p.caption])
        let ja = NSAttributedString(string: cue.ja, attributes: [.font: IntroFonts.sans(10), .foregroundColor: p.subtle]), width = max(zh.size().width, ja.size().width)
        let left = scene.cx - width / 2 - 7
        p.orange.setFill(); NSRect(x: left, y: y, width: 2, height: 40).fill()
        ja.draw(at: NSPoint(x: left + 14, y: y + 1)); zh.draw(at: NSPoint(x: left + 14, y: y + 16))
    }

    // Offscreen render used by `--render-intro <dir>` to check frames without opening a window.
    static func renderFrames(to directory: URL, times: [Double], size: CGSize = CGSize(width: 1440, height: 900)) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, palette) in [("dark", IntroPalette.dark), ("light", IntroPalette.light)] {
            let scene = IntroScene(size: size, palette: palette, connected: true)
            // Stand-in for the workbench snapshot during hand-off.
            let stand = IntroScene(size: size, palette: palette, connected: true)
            let workbench: CGImage? = {
                guard let c = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
                c.translateBy(x: 0, y: size.height); c.scaleBy(x: 1, y: -1)
                NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: c, flipped: true)
                c.setFillColor((palette.light ? NSColor(calibratedRed: 0.99, green: 0.975, blue: 0.97, alpha: 1) : NSColor(calibratedRed: 0.035, green: 0.04, blue: 0.052, alpha: 1)).cgColor); c.fill(CGRect(origin: .zero, size: size))
                stand.text("[ 工作台画面 ]", size.width / 2, size.height / 2, IntroFonts.sans(28), palette.orange, align: .center)
                NSGraphicsContext.restoreGraphicsState(); return c.makeImage()
            }()
            for t in times {
                guard let c = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
                c.translateBy(x: 0, y: size.height); c.scaleBy(x: 1, y: -1)
                NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: c, flipped: true)
                if t >= IntroTiming.handoffStart, let workbench, let source = scene.image(t: t, closing: true, scale: 1) {
                    scene.composeTransfer(c, source: source, target: workbench, progress: introStage(t, IntroTiming.handoffStart, IntroTiming.handoffEnd), t: t)
                } else if t >= IntroTiming.transferStart && t < IntroTiming.transferEnd, let source = scene.image(t: t, closing: false, scale: 1), let target = scene.image(t: t, closing: true, scale: 1) {
                    scene.composeTransfer(c, source: source, target: target, progress: introStage(t, IntroTiming.transferStart, IntroTiming.transferEnd), t: t)
                } else { scene.draw(c, t: t, closing: t >= IntroTiming.transferEnd) }
                drawCaption(scene: scene, t: t)
                if abs(t - IntroTiming.hold) < 0.001 {
                    let card = IntroConfirmCard(); card.palette = palette
                    c.saveGState(); c.translateBy(x: (size.width - 400) / 2, y: size.height - scene.cardBottom - 196); card.draw(card.bounds)
                    let b = card.button; c.translateBy(x: b.frame.minX, y: b.frame.minY); b.draw(b.bounds); c.restoreGState()
                }
                NSGraphicsContext.restoreGraphicsState()
                guard let image = c.makeImage() else { continue }
                let rep = NSBitmapImageRep(cgImage: image)
                try rep.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent(String(format: "%@-%05.2f.png", name, t)))
            }
        }
    }
}
