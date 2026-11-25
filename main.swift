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

// Brings the app forward first: launched from Mail by Alfred, it isn't active.
@discardableResult func show(_ alert: NSAlert) -> NSApplication.ModalResponse {
    NSApp.activate()
    return alert.runModal()
}

func show(_ title: String, _ text: String = "") {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = text
    show(alert)
}

// Explains that Automation access to an app is off and offers to open its Settings pane.
func showDeniedAlert(_ what: String) {
    let alert = NSAlert()
    alert.messageText = "New File Maker can't see \(what)"
    alert.informativeText = "Allow it in Privacy & Security > Automation."
    alert.addButton(withTitle: "Open Settings")
    alert.addButton(withTitle: "Cancel")
    if show(alert) == .alertFirstButtonReturn {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
    }
}

// Makes a file in the Finder folder and selects it, or says why it couldn't.
func makeFile(_ make: (URL) throws -> URL) {
    guard let dir = finderDirectory() else { return showDeniedAlert("your Finder folder") }
    do { NSWorkspace.shared.activateFileViewerSelecting([try make(dir)]) } catch { show(NSAlert(error: error)) }
}

enum Choice { case builtIn(Int), template(URL), openTemplates, mail }

final class Picker: NSObject {
    var choice: Choice?
    @objc func pick(_ item: NSMenuItem) { choice = item.representedObject as? Choice }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let picker = Picker()

    // Saves each email selected in Mail as a PDF in the Finder folder.
    func saveMailSelection() {
        let sources: [String]
        switch mailSelection() {
        case .emails(let found) where found.isEmpty: show("No emails are selected in Mail"); return NSApp.terminate(nil)
        case .emails(let found): sources = found
        case .denied: showDeniedAlert("your Mail selection"); return NSApp.terminate(nil)
        case .failed(let message): show("New File Maker can't read your Mail selection", message); return NSApp.terminate(nil)
        }
        guard let dir = finderDirectory() else {
            showDeniedAlert("your Finder folder")
            return NSApp.terminate(nil)
        }
        Task { @MainActor in
            let renderer = EmailPDF()
            var saved: [URL] = [], failed: [Error] = []
            for source in sources {
                do { saved.append(try await renderer.save(source: Data(source.utf8), in: dir)) } catch { failed.append(error) }
            }
            if !saved.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(saved) }
            if !failed.isEmpty { let (title, text) = pdfFailureAlert(failed); show(title, text) }
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
        let menu = NSMenu()
        func add(_ title: String, _ icon: NSImage, _ choice: Choice) {
            let item = NSMenuItem(title: title, action: #selector(Picker.pick(_:)), keyEquivalent: "")
            item.target = picker
            item.representedObject = choice
            item.image = icon
            item.image?.size = NSSize(width: 18, height: 18)
            menu.addItem(item)
        }
        for (i, (title, ext, _)) in types.enumerated() { add(title, NSWorkspace.shared.icon(for: UTType(filenameExtension: ext) ?? .data), .builtIn(i)) }
        menu.addItem(.separator())
        let found = templates()
        for url in found { add(url.deletingPathExtension().lastPathComponent, NSWorkspace.shared.icon(forFile: url.path), .template(url)) }
        if !found.isEmpty { menu.addItem(.separator()) }
        add("Open Templates Folder", NSWorkspace.shared.icon(for: .folder), .openTemplates)
        if mailOpen {
            menu.addItem(.separator())
            add("Save Mail Selection as PDF", NSWorkspace.shared.icon(for: .pdf), .mail)
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)

        switch picker.choice {
        case .mail: return saveMailSelection()
        case .openTemplates:
            try? FileManager.default.createDirectory(at: templatesFolder, withIntermediateDirectories: true)
            NSWorkspace.shared.open(templatesFolder)
        case .template(let template): makeFile { try copyTemplate(template, to: $0) }
        case .builtIn(let i):
            let (_, ext, body) = types[i]
            makeFile { dir in
                if let template = Bundle.main.url(forResource: "Untitled", withExtension: ext) { return try copyTemplate(template, to: dir) }
                let url = uniqueURL(in: dir, ext: ext)
                try Data(body.utf8).write(to: url, options: .withoutOverwriting)
                if ext == "sh" { try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path) }
                return url
            }
        case nil: break
        }
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
