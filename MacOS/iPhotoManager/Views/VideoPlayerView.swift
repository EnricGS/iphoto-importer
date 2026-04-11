import SwiftUI
import AVKit
import AVFoundation

/// AppKit-based video player per evitar el crash de SwiftUI VideoPlayer
/// (_AVKit_SwiftUI getSuperclassMetadata fatal error a macOS 26.4+).
/// Usa AVPlayerView directament via NSViewRepresentable.
struct VideoPlayerView: View {
    let url: URL

    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            if errorMessage == nil {
                AVPlayerNSView(url: url, onError: { msg in
                    errorMessage = msg
                })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if let errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.orange)
                    Text("No es pot reproduir el vídeo")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(errorMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.6))
            }
        }
    }
}

/// Wrapper NSViewRepresentable d'AVPlayerView (AppKit) — evita el VideoPlayer de SwiftUI
/// que crashja a macOS 26.4+ per un bug de metadata generica.
private struct AVPlayerNSView: NSViewRepresentable {
    let url: URL
    let onError: (String) -> Void

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.showsFullScreenToggleButton = true
        view.videoGravity = .resizeAspect
        configure(view: view, with: url, context: context)
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        // Reconfigurar si l'URL canvia
        if context.coordinator.currentURL != url {
            configure(view: nsView, with: url, context: context)
        }
    }

    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: Coordinator) {
        coordinator.teardown()
        nsView.player?.pause()
        nsView.player = nil
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onError: onError)
    }

    private func configure(view: AVPlayerView, with url: URL, context: Context) {
        context.coordinator.teardown()
        context.coordinator.currentURL = url

        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)

        // Observar errors del player item per mostrar missatge en lloc de crashar
        context.coordinator.statusObserver = item.observe(\.status, options: [.new]) { [weak player] playerItem, _ in
            Task { @MainActor in
                switch playerItem.status {
                case .failed:
                    let err = playerItem.error?.localizedDescription ?? "Codec no suportat o fitxer malmès"
                    context.coordinator.onError(err)
                    player?.pause()
                case .readyToPlay:
                    player?.play()
                default:
                    break
                }
            }
        }

        view.player = player
    }

    final class Coordinator {
        var currentURL: URL?
        var statusObserver: NSKeyValueObservation?
        let onError: (String) -> Void

        init(onError: @escaping (String) -> Void) {
            self.onError = onError
        }

        func teardown() {
            statusObserver?.invalidate()
            statusObserver = nil
        }
    }
}
