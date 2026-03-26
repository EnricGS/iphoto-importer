import SwiftUI

/// Thumbnail grid with virtualized layout, size slider, and multi-selection.
struct ThumbnailGridView: View {
    @Bindable var viewModel: MainViewModel

    // Computed column layout based on thumbnail size
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: viewModel.thumbnailSize, maximum: viewModel.thumbnailSize + 20), spacing: 4)]
    }

    var body: some View {
        VStack(spacing: 0) {
            // Grid controls (slider, counters)
            gridControls

            // Thumbnail grid
            if viewModel.photos.isEmpty && !viewModel.isLoading {
                emptyState
            } else {
                gridContent
            }
        }
        .background(Color.bgDark)
    }

    // MARK: - Grid Controls

    private var gridControls: some View {
        HStack(spacing: 12) {
            // Photo count
            Text("\(viewModel.filteredPhotos.count) items")
                .font(.system(size: 12))
                .foregroundStyle(Color.textSecondary)

            Spacer()

            // Size labels
            Text("S")
                .font(.system(size: 11))
                .foregroundStyle(Color.textDim)

            // Thumbnail size slider
            Slider(value: $viewModel.thumbnailSize, in: 80...400, step: 10)
                .frame(width: 150)
                .tint(Color.accent)

            Text("XL")
                .font(.system(size: 11))
                .foregroundStyle(Color.textDim)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.bgMedium)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 48))
                .foregroundStyle(Color.textDim)
            Text("Open a folder to start viewing images")
                .font(.system(size: 16))
                .foregroundStyle(Color.textSecondary)
            Button("Open Folder") {
                viewModel.openFolder()
            }
            .buttonStyle(PrimaryButtonStyle())
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Grid Content

    private var gridContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(Array(viewModel.filteredPhotos.enumerated()), id: \.element.id) { index, photo in
                        ThumbnailCell(
                            photo: photo,
                            size: viewModel.thumbnailSize,
                            onTap: { modifiers in
                                let isCommand = modifiers.contains(.command)
                                let isShift = modifiers.contains(.shift)
                                viewModel.handleGridClick(item: photo, isCommandPressed: isCommand, isShiftPressed: isShift)
                            }
                        )
                        .id(photo.id)
                    }
                }
                .padding(4)
            }
            .onChange(of: viewModel.scrollToIndex) { _, newValue in
                if let index = newValue, index < viewModel.filteredPhotos.count {
                    let item = viewModel.filteredPhotos[index]
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(item.id, anchor: .center)
                    }
                    viewModel.scrollToIndex = nil
                }
            }
        }
    }
}

// MARK: - Thumbnail Cell

struct ThumbnailCell: View {
    let photo: PhotoItem
    let size: CGFloat
    let onTap: (EventModifiers) -> Void

    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Thumbnail image
            Group {
                if let thumbnail = photo.thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    // Placeholder while loading
                    Rectangle()
                        .fill(Color.bgLight)
                        .overlay {
                            if photo.isVideo {
                                Image(systemName: "video")
                                    .font(.system(size: 24))
                                    .foregroundStyle(Color.textDim)
                            } else {
                                Image(systemName: "photo")
                                    .font(.system(size: 24))
                                    .foregroundStyle(Color.textDim)
                            }
                        }
                }
            }
            .frame(width: size, height: size)
            .clipped()

            // Video indicator
            if photo.isVideo {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
                    .padding(4)
            }

            // Selection checkbox
            if photo.isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.accent)
                    .background(Circle().fill(.white).padding(2))
                    .padding(4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay {
            RoundedRectangle(cornerRadius: 4)
                .stroke(borderColor, lineWidth: borderWidth)
        }
        .shadow(color: .black.opacity(isHovering ? 0.3 : 0), radius: 4)
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture {
            // Simple tap (no modifiers)
            onTap([])
        }
        .simultaneousGesture(
            TapGesture()
                .modifiers(.command)
                .onEnded { _ in
                    onTap(.command)
                }
        )
        .simultaneousGesture(
            TapGesture()
                .modifiers(.shift)
                .onEnded { _ in
                    onTap(.shift)
                }
        )
    }

    private var borderColor: Color {
        if photo.isHighlighted { return Color.accent }
        if photo.isSelected { return Color.accent.opacity(0.6) }
        return Color.clear
    }

    private var borderWidth: CGFloat {
        if photo.isHighlighted { return 3 }
        if photo.isSelected { return 2 }
        return 0
    }
}
