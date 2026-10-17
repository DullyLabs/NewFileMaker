import AppKit
import UniformTypeIdentifiers

// File types offered in the menu: (label, extension, initial contents).
let types: [(String, String, String)] = [
    ("Text File", "txt", ""),
    ("Markdown File", "md", ""),
    ("Rich Text", "rtf", "{\\rtf1}"),
    ("Shell Script", "sh", "#!/bin/zsh\n"),
    ("Python Script", "py", ""),
    ("Swift File", "swift", ""),
    ("JSON", "json", "{}\n"),
    ("HTML", "html", "<!doctype html>\n"),
    ("CSV", "csv", ""),
]

func finderDirectory() -> URL {
    let src = "tell application \"Finder\" to POSIX path of (insertion location as alias)"
    let path = NSAppleScript(source: src)?.executeAndReturnError(nil).stringValue
    return URL(fileURLWithPath: path ?? NSHomeDirectory() + "/Desktop")
}

func uniqueURL(in dir: URL, ext: String) -> URL {
    var url = dir.appendingPathComponent("Untitled.\(ext)")
    var n = 2
    while FileManager.default.fileExists(atPath: url.path) {
        url = dir.appendingPathComponent("Untitled \(n).\(ext)")
        n += 1
    }
    return url
}

final class Picker: NSObject {
    var choice: Int?
    @objc func pick(_ item: NSMenuItem) { choice = item.tag }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.activate(ignoringOtherApps: true)

let picker = Picker()
let menu = NSMenu()
for (i, t) in types.enumerated() {
    let item = NSMenuItem(title: t.0, action: #selector(Picker.pick(_:)), keyEquivalent: "")
    item.target = picker
    item.tag = i
    item.image = NSWorkspace.shared.icon(for: UTType(filenameExtension: t.1) ?? .data)
    item.image?.size = NSSize(width: 18, height: 18)
    menu.addItem(item)
}
menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)

if let i = picker.choice {
    let (_, ext, body) = types[i]
    let url = uniqueURL(in: finderDirectory(), ext: ext)
    let attrs: [FileAttributeKey: Any]? = ext == "sh" ? [.posixPermissions: 0o755] : nil
    FileManager.default.createFile(atPath: url.path, contents: Data(body.utf8), attributes: attrs)
    NSWorkspace.shared.activateFileViewerSelecting([url])
}
