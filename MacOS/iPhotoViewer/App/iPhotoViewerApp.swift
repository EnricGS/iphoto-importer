import SwiftUI
import AppKit

/// iPhoto Manager - macOS native image viewer and manager.
@main
struct iPhotoViewerApp: App {
    init() {
        // Set app icon from bundled resource
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = icon
        }
    }

    var body: some Scene {
        WindowGroup("iPhoto Manager") {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1400, height: 900)
        .commands {
            // File menu
            CommandGroup(replacing: .newItem) {
                Button("Obrir carpeta...") {
                    NotificationCenter.default.post(name: .openFolder, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            // Edit menu - selection commands
            CommandGroup(after: .pasteboard) {
                Divider()

                Button("Seleccionar tot") {
                    NotificationCenter.default.post(name: .selectAll, object: nil)
                }
                .keyboardShortcut("a", modifiers: .command)

                Button("Desseleccionar tot") {
                    NotificationCenter.default.post(name: .deselectAll, object: nil)
                }
                .keyboardShortcut("d", modifiers: .command)
            }

            // View menu
            CommandGroup(after: .toolbar) {
                Button("Canviar mode split/toggle") {
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
