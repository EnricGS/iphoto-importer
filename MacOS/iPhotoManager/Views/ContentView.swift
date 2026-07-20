import SwiftUI
import Combine

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

            // Import modal (centered overlay)
            if viewModel.isImportPanelOpen {
                ImportPanelView(viewModel: viewModel)
                    .transition(.opacity)
            }

            // Undo toast (flotant a sobre de tot, inclòs el visor overlay)
            if viewModel.canUndoDelete {
                VStack {
                    Spacer()
                    HStack(spacing: 12) {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.8))
                        Text(viewModel.statusMessage)
                            .font(.system(size: 12))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Button {
                            Task { await viewModel.undoLastDelete() }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.uturn.backward")
                                    .font(.system(size: 11))
                                Text("Desfer")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.accent)
                            .foregroundStyle(Color.textOnAccent)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .help("Desfer (Cmd+Z)")

                        Button {
                            viewModel.dismissUndoToast()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                        .help("Tancar")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .shadow(color: .black.opacity(0.4), radius: 8, y: 2)
                    .padding(.bottom, 40)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .allowsHitTesting(true)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.canUndoDelete)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isOverlayViewerVisible)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isImportPanelOpen)
        .animation(.easeInOut(duration: 0.15), value: viewModel.showActionBar)
        .frame(minWidth: 900, minHeight: 600)
        .onKeyPress(phases: .down) { press in
            handleKeyPress(press)
        }
        // Barra de menús: els Buttons de .commands{} (iPhotoManagerApp) publiquen
        // aquestes notificacions. Sense aquests onReceive, clicar els ítems del menú
        // no feia res (les dreceres funcionaven per handleKeyPress, els clics no).
        .onReceive(NotificationCenter.default.publisher(for: .openFolder)) { _ in
            viewModel.openFolder()
        }
        .onReceive(NotificationCenter.default.publisher(for: .selectAll)) { _ in
            viewModel.selectAll()
        }
        .onReceive(NotificationCenter.default.publisher(for: .deselectAll)) { _ in
            viewModel.deselectAll()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleViewMode)) { _ in
            viewModel.toggleViewMode()
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
                    .overlay(alignment: .trailing) {
                        if viewModel.isSplitViewerVisible {
                            Rectangle()
                                .fill(Color.accent.opacity(0.6))
                                .frame(width: 3)
                                .allowsHitTesting(false)
                        }
                    }

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
            case "z":
                Task { await viewModel.undoLastDelete() }
                return .handled
            default:
                break
            }
        }

        if press.key == .delete || press.key == .deleteForward {
            // Amb el visor obert, Delete elimina NOMÉS la foto del visor (com la
            // paperera del visor), sense tocar la selecció.
            if viewModel.isViewerOpen {
                if viewModel.isDeviceBrowseMode {
                    Task { await viewModel.deleteCurrentViewerFromDevice() }
                } else {
                    Task { await viewModel.deleteCurrentViewerPhoto() }
                }
                return .handled
            }
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
