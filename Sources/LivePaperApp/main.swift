import AppKit
import AVFoundation
import CoreMedia
#if canImport(Darwin)
import Darwin
#endif
import Foundation
import LivePaperCore
import ServiceManagement
import SwiftUI

private func makeLivePaperIcon(template: Bool, pointSize: CGFloat) -> NSImage {
    let size = NSSize(width: pointSize, height: pointSize)
    let image = NSImage(size: size)
    image.lockFocus()
    defer { image.unlockFocus() }

    let bounds = NSRect(origin: .zero, size: size)
    let iconBounds = bounds.insetBy(dx: pointSize * 0.10, dy: pointSize * 0.10)

    if template {
        let triangle = NSBezierPath()
        let triW = iconBounds.width * 0.52
        let triH = iconBounds.height * 0.58
        let cx = iconBounds.midX
        let cy = iconBounds.midY
        triangle.move(to: NSPoint(x: cx - triW * 0.40, y: cy - triH * 0.50))
        triangle.line(to: NSPoint(x: cx - triW * 0.40, y: cy + triH * 0.50))
        triangle.line(to: NSPoint(x: cx + triW * 0.60, y: cy))
        triangle.close()
        NSColor.labelColor.setFill()
        triangle.fill()
    } else {
        let rounded = NSBezierPath(
            roundedRect: iconBounds,
            xRadius: max(4, pointSize * 0.20),
            yRadius: max(4, pointSize * 0.20)
        )
        let gradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.12, green: 0.56, blue: 0.95, alpha: 1.0),
            NSColor(calibratedRed: 0.17, green: 0.33, blue: 0.86, alpha: 1.0)
        ]) ?? NSGradient(starting: .systemBlue, ending: .systemIndigo)
        gradient?.draw(in: rounded, angle: -35)

        let play = NSBezierPath()
        let triW = iconBounds.width * 0.44
        let triH = iconBounds.height * 0.52
        let cx = iconBounds.midX
        let cy = iconBounds.midY
        play.move(to: NSPoint(x: cx - triW * 0.40, y: cy - triH * 0.50))
        play.line(to: NSPoint(x: cx - triW * 0.40, y: cy + triH * 0.50))
        play.line(to: NSPoint(x: cx + triW * 0.60, y: cy))
        play.close()
        NSColor.white.setFill()
        play.fill()

        NSColor.white.withAlphaComponent(0.18).setStroke()
        rounded.lineWidth = max(1, pointSize * 0.04)
        rounded.stroke()
    }

    image.isTemplate = false
    return image
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var statusLineItem: NSMenuItem?
    private var sourceLineItem: NSMenuItem?
    private var preferredVideoLineItem: NSMenuItem?
    private var displayAssignmentsLineItem: NSMenuItem?
    private var metricsLineItem: NSMenuItem?
    private var muteItem: NSMenuItem?
    private var startAtLoginItem: NSMenuItem?
    private var pausePlaybackItem: NSMenuItem?
    private var optimizeItem: NSMenuItem?
    private var scaleItems: [ScaleMode: NSMenuItem] = [:]
    private var displayAssignmentSubmenu: NSMenu?

    private var workerProcess: Process?
    private var pollTimer: Timer?
    private var config: LivePaperConfig = .init()

    private let configStore = ConfigStore()
    private let statusStore = StatusStore()
    private let commandStore = CommandStore()
    private let videoCatalog = VideoCatalog()
    private let controlCenterModel = ControlCenterModel()
    private var controlCenterWindow: NSWindow?
    private var wallpaperApplyTimeout: DispatchWorkItem?
    private var saverApplyTimeout: DispatchWorkItem?
    private var currentScreenSaverApplyID: UUID?
    private let mediaWorkQueue = DispatchQueue(label: "com.livepaper.app.media", qos: .userInitiated)
    private var isTerminating = false
    private var privacyModeEnabled: Bool { config.privacyModeEnabled ?? true }

    func applicationDidFinishLaunching(_ notification: Notification) {
        bootstrapConfigIfNeeded()
        loadConfig()
        buildMenuBarUI()
        startPolling()
        DispatchQueue.main.async { [weak self] in
            self?.openControlCenter()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        pollTimer?.invalidate()
        performTerminationCleanup(reason: "app_terminate")
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openControlCenter()
        return true
    }

    private func bootstrapConfigIfNeeded() {
        do {
            let configPath = try configStore.defaultConfigPath()
            _ = try configStore.load(from: configPath)
            if !FileManager.default.fileExists(atPath: configPath.path) {
                try configStore.save(LivePaperConfig(), to: configPath)
            }
        } catch {
            PrivacyDiagnostics.log("LivePaperApp", "Failed to initialize config", error: error, privacyModeEnabled: privacyModeEnabled)
        }
    }

    private func buildMenuBarUI() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = makeLivePaperIcon(template: true, pointSize: 18)
            button.title = ""
            button.toolTip = "LivePaper"
        }
        self.statusItem = item

        let menu = NSMenu()

        self.statusLineItem = nil

        let openControlCenterItem = NSMenuItem(title: "Open Control Center", action: #selector(openControlCenter), keyEquivalent: "d")
        openControlCenterItem.target = self
        menu.addItem(openControlCenterItem)

        let restartWorkerItem = NSMenuItem(title: "Restart Worker", action: #selector(restartWorker), keyEquivalent: "r")
        restartWorkerItem.target = self
        menu.addItem(restartWorkerItem)

        menu.addItem(NSMenuItem.separator())

        self.sourceLineItem = nil
        self.preferredVideoLineItem = nil
        self.displayAssignmentsLineItem = nil
        self.metricsLineItem = nil
        self.muteItem = nil
        self.optimizeItem = nil
        self.pausePlaybackItem = nil
        self.startAtLoginItem = nil
        self.displayAssignmentSubmenu = nil
        self.scaleItems = [:]

        let quitItem = NSMenuItem(title: "Quit LivePaper", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        menu.delegate = self
        item.menu = menu
        refreshConfigUI()
        rebuildDisplayAssignmentMenu()
    }

    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refreshStatusLine()
        }
        pollTimer?.tolerance = 0.5
        refreshStatusLine()
    }

    private func refreshStatusLine() {
        if let status = loadCurrentStatus() {
            let msg: String
            if let message = status.message, !message.isEmpty {
                msg = " (\(message))"
            } else {
                msg = ""
            }
            let displays = status.activeDisplayCount.map { " displays=\($0)" } ?? ""
            let cpu = status.cpuPercent.map { String(format: " cpu=%.1f%%", $0) } ?? ""
            statusLineItem?.title = "Worker: \(status.state.rawValue) pid=\(status.pid)\(displays)\(cpu)\(msg)"

            let memText = status.memoryMB.map { String(format: "%.1fMB", $0) } ?? "-"
            let cpuText = status.cpuPercent.map { String(format: "%.1f%%", $0) } ?? "-"
            let rateText = status.playbackRate.map { String(format: "%.2fx", $0) } ?? "-"
            metricsLineItem?.title = "Metrics: cpu=\(cpuText) mem=\(memText) rate=\(rateText)"
            controlCenterModel.status = status

            if let pending = controlCenterModel.applyingWallpaperPath,
               status.currentVideoPath == pending,
               status.state == .running || status.state == .paused {
                controlCenterModel.isApplyingWallpaper = false
                controlCenterModel.applyingWallpaperPath = nil
                wallpaperApplyTimeout?.cancel()
                wallpaperApplyTimeout = nil
            }
            return
        }

        statusLineItem?.title = "Worker: stopped"
        metricsLineItem?.title = "Metrics: cpu=- mem=- rate=-"
        controlCenterModel.status = nil
    }

    private func loadCurrentStatus() -> WorkerStatus? {
        do {
            let statusPath = try statusStore.defaultStatusPath()
            return try statusStore.load(from: statusPath)
        } catch {
            PrivacyDiagnostics.log("LivePaperApp", "Failed to read worker status", error: error, privacyModeEnabled: privacyModeEnabled)
            return nil
        }
    }

    private func refreshConfigUI() {
        let sourceLabel: String
        if config.sourceFolder.isEmpty {
            sourceLabel = "Source: not set"
        } else {
            sourceLabel = "Source: \((config.sourceFolder as NSString).lastPathComponent)"
        }
        sourceLineItem?.title = sourceLabel

        let wall = config.wallpaperSelectedVideoPath ?? config.selectedVideoPath
        let saver = config.screenSaverSelectedVideoPath ?? config.selectedVideoPath
        if (wall?.isEmpty == false) || (saver != nil) {
            let wallName = wall.map { ($0 as NSString).lastPathComponent } ?? "auto"
            let saverName = saver.map { ($0 as NSString).lastPathComponent } ?? "auto"
            preferredVideoLineItem?.title = "W: \(wallName) / S: \(saverName)"
        } else {
            preferredVideoLineItem?.title = "Wallpaper/Saver: auto"
        }

        displayAssignmentsLineItem?.title = "Display assignments: \(config.displayAssignments.count)"

        muteItem?.state = config.muteAudio ? .on : .off
        let isPaused = config.userPaused ?? false
        pausePlaybackItem?.state = isPaused ? .on : .off
        pausePlaybackItem?.title = isPaused ? "Resume Playback" : "Pause Playback"
        optimizeItem?.state = (config.optimizeForEfficiency ?? true) ? .on : .off
        startAtLoginItem?.state = config.startAtLogin ? .on : .off

        for (mode, menuItem) in scaleItems {
            menuItem.state = (config.scaleMode == mode) ? .on : .off
        }
        controlCenterModel.config = config
        controlCenterModel.workerRunning = (workerProcess?.isRunning ?? false)
        refreshLibraryModel()
    }

    private func loadConfig() {
        do {
            let configPath = try configStore.defaultConfigPath()
            self.config = try configStore.load(from: configPath)
        } catch {
            PrivacyDiagnostics.log("LivePaperApp", "Failed to load config", error: error, privacyModeEnabled: privacyModeEnabled)
            self.config = .init()
        }
    }

    private func updateConfig(_ mutate: (inout LivePaperConfig) -> Void) {
        do {
            let configPath = try configStore.defaultConfigPath()
            var newConfig = try configStore.load(from: configPath)
            mutate(&newConfig)
            try configStore.save(newConfig, to: configPath)
            self.config = newConfig
            refreshConfigUI()
            rebuildDisplayAssignmentMenu()
        } catch {
            PrivacyDiagnostics.log("LivePaperApp", "Failed to update config", error: error, privacyModeEnabled: privacyModeEnabled)
        }
    }

    private func refreshLibraryModel() {
        controlCenterModel.sourceFolder = config.sourceFolder
        guard !config.sourceFolder.isEmpty else {
            controlCenterModel.videoItems = []
            controlCenterModel.previewImage = nil
            controlCenterModel.previewVideoPath = nil
            return
        }

        do {
            let items = try videoCatalog.scan(folderPath: config.sourceFolder)
            controlCenterModel.videoItems = items
        } catch {
            controlCenterModel.videoItems = []
        }

        let previewPath = config.wallpaperSelectedVideoPath ?? config.screenSaverSelectedVideoPath ?? config.selectedVideoPath ?? controlCenterModel.videoItems.first?.path
        controlCenterModel.previewVideoPath = previewPath
        controlCenterModel.previewImage = previewPath.flatMap { thumbnailForVideo(path: $0) }
    }

    private func thumbnailForVideo(path: String) -> NSImage? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else { return nil }
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 920, height: 520)

        let times = [CMTime(seconds: 1.0, preferredTimescale: 600), .zero]
        for time in times {
            if let cg = try? generator.copyCGImage(at: time, actualTime: nil) {
                return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            }
        }
        return nil
    }

    private func setWallpaperVideo(from path: String) {
        controlCenterModel.isApplyingWallpaper = true
        controlCenterModel.applyingWallpaperPath = path
        wallpaperApplyTimeout?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.controlCenterModel.isApplyingWallpaper = false
            self?.controlCenterModel.applyingWallpaperPath = nil
        }
        wallpaperApplyTimeout = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: item)

        updateConfig { cfg in
            cfg.wallpaperSelectedVideoPath = path
            if cfg.selectedVideoPath == nil {
                cfg.selectedVideoPath = path
            }
        }
        ensureWorkerRunningForPlayback()
        sendWorkerCommand(.resetRuntimeState)
    }

    private func setScreenSaverVideo(from path: String) {
        let applyID = UUID()
        currentScreenSaverApplyID = applyID
        controlCenterModel.isApplyingScreenSaver = true
        controlCenterModel.applyingScreenSaverPath = path
        saverApplyTimeout?.cancel()
        let saverItem = DispatchWorkItem { [weak self] in
            self?.finishApplyingScreenSaver()
        }
        saverApplyTimeout = saverItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 180, execute: saverItem)

        mediaWorkQueue.async { [weak self] in
            guard let self else { return }
            let stagedPath = self.stageVideoForSharedAccess(from: path) ?? path
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard self.currentScreenSaverApplyID == applyID else { return }

                self.updateConfig { cfg in
                    cfg.screenSaverSelectedVideoPath = stagedPath
                    cfg.selectedVideoPath = stagedPath
                }
                self.ensureWorkerRunningForPlayback()
                self.finishApplyingScreenSaver()
            }
        }
    }

    private func ensureWorkerRunningForPlayback() {
        if workerProcess?.isRunning == true {
            return
        }
        if let pids = try? runningWorkerPIDs(), !pids.isEmpty {
            return
        }
        startWorker()
    }

    private func finishApplyingScreenSaver() {
        currentScreenSaverApplyID = nil
        controlCenterModel.isApplyingScreenSaver = false
        controlCenterModel.applyingScreenSaverPath = nil
        saverApplyTimeout?.cancel()
        saverApplyTimeout = nil
    }

    private func stageVideoForSharedAccess(from originalPath: String) -> String? {
        let fm = FileManager.default
        do {
            let configPath = try configStore.defaultConfigPath()
            let appDir = configPath.deletingLastPathComponent()
            let mediaDir = appDir.appendingPathComponent("Media", isDirectory: true)
            if !fm.fileExists(atPath: mediaDir.path) {
                try fm.createDirectory(at: mediaDir, withIntermediateDirectories: true)
            }

            let ext = (originalPath as NSString).pathExtension
            let normalizedExt = ext.isEmpty ? "mp4" : ext
            let stagedURL = mediaDir.appendingPathComponent("preferred.\(normalizedExt)")
            let sourceURL = URL(fileURLWithPath: originalPath)

            if fm.fileExists(atPath: stagedURL.path) {
                try fm.removeItem(at: stagedURL)
            }
            try fm.copyItem(at: sourceURL, to: stagedURL)

            let compatURL = mediaDir.appendingPathComponent("preferred_compat.mp4")
            if fm.fileExists(atPath: compatURL.path) {
                try fm.removeItem(at: compatURL)
            }
            if let converted = exportSaverCompatibleVideo(sourceURL: sourceURL, outputURL: compatURL) {
                stageVideoIntoSaverBundle(from: converted)
                return converted.path
            }

            stageVideoIntoSaverBundle(from: stagedURL)
            return stagedURL.path
        } catch {
            PrivacyDiagnostics.log("LivePaperApp", "Failed to stage preferred video for saver access", error: error, privacyModeEnabled: privacyModeEnabled)
            return nil
        }
    }

    private func exportSaverCompatibleVideo(sourceURL: URL, outputURL: URL) -> URL? {
        let asset = AVURLAsset(url: sourceURL)
        let preset = AVAssetExportPreset1920x1080
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            return nil
        }

        session.outputURL = outputURL
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = false

        let sem = DispatchSemaphore(value: 0)
        session.exportAsynchronously {
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + 120)

        guard session.status == .completed else {
            let errorMessage = session.error.map {
                PrivacyDiagnostics.errorSummary($0, privacyModeEnabled: privacyModeEnabled)
            } ?? "unknown"
            PrivacyDiagnostics.log("LivePaperApp", "preferred video compat export failed (\(errorMessage))", privacyModeEnabled: privacyModeEnabled)
            return nil
        }
        return outputURL
    }

    private func stageVideoIntoSaverBundle(from sourceURL: URL) {
        let fm = FileManager.default
        let bundlePath = "\(NSHomeDirectory())/Library/Screen Savers/LivePaper.saver/Contents/Resources"
        let dirURL = URL(fileURLWithPath: bundlePath, isDirectory: true)
        do {
            if !fm.fileExists(atPath: dirURL.path) {
                try fm.createDirectory(at: dirURL, withIntermediateDirectories: true)
            }
            let target = dirURL.appendingPathComponent("preferred_compat.mp4")
            if fm.fileExists(atPath: target.path) {
                try fm.removeItem(at: target)
            }
            try fm.copyItem(at: sourceURL, to: target)
        } catch {
            PrivacyDiagnostics.log("LivePaperApp", "Failed to stage video into saver bundle", error: error, privacyModeEnabled: privacyModeEnabled)
        }
    }

    @objc private func selectSourceFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Select"
        panel.message = "Choose a folder containing videos (.mp4, .mov, .m4v)."

        if panel.runModal() == .OK, let selected = panel.urls.first {
            updateConfig { cfg in
                cfg.sourceFolder = selected.path
            }
        }
    }

    @objc private func toggleMuteAudio() {
        updateConfig { cfg in
            cfg.muteAudio.toggle()
        }
    }

    @objc private func togglePausePlayback() {
        updateConfig { cfg in
            cfg.userPaused = !(cfg.userPaused ?? false)
        }
    }

    @objc private func toggleOptimizeForEfficiency() {
        updateConfig { cfg in
            cfg.optimizeForEfficiency = !(cfg.optimizeForEfficiency ?? true)
        }
    }

    @objc private func toggleStartAtLogin() {
        let desired = !config.startAtLogin
        do {
            try syncStartAtLogin(enabled: desired)
            updateConfig { cfg in
                cfg.startAtLogin = desired
            }
        } catch {
            PrivacyDiagnostics.log("LivePaperApp", "Failed to sync Start at Login via SMAppService", error: error, privacyModeEnabled: privacyModeEnabled)
        }
    }

    @objc private func selectPreferredVideo() {
        guard !config.sourceFolder.isEmpty else {
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: config.sourceFolder)
        panel.prompt = "Select"
        panel.message = "Choose a preferred video file."

        if panel.runModal() == .OK, let selected = panel.urls.first {
            let ext = selected.pathExtension.lowercased()
            if ["mp4", "mov", "m4v"].contains(ext) {
                setWallpaperVideo(from: selected.path)
            }
        }
    }

    @objc private func clearPreferredVideo() {
        updateConfig { cfg in
            cfg.selectedVideoPath = nil
            cfg.wallpaperSelectedVideoPath = nil
            cfg.screenSaverSelectedVideoPath = nil
        }
        sendWorkerCommand(.resetRuntimeState)
    }

    @objc private func assignVideoToDisplay(_ sender: NSMenuItem) {
        guard !config.sourceFolder.isEmpty else {
            return
        }
        guard let idNumber = sender.representedObject as? NSNumber else {
            return
        }
        let displayID = idNumber.uint32Value

        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: config.sourceFolder)
        panel.prompt = "Assign"
        panel.message = "Choose a video for this display."

        if panel.runModal() == .OK, let selected = panel.urls.first {
            let ext = selected.pathExtension.lowercased()
            guard ["mp4", "mov", "m4v"].contains(ext) else { return }

            updateConfig { cfg in
                cfg.displayAssignments.removeAll { $0.displayID == displayID }
                cfg.displayAssignments.append(DisplayAssignment(displayID: displayID, videoPath: selected.path))
            }
        }
    }

    @objc private func clearDisplayAssignment(_ sender: NSMenuItem) {
        guard let idNumber = sender.representedObject as? NSNumber else {
            return
        }
        let displayID = idNumber.uint32Value

        updateConfig { cfg in
            cfg.displayAssignments.removeAll { $0.displayID == displayID }
        }
    }

    @objc private func clearAllDisplayAssignments() {
        updateConfig { cfg in
            cfg.displayAssignments.removeAll()
        }
    }

    @objc private func selectScaleMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = ScaleMode(rawValue: raw) else {
            return
        }

        updateConfig { cfg in
            cfg.scaleMode = mode
        }
    }

    @objc private func startWorker() {
        stopAllWorkers()

        guard let workerPath = resolveWorkerPath() else {
            statusLineItem?.title = "Worker: error (binary not found)"
            return
        }

        let process = Process()
        process.executableURL = workerPath

        do {
            try process.run()
            workerProcess = process
            statusLineItem?.title = "Worker: starting"
            controlCenterModel.workerRunning = true
        } catch {
            statusLineItem?.title = "Worker: error (failed to launch)"
            PrivacyDiagnostics.log("LivePaperApp", "Failed to start worker", error: error, privacyModeEnabled: privacyModeEnabled)
            controlCenterModel.workerRunning = false
        }
    }

    @objc private func stopWorker() {
        stopAllWorkers()
        writeStoppedStatus(message: "stopped_by_user")

        statusLineItem?.title = "Worker: stopped"
        controlCenterModel.workerRunning = false
    }

    private func stopAllWorkers() {
        var pidsToStop = Set<Int32>()

        if let workerProcess, workerProcess.isRunning {
            pidsToStop.insert(Int32(workerProcess.processIdentifier))
            workerProcess.terminate()
            self.workerProcess = nil
        }

        if let statusPath = try? statusStore.defaultStatusPath(),
           let status = try? statusStore.load(from: statusPath),
           status.pid > 0 {
            pidsToStop.insert(status.pid)
        }

        if let pids = try? runningWorkerPIDs() {
            pidsToStop.formUnion(pids)
        }

        let currentPID = Int32(ProcessInfo.processInfo.processIdentifier)
        pidsToStop.remove(currentPID)

        guard !pidsToStop.isEmpty else { return }

        for pid in pidsToStop {
            kill(pid_t(pid), SIGTERM)
        }
        usleep(250_000)
        for pid in pidsToStop where kill(pid_t(pid), 0) == 0 {
            kill(pid_t(pid), SIGKILL)
        }
    }

    private func runningWorkerPIDs() throws -> [Int32] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-x", "LivePaperWorker"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        try task.run()
        task.waitUntilExit()
        if task.terminationStatus != 0 {
            return []
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let raw = String(data: data, encoding: .utf8) else { return [] }
        let currentPID = Int32(ProcessInfo.processInfo.processIdentifier)
        return raw
            .split(whereSeparator: \.isNewline)
            .compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
            .filter { $0 != currentPID }
    }

    @objc private func restartWorker() {
        stopWorker()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.startWorker()
        }
    }

    @objc private func clearWorkerCache() {
        sendWorkerCommand(.clearPlayableCache)
    }

    @objc private func resetSettings() {
        stopWorker()
        do {
            let configPath = try configStore.defaultConfigPath()
            try configStore.save(LivePaperConfig(), to: configPath)
            loadConfig()
            refreshConfigUI()
            rebuildDisplayAssignmentMenu()
            sendWorkerCommand(.resetRuntimeState)
            statusLineItem?.title = "Worker: settings reset"
        } catch {
            PrivacyDiagnostics.log("LivePaperApp", "Failed to reset settings", error: error, privacyModeEnabled: privacyModeEnabled)
        }
    }

    private func sendWorkerCommand(_ action: WorkerCommandAction) {
        do {
            let commandPath = try commandStore.defaultCommandPath()
            try commandStore.save(WorkerCommand(action: action), to: commandPath)
        } catch {
            PrivacyDiagnostics.log("LivePaperApp", "Failed to send worker command", error: error, privacyModeEnabled: privacyModeEnabled)
        }
    }

    @objc private func openControlCenter() {
        if let window = controlCenterWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = ControlCenterView(
            model: controlCenterModel,
            onSelectFolder: { [weak self] in self?.selectSourceFolder() },
            onClearPreferredVideo: { [weak self] in self?.clearPreferredVideo() },
            onChooseWallpaperFromLibrary: { [weak self] path in self?.setWallpaperVideo(from: path) },
            onChooseScreenSaverFromLibrary: { [weak self] path in self?.setScreenSaverVideo(from: path) },
            onTogglePause: { [weak self] in self?.togglePausePlayback() },
            onToggleOptimize: { [weak self] in self?.toggleOptimizeForEfficiency() },
            onToggleStartAtLogin: { [weak self] in self?.toggleStartAtLogin() },
            onStart: { [weak self] in self?.startWorker() },
            onStop: { [weak self] in self?.stopWorker() },
            onRestart: { [weak self] in self?.restartWorker() },
            onClearCache: { [weak self] in self?.clearWorkerCache() },
            onReset: { [weak self] in self?.resetSettings() },
            onRefreshLibrary: { [weak self] in self?.refreshLibraryModel() }
        )

        let host = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: host)
        window.title = "LivePaper Control Center"
        window.setContentSize(NSSize(width: 980, height: 700))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 860, height: 620)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.controlCenterWindow = window
    }

    @objc private func openConfigFolder() {
        do {
            let configPath = try configStore.defaultConfigPath()
            NSWorkspace.shared.activateFileViewerSelecting([configPath.deletingLastPathComponent()])
        } catch {
            PrivacyDiagnostics.log("LivePaperApp", "Failed to open config folder", error: error, privacyModeEnabled: privacyModeEnabled)
        }
    }

    @objc private func quitApp() {
        performTerminationCleanup(reason: "quit_action")
        NSApplication.shared.terminate(nil)
    }

    private func performTerminationCleanup(reason: String) {
        guard !isTerminating else { return }
        isTerminating = true
        stopAllWorkers()
        writeStoppedStatus(message: reason)
    }

    private func writeStoppedStatus(message: String) {
        do {
            let statusPath = try statusStore.defaultStatusPath()
            let status = WorkerStatus(pid: 0, state: .stopped, message: message)
            try statusStore.save(status, to: statusPath)
        } catch {
            PrivacyDiagnostics.log("LivePaperApp", "Failed to write stopped state", error: error, privacyModeEnabled: privacyModeEnabled)
        }
    }

    private func resolveWorkerPath() -> URL? {
        let fm = FileManager.default

        if let fromEnv = ProcessInfo.processInfo.environment["LIVE_SCENE_WORKER_PATH"] {
            let url = URL(fileURLWithPath: fromEnv)
            if fm.isExecutableFile(atPath: url.path) { return url }
        }

        if let execDir = Bundle.main.executableURL?.deletingLastPathComponent() {
            let candidate = execDir.appendingPathComponent("LivePaperWorker")
            if fm.isExecutableFile(atPath: candidate.path) { return candidate }
        }

        let cwdCandidate = URL(fileURLWithPath: fm.currentDirectoryPath)
            .appendingPathComponent(".build/debug/LivePaperWorker")
        if fm.isExecutableFile(atPath: cwdCandidate.path) {
            return cwdCandidate
        }

        return nil
    }

    private func syncStartAtLogin(enabled: Bool) throws {
        guard #available(macOS 13.0, *) else {
            return
        }

        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    private func rebuildDisplayAssignmentMenu() {
        guard let submenu = displayAssignmentSubmenu else { return }
        submenu.removeAllItems()

        let displays = currentDisplays()
        if displays.isEmpty {
            let item = NSMenuItem(title: "No displays detected", action: nil, keyEquivalent: "")
            item.isEnabled = false
            submenu.addItem(item)
            return
        }

        for display in displays {
            let currentAssignment = config.displayAssignments.first { $0.displayID == display.id }
            let assignedName: String
            if let path = currentAssignment?.videoPath, !path.isEmpty {
                assignedName = (path as NSString).lastPathComponent
            } else {
                assignedName = "auto"
            }

            let assignItem = NSMenuItem(
                title: "Set \(display.name) (\(display.id)) -> \(assignedName)",
                action: #selector(assignVideoToDisplay(_:)),
                keyEquivalent: ""
            )
            assignItem.target = self
            assignItem.representedObject = NSNumber(value: display.id)
            submenu.addItem(assignItem)

            let clearItem = NSMenuItem(
                title: "Clear \(display.name) (\(display.id))",
                action: #selector(clearDisplayAssignment(_:)),
                keyEquivalent: ""
            )
            clearItem.target = self
            clearItem.representedObject = NSNumber(value: display.id)
            submenu.addItem(clearItem)
        }

        submenu.addItem(NSMenuItem.separator())
        let clearAll = NSMenuItem(title: "Clear All Assignments", action: #selector(clearAllDisplayAssignments), keyEquivalent: "")
        clearAll.target = self
        submenu.addItem(clearAll)
    }

    private func currentDisplays() -> [(id: UInt32, name: String)] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            let name = screen.localizedName
            return (number.uint32Value, name)
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        if menu == statusItem?.menu {
            loadConfig()
            refreshConfigUI()
            rebuildDisplayAssignmentMenu()
            refreshStatusLine()
        }
    }
}

final class ControlCenterModel: ObservableObject {
    @Published var config: LivePaperConfig = .init()
    @Published var status: WorkerStatus?
    @Published var workerRunning: Bool = false
    @Published var selectedTab: ControlCenterTab = .dashboard
    @Published var sourceFolder: String = ""
    @Published var videoItems: [VideoItem] = []
    @Published var previewImage: NSImage?
    @Published var previewVideoPath: String?
    @Published var isApplyingWallpaper: Bool = false
    @Published var isApplyingScreenSaver: Bool = false
    @Published var applyingWallpaperPath: String?
    @Published var applyingScreenSaverPath: String?
}

enum ControlCenterTab: String, CaseIterable, Hashable {
    case dashboard = "Dashboard"
    case library = "Library"
    case settings = "Settings"

    var icon: String {
        switch self {
        case .dashboard: return "rectangle.grid.2x2"
        case .library: return "film.stack"
        case .settings: return "slider.horizontal.3"
        }
    }

    var subtitle: String {
        switch self {
        case .dashboard: return "Runtime + Quick Control"
        case .library: return "Source Folder + Video Preview"
        case .settings: return "Behavior + Startup"
        }
    }
}

private struct ControlCenterView: View {
    @ObservedObject var model: ControlCenterModel
    @State private var librarySearchText = ""

    let onSelectFolder: () -> Void
    let onClearPreferredVideo: () -> Void
    let onChooseWallpaperFromLibrary: (String) -> Void
    let onChooseScreenSaverFromLibrary: (String) -> Void
    let onTogglePause: () -> Void
    let onToggleOptimize: () -> Void
    let onToggleStartAtLogin: () -> Void
    let onStart: () -> Void
    let onStop: () -> Void
    let onRestart: () -> Void
    let onClearCache: () -> Void
    let onReset: () -> Void
    let onRefreshLibrary: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            topStrip
            Divider()
            HStack(spacing: 0) {
                sidebar
                    .frame(width: 250)
                Divider()
                ZStack {
                    Color(nsColor: .underPageBackgroundColor).ignoresSafeArea()
                    ScrollView {
                        activePage
                            .padding(22)
                    }
                    .id(model.selectedTab)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(.easeInOut(duration: 0.18), value: model.selectedTab)
    }

    private var topStrip: some View {
        HStack(spacing: 14) {
            HStack(spacing: 10) {
                Image(nsImage: makeLivePaperIcon(template: false, pointSize: 28))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("LivePaper Control Center")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text(statusText)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(statusColor)
                }
            }
            Spacer()
            HStack(spacing: 8) {
                Button("Start", action: onStart).buttonStyle(.borderedProminent)
                Button("Stop", action: onStop).buttonStyle(.bordered)
                Button("Restart", action: onRestart).buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            LinearGradient(
                colors: [Color.accentColor.opacity(0.10), Color(nsColor: .windowBackgroundColor)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pages")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 12)

            ForEach(ControlCenterTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        model.selectedTab = tab
                    }
                } label: {
                    HStack(alignment: .center, spacing: 10) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(tab.rawValue)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                            Text(tab.subtitle)
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(model.selectedTab == tab ? Color.accentColor.opacity(0.18) : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(model.selectedTab == tab ? Color.accentColor.opacity(0.45) : Color.clear, lineWidth: 1)
                    )
                }
                .contentShape(Rectangle())
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
            }

            Spacer()
            Text("Live Wallpaper + Screen Saver")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(14)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var activePage: some View {
        switch model.selectedTab {
        case .dashboard:
            dashboardPage
                .transition(.opacity.combined(with: .move(edge: .trailing)))
        case .library:
            libraryPage
                .transition(.opacity.combined(with: .move(edge: .trailing)))
        case .settings:
            settingsPage
                .transition(.opacity.combined(with: .move(edge: .trailing)))
        }
    }

    private var dashboardPage: some View {
        VStack(spacing: 14) {
            metricsGrid
            HStack(alignment: .top, spacing: 14) {
                quickActionsCard
                nowPlayingCard
            }
        }
    }

    private var libraryPage: some View {
        VStack(spacing: 14) {
            libraryHeaderCard
            HStack(alignment: .top, spacing: 14) {
                sourceCard
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                previewCard
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            videoListCard
        }
    }

    private var settingsPage: some View {
        VStack(spacing: 14) {
            settingsOverviewCard
            settingsCard
            maintenanceCard
        }
    }

    private var libraryHeaderCard: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Library")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Text("Pick source and assign separate videos for Wallpaper/Screen Saver.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            metricBadge("Videos", "\(filteredVideoItems.count)", icon: "film")
            metricBadge("Source", compactFolderName(model.sourceFolder), icon: "folder")
        }
        .padding(16)
        .background(cardBackground)
    }

    private var metricsGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Runtime")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                spacing: 12
            ) {
                metricCard("CPU", model.status?.cpuPercent.map { String(format: "%.1f%%", $0) } ?? "-", systemImage: "cpu")
                metricCard("Memory", model.status?.memoryMB.map { String(format: "%.1f MB", $0) } ?? "-", systemImage: "memorychip")
                metricCard("Playback Rate", model.status?.playbackRate.map { String(format: "%.2fx", $0) } ?? "-", systemImage: "speedometer")
                metricCard("Displays", model.status?.activeDisplayCount.map(String.init) ?? "-", systemImage: "display.2")
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    private func metricCard(_ title: String, _ value: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title.uppercased(), systemImage: systemImage)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Source")
                .font(.system(size: 17, weight: .bold, design: .rounded))
            Text("Select a folder, then assign videos from the list")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            detailPathRow("Source Folder", model.sourceFolder.isEmpty ? "Not selected" : model.sourceFolder)
            detailPathRow("Wallpaper Video", model.config.wallpaperSelectedVideoPath ?? model.config.selectedVideoPath ?? "Auto")
            detailPathRow("Screen Saver Video", model.config.screenSaverSelectedVideoPath ?? model.config.selectedVideoPath ?? "Auto")
            if model.isApplyingWallpaper || model.isApplyingScreenSaver {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(model.isApplyingWallpaper ? "Applying wallpaper..." : "Applying screen saver...")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Button("Select Folder", action: onSelectFolder)
                    .buttonStyle(.borderedProminent)
                Button("Clear", action: onClearPreferredVideo)
                    .buttonStyle(.bordered)
                Button("Refresh", action: onRefreshLibrary)
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(16)
        .background(cardBackground)
    }

    private var videoListCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Folder Videos")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Spacer()
                Text("\(filteredVideoItems.count)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
            }
            TextField("Search videos", text: $librarySearchText)
                .textFieldStyle(.roundedBorder)

            if filteredVideoItems.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "film.stack")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("No videos found")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Text("Drop `.mp4`, `.mov`, or `.m4v` files into the selected folder.")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(filteredVideoItems, id: \.path) { item in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "film")
                                        .foregroundStyle(.secondary)
                                        .frame(width: 16, height: 16)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(item.name)
                                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                                            .lineLimit(1)
                                        Text(compactPathForDisplay(item.path))
                                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                            .help(item.path)
                                    }
                                    Spacer()
                                    HStack(spacing: 6) {
                                        if isWallpaperSelected(item.path) {
                                            stateBadge("Wallpaper")
                                        }
                                        if isScreenSaverSelected(item.path) {
                                            stateBadge("Saver")
                                        }
                                    }
                                }

                                HStack(spacing: 8) {
                                    Button {
                                        onChooseWallpaperFromLibrary(item.path)
                                    } label: {
                                        if model.isApplyingWallpaper && model.applyingWallpaperPath == item.path {
                                            HStack(spacing: 6) {
                                                ProgressView().controlSize(.small)
                                                Text("Applying")
                                            }
                                        } else {
                                            Text("Set as Wallpaper")
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                    .disabled(model.isApplyingWallpaper)

                                    Button {
                                        onChooseScreenSaverFromLibrary(item.path)
                                    } label: {
                                        if model.isApplyingScreenSaver && model.applyingScreenSaverPath == item.path {
                                            HStack(spacing: 6) {
                                                ProgressView().controlSize(.small)
                                                Text("Applying")
                                            }
                                        } else {
                                            Text("Set as Screen Saver")
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .disabled(model.isApplyingScreenSaver)
                                }
                            }
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(isPreferred(item.path) ? Color.accentColor.opacity(0.16) : Color(nsColor: .controlBackgroundColor))
                            )
                        }
                    }
                }
                .frame(maxHeight: 420)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(16)
        .background(cardBackground)
    }

    private var settingsOverviewCard: some View {
        HStack(spacing: 12) {
            metricBadge("Playback", (model.config.userPaused ?? false) ? "Paused" : "Running", icon: "play.circle")
            metricBadge("Efficiency", (model.config.optimizeForEfficiency ?? true) ? "On" : "Off", icon: "bolt.lefthalf.filled")
            metricBadge("Start At Login", model.config.startAtLogin ? "On" : "Off", icon: "power")
        }
        .padding(16)
        .background(cardBackground)
    }

    private var quickActionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.system(size: 17, weight: .bold, design: .rounded))
            Text("Fast controls for heavy-load moments")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            HStack {
                Button((model.config.userPaused ?? false) ? "Resume Playback" : "Pause Playback", action: onTogglePause)
                    .buttonStyle(.borderedProminent)
                Button((model.config.optimizeForEfficiency ?? true) ? "Efficiency: On" : "Efficiency: Off", action: onToggleOptimize)
                    .buttonStyle(.bordered)
            }

            Divider()

            detailRow("Worker Message", model.status?.message ?? "No status yet")
            detailRow("Worker PID", model.status.map { String($0.pid) } ?? "-")

            HStack {
                Button("Clear Cache", action: onClearCache)
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(16)
        .background(cardBackground)
    }

    private var nowPlayingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Now Playing")
                .font(.system(size: 17, weight: .bold, design: .rounded))
            detailPathRow("Current Video", model.status?.currentVideoPath ?? "Unknown")
            detailRow("Playback Message", model.status?.message ?? "-")
            detailPathRow("Wallpaper", model.config.wallpaperSelectedVideoPath ?? model.config.selectedVideoPath ?? "Auto")
            detailPathRow("Screen Saver", model.config.screenSaverSelectedVideoPath ?? model.config.selectedVideoPath ?? "Auto")
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(16)
        .background(cardBackground)
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Preview")
                .font(.system(size: 17, weight: .bold, design: .rounded))
            if let image = model.previewImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, minHeight: 260, maxHeight: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .frame(maxWidth: .infinity, minHeight: 260, maxHeight: 360)
                    .overlay(
                        Text("Preview unavailable")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    )
            }
            detailPathRow("Selected", model.previewVideoPath ?? "No video selected")
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(16)
        .background(cardBackground)
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Playback Settings")
                .font(.system(size: 17, weight: .bold, design: .rounded))
            Text("Tune startup and runtime behavior from one place.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                actionTile(
                    title: (model.config.userPaused ?? false) ? "Resume Playback" : "Pause Playback",
                    subtitle: "Temporarily stop live rendering",
                    icon: "playpause",
                    prominent: true,
                    action: onTogglePause
                )
                actionTile(
                    title: (model.config.optimizeForEfficiency ?? true) ? "Efficiency Mode On" : "Efficiency Mode Off",
                    subtitle: "Lower CPU and battery usage",
                    icon: "leaf",
                    prominent: false,
                    action: onToggleOptimize
                )
                actionTile(
                    title: model.config.startAtLogin ? "Start At Login On" : "Start At Login Off",
                    subtitle: "Launch app after user sign in",
                    icon: "power",
                    prominent: false,
                    action: onToggleStartAtLogin
                )
                actionTile(
                    title: "Refresh Library",
                    subtitle: "Rescan source folder content",
                    icon: "arrow.clockwise",
                    prominent: false,
                    action: onRefreshLibrary
                )
            }
            detailRow("Scale Mode", model.config.scaleMode.rawValue.capitalized)
            detailPathRow("Source Folder", model.config.sourceFolder.isEmpty ? "Not selected" : model.config.sourceFolder)
        }
        .padding(16)
        .background(cardBackground)
    }

    private var maintenanceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Maintenance")
                .font(.system(size: 17, weight: .bold, design: .rounded))
            Text("Cleanup and reset controls")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                maintenanceActionTile(
                    title: "Clear Cache",
                    subtitle: "Remove generated previews and temporary media artifacts.",
                    icon: "trash",
                    color: Color(nsColor: .controlBackgroundColor),
                    foreground: .primary,
                    subtitleOpacity: 0.7,
                    action: onClearCache
                )
                maintenanceActionTile(
                    title: "Reset Settings",
                    subtitle: "Restore defaults for playback, startup, and selected media paths.",
                    icon: "arrow.uturn.backward.circle",
                    color: Color.red.opacity(0.92),
                    foreground: .white,
                    subtitleOpacity: 0.92,
                    action: onReset
                )
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    private func detailRow(_ key: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(key)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func actionTile(
        title: String,
        subtitle: String,
        icon: String,
        prominent: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: icon)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(prominent ? .white : .primary)
                Text(subtitle)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(prominent ? .white.opacity(0.9) : .secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(prominent ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
            )
        }
        .buttonStyle(.plain)
    }

    private func maintenanceActionTile(
        title: String,
        subtitle: String,
        icon: String,
        color: Color,
        foreground: Color,
        subtitleOpacity: Double,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 18)
                    .foregroundStyle(foreground)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(foreground)
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(foreground.opacity(subtitleOpacity))
                        .lineLimit(2)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(color)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(subtitleOpacity > 0.85 ? 0 : 0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func detailPathRow(_ key: String, _ value: String) -> some View {
        let display = compactPathForDisplay(value)
        return VStack(alignment: .leading, spacing: 3) {
            Text(key)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(display)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(value)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color(nsColor: .windowBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.25), lineWidth: 1)
            )
    }

    private var filteredVideoItems: [VideoItem] {
        let text = librarySearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return model.videoItems }
        return model.videoItems.filter {
            $0.name.localizedCaseInsensitiveContains(text) ||
            $0.path.localizedCaseInsensitiveContains(text)
        }
    }

    private func metricBadge(_ title: String, _ value: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            Capsule(style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func compactPathForDisplay(_ raw: String) -> String {
        guard raw.contains("/") else { return raw }
        let home = NSHomeDirectory()
        let normalized = raw.hasPrefix(home) ? "~" + raw.dropFirst(home.count) : raw
        let maxLength = 72
        guard normalized.count > maxLength else { return normalized }

        let headCount = 28
        let tailCount = 36
        let head = normalized.prefix(headCount)
        let tail = normalized.suffix(tailCount)
        return "\(head)...\(tail)"
    }

    private func compactFolderName(_ path: String) -> String {
        guard !path.isEmpty else { return "Not set" }
        return (path as NSString).lastPathComponent
    }

    private func isPreferred(_ path: String) -> Bool {
        let wall = model.config.wallpaperSelectedVideoPath ?? model.config.selectedVideoPath
        let saver = model.config.screenSaverSelectedVideoPath ?? model.config.selectedVideoPath
        let rhs = (path as NSString).lastPathComponent.lowercased()
        let wallMatch = wall.map { ($0 as NSString).lastPathComponent.lowercased() == rhs || $0 == path } ?? false
        let saverMatch = saver.map { ($0 as NSString).lastPathComponent.lowercased() == rhs || $0 == path } ?? false
        return wallMatch || saverMatch
    }

    private func isWallpaperSelected(_ path: String) -> Bool {
        let wall = model.config.wallpaperSelectedVideoPath ?? model.config.selectedVideoPath
        let rhs = (path as NSString).lastPathComponent.lowercased()
        return wall.map { ($0 as NSString).lastPathComponent.lowercased() == rhs || $0 == path } ?? false
    }

    private func isScreenSaverSelected(_ path: String) -> Bool {
        let saver = model.config.screenSaverSelectedVideoPath ?? model.config.selectedVideoPath
        let rhs = (path as NSString).lastPathComponent.lowercased()
        return saver.map { ($0 as NSString).lastPathComponent.lowercased() == rhs || $0 == path } ?? false
    }

    private func stateBadge(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
    }

    private var statusText: String {
        guard let status = model.status else { return "Worker status unavailable" }
        switch status.state {
        case .running:
            return "Running"
        case .paused:
            return "Paused"
        case .error:
            return "Error"
        case .stopped:
            return "Stopped"
        }
    }

    private var statusColor: Color {
        guard let status = model.status else { return .gray }
        switch status.state {
        case .running:
            return .green
        case .paused:
            return .orange
        case .error:
            return .red
        case .stopped:
            return .gray
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
