import Foundation

let errAEEventNotPermitted = -1743

// The folder open in the front Finder window; nil if Automation access to Finder is off.
func finderDirectory() -> URL? {
    var error: NSDictionary?
    let path = NSAppleScript(source: "tell application \"Finder\" to POSIX path of (insertion location as alias)")?.executeAndReturnError(&error).stringValue
    return newFileFolder(path: path, errorNumber: error?[NSAppleScript.errorNumber] as? Int)
}

// Other script errors (e.g. Finder not running) fall back to the Desktop.
func newFileFolder(path: String?, errorNumber: Int?) -> URL? {
    if errorNumber == errAEEventNotPermitted { return nil }
    return URL(fileURLWithPath: path ?? NSHomeDirectory() + "/Desktop")
}

enum MailSelection: Equatable { case emails([String]), denied, failed(String) }

// The raw source of each email selected in Mail, or why it couldn't be read.
func mailSelection() -> MailSelection {
    var error: NSDictionary?
    let list = NSAppleScript(source: "tell application \"Mail\"\nset out to {}\nrepeat with m in (get selection)\nset end of out to source of m\nend repeat\nout\nend tell")?.executeAndReturnError(&error)
    return mailSelection(list: list, error: error)
}

func mailSelection(list: NSAppleEventDescriptor?, error: NSDictionary?) -> MailSelection {
    if let error {
        let number = error[NSAppleScript.errorNumber] as? Int
        return number == errAEEventNotPermitted ? .denied : .failed(error[NSAppleScript.errorMessage] as? String ?? "Error \(number ?? 0)")
    }
    return .emails((0..<(list?.numberOfItems ?? 0)).compactMap { list?.atIndex($0 + 1)?.stringValue })
}
