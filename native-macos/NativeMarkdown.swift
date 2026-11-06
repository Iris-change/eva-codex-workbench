import AppKit

// Markdown for assistant / user messages. Block structure (headings, lists, task lists, quotes, fenced code,
// tables, rules) is parsed line by line; inline syntax (bold, italic, code, strikethrough, links) uses
// Foundation's Markdown parser and is restyled with the EVA fonts and colours. Text is never executed or
// fetched: links stay plain attributes that open only when clicked.

enum MarkdownTheme {
    static let text = EVAStyle.dyn("md.text", 0xe1dcd3, 0x2f2020)
    static let strong = EVAStyle.dyn("md.strong", 0xf4eee4, 0x1d1010)
    static let muted = EVAStyle.dyn("md.muted", 0xa99c90, 0x7f655a)
    static let codeText = EVAStyle.dyn("md.code", 0xf2c79a, 0x8a2a14)
    static let codeBackground = EVAStyle.dyn("md.codeBg", 0x1b1816, 0xf3e7e1)
    static let blockBackground = EVAStyle.dyn("md.blockBg", 0x151314, 0xf6eee9)
    static let rule = EVAStyle.dyn("md.rule", 0x3a3230, 0xdcc8c0)
    static let link = EVAStyle.orange
    static let emphasis = EVAStyle.dyn("md.em", 0xf0b48a, 0xa23a1c)
    static let body = EVAStyle.ui(14), mono = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
}

private let fencePattern = try! NSRegularExpression(pattern: #"^\s*(```+|~~~+)\s*([\w+#.-]*)\s*$"#)
private let headingPattern = try! NSRegularExpression(pattern: #"^\s{0,3}(#{1,6})\s+(.*?)\s*#*\s*$"#)
private let rulePattern = try! NSRegularExpression(pattern: #"^\s{0,3}((\*\s*){3,}|(-\s*){3,}|(_\s*){3,})$"#)
private let bulletPattern = try! NSRegularExpression(pattern: #"^(\s*)([-*+])\s+(\[[ xX]\]\s+)?(.*)$"#)
private let orderedPattern = try! NSRegularExpression(pattern: #"^(\s*)(\d{1,4})[.)]\s+(.*)$"#)
private let quotePattern = try! NSRegularExpression(pattern: #"^\s{0,3}>\s?(.*)$"#)
private let tableSeparator = try! NSRegularExpression(pattern: #"^\s*\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?\s*$"#)

private func groups(_ regex: NSRegularExpression, _ line: String) -> [String]? {
    let ns = line as NSString
    guard let m = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
    return (0..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? "" : ns.substring(with: m.range(at: $0)) }
}

private func paragraph(indent: CGFloat = 0, hanging: CGFloat = 0, before: CGFloat = 0, after: CGFloat = 6, lineSpacing: CGFloat = 5, tabs: [CGFloat] = []) -> NSParagraphStyle {
    let p = NSMutableParagraphStyle(); p.lineSpacing = lineSpacing; p.paragraphSpacingBefore = before; p.paragraphSpacing = after
    p.firstLineHeadIndent = indent; p.headIndent = indent + hanging
    p.tabStops = tabs.map { NSTextTab(textAlignment: .left, location: $0) }; p.defaultTabInterval = 28
    return p
}

/// Inline Markdown → attributed text with EVA styling.
func inlineMarkdown(_ source: String, font base: NSFont = MarkdownTheme.body, color: NSColor = MarkdownTheme.text) -> NSMutableAttributedString {
    let options = AttributedString.MarkdownParsingOptions(allowsExtendedAttributes: false, interpretedSyntax: .inlineOnlyPreservingWhitespace, failurePolicy: .returnPartiallyParsedIfPossible)
    guard let parsed = try? AttributedString(markdown: source, options: options) else { return NSMutableAttributedString(string: source, attributes: [.font: base, .foregroundColor: color]) }
    let output = NSMutableAttributedString()
    for run in parsed.runs {
        let piece = String(parsed[run.range].characters), intent = run.inlinePresentationIntent ?? []
        var font = base, attributes: [NSAttributedString.Key: Any] = [.foregroundColor: color]
        if intent.contains(.code) {
            font = NSFont.monospacedSystemFont(ofSize: max(11, base.pointSize - 1.5), weight: .regular)
            attributes[.foregroundColor] = MarkdownTheme.codeText; attributes[.backgroundColor] = MarkdownTheme.codeBackground
        }
        if intent.contains(.stronglyEmphasized) {
            font = NSFont(name: "PingFangSC-Semibold", size: font.pointSize).flatMap { intent.contains(.code) ? nil : $0 } ?? NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
            if !intent.contains(.code) { attributes[.foregroundColor] = MarkdownTheme.strong }
        }
        if intent.contains(.emphasized) { attributes[.obliqueness] = 0.16; if !intent.contains(.code) { attributes[.foregroundColor] = MarkdownTheme.emphasis } }
        if intent.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue; attributes[.foregroundColor] = MarkdownTheme.muted }
        if let link = run.link { attributes[.link] = link; attributes[.foregroundColor] = MarkdownTheme.link; attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        attributes[.font] = font
        output.append(NSAttributedString(string: piece, attributes: attributes))
    }
    return output
}

func messageText(_ value: String) -> NSAttributedString {
    let output = NSMutableAttributedString(), lines = value.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
    func append(_ text: NSAttributedString, _ style: NSParagraphStyle) {
        let block = NSMutableAttributedString(attributedString: text); block.append(NSAttributedString(string: "\n"))
        block.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: block.length)); output.append(block)
    }
    var i = 0, paragraphLines: [String] = []
    func flushParagraph() {
        guard !paragraphLines.isEmpty else { return }
        append(inlineMarkdown(paragraphLines.joined(separator: "\n")), paragraph(after: 9)); paragraphLines.removeAll()
    }
    while i < lines.count {
        let line = lines[i]
        if line.trimmingCharacters(in: .whitespaces).isEmpty { flushParagraph(); i += 1; continue }
        // Fenced code block (unterminated fences run to the end, as while a reply is still streaming).
        if let fence = groups(fencePattern, line) {
            flushParagraph(); var code: [String] = []; i += 1
            while i < lines.count, !(lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(String(fence[1].prefix(3)))) { code.append(lines[i]); i += 1 }
            i += 1
            if !fence[2].isEmpty { append(NSAttributedString(string: fence[2].uppercased(), attributes: [.font: EVAStyle.mono(9, .medium), .foregroundColor: EVAStyle.orange, .kern: 1]), paragraph(indent: 10, before: 4, after: 2)) }
            // The newline is part of the shaded run so every line of the block gets the same full-width background.
            let body = NSMutableAttributedString(string: code.joined(separator: "\n").replacingOccurrences(of: "\t", with: "    ") + "\n", attributes: [.font: MarkdownTheme.mono, .foregroundColor: MarkdownTheme.codeText, .backgroundColor: MarkdownTheme.blockBackground])
            body.addAttribute(.paragraphStyle, value: paragraph(indent: 10, before: fence[2].isEmpty ? 4 : 0, after: 12, lineSpacing: 3), range: NSRange(location: 0, length: body.length)); output.append(body); continue
        }
        if let h = groups(headingPattern, line) {
            flushParagraph(); let level = h[1].count, size: CGFloat = [21, 18.5, 16.5, 15, 14, 14][level - 1]
            let text = inlineMarkdown(h[2], font: level <= 2 ? EVAStyle.title(size) : EVAStyle.ui(size, .semibold), color: MarkdownTheme.strong)
            append(text, paragraph(before: level <= 2 ? 10 : 6, after: 6)); i += 1; continue
        }
        if groups(rulePattern, line) != nil {
            flushParagraph(); append(NSAttributedString(string: String(repeating: "─", count: 48), attributes: [.font: EVAStyle.mono(7), .foregroundColor: MarkdownTheme.rule]), paragraph(before: 4, after: 10)); i += 1; continue
        }
        // Table: header row, separator row, then rows containing pipes.
        if line.contains("|"), i + 1 < lines.count, groups(tableSeparator, lines[i + 1]) != nil {
            flushParagraph()
            func cells(_ row: String) -> [String] {
                var trimmed = row.trimmingCharacters(in: .whitespaces); if trimmed.hasPrefix("|") { trimmed.removeFirst() }; if trimmed.hasSuffix("|") { trimmed.removeLast() }
                return trimmed.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            }
            var rows = [cells(line)]; i += 2
            while i < lines.count, lines[i].contains("|"), !lines[i].trimmingCharacters(in: .whitespaces).isEmpty { rows.append(cells(lines[i])); i += 1 }
            let columns = rows.map(\.count).max() ?? 0
            let rendered = rows.enumerated().map { index, row in (0..<columns).map { inlineMarkdown(row.indices.contains($0) ? row[$0] : "", font: index == 0 ? EVAStyle.ui(13, .semibold) : EVAStyle.ui(13), color: index == 0 ? MarkdownTheme.strong : MarkdownTheme.text) } }
            var widths = [CGFloat](repeating: 0, count: columns)
            for row in rendered { for (c, cell) in row.enumerated() { widths[c] = max(widths[c], min(320, ceil(cell.size().width))) } }
            var stops: [CGFloat] = [], x: CGFloat = 10; for w in widths.dropLast() { x += w + 26; stops.append(x) }
            for (index, row) in rendered.enumerated() {
                let text = NSMutableAttributedString(); for (c, cell) in row.enumerated() { if c > 0 { text.append(NSAttributedString(string: "\t")) }; text.append(cell) }
                append(text, paragraph(indent: 10, before: index == 0 ? 4 : 0, after: index == 0 ? 2 : 3, tabs: stops))
                if index == 0 { append(NSAttributedString(string: String(repeating: "─", count: 48), attributes: [.font: EVAStyle.mono(7), .foregroundColor: MarkdownTheme.rule]), paragraph(indent: 10, after: 3)) }
            }
            output.append(NSAttributedString(string: "\n", attributes: [.font: EVAStyle.ui(6)])); continue
        }
        if let q = groups(quotePattern, line) {
            flushParagraph(); var quoted = [q[1]]; i += 1
            while i < lines.count, let next = groups(quotePattern, lines[i]) { quoted.append(next[1]); i += 1 }
            let text = NSMutableAttributedString(string: "▍ ", attributes: [.font: EVAStyle.ui(14), .foregroundColor: EVAStyle.orange])
            text.append(inlineMarkdown(quoted.joined(separator: "\n"), color: MarkdownTheme.muted))
            append(text, paragraph(indent: 4, hanging: 16, before: 2, after: 10)); continue
        }
        if let b = groups(bulletPattern, line) {
            flushParagraph(); let level = min(3, b[1].replacingOccurrences(of: "\t", with: "    ").count / 2)
            let box = b[3].trimmingCharacters(in: .whitespaces), marker = box.isEmpty ? ["•", "◦", "▪", "▫"][level] : (box.lowercased() == "[x]" ? "☑" : "☐")
            let text = NSMutableAttributedString(string: marker + "\t", attributes: [.font: EVAStyle.ui(14), .foregroundColor: box.isEmpty ? EVAStyle.orange : MarkdownTheme.muted])
            text.append(inlineMarkdown(b[4], color: box.lowercased() == "[x]" ? MarkdownTheme.muted : MarkdownTheme.text))
            let indent = 6 + CGFloat(level) * 18; append(text, paragraph(indent: indent, hanging: 16, after: 4, tabs: [indent + 16])); i += 1; continue
        }
        if let o = groups(orderedPattern, line) {
            flushParagraph(); let level = min(3, o[1].count / 2), indent = 6 + CGFloat(level) * 18
            let text = NSMutableAttributedString(string: o[2] + ".\t", attributes: [.font: EVAStyle.mono(12.5, .medium), .foregroundColor: EVAStyle.orange])
            text.append(inlineMarkdown(o[3])); append(text, paragraph(indent: indent, hanging: 22, after: 4, tabs: [indent + 22])); i += 1; continue
        }
        paragraphLines.append(line); i += 1
    }
    flushParagraph()
    if output.length > 0, output.string.hasSuffix("\n") { output.deleteCharacters(in: NSRange(location: output.length - 1, length: 1)) }
    return output
}
