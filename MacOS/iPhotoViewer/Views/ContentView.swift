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
            Color.bgBase
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

        // Escape: exit device browse mode (only when viewer is not open)
        if press.key == .escape && viewModel.isDeviceBrowseMode {
            viewModel.exitDeviceBrowseMode()
            return .handled
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
                if viewModel.isDeviceBrowseMode {
                    Task { await viewModel.deleteSelectedFromDevice() }
                } else {
                    Task { await viewModel.deleteSelected() }
                }
                return .handled
            }
        }

        return .ignored
    }
}

// MARK: - Color Extensions (warm dark theme matching Windows)

extension Color {
    // Backgrounds
    static let bgBase = Color(red: 0.078, green: 0.071, blue: 0.086)       // #141216
    static let bgSurface = Color(red: 0.110, green: 0.102, blue: 0.122)    // #1C1A1F
    static let bgElevated = Color(red: 0.145, green: 0.133, blue: 0.161)   // #252229
    static let bgCard = Color(red: 0.165, green: 0.153, blue: 0.188)       // #2A2730
    static let bgHover = Color(red: 0.208, green: 0.184, blue: 0.227)      // #352F3A

    // Accent (warm amber/terracotta)
    static let accent = Color(red: 0.910, green: 0.576, blue: 0.353)       // #E8935A
    static let accentLight = Color(red: 0.941, green: 0.659, blue: 0.439)  // #F0A870
    static let accentDim = Color(red: 0.690, green: 0.408, blue: 0.188)    // #B06830
    static let accentSubtle = Color(red: 0.910, green: 0.576, blue: 0.353).opacity(0.15)

    // Text
    static let textPrimary = Color(red: 0.941, green: 0.929, blue: 0.910)  // #F0EDE8
    static let textSecondary = Color(red: 0.659, green: 0.627, blue: 0.690) // #A8A0B0
    static let textDim = Color(red: 0.439, green: 0.408, blue: 0.471)      // #706878
    static let textOnAccent = Color(red: 0.102, green: 0.063, blue: 0.094) // #1A1018

    // Borders
    static let borderSubtle = Color.white.opacity(0.19)
    static let borderMedium = Color.white.opacity(0.25)

    // Semantics
    static let successColor = Color(red: 0.431, green: 0.796, blue: 0.545) // #6ECB8B
    static let dangerColor = Color(red: 0.910, green: 0.353, blue: 0.435)  // #E85A6F
}
