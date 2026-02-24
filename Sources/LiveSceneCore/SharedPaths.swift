import Foundation

#if canImport(Darwin)
import Darwin
#endif

enum SharedPaths {
    static func liveSceneAppSupportDirectory(fileManager: FileManager = .default) throws -> URL {
        let homePath = resolvedUserHomePath()
        let dir = URL(fileURLWithPath: homePath, isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("LiveScene", isDirectory: true)

        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private static func resolvedUserHomePath() -> String {
        #if canImport(Darwin)
        var st = stat()
        if stat("/dev/console", &st) == 0,
           let consolePw = getpwuid(st.st_uid),
           let consoleHome = consolePw.pointee.pw_dir {
            return String(cString: consoleHome)
        }

        if let pw = getpwuid(getuid()), let raw = pw.pointee.pw_dir {
            return String(cString: raw)
        }
        #endif
        return NSHomeDirectory()
    }
}
