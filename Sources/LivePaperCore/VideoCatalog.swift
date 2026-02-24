import Foundation

public struct VideoItem: Hashable {
    public let path: String
    public let name: String

    public init(path: String, name: String) {
        self.path = path
        self.name = name
    }
}

public final class VideoCatalog {
    private let fm: FileManager
    private let allowedExtensions: Set<String>

    public init(fileManager: FileManager = .default, allowedExtensions: Set<String> = ["mp4", "mov", "m4v"]) {
        self.fm = fileManager
        self.allowedExtensions = allowedExtensions
    }

    public func scan(folderPath: String) throws -> [VideoItem] {
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: folderPath, isDirectory: &isDir), isDir.boolValue else {
            throw LivePaperCoreError.invalidSourceFolder(folderPath)
        }

        let files = try fm.contentsOfDirectory(atPath: folderPath)
        let items = files.compactMap { entry -> VideoItem? in
            let ext = URL(fileURLWithPath: entry).pathExtension.lowercased()
            guard allowedExtensions.contains(ext) else { return nil }

            let full = (folderPath as NSString).appendingPathComponent(entry)
            return VideoItem(path: full, name: entry)
        }

        return items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
