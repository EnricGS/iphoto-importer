import Foundation

/// Display mode for the viewer.
enum ViewMode: String, CaseIterable {
    /// Split mode: grid + viewer side by side (Lightroom style)
    case split
    /// Toggle mode: viewer overlays the grid
    case toggle

    var label: String {
        switch self {
        case .split: return "Split"
        case .toggle: return "Toggle"
        }
    }
}
