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
