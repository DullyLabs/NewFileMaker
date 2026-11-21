// Run: swiftc Finder.swift Templates.swift tests/main.swift -o $TMPDIR/t && $TMPDIR/t
import Foundation

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
