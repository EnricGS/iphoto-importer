import SwiftUI
import AVKit

/// Full-screen overlay viewer (toggle mode).
/// Shows the current image/video with zoom, pan, and navigation.
struct ViewerOverlayView: View {
    @Bindable var viewModel: MainViewModel

    @State private var isDragging = false
    @State private var dragStartOffset: CGSize = .zero

    var body: some View {
        ZStack {
            // Dark background
            Color.black.opacity(0.92)
                .ignoresSafeArea()
                .onTapGesture(count: 2) {
                    viewModel.closeViewer()
                }

            // Image or video content
            if viewModel.isViewingVideo, let videoURL = viewModel.viewerVideoURL {
                VideoPlayerView(url: videoURL)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let image = viewModel.viewerImage {
                imageContent(image)
            }

            // Navigation buttons
            HStack {
                // Previous
                Button {
                    viewModel.viewerPrevious()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 50, height: 100)
                        .background(Color.black.opacity(0.3))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .padding(.leading, 12)

                Spacer()

                // Next
                Button {
                    viewModel.viewerNext()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 50, height: 100)
                        .background(Color.black.opacity(0.3))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .padding(.trailing, 12)
            }

            // Top bar: close button and info
            VStack {
                HStack {
                    // Close button
                    Button {
                        viewModel.closeViewer()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .padding(12)

                    Spacer()

                    // Zoom controls
                    HStack(spacing: 8) {
                        Button { viewModel.viewerZoomOut() } label: {
                            Image(systemName: "minus.magnifyingglass")
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)

                        Text("\(Int(viewModel.viewerZoom * 100))%")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.8))
                            .frame(width: 50)

                        Button { viewModel.viewerZoomIn() } label: {
                            Image(systemName: "plus.magnifyingglass")
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)

                        Button { viewModel.viewerZoomReset() } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                        .help("Reset zoom (0)")

                        Button { viewModel.viewerFitToScreen() } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                        .help("Fit to screen (F)")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(12)
                }

                Spacer()

                // Bottom info bar
                Text(viewModel.viewerInfoText)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.bottom, 12)
            }
        }
    }

    // MARK: - Image Content with Zoom & Pan

    @ViewBuilder
    private func imageContent(_ image: NSImage) -> some View {
        GeometryReader { geometry in
            let imageSize = image.size
            let containerSize = geometry.size

            // Calculate fit scale
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
                .onScrollGesture { delta in
                    if delta > 0 {
                        viewModel.viewerZoomIn()
                    } else {
                        viewModel.viewerZoomOut()
                    }
                }
        }
    }
}

// MARK: - Scroll Gesture Modifier

extension View {
    func onScrollGesture(action: @escaping (CGFloat) -> Void) -> some View {
        self.onContinuousHover { phase in
            // Scroll handled via NSEvent monitoring below
        }
        .background(ScrollGestureView(action: action))
    }
}

/// NSView wrapper to capture scroll wheel events.
struct ScrollGestureView: NSViewRepresentable {
    let action: (CGFloat) -> Void

    func makeNSView(context: Context) -> ScrollCaptureNSView {
        let view = ScrollCaptureNSView()
        view.action = action
        return view
    }

    func updateNSView(_ nsView: ScrollCaptureNSView, context: Context) {
        nsView.action = action
    }
}

class ScrollCaptureNSView: NSView {
    var action: ((CGFloat) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        action?(event.scrollingDeltaY)
    }
}
