import AppKit
import AVFoundation
import Foundation
import LivePaperCore

private struct DisplayTarget {
    let id: UInt32
    let screen: NSScreen
}

private final class DisplaySession {
    let screenID: UInt32
    let screen: NSScreen
    let window: NSWindow
    let player: AVQueuePlayer
    var looper: AVPlayerLooper
    let playerLayer: AVPlayerLayer
    var videoPath: String
    private var isStopped = false

    init(screenID: UInt32, screen: NSScreen, videoPath: String, scaleMode: ScaleMode, muteAudio: Bool) {
        self.screenID = screenID
        self.screen = screen
        self.videoPath = videoPath

        let frame = screen.frame
        let window = NSWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )

        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) - 1)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.sharingType = .none

        let item = AVPlayerItem(url: URL(fileURLWithPath: videoPath))
        item.preferredForwardBufferDuration = 2.0
        let player = AVQueuePlayer(items: [])
        let looper = AVPlayerLooper(player: player, templateItem: item)
        player.isMuted = muteAudio
        player.automaticallyWaitsToMinimizeStalling = false

        let layer = AVPlayerLayer(player: player)
        layer.frame = window.contentView?.bounds ?? frame
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]

        window.contentView?.wantsLayer = true
        window.contentView?.layer = layer

        self.window = window
        self.player = player
        self.looper = looper
        self.playerLayer = layer

        applyScale(scaleMode)
        window.orderBack(nil)
        player.play()
    }

    func applyScale(_ mode: ScaleMode) {
        switch mode {
        case .fill:
            playerLayer.videoGravity = .resizeAspectFill
        case .fit:
            playerLayer.videoGravity = .resizeAspect
        case .stretch:
            playerLayer.videoGravity = .resize
        case .center:
            playerLayer.videoGravity = .resizeAspect
        }
    }

    func update(videoPath: String, scaleMode: ScaleMode, muteAudio: Bool) {
        guard !isStopped else { return }
        player.isMuted = muteAudio
        applyScale(scaleMode)

        guard self.videoPath != videoPath else { return }
        self.videoPath = videoPath

        player.pause()
        looper.disableLooping()

        let newItem = AVPlayerItem(url: URL(fileURLWithPath: videoPath))
        newItem.preferredForwardBufferDuration = 2.0
        looper = AVPlayerLooper(player: player, templateItem: newItem)
        player.play()
    }

    func stop() {
        guard !isStopped else { return }
        isStopped = true
        player.pause()
        looper.disableLooping()
        player.removeAllItems()
        playerLayer.player = nil
        window.contentView?.layer = nil
        window.contentView?.wantsLayer = false
        window.orderOut(nil)
        window.close()
    }
}

final class MultiDisplayRenderer {
    private var sessions: [UInt32: DisplaySession] = [:]
    private var runtimeRate: Float = 1.0
    private var runtimePaused = false

    fileprivate func render(targets: [DisplayTarget], videosByDisplay: [UInt32: String], scaleMode: ScaleMode, muteAudio: Bool) {
        let activeIDs = Set(targets.map { $0.id })

        let staleIDs = sessions.keys.filter { !activeIDs.contains($0) }
        for screenID in staleIDs {
            sessions[screenID]?.stop()
            sessions.removeValue(forKey: screenID)
        }

        for target in targets {
            guard let videoPath = videosByDisplay[target.id], FileManager.default.fileExists(atPath: videoPath) else {
                sessions[target.id]?.stop()
                sessions.removeValue(forKey: target.id)
                continue
            }

            if let session = sessions[target.id] {
                session.update(videoPath: videoPath, scaleMode: scaleMode, muteAudio: muteAudio)
            } else {
                sessions[target.id] = DisplaySession(
                    screenID: target.id,
                    screen: target.screen,
                    videoPath: videoPath,
                    scaleMode: scaleMode,
                    muteAudio: muteAudio
                )
            }
            sessions[target.id]?.player.rate = runtimePaused ? 0.0 : runtimeRate
            if runtimePaused {
                sessions[target.id]?.player.pause()
            } else {
                sessions[target.id]?.player.play()
            }
        }
    }

    func stopAll() {
        for (_, session) in sessions {
            session.stop()
        }
        sessions.removeAll()
    }

    var activeDisplayCount: Int {
        sessions.count
    }

    func applyRuntime(rate: Float, paused: Bool) {
        runtimeRate = max(0.1, min(rate, 1.0))
        runtimePaused = paused
        for (_, session) in sessions {
            if paused {
                session.player.pause()
                continue
            }
            session.player.play()
            session.player.rate = runtimeRate
        }
    }
}

final class Worker {
    private struct RenderSignature: Equatable {
        let targetIDs: [UInt32]
        let videosByDisplay: [UInt32: String]
        let scaleMode: ScaleMode
        let muteAudio: Bool
    }

    private struct RuntimeSignature: Equatable {
        let rate: Float
        let paused: Bool
    }

    private let configStore = ConfigStore()
    private let statusStore = StatusStore()
    private let commandStore = CommandStore()
    private let catalog = VideoCatalog()
    private let resolver = DisplayVideoResolver()
    private let renderer = MultiDisplayRenderer()
    private var policy = PlaybackPolicy(maxCPUPercent: 35.0)

    private var timer: DispatchSourceTimer?
    private var signalINT: DispatchSourceSignal?
    private var signalTERM: DispatchSourceSignal?
    private var screenObserver: NSObjectProtocol?
    private var spaceObserver: NSObjectProtocol?
    private var shouldStop = false
    private var consecutiveRenderMisses = 0
    private let tickQueue = DispatchQueue(label: "com.livepaper.worker.tick", qos: .utility)
    private var immediateTickPending = false
    private var playableCache: [String: (value: Bool, checkedAt: Date)] = [:]
    private let playableCacheTTL: TimeInterval = 300
    private var lastBatteryCheckAt = Date.distantPast
    private var cachedOnBattery = false
    private let batteryCacheTTL: TimeInterval = 30
    private var lastProcessSampleAt = Date.distantPast
    private var cachedProcessSample: (cpu: Double?, memory: Double?) = (nil, nil)
    private let processSampleTTL: TimeInterval = 2
    private var lastRenderSignature: RenderSignature?
    private var lastRuntimeSignature: RuntimeSignature?
    private var privacyModeEnabled = true

    func start() {
        setupSignals()
        setupRuntimeObservers()
        writeStatus(state: .running, message: "booting")

        let timer = DispatchSource.makeTimerSource(queue: tickQueue)
        timer.schedule(deadline: .now(), repeating: .seconds(5), leeway: .milliseconds(500))
        timer.setEventHandler { [self] in
            tick()
        }
        self.timer = timer
        timer.resume()
    }

    func stop(reason: String = "stopped") {
        guard !shouldStop else { return }
        shouldStop = true

        timer?.cancel()
        removeRuntimeObservers()
        stopAllRendering()
        writeStatus(state: .stopped, message: reason)
    }

    private func setupSignals() {
        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)

        let sigQueue = DispatchQueue(label: "com.livepaper.worker.signals")

        let intSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: sigQueue)
        intSource.setEventHandler { [self] in
            shutdown(reason: "sigint")
        }
        intSource.resume()
        self.signalINT = intSource

        let termSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: sigQueue)
        termSource.setEventHandler { [self] in
            shutdown(reason: "sigterm")
        }
        termSource.resume()
        self.signalTERM = termSource
    }

    private func setupRuntimeObservers() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.requestImmediateTick(reason: "screen_change")
        }

        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.requestImmediateTick(reason: "space_change")
        }
    }

    private func removeRuntimeObservers() {
        if let observer = screenObserver {
            NotificationCenter.default.removeObserver(observer)
            screenObserver = nil
        }
        if let observer = spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            spaceObserver = nil
        }
    }

    private func requestImmediateTick(reason: String) {
        tickQueue.async { [weak self] in
            guard let self else { return }
            guard !self.immediateTickPending else { return }
            self.immediateTickPending = true

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.35) { [weak self] in
                guard let self else { return }
                self.tickQueue.async {
                    self.immediateTickPending = false
                    self.tick()
                }
            }
        }
    }

    private func tick() {
        guard !shouldStop else { return }

        do {
            try processPendingCommandIfAny()

            let configPath = try configStore.defaultConfigPath()
            let config = try configStore.load(from: configPath)
            privacyModeEnabled = config.privacyModeEnabled ?? true

            guard !config.sourceFolder.isEmpty else {
                stopAllRendering()
                writeStatus(state: .paused, message: "set_source_folder")
                return
            }

            let items = try catalog.scan(folderPath: config.sourceFolder)
            guard !items.isEmpty else {
                stopAllRendering()
                writeStatus(state: .paused, message: "no_videos_found")
                return
            }

            let playableCatalogPaths = filterPlayablePaths(items.map { $0.path })
            guard !playableCatalogPaths.isEmpty else {
                stopAllRendering()
                writeStatus(state: .paused, message: "no_playable_video")
                return
            }

            let targets = detectDisplays()
            guard !targets.isEmpty else {
                stopAllRendering()
                writeStatus(state: .paused, message: "no_displays")
                return
            }

            let videosByDisplay = resolveVideosByDisplay(config: config, displays: targets, catalogPaths: playableCatalogPaths)
            guard !videosByDisplay.isEmpty else {
                stopAllRendering()
                writeStatus(state: .paused, message: "no_assignable_video")
                return
            }

            let processSample = sampledProcessUsage()
            let runtimeControl = computeRuntimeControl(config: config, cpuPercent: processSample.cpu)
            let renderSignature = RenderSignature(
                targetIDs: targets.map(\.id).sorted(),
                videosByDisplay: videosByDisplay,
                scaleMode: config.scaleMode,
                muteAudio: config.muteAudio
            )
            let runtimeSignature = RuntimeSignature(
                rate: runtimeControl.rate,
                paused: runtimeControl.paused
            )
            let shouldRender = renderSignature != lastRenderSignature
            let shouldApplyRuntime = runtimeSignature != lastRuntimeSignature

            var renderedDisplayCount = 0
            onMain {
                if shouldRender {
                    self.renderer.render(targets: targets, videosByDisplay: videosByDisplay, scaleMode: config.scaleMode, muteAudio: config.muteAudio)
                }
                if shouldRender || shouldApplyRuntime {
                    self.renderer.applyRuntime(rate: runtimeControl.rate, paused: runtimeControl.paused)
                }
                renderedDisplayCount = self.renderer.activeDisplayCount
            }
            lastRenderSignature = renderSignature
            lastRuntimeSignature = runtimeSignature

            if renderedDisplayCount == 0 {
                consecutiveRenderMisses += 1

                if consecutiveRenderMisses >= 3 {
                    stopAllRendering()
                    writeStatus(
                        state: .error,
                        currentVideoPath: nil,
                        activeDisplayCount: 0,
                        cpuPercent: processSample.cpu,
                        message: "render_recovery_backoff"
                    )
                } else {
                    writeStatus(
                        state: .paused,
                        currentVideoPath: nil,
                        activeDisplayCount: 0,
                        cpuPercent: processSample.cpu,
                        message: "no_playable_video_retry_\(consecutiveRenderMisses)"
                    )
                }
                return
            }

            consecutiveRenderMisses = 0
            let firstVideo = videosByDisplay.values.sorted().first
            let finalState: WorkerState = runtimeControl.paused ? .paused : .running
            writeStatus(
                state: finalState,
                currentVideoPath: firstVideo,
                activeDisplayCount: renderedDisplayCount,
                cpuPercent: processSample.cpu,
                memoryMB: processSample.memory,
                playbackRate: runtimeControl.paused ? 0.0 : runtimeControl.rate,
                message: runtimeControl.message
            )
        } catch {
            stopAllRendering()
            let sample = sampledProcessUsage()
            writeStatus(state: .error, cpuPercent: sample.cpu, memoryMB: sample.memory, message: error.localizedDescription)
        }
    }

    private func processPendingCommandIfAny() throws {
        let commandPath = try commandStore.defaultCommandPath()
        guard let command = try commandStore.load(from: commandPath) else { return }

        switch command.action {
        case .clearPlayableCache:
            playableCache.removeAll()
            let sample = sampledProcessUsage()
            writeStatus(state: .paused, cpuPercent: sample.cpu, memoryMB: sample.memory, message: "cache_cleared")
        case .resetRuntimeState:
            playableCache.removeAll()
            consecutiveRenderMisses = 0
            lastRuntimeSignature = nil
            onMain {
                self.renderer.applyRuntime(rate: 1.0, paused: false)
            }
            let sample = sampledProcessUsage()
            writeStatus(state: .paused, cpuPercent: sample.cpu, memoryMB: sample.memory, message: "runtime_reset")
        }

        try commandStore.clear(at: commandPath)
    }

    private func detectDisplays() -> [DisplayTarget] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            return DisplayTarget(id: number.uint32Value, screen: screen)
        }
    }

    private func resolveVideosByDisplay(config: LivePaperConfig, displays: [DisplayTarget], catalogPaths: [String]) -> [UInt32: String] {
        let preferredPath = config.wallpaperSelectedVideoPath ?? config.selectedVideoPath
        let displayIDs = displays.map(\.id)
        return resolver.resolve(
            displayIDs: displayIDs,
            explicitAssignments: config.displayAssignments,
            preferredVideoPath: preferredPath,
            catalogPaths: catalogPaths
        ) { [weak self] path in
            guard FileManager.default.fileExists(atPath: path) else { return false }
            return self?.isPathPlayable(path) ?? false
        }
    }

    private func filterPlayablePaths(_ paths: [String]) -> [String] {
        prunePlayableCache()
        return paths.filter { isPathPlayable($0) }
    }

    private func prunePlayableCache() {
        let cutoff = Date().addingTimeInterval(-playableCacheTTL)
        playableCache = playableCache.filter { $0.value.checkedAt >= cutoff }
    }

    private func isPathPlayable(_ path: String) -> Bool {
        guard FileManager.default.fileExists(atPath: path) else {
            return false
        }

        if let cached = playableCache[path], Date().timeIntervalSince(cached.checkedAt) < playableCacheTTL {
            return cached.value
        }

        let playable = probePlayable(path: path)
        playableCache[path] = (playable, Date())
        return playable
    }

    private func probePlayable(path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        let asset = AVURLAsset(url: url)
        let keys = ["playable", "tracks"]
        let semaphore = DispatchSemaphore(value: 0)
        asset.loadValuesAsynchronously(forKeys: keys) {
            semaphore.signal()
        }

        let waitResult = semaphore.wait(timeout: .now() + 2.0)
        if waitResult == .timedOut {
            return false
        }

        for key in keys {
            var error: NSError?
            let status = asset.statusOfValue(forKey: key, error: &error)
            guard status == .loaded else {
                return false
            }
        }

        guard asset.isPlayable else { return false }
        return !asset.tracks(withMediaType: .video).isEmpty
    }

    private func computeRuntimeControl(config: LivePaperConfig, cpuPercent: Double?) -> (rate: Float, paused: Bool, message: String) {
        let cpu = cpuPercent

        if config.userPaused ?? false {
            return (1.0, true, "paused_by_user")
        }

        let optimize = config.optimizeForEfficiency ?? true
        guard optimize else {
            return (1.0, false, "playing_multi_display")
        }

        let cpuValue = cpu ?? 0
        let env = PlaybackEnvironment(
            onBattery: isOnBatteryPowerCached(),
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            thermalPressure: thermalPressureLevel(),
            processCPUPercent: cpuValue
        )

        switch policy.evaluate(env) {
        case .runNormal:
            return (1.0, false, "playing_multi_display")
        case .runReducedRate(let rate):
            let clamped = max(0.4, min(rate, 1.0))
            return (Float(clamped), false, String(format: "playing_reduced_rate_%.2f", clamped))
        case .pause(let reason):
            return (1.0, true, "policy_pause_\(reason)")
        }
    }

    private func thermalPressureLevel() -> Int {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:
            return 0
        case .fair:
            return 1
        case .serious:
            return 2
        case .critical:
            return 3
        @unknown default:
            return 1
        }
    }

    private func isOnBatteryPowerCached() -> Bool {
        let now = Date()
        if now.timeIntervalSince(lastBatteryCheckAt) < batteryCacheTTL {
            return cachedOnBattery
        }
        lastBatteryCheckAt = now
        cachedOnBattery = isOnBatteryPower()
        return cachedOnBattery
    }

    private func isOnBatteryPower() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        task.arguments = ["-g", "batt"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let raw = String(data: data, encoding: .utf8) else { return false }
            return raw.localizedCaseInsensitiveContains("Battery Power")
        } catch {
            return false
        }
    }

    private func sampledProcessUsage() -> (cpu: Double?, memory: Double?) {
        let now = Date()
        if now.timeIntervalSince(lastProcessSampleAt) < processSampleTTL {
            return cachedProcessSample
        }
        lastProcessSampleAt = now

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-p", "\(ProcessInfo.processInfo.processIdentifier)", "-o", "%cpu=,rss="]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let raw = String(data: data, encoding: .utf8) else {
                cachedProcessSample = (nil, nil)
                return cachedProcessSample
            }

            let tokens = raw
                .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
                .map(String.init)

            let cpu = tokens.indices.contains(0) ? Double(tokens[0]) : nil
            let memoryMB: Double?
            if let rssToken = tokens.indices.contains(1) ? tokens[1] : nil,
               let rssKB = Double(rssToken) {
                memoryMB = rssKB / 1024.0
            } else {
                memoryMB = nil
            }
            cachedProcessSample = (cpu, memoryMB)
            return cachedProcessSample
        } catch {
            cachedProcessSample = (nil, nil)
            return cachedProcessSample
        }
    }

    private func writeStatus(
        state: WorkerState,
        currentVideoPath: String? = nil,
        activeDisplayCount: Int? = nil,
        cpuPercent: Double? = nil,
        memoryMB: Double? = nil,
        playbackRate: Float? = nil,
        message: String? = nil
    ) {
        do {
            let statusPath = try statusStore.defaultStatusPath()
            let status = WorkerStatus(
                pid: Int32(ProcessInfo.processInfo.processIdentifier),
                state: state,
                currentVideoPath: currentVideoPath,
                activeDisplayCount: activeDisplayCount,
                cpuPercent: cpuPercent,
                memoryMB: memoryMB,
                playbackRate: playbackRate,
                message: message,
                updatedAt: Date()
            )
            try statusStore.save(status, to: statusPath)
        } catch {
            PrivacyDiagnostics.log("LivePaperWorker", "Failed to write status", error: error, privacyModeEnabled: privacyModeEnabled)
        }
    }

    private func shutdown(reason: String) {
        stop(reason: reason)
        DispatchQueue.main.async {
            NSApplication.shared.terminate(nil)
        }
    }

    private func stopAllRendering() {
        onMain {
            self.renderer.stopAll()
        }
        lastRenderSignature = nil
        lastRuntimeSignature = nil
    }

    private func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.sync(execute: work)
        }
    }
}

final class WorkerAppDelegate: NSObject, NSApplicationDelegate {
    private let worker = Worker()

    func applicationDidFinishLaunching(_ notification: Notification) {
        worker.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        worker.stop(reason: "app_terminate")
    }
}

let app = NSApplication.shared
let delegate = WorkerAppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
