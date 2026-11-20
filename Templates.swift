import Foundation

// Files dropped here show up in the menu; picking one copies it into the Finder folder.
let templatesFolder = URL.applicationSupportDirectory.appending(path: "NewFileMaker/Templates")

// The folder's visible items (files, folders and packages alike), in Finder's name order.
func templates(in folder: URL = templatesFolder) -> [URL] {
    let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
    return urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
}

func uniqueURL(in dir: URL, name: String = "Untitled", ext: String) -> URL {
    let url = { (n: Int) in dir.appendingPathComponent((n == 1 ? name : "\(name) \(n)") + (ext.isEmpty ? "" : ".\(ext)")) }
    var n = 1
    while FileManager.default.fileExists(atPath: url(n).path) { n += 1 }
    return url(n)
}

// Copies a template (the file a symlink points to) under its own name, dated now so it sorts as new.
func copyTemplate(_ template: URL, to dir: URL) throws -> URL {
    let url = uniqueURL(in: dir, name: template.deletingPathExtension().lastPathComponent, ext: template.pathExtension)
    try FileManager.default.copyItem(at: template.resolvingSymlinksInPath(), to: url)
    try? FileManager.default.setAttributes([.creationDate: Date(), .modificationDate: Date()], ofItemAtPath: url.path)
    return url
}
