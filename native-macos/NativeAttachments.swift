import AppKit
import UniformTypeIdentifiers
import PDFKit

func imageFile(_ url: URL) -> Bool { ["png", "jpg", "jpeg", "webp", "heic", "heif", "bmp", "gif", "tif", "tiff"].contains(url.pathExtension.lowercased()) }
func fileUpload(_ url: URL) throws -> JSON {
    let info = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
    guard info.isRegularFile == true else { throw NSError(domain: "EVA", code: 20, userInfo: [NSLocalizedDescriptionKey: "请选择单个普通文件；文件夹请先压缩后添加。"]) }
    guard (info.fileSize ?? 0) <= 32 * 1024 * 1024 else { throw NSError(domain: "EVA", code: 21, userInfo: [NSLocalizedDescriptionKey: "每个文件不能超过 32 MB。"]) }
    if imageFile(url) { do { return try imageUpload(url) } catch { if ["png", "jpg", "jpeg"].contains(url.pathExtension.lowercased()) { throw error } } }
    let data = try Data(contentsOf: url, options: .mappedIfSafe)
    var result: JSON = ["name": url.lastPathComponent, "dataBase64": data.base64EncodedString()]
    if url.pathExtension.lowercased() == "pdf", let document = PDFDocument(url: url), !document.isLocked {
        var text = "", truncated = document.pageCount > 500
        for index in 0..<min(document.pageCount, 500) {
            text += "\n[第 \(index + 1) 页]\n" + (document.page(at: index)?.string ?? "")
            if text.count > 512000 { text = String(text.prefix(512000)); truncated = true; break }
        }
        if text.replacingOccurrences(of: "\\[第 \\d+ 页\\]", with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { text = "" }
        result["textPreview"] = text; result["previewTruncated"] = truncated
    }
    return result
}

@MainActor
extension NativeWorkbench {
    func uploadFiles(_ urls: [URL]) {
        guard attachButton.isEnabled else { notice("请先在可发送的会话中添加文件。"); return }
        let epoch = draftEpoch, capacity = max(0, 8 - draftAttachments.count - pendingUploads)
        if urls.count > capacity { notice("每条消息最多 8 个附件，超出的文件未添加。") }
        for url in urls.prefix(capacity) {
            let image = imageFile(url)
            if image && draftAttachments.filter({ string($0["mime"]).hasPrefix("image/") }).count + pendingImageUploads >= 4 { notice("每条消息最多 4 张图片。"); continue }
            pendingUploads += 1; if image { pendingImageUploads += 1 }; updateControls()
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let prepared = Result { try fileUpload(url) }
                DispatchQueue.main.async {
                    guard let self else { return }
                    switch prepared {
                    case .failure(let error): self.pendingUploads -= 1; if image { self.pendingImageUploads -= 1 }; self.notice(error.localizedDescription); self.updateControls()
                    case .success(let body):
                        self.api.request("/api/attachment", body: body, timeout: 90) { [weak self] result in
                            guard let self else { return }; self.pendingUploads -= 1; if image { self.pendingImageUploads -= 1 }
                            switch result {
                            case .success(let value): if self.draftEpoch == epoch { self.draftAttachments.append(object(value)); self.renderAttachments() }
                            case .failure(let error): self.notice(error.localizedDescription)
                            }
                            self.updateControls()
                        }
                    }
                }
            }
        }
    }
    @objc func previewDraftFile(_ sender: NSButton) { if let id = sender.identifier?.rawValue, let file = draftAttachments.first(where: { string($0["id"]) == id }) { openImage(file) } }
    func previewAttachment(_ file: JSON) {
        guard !string(file["id"]).isEmpty else { return }
        perform("/api/attachment-info", query: ["id": string(file["id"])]) { value in
            let data = object(value), item = object(data["item"]), text = string(data["text"])
            let preview = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 620), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            preview.title = string(item["name"]); preview.isReleasedWhenClosed = false; preview.delegate = self; preview.backgroundColor = EVATheme.background
            let header = EVATheme.label(string(item["readability"]) + " · " + ByteCountFormatter.string(fromByteCount: Int64((item["bytes"] as? Int) ?? 0), countStyle: .file), size: 12, color: EVATheme.orange)
            let hint = NSTextField(wrappingLabelWithString: (flag(data["previewTruncated"]) ? "这里只显示部分文字，原文件完整保留。\n" : "") + string(item["warning"]))
            hint.font = .systemFont(ofSize: 11); hint.textColor = EVATheme.muted
            let body = NSTextView(); body.isEditable = false; body.isSelectable = true; body.font = .monospacedSystemFont(ofSize: 12, weight: .regular); body.textColor = EVATheme.cream; body.backgroundColor = EVATheme.panel
            body.string = text.isEmpty ? "此文件已保存，但没有可直接预览的文字。可通过支持该格式的工具读取；文件内容不会被自动执行。" : text
            let scroll = NSScrollView(); scroll.documentView = body; scroll.hasVerticalScroller = true
            let reveal = EVATheme.button("在 Finder 中显示原文件", target: self, action: #selector(NativeWorkbench.revealAttachment(_:))); reveal.identifier = NSUserInterfaceItemIdentifier(string(data["file"]))
            let content = EVATheme.vertical([header, hint, scroll, reveal], spacing: 12); preview.contentView = self.pinned(content, padding: 20, color: EVATheme.background)
            header.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true; hint.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true; scroll.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true; scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 250).isActive = true
            preview.center(); preview.makeKeyAndOrderFront(nil); self.imageWindows.append(preview)
        }
    }
    @objc func revealAttachment(_ sender: NSButton) { if let path = sender.identifier?.rawValue { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) } }
    @objc func previewTransfer() { if let id = object(selectedThread?["transfer"])["fileId"] as? String { previewAttachment(["id": id]) } }
    @objc func transferConversation() { startTransfer(recent: false) }
    func startTransfer(recent: Bool) {
        guard let source = selectedThread, !sending else { return }
        let id = string(source["id"]), target = provider == "claude" ? "codex" : "claude"
        sending = true; updateControls(); notice("正在把这段对话交给\(target == "claude" ? " Claude Code" : " Codex")…")
        api.request("/api/thread/transfer", body: ["threadId": id, "targetProvider": target, "recent": recent, "inPlace": true], timeout: 120) { [weak self] result in
            guard let self else { return }; self.sending = false
            switch result {
            case .success(let value): self.notice(""); self.useThread(object(object(value)["thread"])); self.window.makeFirstResponder(self.composer)
            case .failure(let error):
                self.notice(error.localizedDescription)
                if !recent && error.localizedDescription.contains("8 MB") {
                    let alert = NSAlert(); alert.messageText = "来源会话过长"; alert.informativeText = "完整转录超过 8 MB。是否只把最近 200 条可读取消息交给另一助手？原记录会保留。"; alert.addButton(withTitle: "取消"); alert.addButton(withTitle: "只带最近 200 条")
                    alert.beginSheetModal(for: self.window) { response in if response == .alertSecondButtonReturn && self.selectedThreadID == id { self.startTransfer(recent: true) } }
                }
            }
            self.updateControls()
        }
    }
}
