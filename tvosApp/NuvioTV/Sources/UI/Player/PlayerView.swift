import SwiftUI
import UIKit

struct PlayerView: View {
    @StateObject private var viewModel = PlayerViewModel()

    let url: URL
    let meta: NuvioMeta
    let subtitle: String
    let externalSubtitles: [NuvioSubtitle]
    let resumeFrom: Double?
    var onBack: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // libmpv renders into the Metal layer owned by this controller.
            MPVVideoSurface(controller: viewModel.playerController)
                .ignoresSafeArea()

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

            if !viewModel.showControls {
                PlayerRemoteInputOverlay(
                    onSelect: viewModel.revealControls,
                    onLeft: viewModel.skipBackward,
                    onRight: viewModel.skipForward,
                    onExit: onBack
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
            }

            // Kept mounted (not gated by an `if`) so the hide animates too: removing
            // a view that holds tvOS focus makes the focus engine finalize the
            // removal before the transition can play, so only the appear would
            // animate. Animating opacity/scale on a mounted view sidesteps that —
            // focusability is gated inside PlayerControls so focus still hands off
            // cleanly to the remote-input overlay when hidden.
            PlayerControls(viewModel: viewModel)
                .opacity(viewModel.showControls ? 1 : 0)
                .scaleEffect(viewModel.showControls ? 1 : 0.95)
                .allowsHitTesting(viewModel.showControls)
                .animation(.playerControls, value: viewModel.showControls)
        }
        .onAppear {
            viewModel.load(url: url, meta: meta, subtitle: subtitle, externalSubtitles: externalSubtitles, resumeFrom: resumeFrom)
        }
        .onDisappear {
            viewModel.pause()
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
        .onExitCommand(perform: onBack)
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

private struct PlayerRemoteInputOverlay: UIViewRepresentable {
    let onSelect: () -> Void
    let onLeft: () -> Void
    let onRight: () -> Void
    let onExit: () -> Void

    func makeUIView(context: Context) -> RemoteInputView {
        let view = RemoteInputView()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.onSelect = onSelect
        view.onLeft = onLeft
        view.onRight = onRight
        view.onExit = onExit
        return view
    }

    func updateUIView(_ uiView: RemoteInputView, context: Context) {
        uiView.onSelect = onSelect
        uiView.onLeft = onLeft
        uiView.onRight = onRight
        uiView.onExit = onExit
        DispatchQueue.main.async {
            uiView.setNeedsFocusUpdate()
            uiView.updateFocusIfNeeded()
        }
    }

    final class RemoteInputView: UIView {
        var onSelect: (() -> Void)?
        var onLeft: (() -> Void)?
        var onRight: (() -> Void)?
        var onExit: (() -> Void)?

        override var canBecomeFocused: Bool { true }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            setNeedsFocusUpdate()
            updateFocusIfNeeded()
        }

        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            var handledPresses = Set<UIPress>()

            for press in presses {
                switch press.type {
                case .leftArrow:
                    onLeft?()
                    handledPresses.insert(press)
                case .rightArrow:
                    onRight?()
                    handledPresses.insert(press)
                case .select:
                    onSelect?()
                    handledPresses.insert(press)
                case .menu:
                    onExit?()
                    handledPresses.insert(press)
                default:
                    break
                }
            }

            let remainingPresses = presses.subtracting(handledPresses)
            if !remainingPresses.isEmpty {
                super.pressesBegan(remainingPresses, with: event)
            }
        }
    }
}
