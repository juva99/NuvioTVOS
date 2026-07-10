import AVFoundation

/// Dependency-free adaptation of KSPlayer 2.3.4's native AVPlayer backend.
@MainActor
public final class KSOptions {
    public var isAutoPlay = false
    public init() {}
}

@MainActor
public final class KSAVPlayer {
    public let player = AVQueuePlayer()

    private var url: URL
    private let options: KSOptions

    public init(url: URL, options: KSOptions) {
        self.url = url
        self.options = options
        player.automaticallyWaitsToMinimizeStalling = false
    }

    public var currentPlaybackTime: TimeInterval {
        get { player.currentTime().seconds.isFinite ? player.currentTime().seconds : 0 }
        set { player.seek(to: CMTime(seconds: max(newValue, 0), preferredTimescale: 600)) }
    }

    public func prepareToPlay() {
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        if options.isAutoPlay { player.play() }
    }

    public func play() {
        player.play()
    }

    public func shutdown() {
        player.pause()
        player.replaceCurrentItem(with: nil)
    }
}
