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

/// Filter for the type of media shown in the grid.
enum MediaFilter: String, CaseIterable {
    case all = "All"
    case photos = "Photos"
    case videos = "Videos"
}
