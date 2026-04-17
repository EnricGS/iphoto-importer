import SwiftUI

/// Thumbnail grid with virtualized layout, size slider, filter toggles, and multi-selection.
/// Split/Import buttons are positioned above the grid only (not spanning the viewer).
struct ThumbnailGridView: View {
    @Bindable var viewModel: MainViewModel

    // Computed column layout based on thumbnail size
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: viewModel.thumbnailSize, maximum: viewModel.thumbnailSize + 20), spacing: 4)]
    }

    var body: some View {
        VStack(spacing: 0) {
            // Device browse banner
            if viewModel.isDeviceBrowseMode {
                deviceBrowseBanner
            }

            // Grid controls (filter toggles, counter, slider) — show when any photos loaded
            if viewModel.photoCount + viewModel.videoCount > 0 {
                gridControls
            }

            // Thumbnail grid
            if viewModel.photos.isEmpty && !viewModel.isLoading && viewModel.photoCount + viewModel.videoCount == 0 {
                emptyState
            } else if viewModel.isTimelineMode {
                timelineContent
            } else {
                gridContent
            }
        }
        .background(Color.bgBase)
    }

    // MARK: - Device Browse Banner

    private var deviceBrowseBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "iphone")
                .foregroundStyle(Color.accent)
            Text("Browsing: \(viewModel.deviceService.selectedDevice?.name ?? "Device")")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.accent)
            Spacer()
            Button {
                viewModel.exitDeviceBrowseMode()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                    Text("Sortir")
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .buttonStyle(ToolbarButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.accentSubtle)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.accent.opacity(0.3)).frame(height: 1)
        }
    }

    // MARK: - Grid Controls

    private var gridControls: some View {
        HStack(spacing: 12) {
            // Element count
            HStack(spacing: 2) {
                Text("\(viewModel.photos.count)")
                    .foregroundStyle(Color.textSecondary)
                Text("elements")
                    .foregroundStyle(Color.textDim)
            }
            .font(.system(size: 12))

            // Filter toggles (pill style)
            HStack(spacing: 0) {
                // Photos filter toggle
                Button {
                    viewModel.filterPhotos.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "photo")
                            .font(.system(size: 11))
                        Text("\(viewModel.photoCount)")
                            .font(.system(size: 11))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(viewModel.filterPhotos ? Color.accentSubtle : Color.clear)
                    .foregroundStyle(viewModel.filterPhotos ? Color.accent : Color.textDim)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(viewModel.filterPhotos ? Color.accentDim : Color.clear, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Mostrar/amagar fotos")

                Divider().frame(height: 14)

                // Videos filter toggle
                Button {
                    viewModel.filterVideos.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "video")
                            .font(.system(size: 11))
                        Text("\(viewModel.videoCount)")
                            .font(.system(size: 11))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(viewModel.filterVideos ? Color.accentSubtle : Color.clear)
                    .foregroundStyle(viewModel.filterVideos ? Color.accent : Color.textDim)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(viewModel.filterVideos ? Color.accentDim : Color.clear, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Mostrar/amagar vídeos")
            }
            .padding(2)
            .background(Color.bgElevated)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Select all pill (with integrated deselect when items selected)
            Button {
                if viewModel.selectedPhotosCount > 0 {
                    viewModel.deselectAll()
                } else {
                    viewModel.selectAll()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: viewModel.selectedPhotosCount > 0 ? "checkmark.circle.fill" : "checkmark.circle")
                        .font(.system(size: 11))
                    if viewModel.selectedPhotosCount > 0 {
                        Text("\(viewModel.selectedPhotosCount)")
                            .font(.system(size: 11))
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(viewModel.selectedPhotosCount > 0 ? Color.accentSubtle : Color.clear)
                .foregroundStyle(viewModel.selectedPhotosCount > 0 ? Color.accent : Color.textDim)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(viewModel.selectedPhotosCount > 0 ? Color.accentDim : Color.clear, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help(viewModel.selectedPhotosCount > 0
                ? "Desseleccionar tot (Cmd+D)"
                : "Seleccionar tot (Cmd+A)")

            // Sort order toggle
            Button {
                viewModel.toggleSortOrder()
            } label: {
                HStack(spacing: 1) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(viewModel.sortAscending ? Color.accent : Color.textDim)
                    Image(systemName: "arrow.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(!viewModel.sortAscending ? Color.accent : Color.textDim)
                }
            }
            .buttonStyle(IconButtonStyle())
            .help(viewModel.sortAscending ? "Més antics primer (clic per canviar)" : "Més recents primer (clic per canviar)")

            // Split view toggle (moved from old bar 2)
            Button {
                viewModel.toggleViewMode()
            } label: {
                Image(systemName: viewModel.isSplitMode ? "rectangle.split.2x1" : "rectangle")
                    .font(.system(size: 12))
            }
            .buttonStyle(IconButtonStyle())
            .help("Mode split/toggle (Tab)")

            // Grid/Timeline toggle — show icon of the mode NOT active
            Button {
                viewModel.toggleTimelineMode()
            } label: {
                Image(systemName: viewModel.isTimelineMode ? "square.grid.2x2" : "calendar")
                    .font(.system(size: 12))
            }
            .buttonStyle(IconButtonStyle())
            .help(viewModel.isTimelineMode ? "Vista graella" : "Vista timeline")

            // Timeline grouping selector (only in timeline mode)
            if viewModel.isTimelineMode {
                HStack(spacing: 0) {
                    ForEach(TimelineGrouping.allCases, id: \.self) { grouping in
                        Button {
                            viewModel.setTimelineGrouping(grouping)
                        } label: {
                            Text(grouping.label)
                                .font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(viewModel.timelineGrouping == grouping ? Color.accentSubtle : Color.clear)
                                .foregroundStyle(viewModel.timelineGrouping == grouping ? Color.accent : Color.textDim)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(1)
                .background(Color.bgElevated)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // Thumbnail size slider
            HStack(spacing: 6) {
                Image(systemName: "square.grid.3x3")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.textPrimary)

                Slider(value: $viewModel.thumbnailSize, in: 80...400, step: 10)
                    .frame(width: 100)
                    .tint(Color.accent)
            }

            // Duplicates filters (independent pills, like photo/video)
            if viewModel.photoCount + viewModel.videoCount > 0 {
                // Exact duplicates pill
                Button {
                    viewModel.filterExactDuplicates.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Text("=")
                            .font(.system(size: 13, weight: .bold))
                        Text("\(viewModel.exactDuplicateCount)")
                            .font(.system(size: 11))
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(viewModel.filterExactDuplicates ? Color.accentSubtle : Color.bgElevated)
                    .foregroundStyle(viewModel.filterExactDuplicates ? Color.accent : Color.textDim)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(viewModel.filterExactDuplicates ? Color.accentDim : Color.clear, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .opacity(viewModel.isScanningExact ? 0.4 : 1.0)
                    .animation(
                        viewModel.isScanningExact
                            ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                            : .default,
                        value: viewModel.isScanningExact
                    )
                }
                .buttonStyle(.plain)
                .help(viewModel.isScanningExact ? "Cercant duplicats exactes..." : "Duplicats exactes")

                // Similar duplicates pill
                Button {
                    viewModel.filterSimilarDuplicates.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Text("≈")
                            .font(.system(size: 13, weight: .bold))
                        Text("\(viewModel.similarDuplicateCount)")
                            .font(.system(size: 11))
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(viewModel.filterSimilarDuplicates ? Color.accentSubtle : Color.bgElevated)
                    .foregroundStyle(viewModel.filterSimilarDuplicates ? Color.accent : Color.textDim)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(viewModel.filterSimilarDuplicates ? Color.accentDim : Color.clear, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .opacity(viewModel.isScanningSimilar ? 0.4 : 1.0)
                    .animation(
                        viewModel.isScanningSimilar
                            ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                            : .default,
                        value: viewModel.isScanningSimilar
                    )
                }
                .buttonStyle(.plain)
                .help(viewModel.isScanningSimilar ? "Cercant duplicats similars..." : "Duplicats similars")
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.bgSurface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.borderSubtle).frame(height: 1)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.accentSubtle)
                    .frame(width: 72, height: 72)
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.accent)
            }

            Text("Afegeix una carpeta per veure imatges")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(Color.textPrimary)
                .opacity(0.8)

            Text("o importa fotos des d'un dispositiu")
                .font(.system(size: 13))
                .foregroundStyle(Color.textDim)

            Button {
                viewModel.openFolder()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 16))
                    Text("Afegir carpeta")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.top, 8)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Grid Content

    // Rubber band selection state
    @State private var rubberBandStart: CGPoint?
    @State private var rubberBandCurrent: CGPoint?
    @State private var thumbnailFrames: [String: CGRect] = [:]
    @State private var headerFrames: [String: CGRect] = [:]

    private var gridContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                ZStack(alignment: .topLeading) {
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(viewModel.photos, id: \.id) { photo in
                            thumbnailItem(photo: photo)
                        }
                    }
                    .padding(8)

                    // Rubber band selection rectangle
                    if let start = rubberBandStart, let current = rubberBandCurrent {
                        let rect = rubberBandRect(from: start, to: current)
                        Rectangle()
                            .fill(Color.accent.opacity(0.15))
                            .overlay(
                                Rectangle()
                                    .stroke(Color.accent.opacity(0.6), lineWidth: 1)
                            )
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                            .allowsHitTesting(false)
                    }
                }
                .coordinateSpace(name: "gridCoordSpace")
                .onPreferenceChange(ThumbnailFramePreferenceKey.self) { frames in
                    thumbnailFrames.merge(frames) { _, new in new }
                }
                .onPreferenceChange(HeaderFramePreferenceKey.self) { frames in
                    headerFrames.merge(frames) { _, new in new }
                }
                .background(
                    RubberBandGestureView(
                        onDragStart: { point in
                            // Only start if not clicking on a thumbnail or header
                            let hitsThumbnail = thumbnailFrames.values.contains { $0.contains(point) }
                            let hitsHeader = headerFrames.values.contains { $0.contains(point) }
                            if !hitsThumbnail && !hitsHeader {
                                rubberBandStart = point
                                rubberBandCurrent = point
                            }
                        },
                        onDragChanged: { point in
                            guard rubberBandStart != nil else { return }
                            rubberBandCurrent = point
                            updateRubberBandSelection()
                        },
                        onDragEnded: {
                            rubberBandStart = nil
                            rubberBandCurrent = nil
                        },
                        onClickAt: { point in
                            // Check if click was on a header
                            for (key, frame) in headerFrames where frame.contains(point) {
                                viewModel.toggleGroupCollapse(key)
                                break
                            }
                        }
                    )
                )
            }
            .onChange(of: viewModel.scrollToIndex) { _, newValue in
                if let index = newValue, index < viewModel.photos.count {
                    let item = viewModel.photos[index]
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(item.id, anchor: .center)
                    }
                    viewModel.scrollToIndex = nil
                }
            }
        }
    }

    // MARK: - Thumbnail Item (shared between grid and timeline)

    @ViewBuilder
    private func thumbnailItem(photo: PhotoItem) -> some View {
        ThumbnailCell(
            photo: photo,
            size: viewModel.thumbnailSize,
            onImageTap: {
                viewModel.handleGridClick(item: photo)
            },
            onCheckboxTap: { isShift in
                viewModel.handleCheckboxClick(item: photo, isShiftPressed: isShift)
            }
        )
        .id(photo.id)
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: ThumbnailFramePreferenceKey.self,
                    value: [photo.id: geo.frame(in: .named("gridCoordSpace"))]
                )
            }
        )
        .overlay(alignment: .topLeading) {
            if photo.isLocal {
                MultiDragSourceView(
                    urlsProvider: {
                        if photo.isSelected {
                            let selected = viewModel.selectedFileURLs()
                            return selected.isEmpty ? [URL(fileURLWithPath: photo.fullPath)] : selected
                        }
                        return [URL(fileURLWithPath: photo.fullPath)]
                    },
                    thumbnailProvider: { photo.thumbnail },
                    onClick: { viewModel.handleGridClick(item: photo) }
                )
                .padding(.leading, 32)
                .padding(.top, 32)
            }
        }
    }

    // MARK: - Timeline Content (grouped, no rubber band)

    private var timelineContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(viewModel.groupedPhotos, id: \.key) { group in
                        // Section header
                        VStack(spacing: 0) {
                            HStack(spacing: 6) {
                                Image(systemName: viewModel.collapsedGroups.contains(group.key) ? "chevron.right" : "chevron.down")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Color.textDim)
                                    .frame(width: 12)
                                Text(group.key)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color.textPrimary)
                                Text("\(group.photos.count)")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.textDim)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            Rectangle().fill(Color.borderSubtle).frame(height: 1)
                        }
                        .background(Color.bgElevated)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.toggleGroupCollapse(group.key)
                        }
                        .zIndex(1)
                        .id("header_\(group.key)")

                        // Photos grid (if not collapsed)
                        if !viewModel.collapsedGroups.contains(group.key) {
                            LazyVGrid(columns: columns, spacing: 4) {
                                ForEach(group.photos, id: \.id) { photo in
                                    thumbnailItem(photo: photo)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.bottom, 4)
                        }
                    }
                }
                .padding(.top, 4)
            }
            .onChange(of: viewModel.scrollToIndex) { _, newValue in
                if let index = newValue, index < viewModel.photos.count {
                    let item = viewModel.photos[index]
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(item.id, anchor: .center)
                    }
                    viewModel.scrollToIndex = nil
                }
            }
        }
    }

    private func rubberBandRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    private func updateRubberBandSelection() {
        guard let start = rubberBandStart, let current = rubberBandCurrent else { return }
        let selRect = rubberBandRect(from: start, to: current)
        var selected = Set<PhotoItem>()
        for photo in viewModel.photos {
            if let frame = thumbnailFrames[photo.id], selRect.intersects(frame) {
                selected.insert(photo)
            }
        }
        viewModel.selectItems(selected)
    }
}

// MARK: - Preference Key for Thumbnail Frames

struct ThumbnailFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

struct HeaderFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

// MARK: - Rubber Band Gesture View (NSView-based for raw mouse events)

struct RubberBandGestureView: NSViewRepresentable {
    let onDragStart: (CGPoint) -> Void
    let onDragChanged: (CGPoint) -> Void
    let onDragEnded: () -> Void
    var onClickAt: ((CGPoint) -> Void)?

    func makeNSView(context: Context) -> RubberBandNSView {
        let view = RubberBandNSView()
        view.onDragStart = onDragStart
        view.onDragChanged = onDragChanged
        view.onDragEnded = onDragEnded
        view.onClickAt = onClickAt
        return view
    }

    func updateNSView(_ nsView: RubberBandNSView, context: Context) {
        nsView.onDragStart = onDragStart
        nsView.onDragChanged = onDragChanged
        nsView.onDragEnded = onDragEnded
        nsView.onClickAt = onClickAt
    }
}

class RubberBandNSView: NSView {
    var onDragStart: ((CGPoint) -> Void)?
    var onDragChanged: ((CGPoint) -> Void)?
    var onDragEnded: (() -> Void)?
    var onClickAt: ((CGPoint) -> Void)?

    private var isDragging = false
    private var didDrag = false
    private var mouseDownPoint: CGPoint = .zero

    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        let flipped = CGPoint(x: loc.x, y: bounds.height - loc.y)
        mouseDownPoint = flipped
        isDragging = true
        didDrag = false
        onDragStart?(flipped)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        didDrag = true
        let loc = convert(event.locationInWindow, from: nil)
        let flipped = CGPoint(x: loc.x, y: bounds.height - loc.y)
        onDragChanged?(flipped)
    }

    override func mouseUp(with event: NSEvent) {
        let wasDrag = didDrag
        isDragging = false
        didDrag = false
        onDragEnded?()

        // If it was a click (no drag), notify with the position
        if !wasDrag {
            onClickAt?(mouseDownPoint)
        }
    }
}

// MARK: - Thumbnail Cell

struct ThumbnailCell: View {
    let photo: PhotoItem
    let size: CGFloat
    let onImageTap: () -> Void
    let onCheckboxTap: (Bool) -> Void  // Bool = isShiftPressed

    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // Thumbnail image (clickable — opens viewer)
            Group {
                if let thumbnail = photo.thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Rectangle()
                        .fill(Color.bgElevated)
                        .overlay {
                            if photo.isVideo {
                                Image(systemName: "video")
                                    .font(.system(size: 24))
                                    .foregroundStyle(Color.textDim)
                                    .opacity(0.5)
                            } else {
                                Image(systemName: "photo")
                                    .font(.system(size: 24))
                                    .foregroundStyle(Color.textDim)
                                    .opacity(0.5)
                            }
                        }
                }
            }
            .frame(width: size, height: size)
            .clipped()
            .onTapGesture {
                onImageTap()
            }

            // Video indicator (center)
            if photo.isVideo, photo.thumbnail != nil {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            }

            // Gradient overlay at bottom
            LinearGradient(
                colors: [.clear, .black.opacity(0.6)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 46)
            .allowsHitTesting(false)

            // Date and location labels at bottom
            VStack(alignment: .leading, spacing: 1) {
                if let dateText = Self.catalanDateText(from: photo.dateTaken) {
                    Text(dateText)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                if let location = photo.location {
                    Text(location)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .allowsHitTesting(false)

            // Checkbox (top-left, always visible on hover or when selected)
            Image(systemName: photo.isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18))
                .foregroundStyle(photo.isSelected ? Color.accent : .white.opacity(0.7))
                .background(
                    Circle()
                        .fill(photo.isSelected ? .white : .black.opacity(0.4))
                        .padding(3)
                )
                .shadow(color: .black.opacity(0.5), radius: 2)
                .padding(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .opacity(photo.isSelected || isHovering ? 1 : 0)
                .onTapGesture {
                    onCheckboxTap(false)
                }
                .simultaneousGesture(
                    TapGesture()
                        .modifiers(.shift)
                        .onEnded { _ in
                            onCheckboxTap(true)
                        }
                )
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(borderColor, lineWidth: borderWidth)
        }
        .shadow(color: .black.opacity(isHovering ? 0.3 : 0), radius: 4)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private static let catalanMonths = [
        "Gener", "Febrer", "Març", "Abril", "Maig", "Juny",
        "Juliol", "Agost", "Setembre", "Octubre", "Novembre", "Desembre"
    ]

    private static func catalanDateText(from date: Date?) -> String? {
        guard let date else { return nil }
        let calendar = Calendar.current
        let month = calendar.component(.month, from: date)
        let year = calendar.component(.year, from: date)
        return "\(catalanMonths[month - 1]) \(year)"
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

// MARK: - Section Header Tap View (NSView-based, captures clicks before rubber band)

struct SectionHeaderTapView: NSViewRepresentable {
    let onTap: () -> Void

    func makeNSView(context: Context) -> SectionHeaderTapNSView {
        let view = SectionHeaderTapNSView()
        view.onTap = onTap
        return view
    }

    func updateNSView(_ nsView: SectionHeaderTapNSView, context: Context) {
        nsView.onTap = onTap
    }
}

class SectionHeaderTapNSView: NSView {
    var onTap: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        // Consume — don't let rubber band see it
    }

    override func mouseUp(with event: NSEvent) {
        onTap?()
    }

    override func mouseDragged(with event: NSEvent) {
        // Consume — don't start rubber band
    }
}

// MARK: - Multi-item Drag Source (permet arrossegar N fotos a Finder/Mail)

struct MultiDragSourceView: NSViewRepresentable {
    let urlsProvider: () -> [URL]
    let thumbnailProvider: () -> NSImage?
    let onClick: () -> Void

    func makeNSView(context: Context) -> MultiDragNSView {
        let view = MultiDragNSView()
        view.urlsProvider = urlsProvider
        view.thumbnailProvider = thumbnailProvider
        view.onClick = onClick
        return view
    }

    func updateNSView(_ nsView: MultiDragNSView, context: Context) {
        nsView.urlsProvider = urlsProvider
        nsView.thumbnailProvider = thumbnailProvider
        nsView.onClick = onClick
    }
}

final class MultiDragNSView: NSView, NSDraggingSource {
    var urlsProvider: (() -> [URL])?
    var thumbnailProvider: (() -> NSImage?)?
    var onClick: (() -> Void)?

    private var mouseDownPoint: NSPoint?
    private var didStartDrag = false
    private static let dragThreshold: CGFloat = 4

    // No volem ser first responder (interfereix amb la focus chain de SwiftUI).
    // Només volem rebre events de ratolí.
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        // .copy perquè Finder arrossegui una còpia; si volem moure, usar .generic
        return [.copy]
    }

    // Quan la drag session acaba, AppKit no envia mouseUp al NSView original.
    // Cal resetejar estat manualment i retornar el first responder a la finestra
    // perquè la UI torni a respondre clics.
    func draggingSession(_ session: NSDraggingSession,
                         endedAt screenPoint: NSPoint,
                         operation: NSDragOperation) {
        mouseDownPoint = nil
        didStartDrag = false
        if let window = self.window, window.firstResponder === self {
            window.makeFirstResponder(nil)
        }
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = convert(event.locationInWindow, from: nil)
        didStartDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint, !didStartDrag else { return }
        let current = convert(event.locationInWindow, from: nil)
        let dx = current.x - start.x
        let dy = current.y - start.y
        guard (dx * dx + dy * dy) >= (Self.dragThreshold * Self.dragThreshold) else { return }

        let urls = (urlsProvider?() ?? []).filter {
            FileManager.default.fileExists(atPath: $0.path)
        }
        guard !urls.isEmpty else { return }

        let preview = thumbnailProvider?() ?? NSImage(size: NSSize(width: 64, height: 64))
        let itemSize = NSSize(width: 80, height: 80)

        let items: [NSDraggingItem] = urls.enumerated().map { idx, url in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let stackOffset = CGFloat(min(idx, 4)) * 5
            let frame = NSRect(
                x: start.x - itemSize.width / 2 + stackOffset,
                y: start.y - itemSize.height / 2 - stackOffset,
                width: itemSize.width,
                height: itemSize.height
            )
            item.setDraggingFrame(frame, contents: preview)
            return item
        }

        didStartDrag = true
        beginDraggingSession(with: items, event: event, source: self)
        mouseDownPoint = nil
    }

    override func mouseUp(with event: NSEvent) {
        if !didStartDrag, mouseDownPoint != nil {
            onClick?()
        }
        mouseDownPoint = nil
        didStartDrag = false
    }
}
