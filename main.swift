import AppKit
import UniformTypeIdentifiers

// File types offered in the menu: (label, extension, initial contents).
// Extensions with a Templates/Untitled.<ext> copy that blank document instead.
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
    ("Pages Document", "pages", ""),
]

func finderDirectory() -> URL {
    let src = "tell application \"Finder\" to POSIX path of (insertion location as alias)"
    let path = NSAppleScript(source: src)?.executeAndReturnError(nil).stringValue
    return URL(fileURLWithPath: path ?? NSHomeDirectory() + "/Desktop")
}

func uniqueURL(in dir: URL, name: String = "Untitled", ext: String) -> URL {
    var url = dir.appendingPathComponent("\(name).\(ext)")
    var n = 2
    while FileManager.default.fileExists(atPath: url.path) {
        url = dir.appendingPathComponent("\(name) \(n).\(ext)")
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

    // Saves each email selected in Mail as a PDF in the Finder folder.
    func saveMailSelection() {
        let list = NSAppleScript(source: "tell application \"Mail\"\nset out to {}\nrepeat with m in (get selection)\nset end of out to source of m\nend repeat\nout\nend tell")?.executeAndReturnError(nil)
        let sources = (0..<(list?.numberOfItems ?? 0)).compactMap { list?.atIndex($0 + 1)?.stringValue }
        let dir = finderDirectory()
        Task { @MainActor in
            let renderer = EmailPDF()
            var saved: [URL] = []
            for source in sources {
                if let pdf = try? await renderer.save(source: Data(source.utf8), in: dir) { saved.append(pdf) }
            }
            NSWorkspace.shared.activateFileViewerSelecting(saved)
            NSApp.terminate(nil)
        }
    }

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
        // Launched from Mail (by the Alfred hotkey): skip the menu and save the selected emails.
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.mail" { return saveMailSelection() }
        NSApp.activate(ignoringOtherApps: true)
        // Offered only while Mail is open, so the menu never launches Mail.
        let mailOpen = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.mail").isEmpty
        let items = types.map { ($0.0, $0.1) } + (mailOpen ? [("Save Mail Selection as PDF", "pdf")] : [])
        let menu = NSMenu()
        for (i, (title, ext)) in items.enumerated() {
            if i == types.count { menu.addItem(.separator()) }
            let item = NSMenuItem(title: title, action: #selector(Picker.pick(_:)), keyEquivalent: "")
            item.target = picker
            item.tag = i
            item.image = NSWorkspace.shared.icon(for: UTType(filenameExtension: ext) ?? .data)
            item.image?.size = NSSize(width: 18, height: 18)
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)

        if picker.choice == types.count { return saveMailSelection() }
        if let i = picker.choice {
            let (_, ext, body) = types[i]
            let url = uniqueURL(in: finderDirectory(), ext: ext)
            let attrs: [FileAttributeKey: Any]? = ext == "sh" ? [.posixPermissions: 0o755] : nil
            if let template = Bundle.main.url(forResource: "Untitled", withExtension: ext) {
                try? FileManager.default.copyItem(at: template, to: url)
            } else {
                FileManager.default.createFile(atPath: url.path, contents: Data(body.utf8), attributes: attrs)
            }
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
