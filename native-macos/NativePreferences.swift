import AppKit

func metricNumber(_ value: Any?) -> Double? { guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite else { return nil }; return n.doubleValue }

final class UsageBar: NSView {
    var percent: Double? { didSet { needsDisplay = true; setAccessibilityValue(percent.map { String(format: "%.1f%%", $0) } ?? "未知") } }
    override init(frame: NSRect) { super.init(frame: frame); setAccessibilityElement(true); setAccessibilityRole(.progressIndicator) }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override func draw(_ rect: NSRect) {
        EVATheme.border.withAlphaComponent(0.4).setFill(); NSBezierPath(roundedRect: bounds, xRadius: 3, yRadius: 3).fill()
        if let percent { EVATheme.red.setFill(); NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: bounds.width * min(100, max(0, percent)) / 100, height: bounds.height), xRadius: 3, yRadius: 3).fill() }
    }
}
final class UsageMetric: NSStackView {
    let name = EVATheme.label("", size: 12, weight: .semibold), value = EVATheme.label("未知", size: 12, color: EVATheme.orange, weight: .semibold)
    let detail = EVATheme.label("", size: 10, color: EVATheme.muted), bar = UsageBar(frame: .zero)
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect); orientation = .vertical; alignment = .leading; spacing = 7
        let header = EVATheme.horizontal([name, EVATheme.spacer(), value]); addArrangedSubview(header); header.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        addArrangedSubview(bar); bar.widthAnchor.constraint(equalTo: widthAnchor).isActive = true; bar.heightAnchor.constraint(equalToConstant: 6).isActive = true
        detail.lineBreakMode = .byTruncatingTail; addArrangedSubview(detail); detail.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
    }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError() }
    func update(title: String, percent: Double?, description: String, estimated: Bool = false) {
        name.stringValue = title; bar.percent = percent
        value.stringValue = percent.map { (estimated ? "约 " : "已用 ") + String(format: "%.1f%%", $0) } ?? "暂不可用"
        detail.stringValue = description; detail.toolTip = description; bar.setAccessibilityLabel(title)
    }
}

@MainActor
extension NativeWorkbench {
    func setThemeAppearance() {
        switch UserDefaults.standard.string(forKey: "native.theme") ?? "system" {
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        default: NSApp.appearance = nil
        }
    }
    @objc func themeChanged() {
        UserDefaults.standard.set(["system", "dark", "light"][max(0, themePicker.indexOfSelectedItem)], forKey: "native.theme")
        setThemeAppearance(); window.appearance = nil; window.backgroundColor = EVATheme.background
        window.contentView?.needsDisplay = true
    }
    func buildUsagePopover() {
        let title = EVATheme.label("LINK STATUS / 用量速览", size: 13, color: EVATheme.orange, weight: .semibold)
        configure(usageRefreshButton, "刷新官方数据", #selector(refreshUsage))
        let caption = EVATheme.label("上下文属于当前对话；额度为账号共享，均显示已用比例。", size: 10, color: EVATheme.muted)
        caption.maximumNumberOfLines = 2; caption.cell?.wraps = true
        usageSourceLabel.font = .systemFont(ofSize: 10); usageSourceLabel.textColor = EVATheme.muted; usageSourceLabel.maximumNumberOfLines = 5
        let content = EVATheme.vertical([title, caption, contextMetric, fiveHourMetric, weekMetric, usageSourceLabel, usageRefreshButton], spacing: 16)
        for view in [caption, contextMetric, fiveHourMetric, weekMetric, usageSourceLabel] { view.widthAnchor.constraint(equalToConstant: 340).isActive = true }
        let controller = NSViewController(); controller.view = pinned(content, padding: 20, color: EVATheme.panel)
        usagePopover.contentViewController = controller; usagePopover.behavior = .transient; usagePopover.animates = false
        usageButton.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
    }
    func dateFromUsage(_ value: Any?) -> Date? {
        guard let raw = value as? String else { return nil }
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) { return date }; formatter.formatOptions = [.withInternetDateTime]; return formatter.date(from: raw)
    }
    func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "zh_CN"); formatter.timeZone = TimeZone(identifier: "Asia/Shanghai"); formatter.dateFormat = "MM-dd HH:mm"; return formatter.string(from: date)
    }
    func tokenCount(_ value: Double?) -> String { guard let value else { return "—" }; return value >= 1000 ? String(format: "%.1fK", value / 1000) : String(format: "%.0f", value) }
    func updateUsageWidget() {
        let context = object(selectedThread?["contextUsage"]), rates = object(providerState["usage"]), windows = objects(rates["windows"])
        let five = windows.first { string($0["id"]) == "five_hour" } ?? windows.first { string($0["id"]) != "seven_day" } ?? [:]
        let week = windows.first { string($0["id"]) == "seven_day" } ?? [:]
        let cp = metricNumber(context["usedPercent"]), fp = metricNumber(five["usedPercent"]), wp = metricNumber(week["usedPercent"])
        func percent(_ value: Double?) -> String { value.map { String(format: "%.0f%%", $0) } ?? "—" }
        let firstLabel = string(five["label"]).isEmpty || string(five["id"]) == "five_hour" ? "5h" : string(five["label"])
        usageButton.title = "上下文 " + percent(cp) + " · " + firstLabel + " " + percent(fp) + " · 周 " + percent(wp) + (flag(rates["stale"]) ? " ⟳" : "")
        usageButton.toolTip = providerName + " · 点击查看上下文、账号额度与重置时间（显示已用比例）"
        let contextHint = cp == nil ? (selectedThread == nil ? "新对话将在首次回复后显示" : "等待下一次回复；不会按可见消息字数猜测") : tokenCount(metricNumber(context["usedTokens"])) + " / " + tokenCount(metricNumber(context["maxTokens"])) + " tokens · " + string(context["source"])
        contextMetric.update(title: "对话上下文", percent: cp, description: contextHint, estimated: flag(context["estimated"]))
        func windowDetail(_ row: JSON) -> String {
            guard let date = dateFromUsage(row["resetsAt"]) else { return "官方未返回重置时间" }
            if date < Date() { return "已到重置时间，等待下一次官方刷新" }
            return shortDate(date) + " 重置"
        }
        fiveHourMetric.update(title: firstLabel == "5h" ? "5 小时额度" : firstLabel + "额度", percent: fp, description: windowDetail(five))
        weekMetric.update(title: "周额度", percent: wp, description: windowDetail(week))
        var source = string(rates["source"])
        if let timestamp = metricNumber(rates["updatedAt"]) { source += "\n更新于 " + shortDate(Date(timeIntervalSince1970: timestamp / 1000)) }
        if flag(rates["stale"]) { source += "\n当前为旧数据" }
        if !string(rates["error"]).isEmpty { source += "\n" + string(rates["error"]) }
        if let error = usageErrors[provider] { source += "\n刷新失败：" + error }
        if source.isEmpty { source = "等待官方用量数据，可手动刷新。" }
        let extras = windows.filter { ![string(five["id"]), "seven_day"].contains(string($0["id"])) }.map { string($0["label"]) + " " + percent(metricNumber($0["usedPercent"])) }
        if !extras.isEmpty { source += "\n" + extras.joined(separator: " · ") }
        usageSourceLabel.stringValue = source; usageRefreshButton.isEnabled = ready && !usageRefreshing
        usageRefreshButton.title = usageRefreshing ? "刷新中…" : "刷新官方数据"
    }
    @objc func showUsage() { updateUsageWidget(); usagePopover.show(relativeTo: usageButton.bounds, of: usageButton, preferredEdge: .minY); refreshUsage() }
    @objc func refreshUsage() {
        guard ready && !stopping && !usageRefreshing else { return }
        let target = provider; usageRefreshing = true; updateUsageWidget()
        api.request("/api/usage/refresh", body: ["provider": target, "threadId": selectedThreadID], timeout: 70) { [weak self] result in
            guard let self else { return }; self.usageRefreshing = false
            switch result {
            case .success(let value):
                self.usageErrors.removeValue(forKey: target)
                if target == "claude" { var providers = object(self.state["providers"]), claude = object(providers["claude"]); claude["usage"] = object(value); providers["claude"] = claude; self.state["providers"] = providers }
                else { self.state["usage"] = object(value) }
            case .failure(let error): self.usageErrors[target] = error.localizedDescription
            }
            self.updateUsageWidget()
        }
    }
    func applyPermissionMode(_ requested: String, confirmed: Bool) {
        guard let t = selectedThread, object(t["localHistory"]).isEmpty else { mode = requested; fullAccessAcknowledged = confirmed; updateControls(); return }
        let id = string(t["id"]); changingMode = true; updateControls()
        api.request("/api/thread/mode", body: ["threadId": id, "mode": requested, "confirmFullAccess": confirmed]) { [weak self] result in
            guard let self else { return }; self.changingMode = false
            switch result {
            case .success(let value): let thread = object(object(value)["thread"]); self.state["threads"] = self.threads.map { string($0["id"]) == id ? thread : $0 }; if self.selectedThreadID == id { self.mode = requested; self.fullAccessAcknowledged = confirmed }
            case .failure(let error): self.notice(error.localizedDescription)
            }
            self.applyState(self.state)
        }
    }
}
