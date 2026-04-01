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

/// Timeline grouping level for the thumbnail grid.
enum TimelineGrouping: String, CaseIterable {
    case day
    case month
    case year

    var label: String {
        switch self {
        case .day: return "Dia"
        case .month: return "Mes"
        case .year: return "Any"
        }
    }
}
