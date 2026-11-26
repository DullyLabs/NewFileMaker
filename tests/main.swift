// Run: swiftc Finder.swift Templates.swift EmailPDF.swift tests/main.swift -o $TMPDIR/t && $TMPDIR/t
import AppKit
import Network
import PDFKit

let fm = FileManager.default
let root = URL(filePath: ProcessInfo.processInfo.environment["TMPDIR"] ?? NSTemporaryDirectory()).appending(path: UUID().uuidString)
let src = root.appending(path: "Templates"), out = root.appending(path: "out")
try fm.createDirectory(at: src.appending(path: "Skeleton/sub"), withIntermediateDirectories: true)
try fm.createDirectory(at: out, withIntermediateDirectories: true)
for name in ["starter.sh", "Makefile", "invoice 10.txt", "invoice 9.txt", ".DS_Store", "Skeleton/sub/a.txt"] { try Data().write(to: src.appending(path: name)) }
try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: src.appending(path: "starter.sh").path)
defer { try? fm.removeItem(at: root) }

func check(_ ok: Bool, _ what: String) { print(ok ? "PASS" : "FAIL", what); if !ok { exit(1) } }

check(templates(in: src).map(\.lastPathComponent) == ["invoice 9.txt", "invoice 10.txt", "Makefile", "Skeleton", "starter.sh"], "Finder name order, hidden files skipped")
check(templates(in: root.appending(path: "missing")).isEmpty, "missing folder lists nothing")
let names = try ["Makefile", "Makefile", "starter.sh", "starter.sh", "Skeleton"].map { try copyTemplate(src.appending(path: $0), to: out).lastPathComponent }
check(names == ["Makefile", "Makefile 2", "starter.sh", "starter 2.sh", "Skeleton"], "copies keep the template's name, numbered, no trailing dot")
check(fm.isExecutableFile(atPath: out.appending(path: "starter.sh").path), "scripts stay executable")
check(fm.fileExists(atPath: out.appending(path: "Skeleton/sub/a.txt").path), "folders are copied whole")
check(uniqueURL(in: out, name: "Email", ext: "pdf").lastPathComponent == "Email.pdf", "email PDF names unchanged")
check(newFileFolder(path: nil, errorNumber: errAEEventNotPermitted) == nil, "Finder access denied gives no folder, not the Desktop")
check(newFileFolder(path: nil, errorNumber: -600)?.path == NSHomeDirectory() + "/Desktop", "other script errors fall back to the Desktop")
check(newFileFolder(path: "/tmp/x/", errorNumber: nil)?.path == "/tmp/x", "the Finder folder is used when allowed")
check(cappedFileName(String(repeating: "é", count: 300)).utf8.count <= 240, "long non-Latin subjects fit in a file name")
check(MIMEPart(raw: "\nbody").headers.isEmpty && MIMEPart(raw: "\nbody").body == "body", "a part opening with a blank line has no headers")
check(String(decoding: decodeQP("caf=C3=A9 \u{4F60}"), as: UTF8.self) == "café \u{4F60}", "quoted-printable with non-Latin text does not crash")
check(mailSelection(list: nil, error: [NSAppleScript.errorNumber: errAEEventNotPermitted]) == .denied, "Mail access off is reported, not read as no emails")
check(mailSelection(list: nil, error: [NSAppleScript.errorNumber: -600, NSAppleScript.errorMessage: "Mail isn’t running."]) == .failed("Mail isn’t running."), "other Mail script errors are reported")
check(pdfFailureAlert([CocoaError(.fileWriteNoPermission, userInfo: [NSFilePathErrorKey: "/ro/Hi.pdf"])]).title == "1 email couldn't be saved as a PDF", "a failed PDF is counted in the alert")
check(pdfFailureAlert([CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: "/ro/Hi.pdf"])]).text.contains("Hi.pdf"), "the alert names the PDF that failed")

// Saving an email as a PDF makes no network requests (issue #5).
var hits = 0
let listener = try NWListener(using: .tcp, on: .any)
listener.newConnectionHandler = { c in hits += 1; c.cancel() }
listener.start(queue: .main)
while listener.port == nil { RunLoop.main.run(until: .now + 0.05) }
let remote = "http://127.0.0.1:\(listener.port!.rawValue)"
let png = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg=="
let email = """
Subject: Tracked\nContent-Type: multipart/related; boundary=b\n\n--b\nContent-Type: text/html\n
<meta http-equiv="refresh" content="0;url=\(remote)/x"><link rel=stylesheet href="\(remote)/s.css"><link rel=preconnect href="\(remote)">
<style>@import url(\(remote)/i.css); @font-face{font-family:f;src:url(\(remote)/f.woff)} p{font-family:f;background:url(\(remote)/b.png)}</style>
<p>Hi</p><img src="\(remote)/p.png"><img srcset="\(remote)/s.png 2x"><iframe src="\(remote)/frame"></iframe><img src="cid:pic">
--b\nContent-Type: image/png\nContent-ID: <pic>\nContent-Transfer-Encoding: base64\n\n\(png)\n--b--\n
"""
_ = NSApplication.shared
var saved: URL?
var saveError: Error?
Task { @MainActor in
    do { saved = try await EmailPDF().save(source: Data(email.utf8), in: out) } catch { saveError = error }
}
while saved == nil && saveError == nil { RunLoop.main.run(until: .now + 0.05) }
RunLoop.main.run(until: .now + 1) // give a late meta refresh time to fire
check(saveError == nil && PDFDocument(url: saved!)?.string?.contains("Hi") == true, "an email with remote content still saves as a PDF of the email")
check(hits == 0, "saving an email as a PDF makes no network requests (\(hits) made)")
