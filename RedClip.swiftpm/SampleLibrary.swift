import Foundation
import UniformTypeIdentifiers

/// Red Clip's own folder in the Files app: On My iPad › Red Clip › Samples.
/// Drop audio in there (from Files, AirDrop, another app) and it shows up under SAMPLES.
/// Files picked with LOAD from anywhere else are copied in too, so they stay available.
enum SampleLibrary {
    static let audioExtensions: Set<String> = ["wav", "aif", "aiff", "caf", "mp3", "m4a", "aac", "flac"]

    static var folder: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Samples", isDirectory: true)
    }

    /// Makes the folder on first launch so it's visible in Files straight away.
    static func prepareFolder() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: folder.path) {
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        }
    }

    /// Every audio file in Samples, including sub-folders, sorted by name.
    static func list() -> [URL] {
        prepareFolder()
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil,
                                                          options: [.skipsHiddenFiles]) else { return [] }
        var found: [URL] = []
        for case let url as URL in walker where audioExtensions.contains(url.pathExtension.lowercased()) {
            found.append(url)
        }
        return found.sorted { relativeName($0).localizedStandardCompare(relativeName($1)) == .orderedAscending }
    }

    /// "Drums/Kick 01" for Samples/Drums/Kick 01.wav
    static func relativeName(_ url: URL) -> String {
        let base = folder.standardizedFileURL.path
        var path = url.deletingPathExtension().standardizedFileURL.path
        if path.hasPrefix(base) { path.removeFirst(base.count) }
        return path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    /// Copies a file picked in Files into Samples (unless it's already there). Returns the copy.
    static func importCopy(of url: URL) -> URL? {
        prepareFolder()
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        if url.standardizedFileURL.path.hasPrefix(folder.standardizedFileURL.path) { return url }
        let fm = FileManager.default
        var target = folder.appendingPathComponent(url.lastPathComponent)
        var n = 2
        while fm.fileExists(atPath: target.path) {
            if let a = try? target.resourceValues(forKeys: [.fileSizeKey]).fileSize,
               let b = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, a == b { return target }
            target = folder.appendingPathComponent("\(url.deletingPathExtension().lastPathComponent) \(n).\(url.pathExtension)")
            n += 1
        }
        do { try fm.copyItem(at: url, to: target); return target } catch { return nil }
    }
}
