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

final class AppDelegate: NSObject, NSApplicationDelegate {
    let picker = Picker()

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = self
    }

    // "Copy Full Path" service (NSServices in build.sh): puts the selected items' paths on the clipboard.
    @objc func copyPath(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        let urls = pboard.readObjects(forClasses: [NSURL.self]) as? [URL] ?? []
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
        NSApp.terminate(nil)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A launch to run the service isn't a default launch; skip the menu.
        if notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool == false { return }
        NSApp.activate(ignoringOtherApps: true)
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
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
