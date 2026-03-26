import SwiftUI

/// iPhoto Viewer - macOS native image viewer and manager.
///
/// Features:
/// - Browse images and videos from local folders
/// - Thumbnail grid with adjustable sizes
/// - Full-screen and split-panel viewer with zoom/pan
/// - Copy, move, and delete operations
/// - Video playback with AVPlayer
/// - Device import (ImageCaptureCore placeholder)
/// - EXIF orientation correction
/// - Keyboard shortcuts
///
/// Architecture:
/// - SwiftUI + MVVM
/// - ImageIO for GPU-accelerated image decoding
/// - AVFoundation for video thumbnails and playback
/// - Persistent thumbnail cache on disk (JPEG 85%, 512px)
/// - LRU in-memory cache for full-resolution images
/// - Progressive rendering (thumbnail -> full-res)
/// - Neighbor prefetching (N +/- 2)
@main
struct iPhotoViewerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1400, height: 900)
        .commands {
            // File menu
            CommandGroup(replacing: .newItem) {
                Button("Open Folder...") {
                    NotificationCenter.default.post(name: .openFolder, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            // Edit menu - selection commands
            CommandGroup(after: .pasteboard) {
                Divider()

                Button("Select All") {
                    NotificationCenter.default.post(name: .selectAll, object: nil)
                }
                .keyboardShortcut("a", modifiers: .command)

                Button("Deselect All") {
                    NotificationCenter.default.post(name: .deselectAll, object: nil)
                }
                .keyboardShortcut("d", modifiers: .command)
            }

            // View menu
            CommandGroup(after: .toolbar) {
                Button("Toggle Split/Toggle Mode") {
                    NotificationCenter.default.post(name: .toggleViewMode, object: nil)
                }
                .keyboardShortcut(.tab, modifiers: [])
            }
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let openFolder = Notification.Name("openFolder")
    static let selectAll = Notification.Name("selectAll")
    static let deselectAll = Notification.Name("deselectAll")
    static let toggleViewMode = Notification.Name("toggleViewMode")
}
