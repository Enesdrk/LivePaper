import Foundation

public final class StatusStore {
    private let fm: FileManager

    public init(fileManager: FileManager = .default) {
        self.fm = fileManager
    }

    public func defaultStatusPath() throws -> URL {
        let dir = try SharedPaths.liveSceneAppSupportDirectory(fileManager: fm)
        return dir.appendingPathComponent("worker-status.json", isDirectory: false)
    }

    public func load(from url: URL) throws -> WorkerStatus? {
        guard fm.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(WorkerStatus.self, from: data)
    }

    public func save(_ status: WorkerStatus, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let dir = url.deletingLastPathComponent()
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        let data = try encoder.encode(status)
        try data.write(to: url, options: .atomic)
    }
}
