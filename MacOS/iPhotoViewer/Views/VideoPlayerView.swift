import SwiftUI
import AVKit

/// AVPlayer-based video player view for both overlay and split modes.
struct VideoPlayerView: View {
    let url: URL

    @State private var player: AVPlayer?

    var body: some View {
        VStack {
            if let player {
                VideoPlayer(player: player)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            let newPlayer = AVPlayer(url: url)
            newPlayer.play()
            player = newPlayer
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
        .onChange(of: url) { _, newURL in
            player?.pause()
            let newPlayer = AVPlayer(url: newURL)
            newPlayer.play()
            player = newPlayer
        }
    }
}
