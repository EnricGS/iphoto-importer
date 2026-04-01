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
                Color.bgBase

                if viewModel.isViewingVideo, let videoURL = viewModel.viewerVideoURL {
                    VideoPlayerView(url: videoURL)
                } else if let image = viewModel.viewerImage {
                    imageContent(image)
                } else {
                    Text("Select an image")
                        .foregroundStyle(Color.textSecondary)
                }

                // Navigation buttons
                HStack {
                    Button { viewModel.viewerPrevious() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 64)
                            .background(Color.black.opacity(0.3))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .opacity(0.5)
                    .padding(.leading, 10)
                    .help("Previous")

                    Spacer()

                    Button { viewModel.viewerNext() } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 16))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 64)
                            .background(Color.black.opacity(0.3))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .opacity(0.5)
                    .padding(.trailing, 10)
                    .help("Next")
                }
            }

            // Bottom info bar removed — info shown in toolbar above
        }
        .background(Color.bgBase)
    }

    // MARK: - Toolbar

    private var viewerToolbar: some View {
        HStack(spacing: 8) {
            // Info text
            Text(viewModel.viewerInfoText)
                .font(.system(size: 10))
                .foregroundStyle(Color.textDim)
                .lineLimit(1)

            Spacer()

            // Zoom controls
            Button { viewModel.viewerZoomOut() } label: {
                Image(systemName: "minus.magnifyingglass")
                    .font(.system(size: 11))
            }
            .buttonStyle(IconButtonStyle())
            .help("Zoom out (-)")

            Text("\(Int(viewModel.viewerZoom * 100))%")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color.textDim)
                .frame(width: 45)

            Button { viewModel.viewerZoomIn() } label: {
                Image(systemName: "plus.magnifyingglass")
                    .font(.system(size: 11))
            }
            .buttonStyle(IconButtonStyle())
            .help("Zoom in (+)")

            Button { viewModel.viewerZoomReset() } label: {
                Text("1:1")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.textDim)
            }
            .buttonStyle(IconButtonStyle())
            .help("Reset zoom (0)")

            // Select/deselect current photo
            Button {
                if let item = viewModel.viewerCurrentItem {
                    viewModel.toggleSelection(for: item)
                }
            } label: {
                Image(systemName: viewModel.viewerCurrentItem?.isSelected == true
                    ? "checkmark.circle.fill" : "checkmark.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(viewModel.viewerCurrentItem?.isSelected == true
                        ? Color.accent : Color.textDim)
            }
            .buttonStyle(IconButtonStyle())
            .help(viewModel.viewerCurrentItem?.isSelected == true ? "Desseleccionar" : "Seleccionar")

            // Copy current photo
            Button {
                Task { await viewModel.copyCurrentPhoto() }
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 13))
            }
            .buttonStyle(IconButtonStyle())
            .help("Copiar foto al destí (C)")

            // Delete current photo
            Button {
                if let item = viewModel.viewerCurrentItem {
                    if !item.isSelected {
                        viewModel.toggleSelection(for: item)
                    }
                    if viewModel.isDeviceBrowseMode {
                        Task { await viewModel.deleteSelectedFromDevice() }
                    } else {
                        Task { await viewModel.deleteSelected() }
                    }
                }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.dangerColor)
            }
            .buttonStyle(IconButtonStyle())
            .help("Eliminar")

            // Close
            Button { viewModel.closeViewer() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textDim)
            }
            .buttonStyle(IconButtonStyle())
            .help("Close viewer (Esc)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.bgSurface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.borderSubtle).frame(height: 1)
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
                .background(
                    SmoothScrollZoomView(containerSize: containerSize) { delta, cursorX, cursorY in
                        withAnimation(.easeOut(duration: 0.15)) {
                            viewModel.viewerSmoothZoom(delta: delta, cursorX: cursorX, cursorY: cursorY)
                        }
                    }
                )
        }
    }
}
