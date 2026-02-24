import AppKit
import AVKit
import AVFoundation
import Foundation
import LiveSceneCore
import ScreenSaver

@objc(LiveSceneSaverView)
public final class LiveSceneSaverView: ScreenSaverView {
    private let configStore = ConfigStore()
    private let catalog = VideoCatalog()
    private var privacyModeEnabled = true

    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var playerView: AVPlayerView?
    private var statusText: NSTextField?
    private var retryCounter = 0
    private var lastRetryTime = Date.distantPast

    public override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)

        wantsLayer = true
        if layer == nil {
            layer = CALayer()
        }
        animationTimeInterval = 1.0 / 30.0

        configurePlaceholderUI()
        startPlaybackIfPossible()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)

        wantsLayer = true
        if layer == nil {
            layer = CALayer()
        }
        animationTimeInterval = 1.0 / 30.0

        configurePlaceholderUI()
        startPlaybackIfPossible()
    }

    deinit {
        stopPlayback()
    }

    public override func startAnimation() {
        super.startAnimation()
        if player == nil {
            attemptStartPlayback()
        } else {
            player?.play()
        }
    }

    public override func stopAnimation() {
        super.stopAnimation()
        player?.pause()
    }

    public override func animateOneFrame() {
        if player == nil, Date().timeIntervalSince(lastRetryTime) >= 5 {
            attemptStartPlayback()
        }
    }

    private func configurePlaceholderUI() {
        let pv = AVPlayerView(frame: bounds)
        pv.autoresizingMask = [.width, .height]
        pv.controlsStyle = .none
        pv.videoGravity = .resizeAspectFill
        pv.isHidden = true
        addSubview(pv, positioned: .below, relativeTo: nil)
        playerView = pv

        let label = NSTextField(labelWithString: "Livepaper Saver")
        label.textColor = .white
        label.font = NSFont.boldSystemFont(ofSize: 20)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        statusText = label
        layer?.backgroundColor = NSColor.black.cgColor
    }

    private func setStatus(_ text: String) {
        statusText?.stringValue = text
    }

    private func startPlaybackIfPossible() {
        var loadedConfig = LiveSceneConfig()
        do {
            let configPath = try configStore.defaultConfigPath()
            loadedConfig = try configStore.load(from: configPath)
            privacyModeEnabled = loadedConfig.privacyModeEnabled ?? true
        } catch {
            PrivacyDiagnostics.log("LiveSceneSaver", "config load failed, continuing with fallback", error: error, privacyModeEnabled: privacyModeEnabled)
        }

        do {
            if let staged = locateStagedPreferredVideo(),
               FileManager.default.fileExists(atPath: staged) {
                try startPlayback(videoPath: staged, scaleMode: loadedConfig.scaleMode, muteAudio: loadedConfig.muteAudio)
                setStatus("")
                return
            }

            if let preferred = resolvedPreferredVideoPath(from: loadedConfig),
               !preferred.isEmpty,
               FileManager.default.fileExists(atPath: preferred) {
                try startPlayback(videoPath: preferred, scaleMode: loadedConfig.scaleMode, muteAudio: loadedConfig.muteAudio)
                setStatus("")
                return
            }

            guard !loadedConfig.sourceFolder.isEmpty else {
                setStatus("Livepaper Saver\nSet source folder in Livepaper app")
                return
            }

            let videos = try catalog.scan(folderPath: loadedConfig.sourceFolder)
            guard let first = videos.first else {
                setStatus("Livepaper Saver\nNo videos found in source folder")
                return
            }

            try startPlayback(videoPath: first.path, scaleMode: loadedConfig.scaleMode, muteAudio: loadedConfig.muteAudio)
            setStatus("")
        } catch {
            PrivacyDiagnostics.log("LiveSceneSaver", "startPlaybackIfPossible error", error: error, privacyModeEnabled: privacyModeEnabled)
            let detail = PrivacyDiagnostics.errorSummary(error, privacyModeEnabled: privacyModeEnabled)
            setStatus("Livepaper Saver\n\(detail)")
        }
    }

    private func locateStagedPreferredVideo() -> String? {
        let fm = FileManager.default
        if let bundled = Bundle.main.url(forResource: "preferred_compat", withExtension: "mp4")?.path,
           fm.fileExists(atPath: bundled) {
            return bundled
        }

        let candidates = [
            "\(NSHomeDirectory())/Library/Application Support/LiveScene/Media/preferred_compat.mp4",
            "\(NSHomeDirectory())/Library/Application Support/LiveScene/Media/preferred.mp4",
            "\(NSHomeDirectory())/Library/Screen Savers/Livepaper.saver/Contents/Resources/preferred_compat.mp4"
        ]
        for path in candidates where fm.fileExists(atPath: path) {
            return path
        }
        return nil
    }

    private func resolvedPreferredVideoPath(from config: LiveSceneConfig) -> String? {
        do {
            let configPath = try configStore.defaultConfigPath()
            let mediaDir = configPath.deletingLastPathComponent().appendingPathComponent("Media", isDirectory: true)
            let staged = ["preferred_compat.mp4", "preferred.mp4", "preferred.mov", "preferred.m4v"]
            for file in staged {
                let candidate = mediaDir.appendingPathComponent(file).path
                if FileManager.default.fileExists(atPath: candidate) {
                    return candidate
                }
            }
        } catch {
            PrivacyDiagnostics.log("LiveSceneSaver", "failed to resolve staged preferred video", error: error, privacyModeEnabled: privacyModeEnabled)
        }

        let selected = config.screenSaverSelectedVideoPath ?? config.selectedVideoPath
        if let selected,
           !selected.isEmpty,
           FileManager.default.fileExists(atPath: selected) {
            return selected
        }
        return nil
    }

    private func startPlayback(videoPath: String, scaleMode: ScaleMode, muteAudio: Bool) throws {
        guard FileManager.default.fileExists(atPath: videoPath) else {
            throw LiveSceneCoreError.invalidSourceFolder(videoPath)
        }

        let item = AVPlayerItem(url: URL(fileURLWithPath: videoPath))
        item.preferredForwardBufferDuration = 2.0
        let player = AVQueuePlayer(items: [])
        let looper = AVPlayerLooper(player: player, templateItem: item)

        player.isMuted = muteAudio
        player.automaticallyWaitsToMinimizeStalling = false

        guard let playerView else {
            throw LiveSceneCoreError.invalidConfigPath
        }
        playerView.player = player
        playerView.videoGravity = gravity(for: scaleMode)
        playerView.isHidden = false

        self.player = player
        self.looper = looper

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePlaybackFailure),
            name: .AVPlayerItemFailedToPlayToEndTime,
            object: item
        )

        let safePath = PrivacyDiagnostics.pathForDisplay(videoPath, privacyModeEnabled: privacyModeEnabled)
        PrivacyDiagnostics.log("LiveSceneSaver", "starting playback at \(safePath)", privacyModeEnabled: privacyModeEnabled)
        player.play()
    }

    private func stopPlayback() {
        NotificationCenter.default.removeObserver(self)
        player?.pause()
        looper?.disableLooping()
        playerView?.player = nil
        playerView?.isHidden = true

        looper = nil
        player = nil
    }

    private func attemptStartPlayback() {
        lastRetryTime = Date()
        retryCounter += 1
        stopPlayback()
        startPlaybackIfPossible()
    }

    @objc private func handlePlaybackFailure() {
        setStatus("Livepaper Saver\nPlayback failed, retrying...")
        attemptStartPlayback()
    }

    private func gravity(for mode: ScaleMode) -> AVLayerVideoGravity {
        switch mode {
        case .fill:
            return .resizeAspectFill
        case .fit, .center:
            return .resizeAspect
        case .stretch:
            return .resize
        }
    }
}
