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
    let iconBounds = bounds.insetBy(dx: pointSize * 0.08, dy: pointSize * 0.08)

    if template {
        let strokeColor = NSColor.labelColor
        strokeColor.setStroke()
        
        let backPath = NSBezierPath(
            roundedRect: NSRect(
                x: iconBounds.minX + iconBounds.width * 0.16,
                y: iconBounds.minY + iconBounds.height * 0.20,
                width: iconBounds.width * 0.70,
                height: iconBounds.height * 0.70
            ),
            xRadius: pointSize * 0.06,
            yRadius: pointSize * 0.06
        )
        backPath.lineWidth = max(1.0, pointSize * 0.06)
        backPath.stroke()
        
        let frontRect = NSRect(
            x: iconBounds.minX + iconBounds.width * 0.04,
            y: iconBounds.minY + iconBounds.height * 0.08,
            width: iconBounds.width * 0.70,
            height: iconBounds.height * 0.70
        )
        let frontPath = NSBezierPath(
            roundedRect: frontRect,
            xRadius: pointSize * 0.06,
            yRadius: pointSize * 0.06
        )
        
        NSGraphicsContext.current?.compositingOperation = .clear
        frontPath.fill()
        NSGraphicsContext.current?.compositingOperation = .sourceOver
        
        frontPath.lineWidth = max(1.0, pointSize * 0.06)
        strokeColor.setStroke()
        frontPath.stroke()
        
        let playPath = NSBezierPath()
        let pw = frontRect.width * 0.30
        let ph = frontRect.height * 0.40
        let cx = frontRect.midX
        let cy = frontRect.midY
        playPath.move(to: NSPoint(x: cx - pw * 0.35, y: cy - ph * 0.50))
        playPath.line(to: NSPoint(x: cx - pw * 0.35, y: cy + ph * 0.50))
        playPath.line(to: NSPoint(x: cx + pw * 0.65, y: cy))
        playPath.close()
        strokeColor.setFill()
        playPath.fill()
    } else {
        let rounded = NSBezierPath(
            roundedRect: iconBounds,
            xRadius: max(6, pointSize * 0.18),
            yRadius: max(6, pointSize * 0.18)
        )
        let bgGradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.07, green: 0.11, blue: 0.22, alpha: 1.0),
            NSColor(calibratedRed: 0.12, green: 0.20, blue: 0.38, alpha: 1.0)
        ])
        bgGradient?.draw(in: rounded, angle: -45)
        
        let backRect = NSRect(
            x: iconBounds.minX + iconBounds.width * 0.18,
            y: iconBounds.minY + iconBounds.height * 0.22,
            width: iconBounds.width * 0.70,
            height: iconBounds.height * 0.70
        )
        let backPath = NSBezierPath(roundedRect: backRect, xRadius: pointSize * 0.06, yRadius: pointSize * 0.06)
        let backGradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.65, green: 0.18, blue: 0.95, alpha: 1.0),
            NSColor(calibratedRed: 0.95, green: 0.22, blue: 0.65, alpha: 1.0)
        ])
        backGradient?.draw(in: backPath, angle: 45)
        
        let frontRect = NSRect(
            x: iconBounds.minX + iconBounds.width * 0.06,
            y: iconBounds.minY + iconBounds.height * 0.10,
            width: iconBounds.width * 0.70,
            height: iconBounds.height * 0.70
        )
        let frontPath = NSBezierPath(roundedRect: frontRect, xRadius: pointSize * 0.06, yRadius: pointSize * 0.06)
        let frontGradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.00, green: 0.60, blue: 1.00, alpha: 1.0),
            NSColor(calibratedRed: 0.00, green: 0.85, blue: 0.70, alpha: 1.0)
        ])
        
        frontGradient?.draw(in: frontPath, angle: 45)
        
        NSColor.white.withAlphaComponent(0.25).setStroke()
        frontPath.lineWidth = max(1.0, pointSize * 0.03)
        frontPath.stroke()
        
        let playPath = NSBezierPath()
        let pw = frontRect.width * 0.28
        let ph = frontRect.height * 0.38
        let cx = frontRect.midX
        let cy = frontRect.midY
        playPath.move(to: NSPoint(x: cx - pw * 0.35, y: cy - ph * 0.50))
        playPath.line(to: NSPoint(x: cx - pw * 0.35, y: cy + ph * 0.50))
        playPath.line(to: NSPoint(x: cx + pw * 0.65, y: cy))
        playPath.close()
        
        NSColor.white.setFill()
        playPath.fill()
        
        NSColor.white.withAlphaComponent(0.4).setStroke()
        playPath.lineWidth = max(0.5, pointSize * 0.02)
        playPath.stroke()
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
        let myPID = ProcessInfo.processInfo.processIdentifier
        let otherInstances = NSWorkspace.shared.runningApplications.filter { app in
            app.processIdentifier != myPID &&
            (app.bundleIdentifier == "com.livepaper.app" || app.localizedName == "LivePaperApp")
        }
        if let otherApp = otherInstances.first {
            otherApp.activate(options: [.activateIgnoringOtherApps])
            NSApp.terminate(nil)
            return
        }

        bootstrapConfigIfNeeded()
        loadConfig()
        buildMenuBarUI()
        startPolling()
        registerAsSystemScreenSaver()
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleSystemWake()
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleSystemWake()
        }
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
            controlCenterModel.thumbnails = [:]
            return
        }

        do {
            let items = try videoCatalog.scan(folderPath: config.sourceFolder)
            controlCenterModel.videoItems = items
            
            let paths = items.map { $0.path }
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                for path in paths {
                    if let thumb = self.thumbnailForVideo(path: path) {
                        DispatchQueue.main.async {
                            self.controlCenterModel.thumbnails[path] = thumb
                        }
                    }
                }
            }
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

    private func verifyFileReadable(at path: String) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else { return false }
        if fm.isReadableFile(atPath: path) {
            return true
        }
        if let file = FileHandle(forReadingAtPath: path) {
            do {
                try file.close()
                return true
            } catch {
                return false
            }
        }
        return false
    }

    private func setWallpaperVideo(from path: String) {
        print("[LivePaperApp] setWallpaperVideo: path = \(path)")
        
        guard verifyFileReadable(at: path) else {
            controlCenterModel.loginAlertMessage = "Cannot read video file.\n\nIf this video is stored in iCloud or another cloud drive, please open Finder and download the file to your local drive first."
            return
        }

        controlCenterModel.isApplyingWallpaper = true
        controlCenterModel.applyingWallpaperPath = path
        wallpaperApplyTimeout?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.controlCenterModel.isApplyingWallpaper = false
            self?.controlCenterModel.applyingWallpaperPath = nil
        }
        wallpaperApplyTimeout = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: item)

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
        print("[LivePaperApp] setScreenSaverVideo: path = \(path)")
        
        guard verifyFileReadable(at: path) else {
            controlCenterModel.loginAlertMessage = "Cannot read video file.\n\nIf this video is stored in iCloud or another cloud drive, please open Finder and download the file to your local drive first."
            return
        }

        let applyID = UUID()
        currentScreenSaverApplyID = applyID
        controlCenterModel.isApplyingScreenSaver = true
        controlCenterModel.applyingScreenSaverPath = path
        saverApplyTimeout?.cancel()
        let saverItem = DispatchWorkItem { [weak self] in
            self?.finishApplyingScreenSaver()
        }
        saverApplyTimeout = saverItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: saverItem)

        mediaWorkQueue.async { [weak self] in
            guard let self else { return }
            let stagedPath = self.stageVideoForSharedAccess(from: path) ?? path
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard self.currentScreenSaverApplyID == applyID else { return }

                self.updateConfig { cfg in
                    cfg.screenSaverSelectedVideoPath = stagedPath
                    cfg.screenSaverOriginalVideoPath = path
                    if cfg.selectedVideoPath == nil {
                        cfg.selectedVideoPath = stagedPath
                    }
                }
                self.ensureWorkerRunningForPlayback()
                self.finishApplyingScreenSaver()
            }
        }
    }

    private func handleSystemWake() {
        ensureWorkerRunningForPlayback()
        sendWorkerCommand(.resetRuntimeState)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.ensureWorkerRunningForPlayback()
            self?.sendWorkerCommand(.resetRuntimeState)
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
        registerAsSystemScreenSaver()
    }

    private func registerAsSystemScreenSaver() {
        let fm = FileManager.default
        var userHome = NSHomeDirectory()
        #if canImport(Darwin)
        if let pwd = getpwuid(getuid()), let dir = pwd.pointee.pw_dir {
            userHome = String(cString: dir)
        }
        #endif
        let saverPath = "\(userHome)/Library/Screen Savers/LivePaper.saver"
        guard fm.fileExists(atPath: saverPath) else { return }

        let moduleDict: [String: Any] = [
            "moduleName": "LivePaper",
            "path": saverPath,
            "type": 0
        ]

        CFPreferencesSetValue(
            "moduleDict" as CFString,
            moduleDict as CFPropertyList,
            "com.apple.screensaver" as CFString,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )
        CFPreferencesSynchronize("com.apple.screensaver" as CFString, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)

        CFPreferencesSetValue(
            "moduleDict" as CFString,
            moduleDict as CFPropertyList,
            "com.apple.screensaver" as CFString,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
        CFPreferencesSynchronize("com.apple.screensaver" as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)

        let byHostDir = "\(userHome)/Library/Preferences/ByHost"
        if let items = try? fm.contentsOfDirectory(atPath: byHostDir) {
            for item in items where item.hasPrefix("com.apple.screensaver.") && item.hasSuffix(".plist") {
                let fullPath = (byHostDir as NSString).appendingPathComponent(item)

                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/plutil")
                task.arguments = [
                    "-replace", "moduleDict.moduleName", "-string", "LivePaper",
                    fullPath
                ]
                try? task.run()
                task.waitUntilExit()

                let task2 = Process()
                task2.executableURL = URL(fileURLWithPath: "/usr/bin/plutil")
                task2.arguments = [
                    "-replace", "moduleDict.path", "-string", saverPath,
                    fullPath
                ]
                try? task2.run()
                task2.waitUntilExit()

                let task3 = Process()
                task3.executableURL = URL(fileURLWithPath: "/usr/bin/plutil")
                task3.arguments = [
                    "-replace", "moduleDict.type", "-integer", "0",
                    fullPath
                ]
                try? task3.run()
                task3.waitUntilExit()
            }
        }

        let stagedPath = "\(userHome)/Library/Application Support/LivePaper/Media/preferred_compat.mp4"
        let videoFileForLockScreen = fm.fileExists(atPath: stagedPath) ? stagedPath : "\(saverPath)/Contents/Resources/preferred_compat.mp4"
        if fm.fileExists(atPath: videoFileForLockScreen) {
            let urlString = URL(fileURLWithPath: videoFileForLockScreen).absoluteString
            CFPreferencesSetValue(
                "SystemWallpaperURL" as CFString,
                urlString as CFString,
                "com.apple.wallpaper" as CFString,
                kCFPreferencesCurrentUser,
                kCFPreferencesAnyHost
            )
            CFPreferencesSynchronize("com.apple.wallpaper" as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            overrideSystemAerialVideoCache(with: URL(fileURLWithPath: videoFileForLockScreen))
        }

        patchWallpaperStoreIndexPlist()
    }

    private func patchWallpaperStoreIndexPlist() {
        let fm = FileManager.default
        var userHome = NSHomeDirectory()
        #if canImport(Darwin)
        if let pwd = getpwuid(getuid()), let dir = pwd.pointee.pw_dir {
            userHome = String(cString: dir)
        }
        #endif

        let indexPlistPath = "\(userHome)/Library/Application Support/com.apple.wallpaper/Store/Index.plist"
        guard fm.fileExists(atPath: indexPlistPath) else { return }

        let targetSaverPath = "\(userHome)/Library/Screen Savers/LivePaper.saver/"
        guard fm.fileExists(atPath: "\(userHome)/Library/Screen Savers/LivePaper.saver") else { return }

        let targetURLString = URL(fileURLWithPath: targetSaverPath).absoluteString
        let configDict: [String: Any] = [
            "module": [
                "relative": targetURLString
            ]
        ]

        guard let configData = try? PropertyListSerialization.data(fromPropertyList: configDict, format: .binary, options: 0) else {
            return
        }

        guard let data = try? Data(contentsOf: URL(fileURLWithPath: indexPlistPath)),
              var rootDict = (try? PropertyListSerialization.propertyList(from: data, options: .mutableContainersAndLeaves, format: nil)) as? [String: Any] else {
            return
        }

        let idleChoice: [String: Any] = [
            "Provider": "com.apple.wallpaper.choice.screen-saver",
            "Files": [],
            "Configuration": configData
        ]

        let idleContent: [String: Any] = [
            "Choices": [idleChoice],
            "Shuffle": "$null"
        ]

        func patchDict(_ dict: inout [String: Any]) {
            if var linked = dict["Linked"] as? [String: Any] {
                linked["Content"] = idleContent
                dict["Linked"] = linked
            }
            if var idle = dict["Idle"] as? [String: Any] {
                idle["Content"] = idleContent
                dict["Idle"] = idle
            }
            if var def = dict["Default"] as? [String: Any] {
                patchDict(&def)
                dict["Default"] = def
            }
            if var displays = dict["Displays"] as? [String: Any] {
                for (dispID, dispObj) in displays {
                    if var dispDict = dispObj as? [String: Any] {
                        patchDict(&dispDict)
                        displays[dispID] = dispDict
                    }
                }
                dict["Displays"] = displays
            }
        }

        if var allObj = rootDict["AllSpacesAndDisplays"] as? [String: Any] {
            patchDict(&allObj)
            rootDict["AllSpacesAndDisplays"] = allObj
        }

        if var sysDefault = rootDict["SystemDefault"] as? [String: Any] {
            patchDict(&sysDefault)
            rootDict["SystemDefault"] = sysDefault
        }

        if var spaces = rootDict["Spaces"] as? [String: Any] {
            for (spaceID, spaceObj) in spaces {
                if var spaceDict = spaceObj as? [String: Any] {
                    patchDict(&spaceDict)
                    spaces[spaceID] = spaceDict
                }
            }
            rootDict["Spaces"] = spaces
        }

        if var displays = rootDict["Displays"] as? [String: Any] {
            for (dispID, dispObj) in displays {
                if var dispDict = dispObj as? [String: Any] {
                    patchDict(&dispDict)
                    displays[dispID] = dispDict
                }
            }
            rootDict["Displays"] = displays
        }

        do {
            let patchedData = try PropertyListSerialization.data(fromPropertyList: rootDict, format: .binary, options: 0)
            try patchedData.write(to: URL(fileURLWithPath: indexPlistPath), options: .atomic)

            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            task.arguments = ["WallpaperAgent", "wallpaperd"]
            try? task.run()
        } catch {
            PrivacyDiagnostics.log("LivePaperApp", "Failed to write patched Index.plist", error: error, privacyModeEnabled: privacyModeEnabled)
        }
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

            let sourceURL = URL(fileURLWithPath: originalPath)
            let compatURL = mediaDir.appendingPathComponent("preferred_compat.mp4")
            
            if fm.fileExists(atPath: compatURL.path) {
                try fm.removeItem(at: compatURL)
            }
            try fm.copyItem(at: sourceURL, to: compatURL)

            stageVideoIntoSaverBundle(from: compatURL)
            overrideSystemAerialVideoCache(with: compatURL)
            return compatURL.path
        } catch {
            PrivacyDiagnostics.log("LivePaperApp", "Failed to stage preferred video for saver access", error: error, privacyModeEnabled: privacyModeEnabled)
            DispatchQueue.main.async { [weak self] in
                self?.controlCenterModel.loginAlertMessage = "Failed to copy video to Screen Saver folder.\n\nError: \(error.localizedDescription)\n\nIf the Screen Saver is currently active, please close it and try again."
            }
            return nil
        }
    }

    private func overrideSystemAerialVideoCache(with sourceURL: URL) {
        let fm = FileManager.default
        var userHome = NSHomeDirectory()
        #if canImport(Darwin)
        if let pwd = getpwuid(getuid()), let dir = pwd.pointee.pw_dir {
            userHome = String(cString: dir)
        }
        #endif

        let searchDirs = [
            "\(userHome)/Library/Application Support/com.apple.wallpaper/aerials/videos",
            "\(userHome)/Library/Containers/com.apple.wallpaper.agent/Data/Library/Caches/com.apple.wallpaper.caches"
        ]

        for dir in searchDirs {
            if !fm.fileExists(atPath: dir) {
                try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
            }
            if let items = try? fm.contentsOfDirectory(atPath: dir) {
                for item in items where item.hasSuffix(".mov") || item.hasSuffix(".mp4") {
                    let targetPath = (dir as NSString).appendingPathComponent(item)
                    try? fm.removeItem(atPath: targetPath)
                    try? fm.copyItem(at: sourceURL, to: URL(fileURLWithPath: targetPath))
                }
            }
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
        var userHome = NSHomeDirectory()
        #if canImport(Darwin)
        if let pwd = getpwuid(getuid()), let dir = pwd.pointee.pw_dir {
            userHome = String(cString: dir)
        }
        #endif

        let mainSaverBundle = "\(userHome)/Library/Screen Savers/LivePaper.saver"
        let agentCacheSaverDir = "\(userHome)/Library/Containers/com.apple.wallpaper.agent/Data/Library/Caches/com.apple.wallpaper.caches/screenSaver-/Library/Screen Savers"

        if fm.fileExists(atPath: mainSaverBundle) {
            let targetAgentBundle = "\(agentCacheSaverDir)/LivePaper.saver"
            do {
                if !fm.fileExists(atPath: agentCacheSaverDir) {
                    try fm.createDirectory(atPath: agentCacheSaverDir, withIntermediateDirectories: true)
                }
                if fm.fileExists(atPath: targetAgentBundle) {
                    try fm.removeItem(atPath: targetAgentBundle)
                }
                try fm.copyItem(atPath: mainSaverBundle, toPath: targetAgentBundle)
            } catch {
                PrivacyDiagnostics.log("LivePaperApp", "Failed to copy .saver bundle to wallpaper agent cache", error: error, privacyModeEnabled: privacyModeEnabled)
            }
        }

        let bundlePaths = [
            "\(userHome)/Library/Screen Savers/LivePaper.saver/Contents/Resources",
            "\(agentCacheSaverDir)/LivePaper.saver/Contents/Resources"
        ]

        for bundlePath in bundlePaths {
            let dirURL = URL(fileURLWithPath: bundlePath, isDirectory: true)
            do {
                if !fm.fileExists(atPath: dirURL.path) {
                    try fm.createDirectory(at: dirURL, withIntermediateDirectories: true)
                }
                let ext = sourceURL.pathExtension.isEmpty ? "mp4" : sourceURL.pathExtension
                let targets = [
                    dirURL.appendingPathComponent("preferred_compat.mp4"),
                    dirURL.appendingPathComponent("preferred_compat.\(ext)"),
                    dirURL.appendingPathComponent("preferred.mp4")
                ]
                for target in targets {
                    if fm.fileExists(atPath: target.path) {
                        try fm.removeItem(at: target)
                    }
                    try fm.copyItem(at: sourceURL, to: target)
                }
            } catch {
                PrivacyDiagnostics.log("LivePaperApp", "Failed to stage video into saver bundle at \(bundlePath)", error: error, privacyModeEnabled: privacyModeEnabled)
            }
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
            controlCenterModel.loginAlertMessage = "macOS requires the application to be placed in your Applications folder and properly code-signed to enable Start at Login automatically.\n\nError: \(error.localizedDescription)\n\nPlease ensure you have allowed background login items under System Settings -> General -> Login Items."
            updateConfig { cfg in
                cfg.startAtLogin = desired
            }
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
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.setContentSize(NSSize(width: 1040, height: 740))
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 900, height: 660)
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
        let launchAgentURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.livepaper.app.plist")

        if enabled {
            var smAppSuccess = false
            if #available(macOS 13.0, *) {
                do {
                    try SMAppService.mainApp.register()
                    smAppSuccess = true
                } catch {
                    print("[LivePaperApp] SMAppService registration failed: \(error.localizedDescription)")
                }
            }

            if !smAppSuccess {
                let execPath = Bundle.main.executablePath ?? CommandLine.arguments.first ?? ""
                guard !execPath.isEmpty else { return }
                
                let plistContent = """
                <?xml version="1.0" encoding="UTF-8"?>
                <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
                <plist version="1.0">
                <dict>
                    <key>Label</key>
                    <string>com.livepaper.app</string>
                    <key>ProgramArguments</key>
                    <array>
                        <string>\(execPath)</string>
                    </array>
                    <key>RunAtLoad</key>
                    <true/>
                    <key>ProcessType</key>
                    <string>Interactive</string>
                </dict>
                </plist>
                """
                let folder = launchAgentURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try plistContent.write(to: launchAgentURL, atomically: true, encoding: .utf8)
            }
        } else {
            if #available(macOS 13.0, *) {
                try? SMAppService.mainApp.unregister()
            }
            if FileManager.default.fileExists(atPath: launchAgentURL.path) {
                try? FileManager.default.removeItem(at: launchAgentURL)
            }
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
    @Published var thumbnails: [String: NSImage] = [:]
    @Published var isApplyingWallpaper: Bool = false
    @Published var isApplyingScreenSaver: Bool = false
    @Published var applyingWallpaperPath: String?
    @Published var applyingScreenSaverPath: String?
    @Published var loginAlertMessage: String? = nil
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

private struct PulsingDot: View {
    let color: Color
    @State private var pulse = false
    
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .stroke(color, lineWidth: 2)
                    .scaleEffect(pulse ? 2.2 : 1.0)
                    .opacity(pulse ? 0.0 : 0.6)
            )
            .onAppear {
                withAnimation(Animation.easeInOut(duration: 1.4).repeatForever(autoreverses: false)) {
                    pulse = true
                }
            }
            .id(color)
    }
}

struct AlertID: Identifiable {
    let id: String
}

private struct ControlCenterView: View {
    @ObservedObject var model: ControlCenterModel
    @State private var librarySearchText = ""
    @State private var hoveredTiles: [String: Bool] = [:]

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
        HStack(spacing: 0) {
            sidebar
                .frame(width: 220)
            
            VStack(spacing: 0) {
                topStrip
                Divider()
                ZStack {
                    Color.clear.ignoresSafeArea()
                    activePage
                        .padding(28)
                }
            }
        }
        .background(.ultraThinMaterial)
        .animation(.easeInOut(duration: 0.2), value: model.selectedTab)
        .alert(item: Binding<AlertID?>(
            get: { model.loginAlertMessage.map { AlertID(id: $0) } },
            set: { model.loginAlertMessage = $0?.id }
        )) { alertId in
            Alert(
                title: Text("Start At Login Status"),
                message: Text(alertId.id),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var topStrip: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.selectedTab.rawValue)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text(model.selectedTab.subtitle)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                Button(action: onStart) {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                        Text("Start")
                    }
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.green.opacity(0.12))
                    .foregroundStyle(.green)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.green.opacity(0.25), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                
                Button(action: onStop) {
                    HStack(spacing: 6) {
                        Image(systemName: "stop.fill")
                        Text("Stop")
                    }
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.red.opacity(0.10))
                    .foregroundStyle(.red)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.red.opacity(0.20), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(Color.clear)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Spacer()
                .frame(height: 52)
            
            Text("LivePaper")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(red: 0.0, green: 0.80, blue: 1.0), Color(red: 0.70, green: 0.15, blue: 0.95)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

            ForEach(ControlCenterTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        model.selectedTab = tab
                    }
                } label: {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(tab.rawValue)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                            Text(tab.subtitle)
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(model.selectedTab == tab ? Color.accentColor.opacity(0.12) : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(model.selectedTab == tab ? Color.accentColor.opacity(0.30) : Color.clear, lineWidth: 1)
                    )
                }
                .contentShape(Rectangle())
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
            }

            Spacer()
            
            HStack(spacing: 10) {
                PulsingDot(color: statusColor)
                Text(statusText)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .padding(16)
        }
        .frame(maxHeight: .infinity)
        .background(Color.primary.opacity(0.01))
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
        ScrollView {
            VStack(spacing: 20) {
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [statusColor.opacity(0.25), statusColor.opacity(0.0)],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 36
                                )
                            )
                            .frame(width: 80, height: 80)
                        
                        Circle()
                            .stroke(statusColor.opacity(0.12), lineWidth: 3)
                            .frame(width: 60, height: 60)
                        
                        PulsingDot(color: statusColor)
                            .scaleEffect(1.6)
                    }
                    .frame(width: 80, height: 80)
                    
                    VStack(alignment: .leading, spacing: 5) {
                        Text(statusText.uppercased())
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(statusColor)
                            .tracking(1.5)
                        
                        let currentPath = model.status?.currentVideoPath ?? "None"
                        let currentName = currentPath == "None" ? "No Active Wallpaper" : stripExtension((currentPath as NSString).lastPathComponent)
                        Text(currentName)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        
                        Text(friendlyStatusMessage(model.status?.message ?? "Waiting for worker status..."))
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                }
                .padding(20)
                .background(cardBackground)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Active Media Layout")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("WALLPAPER")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(.blue)
                                .tracking(1.0)
                            
                            let wallPath = model.config.wallpaperSelectedVideoPath ?? model.config.selectedVideoPath
                            let wallName = wallPath.map { stripExtension(($0 as NSString).lastPathComponent) } ?? "Default / None"
                            
                            ZStack {
                                if let path = wallPath, let thumb = model.thumbnails[path] {
                                    Image(nsImage: thumb)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(height: 120)
                                        .clipped()
                                } else {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color.blue.opacity(0.04))
                                        .frame(height: 120)
                                        .overlay(
                                            Image(systemName: "desktopcomputer")
                                                .font(.system(size: 24))
                                                .foregroundStyle(.blue.opacity(0.4))
                                        )
                                }
                            }
                            .frame(height: 120)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                            )
                            
                            Text(wallName)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .lineLimit(1)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(cardBackground)
                        
                        VStack(alignment: .leading, spacing: 10) {
                            Text("SCREEN SAVER")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(.purple)
                                .tracking(1.0)
                            
                            let saverPath = model.config.screenSaverSelectedVideoPath ?? model.config.selectedVideoPath
                            let saverOriginalPath = model.config.screenSaverOriginalVideoPath ?? saverPath
                            let saverName = saverOriginalPath.map { stripExtension(($0 as NSString).lastPathComponent) } ?? "Default / None"
                            
                            ZStack {
                                if let path = saverOriginalPath, let thumb = model.thumbnails[path] {
                                    Image(nsImage: thumb)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(height: 120)
                                        .clipped()
                                } else {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color.purple.opacity(0.04))
                                        .frame(height: 120)
                                        .overlay(
                                            Image(systemName: "sparkles")
                                                .font(.system(size: 24))
                                                .foregroundStyle(.purple.opacity(0.4))
                                        )
                                }
                            }
                            .frame(height: 120)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                            )
                            
                            Text(saverName)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .lineLimit(1)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(cardBackground)
                    }
                }

                metricsGrid
                
                HStack(alignment: .top, spacing: 16) {
                    quickActionsCard
                    nowPlayingCard
                }
            }
        }
    }

    private var libraryPage: some View {
        VStack(spacing: 20) {
            HStack(alignment: .top, spacing: 16) {
                sourceCard
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                previewCard
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            videoListCard
        }
    }

    private var settingsPage: some View {
        ScrollView {
            VStack(spacing: 20) {
                settingsOverviewCard
                settingsCard
                maintenanceCard
            }
        }
    }

    private var metricsGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Runtime Metrics")
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.02))
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.04), lineWidth: 1)
                )
        )
    }

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Source Folder")
                .font(.system(size: 15, weight: .bold, design: .rounded))
            
            HStack(spacing: 12) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(model.sourceFolder.isEmpty ? Color.secondary : Color.accentColor)
                
                Text(model.sourceFolder.isEmpty ? "No folder selected" : compactFolderName(model.sourceFolder))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(model.sourceFolder.isEmpty ? .secondary : .primary)
                
                Spacer()
            }
            .padding(.vertical, 4)
            
            HStack(spacing: 8) {
                Button(action: onSelectFolder) {
                    Label("Choose...", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                
                Button(action: onClearPreferredVideo) {
                    Label("Clear Selection", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button(action: onRefreshLibrary) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(16)
        .background(cardBackground)
    }

    private var videoListCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Folder Videos")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text("Choose videos to assign as live wallpaper or screen saver")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search library...", text: $librarySearchText)
                        .textFieldStyle(.plain)
                        .frame(width: 180)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary.opacity(0.04))
                        )
                }
            }

            if filteredVideoItems.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "film.stack")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary.opacity(0.7))
                    Text("No videos found")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    Text("Make sure to pick a folder containing playable videos.")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)],
                        spacing: 16
                    ) {
                        ForEach(filteredVideoItems, id: \.path) { item in
                            VStack(alignment: .leading, spacing: 0) {
                                ZStack {
                                    if let thumb = model.thumbnails[item.path] {
                                        Image(nsImage: thumb)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(height: 100)
                                            .clipped()
                                        
                                        LinearGradient(
                                            colors: [Color.black.opacity(0.4), Color.clear],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    } else {
                                        LinearGradient(
                                            colors: isPreferred(item.path) ? 
                                                [Color.accentColor.opacity(0.12), Color.accentColor.opacity(0.03)] :
                                                [Color.primary.opacity(0.03), Color.primary.opacity(0.01)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                        .frame(height: 100)
                                        
                                        Image(systemName: "film")
                                            .font(.system(size: 28))
                                            .foregroundStyle(isPreferred(item.path) ? Color.accentColor : Color.secondary)
                                    }
                                }
                                .frame(height: 100)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    onChooseWallpaperFromLibrary(item.path)
                                }
                                
                                Divider()
                                
                                VStack(alignment: .leading, spacing: 10) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(stripExtension(item.name))
                                            .font(.system(size: 13, weight: .bold, design: .rounded))
                                            .lineLimit(1)
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        onChooseWallpaperFromLibrary(item.path)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        if isWallpaperSelected(item.path) {
                                            Label("Active Wallpaper", systemImage: "desktopcomputer")
                                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                                .foregroundStyle(.blue)
                                        }
                                        if isScreenSaverSelected(item.path) {
                                            Label("Active Screen Saver", systemImage: "sparkles")
                                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                                .foregroundStyle(.purple)
                                        }
                                        
                                        if !isWallpaperSelected(item.path) && !isScreenSaverSelected(item.path) {
                                            Text(" ")
                                                .font(.system(size: 10))
                                                .opacity(0)
                                        }
                                    }
                                    .frame(height: 28, alignment: .leading)
                                    
                                    HStack(spacing: 8) {
                                        Button {
                                            onChooseWallpaperFromLibrary(item.path)
                                        } label: {
                                            if model.isApplyingWallpaper && model.applyingWallpaperPath == item.path {
                                                HStack(spacing: 4) {
                                                    ProgressView()
                                                        .controlSize(.small)
                                                    Text("Applying...")
                                                }
                                                .font(.system(size: 11, weight: .semibold))
                                            } else {
                                                Label("Wallpaper", systemImage: "desktopcomputer")
                                                    .font(.system(size: 11, weight: .semibold))
                                            }
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .tint(.blue)
                                        .controlSize(.small)
                                        .disabled(model.isApplyingWallpaper && model.applyingWallpaperPath == item.path)
                                        
                                        Button {
                                            onChooseScreenSaverFromLibrary(item.path)
                                        } label: {
                                            if model.isApplyingScreenSaver && model.applyingScreenSaverPath == item.path {
                                                HStack(spacing: 4) {
                                                    ProgressView()
                                                        .controlSize(.small)
                                                    Text("Applying...")
                                                }
                                                .font(.system(size: 11, weight: .semibold))
                                            } else {
                                                Label("Saver", systemImage: "sparkles")
                                                    .font(.system(size: 11, weight: .semibold))
                                            }
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                        .disabled(model.isApplyingScreenSaver && model.applyingScreenSaverPath == item.path)
                                    }
                                }
                                .padding(12)
                            }
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.primary.opacity(0.01))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(isPreferred(item.path) ? Color.accentColor.opacity(0.20) : Color.primary.opacity(0.05), lineWidth: 1)
                            )
                        }
                    }
                    .padding(.top, 4)
                }
                .frame(maxHeight: 460)
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

            detailRow("Worker Message", friendlyStatusMessage(model.status?.message ?? "No status yet"))
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
            
            let currentPath = model.status?.currentVideoPath ?? "None"
            let currentName = currentPath == "None" ? "None" : stripExtension((currentPath as NSString).lastPathComponent)
            detailRow("Current Video", currentName)
            
            detailRow("Playback Message", friendlyStatusMessage(model.status?.message ?? "-"))
            
            let wallPath = model.config.wallpaperSelectedVideoPath ?? model.config.selectedVideoPath
            let wallName = wallPath.map { stripExtension(($0 as NSString).lastPathComponent) } ?? "Default / Auto"
            detailRow("Wallpaper", wallName)
            
            let saverPath = model.config.screenSaverSelectedVideoPath ?? model.config.selectedVideoPath
            let saverOriginalPath = model.config.screenSaverOriginalVideoPath ?? saverPath
            let saverName = saverOriginalPath.map { stripExtension(($0 as NSString).lastPathComponent) } ?? "Default / Auto"
            detailRow("Screen Saver", saverName)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(16)
        .background(cardBackground)
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Active Previews")
                .font(.system(size: 15, weight: .bold, design: .rounded))
            
            HStack(spacing: 12) {
                // Wallpaper column
                VStack(alignment: .leading, spacing: 6) {
                    Text("WALLPAPER")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.blue)
                        .tracking(1.0)
                    
                    let wallPath = model.config.wallpaperSelectedVideoPath ?? model.config.selectedVideoPath
                    let wallName = wallPath.map { stripExtension(($0 as NSString).lastPathComponent) } ?? "Default / None"
                    
                    ZStack {
                        if let path = wallPath, let thumb = model.thumbnails[path] {
                            Image(nsImage: thumb)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 90)
                                .clipped()
                        } else {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.blue.opacity(0.04))
                                .frame(height: 90)
                                .overlay(
                                    Image(systemName: "desktopcomputer")
                                        .font(.system(size: 18))
                                        .foregroundStyle(.blue.opacity(0.4))
                                )
                        }
                    }
                    .frame(height: 90)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                    )
                    
                    Text(wallName)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Divider()
                    .frame(height: 100)
                
                // Screen Saver column
                VStack(alignment: .leading, spacing: 6) {
                    Text("SCREEN SAVER")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.purple)
                        .tracking(1.0)
                    
                    let saverPath = model.config.screenSaverSelectedVideoPath ?? model.config.selectedVideoPath
                    let saverOriginalPath = model.config.screenSaverOriginalVideoPath ?? saverPath
                    let saverName = saverOriginalPath.map { stripExtension(($0 as NSString).lastPathComponent) } ?? "Default / None"
                    
                    ZStack {
                        if let path = saverOriginalPath, let thumb = model.thumbnails[path] {
                            Image(nsImage: thumb)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 90)
                                .clipped()
                        } else {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.purple.opacity(0.04))
                                .frame(height: 90)
                                .overlay(
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 18))
                                        .foregroundStyle(.purple.opacity(0.4))
                                )
                        }
                    }
                    .frame(height: 90)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                    )
                    
                    Text(saverName)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
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
                    id: "pause",
                    title: (model.config.userPaused ?? false) ? "Resume Playback" : "Pause Playback",
                    subtitle: "Temporarily stop live rendering",
                    icon: "playpause",
                    prominent: true,
                    action: onTogglePause
                )
                actionTile(
                    id: "optimize",
                    title: (model.config.optimizeForEfficiency ?? true) ? "Efficiency Mode On" : "Efficiency Mode Off",
                    subtitle: "Lower CPU and battery usage",
                    icon: "leaf",
                    prominent: false,
                    action: onToggleOptimize
                )
                actionTile(
                    id: "startAtLogin",
                    title: model.config.startAtLogin ? "Start At Login On" : "Start At Login Off",
                    subtitle: "Launch app after user sign in",
                    icon: "power",
                    prominent: false,
                    action: onToggleStartAtLogin
                )
                actionTile(
                    id: "refresh",
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
                    color: Color.primary.opacity(0.04),
                    foreground: .primary,
                    subtitleOpacity: 0.7,
                    action: onClearCache
                )
                maintenanceActionTile(
                    title: "Reset Settings",
                    subtitle: "Restore defaults for playback, startup, and selected media paths.",
                    icon: "arrow.uturn.backward.circle",
                    color: Color.red.opacity(0.85),
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
                .fill(Color.primary.opacity(0.03))
        )
    }

    private func actionTile(
        id: String,
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
            .padding(12)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(prominent ? Color.accentColor : (hoveredTiles[id] ?? false ? Color.primary.opacity(0.08) : Color.primary.opacity(0.04)))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered in
            hoveredTiles[id] = isHovered
        }
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
                    .stroke(Color.primary.opacity(subtitleOpacity > 0.85 ? 0 : 0.08), lineWidth: 1)
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
                .fill(Color.primary.opacity(0.03))
        )
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.primary.opacity(0.03))
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 4)
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
                .fill(Color.primary.opacity(0.04))
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
        let saver = model.config.screenSaverOriginalVideoPath ?? model.config.screenSaverSelectedVideoPath ?? model.config.selectedVideoPath
        let rhs = (path as NSString).lastPathComponent.lowercased()
        return saver.map { ($0 as NSString).lastPathComponent.lowercased() == rhs || $0 == path } ?? false
    }

    private func stateBadge(_ label: String, color: Color = .secondary) -> some View {
        Text(label.uppercased())
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule(style: .continuous))
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

    private func stripExtension(_ filename: String) -> String {
        let ns = filename as NSString
        return ns.deletingPathExtension
    }

    private func friendlyStatusMessage(_ rawMessage: String) -> String {
        switch rawMessage {
        case "playing_single_display":
            return "Active on Main Display"
        case "playing_multi_display":
            return "Active on All Displays"
        case "paused":
            return "Playback Paused"
        case "stopped":
            return "Playback Stopped"
        default:
            let components = rawMessage.split(separator: "_")
            if !components.isEmpty {
                return components.map { $0.capitalized }.joined(separator: " ")
            }
            return rawMessage
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
