import SwiftUI
import UIKit
import AVKit
import Combine
import GMPlayerKit
import KSPlayer

struct RoutedPlayerView: View {
    let preferredEngine: PlayerEngine
    let url: URL
    let meta: NuvioMeta
    let subtitle: String
    let externalSubtitles: [NuvioSubtitle]
    let resumeFrom: Double?
    var episodes: [NuvioVideo] = []
    var currentEpisode: NuvioVideo? = nil
    var autoPlayNextEnabled: Bool = true
    var resolveNextStream: ((NuvioVideo) async -> PreparedNextStream?)? = nil
    var reloadCurrentStream: (() async -> PreparedNextStream?)? = nil
    var onFinished: (() -> Void)? = nil
    var onBack: () -> Void

    @State private var activeEngine: PlayerEngine
    @State private var shouldTryGMPlayer = false
    @State private var playbackStage: String?

    init(
        preferredEngine: PlayerEngine,
        url: URL,
        meta: NuvioMeta,
        subtitle: String,
        externalSubtitles: [NuvioSubtitle],
        resumeFrom: Double?,
        episodes: [NuvioVideo] = [],
        currentEpisode: NuvioVideo? = nil,
        autoPlayNextEnabled: Bool = true,
        resolveNextStream: ((NuvioVideo) async -> PreparedNextStream?)? = nil,
        reloadCurrentStream: (() async -> PreparedNextStream?)? = nil,
        onFinished: (() -> Void)? = nil,
        onBack: @escaping () -> Void
    ) {
        self.preferredEngine = preferredEngine
        self.url = url
        self.meta = meta
        self.subtitle = subtitle
        self.externalSubtitles = externalSubtitles
        self.resumeFrom = resumeFrom
        self.episodes = episodes
        self.currentEpisode = currentEpisode
        self.autoPlayNextEnabled = autoPlayNextEnabled
        self.resolveNextStream = resolveNextStream
        self.reloadCurrentStream = reloadCurrentStream
        self.onFinished = onFinished
        self.onBack = onBack
        _activeEngine = State(initialValue: preferredEngine)
        _playbackStage = State(
            initialValue: preferredEngine == .ksPlayer ? "Trying native playback..." : nil
        )
    }

    var body: some View {
        Group {
            if activeEngine == .ksPlayer && !shouldTryGMPlayer {
                KSNativePlayerView(
                    url: url,
                    resumeFrom: resumeFrom,
                    onStarted: { playbackStage = nil },
                    onFailure: {
                        playbackStage = "Opening MKV remux engine..."
                        shouldTryGMPlayer = true
                    },
                    onFinished: onFinished ?? onBack
                )
                .onExitCommand(perform: onBack)
            } else if activeEngine == .ksPlayer && shouldTryGMPlayer {
                GMNativePlayerView(
                    url: url,
                    resumeFrom: resumeFrom,
                    onStageChange: { playbackStage = $0 },
                    onFailure: {
                        if playbackStage?.contains("failed") != true &&
                            playbackStage?.contains("timed out") != true {
                            playbackStage = "Native remux failed. Falling back to MPVKit..."
                        }
                        shouldTryGMPlayer = false
                        activeEngine = .mpvKit
                    },
                    onFinished: onFinished ?? onBack
                )
                .onExitCommand(perform: onBack)
            } else {
                PlayerView(
                    url: url,
                    meta: meta,
                    subtitle: subtitle,
                    externalSubtitles: externalSubtitles,
                    resumeFrom: resumeFrom,
                    episodes: episodes,
                    currentEpisode: currentEpisode,
                    autoPlayNextEnabled: autoPlayNextEnabled,
                    resolveNextStream: resolveNextStream,
                    reloadCurrentStream: reloadCurrentStream,
                    onFinished: onFinished,
                    onBack: onBack
                )
            }
        }
        .overlay {
            if let playbackStage {
                VStack(spacing: 20) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(1.5)
                    Text(playbackStage)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 34)
                .padding(.vertical, 26)
                .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 24))
                .allowsHitTesting(false)
            }
        }
        .onChange(of: activeEngine) { engine in
            if engine == .mpvKit {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    if activeEngine == .mpvKit { playbackStage = nil }
                }
            }
        }
    }
}

private struct GMNativePlayerView: UIViewControllerRepresentable {
    let url: URL
    let resumeFrom: Double?
    let onStageChange: (String?) -> Void
    let onFailure: () -> Void
    let onFinished: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onStageChange: onStageChange, onFailure: onFailure, onFinished: onFinished)
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.showsPlaybackControls = true
        context.coordinator.start(url: url, controller: controller, resumeFrom: resumeFrom)
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: Coordinator) {
        coordinator.shutdown()
        controller.player = nil
    }

    @MainActor
    final class Coordinator: NSObject {
        private let model = GMPlayerModel()
        private var cancellables: Set<AnyCancellable> = []
        private var itemObservation: NSKeyValueObservation?
        private var statusObservation: NSKeyValueObservation?
        private var timeControlObservation: NSKeyValueObservation?
        private var endObserver: NSObjectProtocol?
        private var failureObserver: NSObjectProtocol?
        private var preparationTimer: Timer?
        private var startupTimer: Timer?
        private var startupBaseline = 0.0
        private var startupDeadline: Date?
        private var didResume = false
        private var didFail = false
        private let onStageChange: (String?) -> Void
        private let onFailure: () -> Void
        private let onFinished: (() -> Void)?

        init(
            onStageChange: @escaping (String?) -> Void,
            onFailure: @escaping () -> Void,
            onFinished: (() -> Void)?
        ) {
            self.onStageChange = onStageChange
            self.onFailure = onFailure
            self.onFinished = onFinished
        }

        func start(url: URL, controller: AVPlayerViewController, resumeFrom: Double?) {
            controller.player = model.player
            onStageChange("Connecting to stream...")
            model.$state.sink { [weak self] state in
                Task { @MainActor in
                    guard let self else { return }
                    switch state {
                    case .idle:
                        break
                    case .probing(let probe):
                        switch probe.phase {
                        case .connecting:
                            self.onStageChange("Connecting to stream...")
                        case .inspecting:
                            self.onStageChange(Self.probeStage(probe))
                        }
                    case .remuxing(let progress):
                        self.onStageChange("Remuxing MKV... \(Int(progress * 100))%")
                    case .readyToPlay:
                        self.onStageChange("Preparing Dolby Vision playback...")
                    case .failed:
                        self.onStageChange("Dolby Vision preparation failed\nRemux engine could not prepare the stream")
                        self.fail()
                    }
                }
            }.store(in: &cancellables)
            model.monitor.$snapshot.sink { [weak self] snapshot in
                guard snapshot.status == "failed" || !snapshot.lastError.isEmpty else { return }
                Task { @MainActor in
                    guard let self else { return }
                    let detail = snapshot.lastError.isEmpty ? "AVPlayer rejected the stream" : snapshot.lastError
                    self.onStageChange("Dolby Vision preparation failed\n\(detail)")
                    self.fail()
                }
            }.store(in: &cancellables)

            itemObservation = model.player.observe(\.currentItem, options: [.new]) { [weak self] player, _ in
                guard let self, let item = player.currentItem else { return }
                Task { @MainActor in self.observe(item: item, resumeFrom: resumeFrom) }
            }
            timeControlObservation = model.player.observe(
                \.timeControlStatus,
                options: [.initial, .new]
            ) { [weak self] player, _ in
                Task { @MainActor in
                    guard let self, self.didResume, self.startupTimer != nil else { return }
                    switch player.timeControlStatus {
                    case .waitingToPlayAtSpecifiedRate:
                        let reason = player.reasonForWaitingToPlay.map(Self.waitingReason) ?? "buffering"
                        self.onStageChange("Waiting for first video frame...\n\(reason)")
                    case .paused:
                        self.onStageChange("Waiting for first video frame...\nplayer paused")
                    case .playing:
                        self.onStageChange("Waiting for first video frame...\ndecoder started")
                    @unknown default:
                        break
                    }
                }
            }
            model.open(remoteURL: url)
        }
        private func observe(item: AVPlayerItem, resumeFrom: Double?) {
            preparationTimer?.invalidate()
            let timer = Timer(timeInterval: 30, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    guard let self, !self.didResume else { return }
                    self.onStageChange("Dolby Vision preparation timed out\nAVPlayer never became ready")
                    self.fail()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            preparationTimer = timer

            statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                guard let self else { return }
                Task { @MainActor in
                    switch item.status {
                    case .readyToPlay:
                        guard !self.didResume else { return }
                        self.preparationTimer?.invalidate()
                        self.preparationTimer = nil
                        self.didResume = true
                        self.onStageChange("Waiting for first video frame...")
                        if let resumeFrom, resumeFrom > 0 {
                            self.model.player.seek(
                                to: CMTime(seconds: resumeFrom, preferredTimescale: 600)
                            ) { [weak self] _ in
                                Task { @MainActor in self?.startPlaybackWatchdog() }
                            }
                        } else {
                            self.startPlaybackWatchdog()
                        }
                    case .failed:
                        self.fail()
                    default:
                        break
                    }
                }
            }
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.onFinished?() }
            }
            failureObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemFailedToPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.fail() }
            }
        }

        private func fail() {
            guard !didFail else { return }
            didFail = true
            preparationTimer?.invalidate()
            preparationTimer = nil
            startupTimer?.invalidate()
            startupTimer = nil
            model.stop()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [onFailure] in
                onFailure()
            }
        }

        private func startPlaybackWatchdog() {
            guard !didFail else { return }
            startupTimer?.invalidate()
            startupBaseline = model.player.currentTime().seconds.isFinite
                ? model.player.currentTime().seconds : 0
            startupDeadline = Date().addingTimeInterval(30)
            model.player.play()

            let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] timer in
                Task { @MainActor in
                    guard let self, !self.didFail else {
                        timer.invalidate()
                        return
                    }
                    let current = self.model.player.currentTime().seconds
                    if current.isFinite, current >= self.startupBaseline + 0.5 {
                        timer.invalidate()
                        self.startupTimer = nil
                        self.onStageChange(nil)
                    } else if let deadline = self.startupDeadline, Date() >= deadline {
                        timer.invalidate()
                        let reason = self.model.player.reasonForWaitingToPlay
                            .map(Self.waitingReason) ?? "no decoder progress"
                        self.onStageChange("First video frame timed out\n\(reason)")
                        self.fail()
                    }
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            startupTimer = timer
        }

        private static func probeStage(_ probe: GMPlayerModel.ProbeStatus) -> String {
            let bytes = ByteCountFormatter.string(fromByteCount: probe.bytesRead, countStyle: .file)
            guard probe.bytesPerSec > 0 else { return "Inspecting MKV... \(bytes)" }
            let rate = ByteCountFormatter.string(
                fromByteCount: Int64(probe.bytesPerSec),
                countStyle: .file
            )
            return "Inspecting MKV... \(bytes) at \(rate)/s"
        }

        private static func waitingReason(_ reason: AVPlayer.WaitingReason) -> String {
            switch reason {
            case .evaluatingBufferingRate: return "evaluating buffer"
            case .toMinimizeStalls: return "buffering to avoid stalls"
            case .noItemToPlay: return "no playable item"
            default: return reason.rawValue
            }
        }

        func shutdown() {
            itemObservation?.invalidate()
            itemObservation = nil
            statusObservation?.invalidate()
            statusObservation = nil
            timeControlObservation?.invalidate()
            timeControlObservation = nil
            if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
            endObserver = nil
            if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
            failureObserver = nil
            preparationTimer?.invalidate()
            preparationTimer = nil
            startupTimer?.invalidate()
            startupTimer = nil
            cancellables.removeAll()
            model.stop()
        }
    }
}

private struct KSNativePlayerView: UIViewControllerRepresentable {
    let url: URL
    let resumeFrom: Double?
    let onStarted: () -> Void
    let onFailure: () -> Void
    let onFinished: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onStarted: onStarted, onFailure: onFailure, onFinished: onFinished)
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let options = KSOptions()
        options.isAutoPlay = true
        let player = KSAVPlayer(url: url, options: options)
        let controller = AVPlayerViewController()
        controller.player = player.player
        controller.showsPlaybackControls = true
        context.coordinator.start(player: player, resumeFrom: resumeFrom)
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: Coordinator) {
        coordinator.shutdown()
        controller.player = nil
    }

    @MainActor
    final class Coordinator: NSObject {
        private var ksPlayer: KSAVPlayer?
        private var statusTimer: Timer?
        private var endObserver: NSObjectProtocol?
        private var failureObserver: NSObjectProtocol?
        private var didStart = false
        private var didFail = false
        private let onStarted: () -> Void
        private let onFailure: () -> Void
        private let onFinished: (() -> Void)?

        init(
            onStarted: @escaping () -> Void,
            onFailure: @escaping () -> Void,
            onFinished: (() -> Void)?
        ) {
            self.onStarted = onStarted
            self.onFailure = onFailure
            self.onFinished = onFinished
        }

        func start(player: KSAVPlayer, resumeFrom: Double?) {
            ksPlayer = player
            statusTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self, weak player] timer in
                guard let self, let player, let item = player.player.currentItem else { return }
                switch item.status {
                case .readyToPlay:
                    guard !self.didStart else { return }
                    let hasPlayableVideo = item.tracks.contains {
                        $0.assetTrack?.mediaType == .video && $0.assetTrack?.isPlayable == true
                    }
                    guard hasPlayableVideo else {
                        timer.invalidate()
                        self.fail()
                        return
                    }
                    self.didStart = true
                    self.onStarted()
                    if let resumeFrom, resumeFrom > 0 {
                        player.currentPlaybackTime = resumeFrom
                    }
                    player.play()
                case .failed:
                    timer.invalidate()
                    self.fail()
                default:
                    break
                }
            }
            player.prepareToPlay()
            guard let item = player.player.currentItem else {
                fail()
                return
            }
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.onFinished?() }
            }
            failureObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemFailedToPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.fail() }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self, weak player] in
                guard let self, let player, !self.didStart,
                      player.player.currentItem?.status != .readyToPlay else { return }
                self.fail()
            }
        }

        private func fail() {
            guard !didFail else { return }
            didFail = true
            onFailure()
        }

        func shutdown() {
            statusTimer?.invalidate()
            statusTimer = nil
            if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
            endObserver = nil
            if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
            failureObserver = nil
            ksPlayer?.shutdown()
            ksPlayer = nil
        }
    }
}

struct PlayerView: View {
    @StateObject private var viewModel = PlayerViewModel()

    let url: URL
    let meta: NuvioMeta
    let subtitle: String
    let externalSubtitles: [NuvioSubtitle]
    let resumeFrom: Double?
    /// Episode context for the Netflix-style auto-play. Empty for movies/trailers.
    var episodes: [NuvioVideo] = []
    var currentEpisode: NuvioVideo? = nil
    var autoPlayNextEnabled: Bool = true
    /// Resolves a next episode into a ready-to-play stream (add-on fetch + smart
    /// selection), supplied by the app layer. Nil disables auto-advance.
    var resolveNextStream: ((NuvioVideo) async -> PreparedNextStream?)? = nil
    /// Re-resolves a fresh stream for the *current* title/episode, used to
    /// silently recover from an expired link. Nil disables auto-reload.
    var reloadCurrentStream: (() async -> PreparedNextStream?)? = nil
    var onFinished: (() -> Void)? = nil
    var onBack: () -> Void

    @State private var didHandleFinished = false
    @FocusState private var remoteInputFocused: Bool
    @FocusState private var nextEpisodeFocused: Bool
    @FocusState private var skipSegmentFocused: Bool

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // libmpv renders into the Metal layer owned by this controller.
            MPVVideoSurface(controller: viewModel.playerController)
                .ignoresSafeArea()

            RemoteSeekPressCatcher(
                // Active when the controls are hidden, or when they're up and the
                // timeline scrubber holds focus — so a held left/right keeps
                // seeking until release in both states. Never while the play/
                // settings buttons are focused (there left/right navigates) or
                // the settings panel is open. Passed as a plain Bool (not a
                // closure) so `updateUIViewController` runs on every change and
                // the catcher can re-grab first responder — the SwiftUI focus
                // engine hands first responder to the focused control otherwise,
                // and a sibling controller would silently stop receiving presses.
                isActive: !viewModel.showSettingsPanel
                    && (!viewModel.showControls || viewModel.isTimelineFocused),
                onBeginBackward: { viewModel.beginRepeatingSkipBackward() },
                onBeginForward: { viewModel.beginRepeatingSkipForward() },
                onEnd: { viewModel.stopRepeatingSkip() }
            )
            .frame(width: 1, height: 1)
            .accessibilityHidden(true)

            switch viewModel.status {
            case .buffering, .idle:
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(2)
                    .padding(48)
                    .glassCircle()
            case .error(let message):
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(.yellow)
                    Text("Playback failed")
                        .font(.title2.weight(.semibold))
                        .foregroundColor(.white)
                    Text(message)
                        .font(.body)
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 900)
                }
                .padding(48)
                .glassRoundedRect(cornerRadius: 32)
            default:
                EmptyView()
            }

            // Focus sink for when the controls are hidden. tvOS routes the Menu
            // button to the system (which quits the app) and drops directional
            // input whenever no view holds focus, so something must always own it
            // while the controls are down. A bare focusable `Color.clear` is used
            // deliberately, not a Button: a Button draws a white full-screen focus
            // glow on tvOS 26+ (even with `.buttonStyle(.plain)` + focus effect
            // disabled), and dropping its opacity to hide that glow also makes the
            // focus engine skip it entirely — so `up` produced no move command.
            // A focusable Color draws no highlight yet stays reliably focusable at
            // full opacity. Kept mounted full-time (mounting it only when the
            // controls hide raced the timeline losing focusability, leaving focus in
            // a void); non-focusable while the controls are up so focus hands cleanly
            // to the timeline, focusable again the instant they hide. `up`/`down`
            // reveal via the PlayerView `onMoveCommand`; the select click reveals via
            // the tap gesture.
            Color.clear
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .focusable(!viewModel.showControls && !viewModel.showNextEpisodeCard && !viewModel.showSkipSegmentCard)
                .focused($remoteInputFocused)
                .onTapGesture { viewModel.revealControls() }
                .accessibilityHidden(true)

            if viewModel.showSkipSegmentCard, let interval = viewModel.activeSkipInterval {
                SkipSegmentOverlay(
                    interval: interval,
                    countdown: viewModel.skipSegmentCountdown,
                    isFocused: skipSegmentFocused,
                    onSkip: { viewModel.skipActiveInterval() }
                )
                .focused($skipSegmentFocused)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.leading, 60)
                .padding(.bottom, viewModel.showControls ? 200 : 54)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(3)
            }

            // Netflix-style next-episode prompt, shown near the end. Visible even
            // when the transport controls are up (raised above them); focusable
            // only when the controls are down so it doesn't fight them for focus.
            // Left/Right still fast-forward, which cancels the countdown.
            if viewModel.showNextEpisodeCard, let next = viewModel.nextEpisode {
                NextEpisodeOverlay(
                    episode: next,
                    countdown: viewModel.nextEpisodeCountdown,
                    isAdvancing: viewModel.isAdvancingEpisode,
                    isFocused: nextEpisodeFocused,
                    onPlay: { viewModel.playNextEpisode() }
                )
                .focusable(true)
                .focused($nextEpisodeFocused)
                .onTapGesture { viewModel.playNextEpisode() }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, 60)
                .padding(.bottom, viewModel.showControls ? 200 : 54)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(3)
            }

            // Kept mounted (not gated by an `if`) so the hide animates too: removing
            // a view that holds tvOS focus makes the focus engine finalize the
            // removal before the transition can play, so only the appear would
            // animate. Animating opacity/scale on a mounted view sidesteps that —
            // focusability is gated inside PlayerControls so focus still hands off
            // cleanly to the remote-input overlay when hidden.
            PlayerControls(
                viewModel: viewModel,
                isSkipSegmentFocused: skipSegmentFocused,
                isNextEpisodeFocused: nextEpisodeFocused,
                onFocusSkipSegment: { focusSkipSegment() },
                onFocusNextEpisode: { focusNextEpisode() }
            )
                .opacity(viewModel.showControls && !viewModel.showSettingsPanel ? 1 : 0)
                .scaleEffect(viewModel.showControls ? 1 : 0.95)
                .allowsHitTesting(viewModel.showControls && !viewModel.showSettingsPanel)
                .animation(.playerControls, value: viewModel.showControls)
                .animation(.playerControls, value: viewModel.showSettingsPanel)

            // Settings panel (subtitles / audio / speed), over the dimmed video.
            if viewModel.showSettingsPanel {
                PlayerSettingsPanel(viewModel: viewModel) {
                    viewModel.showSettingsPanel = false
                }
                .transition(.opacity)
                .zIndex(2)
            }
        }
        .animation(.playerControls, value: viewModel.showSettingsPanel)
        .animation(.playerControls, value: viewModel.showNextEpisodeCard)
        .animation(.playerControls, value: viewModel.showSkipSegmentCard)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            viewModel.load(url: url, meta: meta, subtitle: subtitle, externalSubtitles: externalSubtitles, resumeFrom: resumeFrom)
            viewModel.reloadCurrentStream = reloadCurrentStream
            if let resolveNextStream {
                viewModel.configureNextEpisode(
                    episodes: episodes,
                    current: currentEpisode,
                    autoPlayEnabled: autoPlayNextEnabled,
                    resolver: resolveNextStream
                )
            }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            viewModel.shutdown()
        }
        .onChange(of: viewModel.status) { status in
            UIApplication.shared.isIdleTimerDisabled = (status == .playing || status == .buffering)
            guard status == .ended,
                  !didHandleFinished,
                  let onFinished else {
                return
            }
            didHandleFinished = true
            onFinished()
        }
        .onChange(of: viewModel.showControls) { isVisible in
            if isVisible {
                remoteInputFocused = false
                nextEpisodeFocused = false
                skipSegmentFocused = false
            } else if viewModel.showNextEpisodeCard {
                focusNextEpisode()
            } else if viewModel.showSkipSegmentCard {
                focusSkipSegment()
            } else {
                focusRemoteInput()
            }
        }
        .onChange(of: viewModel.showNextEpisodeCard) { visible in
            guard !viewModel.showControls else { return }
            if visible {
                focusNextEpisode()
            } else if viewModel.showSkipSegmentCard {
                focusSkipSegment()
            } else {
                focusRemoteInput()
            }
        }
        .onChange(of: viewModel.showSkipSegmentCard) { visible in
            guard !viewModel.showControls, !viewModel.showNextEpisodeCard else { return }
            if visible {
                focusSkipSegment()
            } else {
                skipSegmentFocused = false
                focusRemoteInput()
            }
        }
        .onPlayPauseCommand {
            viewModel.togglePlayPause()
        }
        .onMoveCommand { direction in
            guard !viewModel.showControls else { return }
            switch direction {
            case .left:
                viewModel.skipBackward()
            case .right:
                viewModel.skipForward()
            default:
                viewModel.revealControls()
            }
        }
        .onExitCommand {
            // The panel handles its own exit; this fallback covers the frame
            // where focus hasn't landed inside it yet.
            if viewModel.showSettingsPanel {
                viewModel.showSettingsPanel = false
                return
            }
            remoteInputFocused = false
            onBack()
        }
    }

    private func focusRemoteInput() {
        DispatchQueue.main.async {
            remoteInputFocused = true
        }
    }

    private func focusNextEpisode() {
        DispatchQueue.main.async {
            nextEpisodeFocused = true
        }
    }

    private func focusSkipSegment() {
        DispatchQueue.main.async {
            skipSegmentFocused = true
        }
    }
}

// Hosts the libmpv UIViewController (owns the CAMetalLayer surface).
struct MPVVideoSurface: UIViewControllerRepresentable {
    let controller: MPVPlayerViewController

    func makeUIViewController(context: Context) -> MPVPlayerViewController {
        controller
    }

    func updateUIViewController(_ uiViewController: MPVPlayerViewController, context: Context) {}
}

private struct RemoteSeekPressCatcher: UIViewControllerRepresentable {
    let isActive: Bool
    let onBeginBackward: () -> Void
    let onBeginForward: () -> Void
    let onEnd: () -> Void

    func makeUIViewController(context: Context) -> RemoteSeekPressViewController {
        let controller = RemoteSeekPressViewController()
        controller.onBeginBackward = onBeginBackward
        controller.onBeginForward = onBeginForward
        controller.onEnd = onEnd
        controller.setActive(isActive)
        return controller
    }

    func updateUIViewController(_ controller: RemoteSeekPressViewController, context: Context) {
        controller.onBeginBackward = onBeginBackward
        controller.onBeginForward = onBeginForward
        controller.onEnd = onEnd
        // Re-assert on every SwiftUI update: when a control gains focus the focus
        // engine takes first responder, so a sibling catcher has to grab it back
        // to keep receiving the held left/right presses on the device.
        controller.setActive(isActive)
    }
}

private final class RemoteSeekPressViewController: UIViewController {
    enum Direction {
        case backward
        case forward
    }

    var onBeginBackward: () -> Void = {}
    var onBeginForward: () -> Void = {}
    var onEnd: () -> Void = {}

    private var activeDirection: Direction?
    private var isActive = false

    override var canBecomeFirstResponder: Bool { isActive }

    /// Enable/disable seek interception and (re)claim first responder so held
    /// directional presses route here instead of the focused SwiftUI control.
    func setActive(_ active: Bool) {
        isActive = active
        if active {
            if !isFirstResponder { becomeFirstResponder() }
        } else {
            if activeDirection != nil {
                activeDirection = nil
                onEnd()
            }
            if isFirstResponder { resignFirstResponder() }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if isActive { becomeFirstResponder() }
    }

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        if parent != nil, isActive {
            becomeFirstResponder()
        }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard activeDirection == nil,
              isActive,
              let direction = seekDirection(in: presses) else {
            super.pressesBegan(presses, with: event)
            return
        }

        activeDirection = direction
        switch direction {
        case .backward: onBeginBackward()
        case .forward: onBeginForward()
        }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if activeDirection != nil, seekDirection(in: presses) != nil {
            activeDirection = nil
            onEnd()
        } else {
            super.pressesEnded(presses, with: event)
        }
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if activeDirection != nil {
            activeDirection = nil
            onEnd()
        } else {
            super.pressesCancelled(presses, with: event)
        }
    }

    private func seekDirection(in presses: Set<UIPress>) -> Direction? {
        if presses.contains(where: { $0.type == .leftArrow }) { return .backward }
        if presses.contains(where: { $0.type == .rightArrow }) { return .forward }
        return nil
    }
}
