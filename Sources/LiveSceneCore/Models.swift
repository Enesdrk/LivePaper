import Foundation

public enum ScaleMode: String, Codable, CaseIterable {
    case fill
    case fit
    case stretch
    case center
}

public struct DisplayAssignment: Codable, Hashable {
    public var displayID: UInt32
    public var videoPath: String

    public init(displayID: UInt32, videoPath: String) {
        self.displayID = displayID
        self.videoPath = videoPath
    }
}

public struct LiveSceneConfig: Codable {
    public var schemaVersion: Int
    public var sourceFolder: String
    public var selectedVideoPath: String?
    public var wallpaperSelectedVideoPath: String?
    public var screenSaverSelectedVideoPath: String?
    public var startAtLogin: Bool
    public var muteAudio: Bool
    public var scaleMode: ScaleMode
    public var displayAssignments: [DisplayAssignment]
    public var userPaused: Bool?
    public var optimizeForEfficiency: Bool?
    public var privacyModeEnabled: Bool?

    public init(
        schemaVersion: Int = 1,
        sourceFolder: String = "",
        selectedVideoPath: String? = nil,
        wallpaperSelectedVideoPath: String? = nil,
        screenSaverSelectedVideoPath: String? = nil,
        startAtLogin: Bool = false,
        muteAudio: Bool = true,
        scaleMode: ScaleMode = .fill,
        displayAssignments: [DisplayAssignment] = [],
        userPaused: Bool? = false,
        optimizeForEfficiency: Bool? = true,
        privacyModeEnabled: Bool? = true
    ) {
        self.schemaVersion = schemaVersion
        self.sourceFolder = sourceFolder
        self.selectedVideoPath = selectedVideoPath
        self.wallpaperSelectedVideoPath = wallpaperSelectedVideoPath
        self.screenSaverSelectedVideoPath = screenSaverSelectedVideoPath
        self.startAtLogin = startAtLogin
        self.muteAudio = muteAudio
        self.scaleMode = scaleMode
        self.displayAssignments = displayAssignments
        self.userPaused = userPaused
        self.optimizeForEfficiency = optimizeForEfficiency
        self.privacyModeEnabled = privacyModeEnabled
    }
}

public enum WorkerState: String, Codable {
    case stopped
    case running
    case paused
    case error
}

public struct WorkerStatus: Codable {
    public var pid: Int32
    public var state: WorkerState
    public var currentVideoPath: String?
    public var activeDisplayCount: Int?
    public var cpuPercent: Double?
    public var memoryMB: Double?
    public var playbackRate: Float?
    public var message: String?
    public var updatedAt: Date

    public init(
        pid: Int32,
        state: WorkerState,
        currentVideoPath: String? = nil,
        activeDisplayCount: Int? = nil,
        cpuPercent: Double? = nil,
        memoryMB: Double? = nil,
        playbackRate: Float? = nil,
        message: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.pid = pid
        self.state = state
        self.currentVideoPath = currentVideoPath
        self.activeDisplayCount = activeDisplayCount
        self.cpuPercent = cpuPercent
        self.memoryMB = memoryMB
        self.playbackRate = playbackRate
        self.message = message
        self.updatedAt = updatedAt
    }
}

public enum WorkerCommandAction: String, Codable {
    case clearPlayableCache
    case resetRuntimeState
}

public struct WorkerCommand: Codable {
    public var action: WorkerCommandAction
    public var requestedAt: Date

    public init(action: WorkerCommandAction, requestedAt: Date = Date()) {
        self.action = action
        self.requestedAt = requestedAt
    }
}

public enum LiveSceneCoreError: Error, LocalizedError {
    case invalidConfigPath
    case invalidSourceFolder(String)

    public var errorDescription: String? {
        switch self {
        case .invalidConfigPath:
            return "Config path is invalid."
        case .invalidSourceFolder(let folder):
            return "Source folder does not exist: \(folder)"
        }
    }
}
