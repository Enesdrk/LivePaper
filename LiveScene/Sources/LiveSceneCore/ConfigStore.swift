import Foundation

public final class ConfigStore {
    private let fm: FileManager
    private let homeDirectoryProvider: () -> String

    public init(
        fileManager: FileManager = .default,
        homeDirectoryProvider: @escaping () -> String = { NSHomeDirectory() }
    ) {
        self.fm = fileManager
        self.homeDirectoryProvider = homeDirectoryProvider
    }

    public func defaultConfigPath() throws -> URL {
        let dir = try SharedPaths.liveSceneAppSupportDirectory(fileManager: fm)
        return dir.appendingPathComponent("config.json", isDirectory: false)
    }

    public func load(from url: URL) throws -> LiveSceneConfig {
        let candidatePaths = fallbackReadPaths(primary: url)
        for candidate in candidatePaths {
            guard fm.fileExists(atPath: candidate.path) else { continue }
            do {
                let data = try Data(contentsOf: candidate)
                return try JSONDecoder().decode(LiveSceneConfig.self, from: data)
            } catch {
                continue
            }
        }
        return LiveSceneConfig()
    }

    public func save(_ config: LiveSceneConfig, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)

        let dir = url.deletingLastPathComponent()
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        try data.write(to: url, options: .atomic)
    }

    private func fallbackReadPaths(primary: URL) -> [URL] {
        var urls: [URL] = [primary]

        // Legacy fallback for cases where caller resolved a different home than current process home.
        let legacyHomeCandidate = URL(fileURLWithPath: homeDirectoryProvider(), isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("LiveScene", isDirectory: true)
            .appendingPathComponent("config.json", isDirectory: false)
        urls.append(legacyHomeCandidate)

        var seen = Set<String>()
        return urls.filter { seen.insert($0.path).inserted }
    }
}
