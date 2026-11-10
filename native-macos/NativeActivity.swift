import AppKit

// Live execution transcript: every tool step (command, file read/edit, search, web, MCP, sub-task) is shown in
// the conversation where it happened, with its state and an expandable output — like the Codex and Claude Code
// clients — plus a status line saying what the assistant is doing right now.

struct StepInfo {
    enum State { case running, done, failed, waiting }
    let id: String, label: String, detail: String, output: String, state: State, seconds: Double?
}

private func shortPath(_ path: String, project: String) -> String {
    guard !path.isEmpty else { return "" }
    if !project.isEmpty, path.hasPrefix(project + "/") { return String(path.dropFirst(project.count + 1)) }
    return (path as NSString).abbreviatingWithTildeInPath
}
private func oneLine(_ value: String, _ limit: Int = 220) -> String {
    let flat = value.replacingOccurrences(of: "\n", with: " ⏎ ").trimmingCharacters(in: .whitespaces)
    return flat.count > limit ? String(flat.prefix(limit)) + "…" : flat
}
private func outputText(_ value: Any?) -> String {
    if let text = value as? String { return text }
    if let blocks = value as? [JSON] { return blocks.compactMap { $0["text"] as? String }.joined(separator: "\n") }
    if let value, JSONSerialization.isValidJSONObject(value), let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted]) { return String(data: data, encoding: .utf8) ?? "" }
    return ""
}

/// Normalises a Codex item or a Claude tool call into one readable step; nil for entries that are not steps.
func stepInfo(_ tool: JSON, project: String, tools: [JSON], waiting: Set<String>) -> StepInfo? {
    let id = string(tool["id"]), type = string(tool["type"]), status = string(tool["status"]), input = object(tool["input"])
    var state: StepInfo.State = ["failed", "declined", "error", "interrupted"].contains(status) ? .failed : (status == "inProgress" || status.isEmpty) ? .running : .done
    if waiting.contains(id) { state = .waiting }
    let started = tool["startedAt"] as? Double, ended = tool["endedAt"] as? Double
    let seconds = started.map { ((ended ?? Date().timeIntervalSince1970 * 1000) - $0) / 1000 }
    func make(_ label: String, _ detail: String, _ output: String) -> StepInfo { StepInfo(id: id, label: label, detail: detail, output: output, state: state, seconds: seconds) }
    switch type {
    case "claudeTool":
        let name = string(tool["name"]), out = outputText(tool["output"])
        let diff = tools.first { string($0["id"]) == "change-" + id }.map { objects($0["changes"]).map { string($0["diff"]) }.joined(separator: "\n") } ?? ""
        switch name {
        case "Bash": return make("运行命令", oneLine(string(input["command"])), out)
        case "Read": return make("读取", shortPath(string(input["file_path"]), project: project), "")
        case "Edit", "MultiEdit": return make("编辑", shortPath(string(input["file_path"]), project: project), diff.isEmpty ? out : diff)
        case "Write": return make("写入", shortPath(string(input["file_path"]), project: project), diff.isEmpty ? out : diff)
        case "NotebookEdit": return make("编辑笔记本", shortPath(string(input["notebook_path"]), project: project), out)
        case "Glob": return make("查找文件", string(input["pattern"]) + (string(input["path"]).isEmpty ? "" : "  in " + shortPath(string(input["path"]), project: project)), out)
        case "Grep": return make("搜索内容", string(input["pattern"]) + (string(input["path"]).isEmpty ? "" : "  in " + shortPath(string(input["path"]), project: project)), out)
        case "WebSearch": return make("网页搜索", string(input["query"]), out)
        case "WebFetch": return make("打开网页", string(input["url"]), out)
        case "Task", "Agent": return make("子任务", string(input["description"]).isEmpty ? oneLine(string(input["prompt"]), 120) : string(input["description"]), out)
        case "TodoWrite": let todos = objects(input["todos"]); return make("更新计划", "\(todos.count) 项 · " + todos.map { (string($0["status"]) == "completed" ? "✓ " : string($0["status"]) == "in_progress" ? "▸ " : "· ") + string($0["content"]) }.prefix(3).joined(separator: "  "), todos.map { string($0["status"]) + "  " + string($0["content"]) }.joined(separator: "\n"))
        case "AskUserQuestion": return make("向你提问", oneLine(objects(input["questions"]).map { string($0["question"]) }.joined(separator: " / ")), out)
        case "ToolSearch": return make("加载工具", string(input["query"]), out)
        default: return make(name.hasPrefix("mcp__") ? "MCP · " + name.replacingOccurrences(of: "mcp__", with: "").replacingOccurrences(of: "__", with: " / ") : name, oneLine(outputText(input), 160), out)
        }
    case "fileChange":
        if id.hasPrefix("change-") { return nil }   // shown as the diff of the matching Claude Edit/Write step
        let changes = objects(tool["changes"])
        return make("修改文件", changes.map { shortPath(string($0["path"]), project: project) }.joined(separator: ", "), changes.map { string($0["diff"]) }.joined(separator: "\n"))
    case "commandExecution":
        let exit = tool["exitCode"].flatMap { $0 is NSNull ? nil : "\($0)" }
        let command = (tool["command"] as? [String])?.joined(separator: " ") ?? string(tool["command"])
        return make("运行命令", oneLine(command) + (exit.map { $0 == "0" ? "" : "  · 退出码 \($0)" } ?? ""), string(tool["aggregatedOutput"]))
    case "mcpToolCall": return make("MCP · " + string(tool["server"]) + " / " + string(tool["tool"]), oneLine(outputText(tool["arguments"]), 160), outputText(tool["result"] ?? tool["error"]))
    case "webSearch": return make("网页搜索", string(tool["query"]), "")
    case "imageView": return make("查看图片", shortPath(string(tool["path"]), project: project), "")
    case "reasoning":
        let summary = ((tool["summary"] as? [String]) ?? []).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else { return nil }
        return StepInfo(id: id, label: "思考", detail: oneLine(summary.replacingOccurrences(of: "**", with: ""), 160), output: summary, state: .done, seconds: nil)
    default:
        return type.isEmpty ? nil : make(type, oneLine(outputText(tool["input"] ?? tool["arguments"]), 160), outputText(tool["output"] ?? tool["result"]))
    }
}

/// One step: glyph · action · detail · duration; click to expand the output.
final class StepRow: NSView {
    let info: StepInfo, expanded: Bool, onToggle: (String) -> Void
    private let spinner = NSProgressIndicator()
    override var isFlipped: Bool { true }
    init(_ info: StepInfo, expanded: Bool, onToggle: @escaping (String) -> Void) {
        self.info = info; self.expanded = expanded; self.onToggle = onToggle; super.init(frame: .zero)
        let color: NSColor = info.state == .failed ? EVAStyle.redEdge : info.state == .waiting ? EVAStyle.gold : info.state == .running ? EVAStyle.orange : EVAStyle.faint
        var lead: NSView
        if info.state == .running { spinner.style = .spinning; spinner.controlSize = .small; spinner.isDisplayedWhenStopped = false; spinner.startAnimation(nil); spinner.widthAnchor.constraint(equalToConstant: 12).isActive = true; spinner.heightAnchor.constraint(equalToConstant: 12).isActive = true; lead = spinner }
        else { lead = EVAStyle.label(info.state == .failed ? "✕" : info.state == .waiting ? "⏸" : "✓", EVAStyle.mono(10, .bold), color) }
        let label = EVAStyle.label(info.label, EVAStyle.ui(11.5, .medium), info.state == .done ? EVAStyle.sub : EVAStyle.ink)
        let detail = EVAStyle.label(info.detail, EVAStyle.mono(11), info.state == .done ? EVAStyle.faint : EVAStyle.controlText); detail.lineBreakMode = .byTruncatingMiddle
        detail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        var tail = info.state == .waiting ? "等待你确认" : info.state == .failed ? "失败" : ""
        if let s = info.seconds, info.state != .waiting { tail += (tail.isEmpty ? "" : " · ") + (s < 60 ? String(format: "%.1fs", max(0, s)) : String(format: "%d:%02d", Int(s) / 60, Int(s) % 60)) }
        let time = EVAStyle.label(tail, EVAStyle.mono(9.5), color)
        let chevron = EVAStyle.label(info.output.isEmpty ? " " : expanded ? "▾" : "▸", EVAStyle.mono(10), EVAStyle.faint)
        let line = EVATheme.horizontal([lead, label, detail, EVATheme.spacer(), time, chevron], spacing: 8)
        let stack = EVATheme.vertical([line], spacing: 6)
        if expanded && !info.output.isEmpty {
            let lines = info.output.components(separatedBy: "\n"), shown = lines.suffix(80).joined(separator: "\n")
            let output = NSTextField(wrappingLabelWithString: (lines.count > 80 ? "…（只显示最后 80 行）\n" : "") + String(shown.suffix(12000)))
            output.font = EVAStyle.mono(10.5); output.textColor = EVAStyle.controlText; output.isSelectable = true
            output.drawsBackground = true; output.backgroundColor = MarkdownTheme.blockBackground
            stack.addArrangedSubview(output); output.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -20).isActive = true
            stack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 4, right: 0)
        }
        stack.translatesAutoresizingMaskIntoConstraints = false; addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20), stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8), stack.topAnchor.constraint(equalTo: topAnchor, constant: 4), stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4), line.widthAnchor.constraint(equalTo: stack.widthAnchor)])
        toolTip = info.detail.isEmpty ? info.label : info.label + "\n" + info.detail
    }
    required init?(coder: NSCoder) { fatalError() }
    override func mouseDown(with event: NSEvent) { if !info.output.isEmpty { onToggle(info.id) } }
    override func resetCursorRects() { if !info.output.isEmpty { addCursorRect(bounds, cursor: .pointingHand) } }
    override func draw(_ dirtyRect: NSRect) { EVAStyle.outline.setFill(); NSRect(x: 8, y: 0, width: 1, height: bounds.height).fill() }
}

/// "What is it doing now" line shown under the transcript while a turn runs.
final class ActivityStatusRow: NSView {
    override var isFlipped: Bool { true }
    init(_ text: String, waiting: Bool) {
        super.init(frame: .zero)
        let spinner = NSProgressIndicator(); spinner.style = .spinning; spinner.controlSize = .small; spinner.startAnimation(nil)
        spinner.widthAnchor.constraint(equalToConstant: 14).isActive = true; spinner.heightAnchor.constraint(equalToConstant: 14).isActive = true
        let label = EVAStyle.label(text, EVAStyle.ui(12, .medium), waiting ? EVAStyle.gold : EVAStyle.orange); label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let row = EVATheme.horizontal(waiting ? [EVAStyle.label("⏸", EVAStyle.mono(12, .bold), EVAStyle.gold), label] : [spinner, label], spacing: 9)
        row.translatesAutoresizingMaskIntoConstraints = false; addSubview(row)
        NSLayoutConstraint.activate([row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18), row.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8), row.topAnchor.constraint(equalTo: topAnchor, constant: 10), row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)])
    }
    required init?(coder: NSCoder) { fatalError() }
}

@MainActor
extension NativeWorkbench {
    /// Steps of the selected thread keyed by their transcript position; plus the current activity sentence.
    func activitySnapshot(_ t: JSON) -> (byPosition: [Int: [StepInfo]], live: String?, waiting: Bool) {
        let project = string(currentProject?["path"]), tools = objects(t["tools"])
        let waitingIDs = Set(objects(state["approvals"]).filter { string(object($0["params"])["threadId"]) == string(t["id"]) }.compactMap { a -> String? in
            let p = object(a["params"]); return [string(p["itemId"]), string(p["toolUseId"]), string(p["tool_use_id"])].first { !$0.isEmpty }
        })
        var byPosition: [Int: [StepInfo]] = [:]
        for tool in tools { guard let at = tool["at"] as? Int, let info = stepInfo(tool, project: project, tools: tools, waiting: waitingIDs) else { continue }; byPosition[at, default: []].append(info) }
        let busy = string(t["status"]) == "inProgress" || !string(t["activeTurn"]).isEmpty
        guard busy else { return (byPosition, nil, false) }
        let hasApproval = objects(state["approvals"]).contains { string(object($0["params"])["threadId"]) == string(t["id"]) }
        if hasApproval { return (byPosition, "等待你确认操作…", true) }
        let running = tools.compactMap { stepInfo($0, project: project, tools: tools, waiting: []) }.last { $0.state == .running }
        let who = string(t["provider"]) == "claude" ? "Claude Code" : "Codex", messages = objects(t["messages"])
        if let running { return (byPosition, "\(who) 正在\(running.label)" + (running.detail.isEmpty ? "" : "：" + running.detail), false) }
        if string(messages.last?["role"]) == "assistant" { return (byPosition, "\(who) 正在回复…", false) }
        return (byPosition, "\(who) 正在思考…", false)
    }
    func stepViews(_ steps: [StepInfo]) -> [NSView] {
        steps.map { info in StepRow(info, expanded: expandedSteps.contains(info.id)) { [weak self] id in
            guard let self else { return }; if self.expandedSteps.contains(id) { self.expandedSteps.remove(id) } else { self.expandedSteps.insert(id) }; self.renderMessages(force: true)
        } }
    }
    func activitySignature(_ t: JSON) -> String {
        objects(t["tools"]).map { string($0["id"]) + string($0["status"]) + "\(string($0["aggregatedOutput"]).count)\(string($0["output"]).count)" }.joined(separator: ",")
            + "|" + string(t["status"]) + string(t["activeTurn"]) + "|\(objects(state["approvals"]).count)|" + expandedSteps.sorted().joined(separator: ",")
    }
}
