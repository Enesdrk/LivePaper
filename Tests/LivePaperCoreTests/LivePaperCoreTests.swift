import XCTest
@testable import LivePaperCore

final class LivePaperCoreTests: XCTestCase {
    func testPolicyCriticalThermalPauses() {
        let policy = PlaybackPolicy(maxCPUPercent: 30)
        let env = PlaybackEnvironment(onBattery: false, lowPowerMode: false, thermalPressure: 3, processCPUPercent: 5)
        XCTAssertEqual(policy.evaluate(env), .pause("critical_thermal"))
    }

    func testPolicyBatteryReducesRate() {
        let policy = PlaybackPolicy(maxCPUPercent: 30)
        let env = PlaybackEnvironment(onBattery: true, lowPowerMode: false, thermalPressure: 1, processCPUPercent: 20)
        XCTAssertEqual(policy.evaluate(env), .runReducedRate(0.75))
    }

    func testStatusStoreRoundTrip() throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        let path = tmp.appendingPathComponent("status.json")
        let store = StatusStore(fileManager: fm)
        let status = WorkerStatus(
            pid: 123,
            state: .running,
            currentVideoPath: "/tmp/a.mp4",
            activeDisplayCount: 2,
            cpuPercent: 12.5,
            memoryMB: 256.0,
            playbackRate: 0.8,
            message: "ok"
        )
        try store.save(status, to: path)

        let loaded = try store.load(from: path)
        XCTAssertEqual(loaded?.pid, 123)
        XCTAssertEqual(loaded?.state, .running)
        XCTAssertEqual(loaded?.currentVideoPath, "/tmp/a.mp4")
        XCTAssertEqual(loaded?.activeDisplayCount, 2)
        XCTAssertEqual(loaded?.cpuPercent, 12.5)
        XCTAssertEqual(loaded?.memoryMB, 256.0)
        XCTAssertEqual(loaded?.playbackRate, 0.8)
    }

    func testConfigStorePreferredVideoRoundTrip() throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        let path = tmp.appendingPathComponent("config.json")
        let store = ConfigStore(fileManager: fm)

        var cfg = LivePaperConfig()
        cfg.sourceFolder = "/tmp/videos"
        cfg.selectedVideoPath = "/tmp/videos/preferred.mp4"
        cfg.scaleMode = .fit

        try store.save(cfg, to: path)
        let loaded = try store.load(from: path)

        XCTAssertEqual(loaded.sourceFolder, "/tmp/videos")
        XCTAssertEqual(loaded.selectedVideoPath, "/tmp/videos/preferred.mp4")
        XCTAssertEqual(loaded.scaleMode, .fit)
    }

    func testConfigStoreLoadsLegacyConfigWithoutNewFields() throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        let path = tmp.appendingPathComponent("config.json")
        let store = ConfigStore(fileManager: fm)

        let legacy = """
        {
          "schemaVersion" : 1,
          "sourceFolder" : "/tmp/videos",
          "selectedVideoPath" : null,
          "startAtLogin" : false,
          "muteAudio" : true,
          "scaleMode" : "fill",
          "displayAssignments" : []
        }
        """
        guard let data = legacy.data(using: .utf8) else {
            XCTFail("Failed to encode legacy JSON")
            return
        }
        try data.write(to: path)

        let loaded = try store.load(from: path)
        XCTAssertEqual(loaded.sourceFolder, "/tmp/videos")
        XCTAssertNil(loaded.userPaused)
        XCTAssertNil(loaded.optimizeForEfficiency)
    }

    func testConfigStoreLoadsFromInjectedHomeFallbackWhenPrimaryMissing() throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        let fakeHome = tmp.appendingPathComponent("fake-home", isDirectory: true)
        let appSupportDir = fakeHome
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("LivePaper", isDirectory: true)
        try fm.createDirectory(at: appSupportDir, withIntermediateDirectories: true)

        let fallbackPath = appSupportDir.appendingPathComponent("config.json")
        var cfg = LivePaperConfig()
        cfg.sourceFolder = "/tmp/fallback-videos"
        cfg.wallpaperSelectedVideoPath = "/tmp/fallback-videos/a.mp4"
        let encoder = JSONEncoder()
        let data = try encoder.encode(cfg)
        try data.write(to: fallbackPath, options: .atomic)

        let missingPrimary = tmp.appendingPathComponent("missing/config.json")
        let store = ConfigStore(fileManager: fm, homeDirectoryProvider: { fakeHome.path })
        let loaded = try store.load(from: missingPrimary)

        XCTAssertEqual(loaded.sourceFolder, "/tmp/fallback-videos")
        XCTAssertEqual(loaded.wallpaperSelectedVideoPath, "/tmp/fallback-videos/a.mp4")
    }

    func testDisplayVideoResolverPrefersExplicitAssignmentOverPreferred() {
        let resolver = DisplayVideoResolver()
        let displayIDs: [UInt32] = [1, 2]
        let assignments = [DisplayAssignment(displayID: 2, videoPath: "/assign-2.mp4")]
        let preferred = "/preferred.mp4"
        let catalog = ["/catalog-1.mp4", "/catalog-2.mp4"]

        let resolved = resolver.resolve(
            displayIDs: displayIDs,
            explicitAssignments: assignments,
            preferredVideoPath: preferred,
            catalogPaths: catalog
        ) { path in
            ["/assign-2.mp4", "/preferred.mp4", "/catalog-1.mp4", "/catalog-2.mp4"].contains(path)
        }

        XCTAssertEqual(resolved[1], "/preferred.mp4")
        XCTAssertEqual(resolved[2], "/assign-2.mp4")
    }

    func testDisplayVideoResolverFallsBackToCatalogRotation() {
        let resolver = DisplayVideoResolver()
        let displayIDs: [UInt32] = [10, 11, 12]
        let catalog = ["/a.mp4", "/b.mp4"]

        let resolved = resolver.resolve(
            displayIDs: displayIDs,
            explicitAssignments: [],
            preferredVideoPath: nil,
            catalogPaths: catalog
        ) { path in
            catalog.contains(path)
        }

        XCTAssertEqual(resolved[10], "/a.mp4")
        XCTAssertEqual(resolved[11], "/b.mp4")
        XCTAssertEqual(resolved[12], "/a.mp4")
    }
}
