import AppKit
import WebKit

/// One MIME entity. Text is held as Latin-1 so every byte survives until it is decoded.
struct MIMEPart {
    let headers: [String: String]
    let body: String

    init(raw: String) {
        // A part that opens with a blank line has no headers.
        let split = raw.hasPrefix("\n") ? raw.startIndex..<raw.index(after: raw.startIndex) : raw.range(of: "\n\n")
        body = split.map { String(raw[$0.upperBound...]) } ?? ""
        var h: [String: String] = [:]
        let head = split.map { String(raw[..<$0.lowerBound]) } ?? raw
        for line in head.replacingOccurrences(of: "\n[ \t]+", with: " ", options: .regularExpression).split(separator: "\n") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            let name = line[..<colon].lowercased()
            if h[name] == nil { h[name] = String(data: value.data(using: .isoLatin1)!, encoding: .utf8) ?? value }
        }
        headers = h
    }

    var type: String { (headers["content-type"] ?? "text/plain").prefix { $0 != ";" }.trimmingCharacters(in: .whitespaces).lowercased() }
    var isAttachment: Bool { headers["content-disposition"]?.lowercased().hasPrefix("attachment") ?? false }

    func param(_ name: String) -> String? {
        let ct = headers["content-type"] ?? ""
        guard let r = ct.range(of: "(?<![\\w-])\(name)\\s*=\\s*(\"[^\"]*\"|[^;\\s]+)", options: [.regularExpression, .caseInsensitive]) else { return nil }
        return ct[r].split(separator: "=", maxSplits: 1)[1].trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
    }

    /// The non-multipart parts, depth first.
    var leaves: [MIMEPart] {
        guard type.hasPrefix("multipart/"), let b = param("boundary") else { return [self] }
        return ("\n" + body).components(separatedBy: "\n--" + b).dropFirst()
            .filter { !$0.hasPrefix("--") }
            .flatMap { MIMEPart(raw: String($0.drop { $0 != "\n" }.dropFirst())).leaves }
    }

    var data: Data {
        switch headers["content-transfer-encoding"]?.lowercased() {
        case "base64": Data(base64Encoded: body, options: .ignoreUnknownCharacters) ?? Data()
        case "quoted-printable": decodeQP(body)
        default: body.data(using: .isoLatin1)!
        }
    }

    var text: String { decodeText(data, charset: param("charset")) }
}

func decodeText(_ data: Data, charset: String?) -> String {
    let cf = charset.map { CFStringConvertIANACharSetNameToEncoding($0 as CFString) } ?? kCFStringEncodingInvalidId
    let encoding = cf == kCFStringEncodingInvalidId ? .utf8 : String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
    return String(data: data, encoding: encoding) ?? String(decoding: data, as: UTF8.self)
}

/// File names are capped at 255 bytes; leave room for " 2" and ".pdf".
func cappedFileName(_ name: String) -> String {
    var name = name
    while name.utf8.count > 240 { name.removeLast() }
    return name
}

func decodeQP(_ s: String) -> Data {
    let joined = s.replacingOccurrences(of: "=\n", with: "")
    let bytes = Array(joined.data(using: .isoLatin1) ?? Data(joined.utf8))
    var out = Data()
    var i = 0
    while i < bytes.count {
        if bytes[i] == UInt8(ascii: "="), i + 2 < bytes.count, let v = UInt8(String(decoding: bytes[i + 1...i + 2], as: UTF8.self), radix: 16) {
            out.append(v)
            i += 3
        } else {
            out.append(bytes[i])
            i += 1
        }
    }
    return out
}

/// Decodes RFC 2047 encoded words such as =?UTF-8?B?...?= in a header.
func decodeHeader(_ s: String) -> String {
    let re = try! NSRegularExpression(pattern: "=\\?([^?]+)\\?([BbQq])\\?([^?]*)\\?=(\\s+(?==\\?))?")
    var out = s
    for m in re.matches(in: s, range: NSRange(s.startIndex..., in: s)).reversed() {
        let g = { Range(m.range(at: $0), in: s).map { String(s[$0]) } ?? "" }
        let data = g(2).uppercased() == "B" ? Data(base64Encoded: g(3), options: .ignoreUnknownCharacters) ?? Data()
                                            : decodeQP(g(3).replacingOccurrences(of: "_", with: " "))
        out.replaceSubrange(Range(m.range, in: out)!, with: decodeText(data, charset: g(1)))
    }
    return out
}

func escapeHTML(_ s: String) -> String {
    s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
}

/// Renders raw emails (RFC 822 source) to paginated PDFs with an offscreen web view.
@MainActor final class EmailPDF: NSObject, WKNavigationDelegate {
    private let web: WKWebView
    private let window: NSWindow
    private var loaded: CheckedContinuation<Void, Never>?
    private var printed: CheckedContinuation<Bool, Never>?
    private let content: WKUserContentController
    private var blocksRemote = false

    override init() {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        content = config.userContentController
        web = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 1000), configuration: config)
        window = NSWindow(contentRect: web.frame, styleMask: .borderless, backing: .buffered, defer: false)
        super.init()
        window.contentView = web
        web.navigationDelegate = self
    }

    /// Saves the email as "<subject>.pdf" in `dir` and returns where it went.
    func save(source: Data, in dir: URL) async throws -> URL {
        let raw = String(data: source, encoding: .isoLatin1)!.replacingOccurrences(of: "\r\n", with: "\n")
        let message = MIMEPart(raw: raw)
        let leaves = message.leaves
        let parts = leaves.filter { !$0.isAttachment }
        var html = parts.first { $0.type == "text/html" }?.text
            ?? "<pre style='white-space:pre-wrap;font:13px -apple-system'>\(escapeHTML(parts.first { $0.type == "text/plain" }?.text ?? ""))</pre>"
        for part in leaves {
            guard let id = part.headers["content-id"]?.trimmingCharacters(in: CharacterSet(charactersIn: "<> ")), html.contains("cid:\(id)") else { continue }
            html = html.replacingOccurrences(of: "cid:\(id)", with: "data:\(part.type);base64,\(part.data.base64EncodedString())")
        }
        let header = ["From", "To", "Cc", "Date", "Subject"].compactMap { key in
            message.headers[key.lowercased()].map { "<b>\(key):</b> \(escapeHTML(decodeHeader($0)))<br>" }
        }.joined()
        if !blocksRemote {
            // Block every load with a scheme:// URL (images, CSS, fonts, frames, refreshes) so senders can't see the email was opened.
            // The page itself is about:blank and inline images are data: URLs, so they still render.
            let rules = #"[{"trigger":{"url-filter":"^[a-z0-9+.-]+://"},"action":{"type":"block"}}]"#
            let list = try await WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "BlockRemote", encodedContentRuleList: rules)
            content.add(list!)
            blocksRemote = true
        }
        let page = "<meta charset='utf-8'><div style='font:13px -apple-system;padding-bottom:8px;margin-bottom:12px;border-bottom:1px solid #ccc'>\(header)</div>\(html)"

        await withCheckedContinuation { loaded = $0; web.loadHTMLString(page, baseURL: nil) }

        var subject = decodeHeader(message.headers["subject"] ?? "").components(separatedBy: CharacterSet(charactersIn: "/:\n")).joined(separator: "-")
        subject = cappedFileName(subject)
        let out = uniqueURL(in: dir, name: subject.trimmingCharacters(in: .whitespaces).isEmpty ? "Email" : subject, ext: "pdf")
        let info = NSPrintInfo()
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = out
        info.horizontalPagination = .fit
        info.isVerticallyCentered = false
        let op = web.printOperation(with: info)
        op.showsPrintPanel = false
        op.showsProgressPanel = false
        op.view?.frame = web.bounds
        let ok = await withCheckedContinuation {
            printed = $0
            op.runModal(for: window, delegate: self, didRun: #selector(didPrint(_:success:context:)), contextInfo: nil)
        }
        guard ok, FileManager.default.fileExists(atPath: out.path) else { throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: out.path]) }
        return out
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        MainActor.assumeIsolated { loaded?.resume(); loaded = nil }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        MainActor.assumeIsolated { loaded?.resume(); loaded = nil }
    }

    @objc func didPrint(_ op: NSPrintOperation, success: Bool, context: UnsafeMutableRawPointer?) {
        printed?.resume(returning: success)
        printed = nil
    }
}

/// The alert shown when some emails couldn't be saved; each error names its PDF.
func pdfFailureAlert(_ errors: [Error]) -> (title: String, text: String) {
    let title = errors.count == 1 ? "1 email couldn't be saved as a PDF" : "\(errors.count) emails couldn't be saved as PDFs"
    return (title, errors.map(\.localizedDescription).joined(separator: "\n"))
}
