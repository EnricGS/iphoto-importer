import SwiftUI

/// Root content view that manages the overall layout:
/// - Toolbar at top
/// - Main content area (grid + optional split viewer)
/// - Action bar at bottom (when items selected)
/// - Status bar
struct ContentView: View {
    @State private var viewModel = MainViewModel()

    var body: some View {
        ZStack {
            // Background
            Color.bgDark
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top toolbar
                ToolbarView(viewModel: viewModel)

                // Main content area
                mainContent

                // Action bar (visible when items are selected)
                if viewModel.showActionBar {
                    ActionBarView(viewModel: viewModel)
                }

                // Status bar
                StatusBarView(viewModel: viewModel)
            }

            // Overlay viewer (toggle mode)
            if viewModel.isOverlayViewerVisible {
                ViewerOverlayView(viewModel: viewModel)
                    .transition(.opacity)
            }

            // Import panel (slide from right)
            if viewModel.isImportPanelOpen {
                ImportPanelView(viewModel: viewModel)
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.isOverlayViewerVisible)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isImportPanelOpen)
        .animation(.easeInOut(duration: 0.15), value: viewModel.showActionBar)
        .frame(minWidth: 900, minHeight: 600)
        .onKeyPress(phases: .down) { press in
            handleKeyPress(press)
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        if viewModel.isSplitMode {
            // Split mode: grid + viewer side by side
            HSplitView {
                ThumbnailGridView(viewModel: viewModel)
                    .frame(minWidth: 300)

                if viewModel.isSplitViewerVisible {
                    ViewerPanelView(viewModel: viewModel)
                        .frame(minWidth: 400)
                }
            }
        } else {
            // Toggle mode: grid only (viewer is overlay)
            ThumbnailGridView(viewModel: viewModel)
        }
    }

    // MARK: - Keyboard Shortcuts

    private func handleKeyPress(_ press: KeyPress) -> KeyPress.Result {
        let modifiers = press.modifiers

        // Tab and F5: toggle split/toggle mode
        if press.key == .tab && modifiers.isEmpty {
            viewModel.toggleViewMode()
            return .handled
        }

        // Viewer shortcuts (when viewer is active)
        let viewerActive = viewModel.isViewerOpen || viewModel.isSplitViewerVisible
        if viewerActive {
            switch press.key {
            case .escape:
                viewModel.closeViewer()
                return .handled
            case .leftArrow:
                viewModel.viewerPrevious()
                return .handled
            case .rightArrow:
                viewModel.viewerNext()
                return .handled
            case .space:
                // Toggle video play/pause handled by video player
                return .handled
            default:
                break
            }

            // Zoom shortcuts
            switch press.characters {
            case "+", "=":
                viewModel.viewerZoomIn()
                return .handled
            case "-":
                viewModel.viewerZoomOut()
                return .handled
            case "0":
                viewModel.viewerZoomReset()
                return .handled
            case "f":
                viewModel.viewerFitToScreen()
                return .handled
            case "c" where modifiers.isEmpty:
                Task { await viewModel.copyCurrentPhoto() }
                return .handled
            default:
                break
            }

            // In overlay mode, don't process grid shortcuts
            if viewModel.isOverlayViewerVisible {
                return .ignored
            }
        }

        // Grid shortcuts
        if modifiers.contains(.command) {
            switch press.characters {
            case "o":
                viewModel.openFolder()
                return .handled
            case "a":
                viewModel.selectAll()
                return .handled
            case "d":
                viewModel.deselectAll()
                return .handled
            default:
                break
            }
        }

        if press.key == .delete || press.key == .deleteForward {
            if viewModel.selectedPhotosCount > 0 {
                Task { await viewModel.deleteSelected() }
                return .handled
            }
        }

        return .ignored
    }
}

// MARK: - Color Extensions

extension Color {
    static let bgDark = Color(red: 0.118, green: 0.118, blue: 0.118)       // #1E1E1E
    static let bgMedium = Color(red: 0.176, green: 0.176, blue: 0.176)     // #2D2D2D
    static let bgLight = Color(red: 0.235, green: 0.235, blue: 0.235)      // #3C3C3C
    static let bgHover = Color(red: 0.290, green: 0.290, blue: 0.290)      // #4A4A4A
    static let accent = Color(red: 0.161, green: 0.475, blue: 1.0)         // #2979FF
    static let accentLight = Color(red: 0.267, green: 0.541, blue: 1.0)    // #448AFF
    static let textPrimary = Color(red: 0.925, green: 0.925, blue: 0.925)  // #ECECEC
    static let textSecondary = Color(red: 0.6, green: 0.6, blue: 0.6)      // #999999
    static let textDim = Color(red: 0.4, green: 0.4, blue: 0.4)            // #666666
    static let borderColor = Color(red: 0.251, green: 0.251, blue: 0.251)  // #404040
    static let dangerColor = Color(red: 0.898, green: 0.224, blue: 0.208)  // #E53935
    static let successColor = Color(red: 0.298, green: 0.686, blue: 0.314) // #4CAF50
}
