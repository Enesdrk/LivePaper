import Foundation

public final class CommandStore {
    private let fm: FileManager

    public init(fileManager: FileManager = .default) {
        self.fm = fileManager
    }

    public func defaultCommandPath() throws -> URL {
        let dir = try SharedPaths.liveSceneAppSupportDirectory(fileManager: fm)
        return dir.appendingPathComponent("worker-command.json", isDirectory: false)
    }

    public func load(from url: URL) throws -> WorkerCommand? {
        guard fm.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(WorkerCommand.self, from: data)
    }

    public func save(_ command: WorkerCommand, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let dir = url.deletingLastPathComponent()
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        let data = try encoder.encode(command)
        try data.write(to: url, options: .atomic)
    }

    public func clear(at url: URL) throws {
        guard fm.fileExists(atPath: url.path) else { return }
        try fm.removeItem(at: url)
    }
}
