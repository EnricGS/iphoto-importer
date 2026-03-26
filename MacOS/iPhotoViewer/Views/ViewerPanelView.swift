import SwiftUI
import AVKit

/// Side panel viewer for split mode.
/// Shows the current image/video with zoom, pan, and info.
struct ViewerPanelView: View {
    @Bindable var viewModel: MainViewModel

    @State private var isDragging = false
    @State private var dragStartOffset: CGSize = .zero

    var body: some View {
        VStack(spacing: 0) {
            // Viewer toolbar
            viewerToolbar

            // Content
            ZStack {
                Color.black

                if viewModel.isViewingVideo, let videoURL = viewModel.viewerVideoURL {
                    VideoPlayerView(url: videoURL)
                } else if let image = viewModel.viewerImage {
                    imageContent(image)
                } else {
                    Text("Select an image")
                        .foregroundStyle(Color.textSecondary)
                }
            }

            // Info bar
            if !viewModel.viewerInfoText.isEmpty {
                Text(viewModel.viewerInfoText)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.bgMedium)
            }
        }
        .background(Color.bgDark)
    }

    // MARK: - Toolbar

    private var viewerToolbar: some View {
        HStack(spacing: 8) {
            // Navigation
            Button { viewModel.viewerPrevious() } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.textPrimary)

            Button { viewModel.viewerNext() } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.textPrimary)

            Spacer()

            // Zoom controls
            Button { viewModel.viewerZoomOut() } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.textPrimary)

            Text("\(Int(viewModel.viewerZoom * 100))%")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 45)

            Button { viewModel.viewerZoomIn() } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.textPrimary)

            Button { viewModel.viewerZoomReset() } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.textPrimary)
            .help("Reset zoom")

            Spacer()

            // Close
            Button { viewModel.closeViewer() } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.textSecondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.bgMedium)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    // MARK: - Image Content

    @ViewBuilder
    private func imageContent(_ image: NSImage) -> some View {
        GeometryReader { geometry in
            let imageSize = image.size
            let containerSize = geometry.size

            let scaleX = containerSize.width / imageSize.width
            let scaleY = containerSize.height / imageSize.height
            let fitScale = min(scaleX, scaleY)

            let displayWidth = imageSize.width * fitScale * viewModel.viewerZoom
            let displayHeight = imageSize.height * fitScale * viewModel.viewerZoom

            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: displayWidth, height: displayHeight)
                .offset(x: viewModel.viewerOffsetX, y: viewModel.viewerOffsetY)
                .frame(width: containerSize.width, height: containerSize.height)
                .clipped()
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if viewModel.viewerZoom > 1.0 {
                                if !isDragging {
                                    isDragging = true
                                    dragStartOffset = CGSize(
                                        width: viewModel.viewerOffsetX,
                                        height: viewModel.viewerOffsetY
                                    )
                                }
                                viewModel.viewerOffsetX = dragStartOffset.width + value.translation.width
                                viewModel.viewerOffsetY = dragStartOffset.height + value.translation.height
                            }
                        }
                        .onEnded { _ in
                            isDragging = false
                        }
                )
                .background(ScrollGestureView { delta in
                    if delta > 0 {
                        viewModel.viewerZoomIn()
                    } else {
                        viewModel.viewerZoomOut()
                    }
                })
        }
    }
}
