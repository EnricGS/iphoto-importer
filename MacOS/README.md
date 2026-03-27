# iPhoto Viewer - macOS

Native macOS version of the iPhoto Viewer application for browsing, managing, and importing photos and videos.

## Progress Log

- 2026-03-26 - Phase 1: Project structure, models, services (FileService, ThumbnailCacheService, ImageCacheService, DeviceImportService)
- 2026-03-26 - Phase 2: MainViewModel with full MVVM architecture, all business logic
- 2026-03-26 - Phase 3: SwiftUI views (ContentView, ToolbarView, ThumbnailGridView, ViewerOverlayView, ViewerPanelView, VideoPlayerView, ActionBarView, StatusBarView, ImportPanelView)
- 2026-03-26 - Phase 4: App entry point, keyboard shortcuts, menu commands, README
- 2026-03-27 - Multi-folder support: addFolder, removeFolder, clearAllFolders with folder pill tags in toolbar
- 2026-03-27 - Filter toggle buttons: independent photo/video toggles (both active by default) replacing segmented picker
- 2026-03-27 - Video rotation: tkhd track header parsing for MP4/MOV rotation detection (0/90/180/270 degrees)
- 2026-03-27 - VideoRotation property added to PhotoItem model
- 2026-03-27 - Warm dark theme: updated all colors to match Windows amber/terracotta palette (#E8935A accent)
- 2026-03-27 - Icon-only toolbar: replaced text labels with SF Symbols + tooltips throughout
- 2026-03-27 - Split/Import buttons moved above grid only (not spanning viewer panel)
- 2026-03-27 - Import button icon changed to phone (iphone.and.arrow.forward)
- 2026-03-27 - Copy button added to both overlay and split viewer toolbars
- 2026-03-27 - Filename display added to thumbnail cells (bottom overlay with gradient)
- 2026-03-27 - Quick selection buttons (select all/deselect all) added to grid controls
- 2026-03-27 - Action bar updated with icon-only buttons and accent top border
- 2026-03-27 - Navigation buttons added to split viewer panel
- 2026-03-27 - Status bar updated with new theme colors
- 2026-03-27 - Import panel updated with warm theme and phone icon

## Requirements

- **macOS 14 (Sonoma)** or later
- **Xcode 15.2+** with Swift 5.10
- No external dependencies (pure Apple frameworks)

## Building

### With Xcode

1. Open the `MacOS/` folder in Xcode (File > Open)
2. Xcode will resolve the Swift Package automatically
3. Select the `iPhotoViewer` scheme
4. Build and Run (Cmd+R)

### With Swift CLI

```bash
cd MacOS
swift build
swift run iPhotoViewer
```

## Architecture Overview

### Pattern: MVVM with SwiftUI

```
iPhotoViewer/
  App/
    iPhotoViewerApp.swift        -- App entry point, window config, menu commands
  Models/
    PhotoItem.swift              -- Observable data model for photo/video items
    ViewMode.swift               -- ViewMode (split/toggle) enum
  ViewModels/
    MainViewModel.swift          -- Main ViewModel: multi-folder, grid, viewer, selection, file ops
  Services/
    FileService.swift            -- Folder scanning, thumbnail gen, full image loading, video rotation, file ops
    ThumbnailCacheService.swift  -- Persistent disk + memory thumbnail cache (JPEG 85%, 512px)
    ImageCacheService.swift      -- LRU in-memory cache for full-res images (~20 entries)
    DeviceImportService.swift    -- Device import placeholder (ImageCaptureCore on macOS)
  Views/
    ContentView.swift            -- Root view, layout orchestration, keyboard handler, color palette
    ToolbarView.swift            -- Top toolbar (folder controls, folder pills, destination), button styles
    ThumbnailGridView.swift      -- LazyVGrid grid with split/import bar, filter toggles, size slider
    ViewerOverlayView.swift      -- Full-screen overlay viewer (toggle mode) with zoom/pan
    ViewerPanelView.swift        -- Side panel viewer (split mode) with nav buttons
    VideoPlayerView.swift        -- AVPlayer wrapper for video playback
    ActionBarView.swift          -- Bottom action bar (copy, move, delete) with icon-only buttons
    StatusBarView.swift          -- Bottom status bar with progress
    ImportPanelView.swift        -- Right-side import panel with phone icon
  Resources/
    placeholder.txt              -- Placeholder for app resources
```

### Performance Architecture

| Feature | Implementation |
|---------|---------------|
| Image decoding | ImageIO (CGImageSource) with EXIF transform |
| Video thumbnails | AVAssetImageGenerator with orientation |
| Video rotation | tkhd box parsing from MP4/MOV track header matrix |
| Thumbnail cache (disk) | SHA256-keyed JPEG files in ~/Library/Caches |
| Thumbnail cache (memory) | In-memory dictionary in ThumbnailCacheService |
| Full-res cache (RAM) | LRU cache, 20 images max (ImageCacheService) |
| Grid virtualization | SwiftUI LazyVGrid with adaptive columns |
| Progressive rendering | Thumbnail shown immediately, full-res loaded async |
| Neighbor prefetch | N +/- 2 images preloaded on navigation |
| Background decoding | Swift async/await with Task.detached |
| EXIF orientation | CGImageSource kCGImageSourceCreateThumbnailWithTransform |

### Frameworks Used

| Framework | Purpose |
|-----------|---------|
| SwiftUI | UI layer, declarative views |
| AppKit | NSOpenPanel, NSAlert, NSImage |
| ImageIO | Fast JPEG/HEIC decoding with EXIF |
| AVFoundation | Video thumbnails (AVAssetImageGenerator) |
| AVKit | Video playback (VideoPlayer/AVPlayer) |
| CryptoKit | SHA256 for cache keys |
| UniformTypeIdentifiers | File type identification |

## Feature List

1. **Multi-folder support** - Add multiple folders, remove individual ones, clear all
2. **Thumbnail grid** - Adaptive grid with size slider (S to XL, 80-400px)
3. **Multi-selection** - Cmd+click (individual), Shift+click (range)
4. **Full-screen viewer** - Overlay viewer with zoom/pan (toggle mode)
5. **Split mode** - Grid + viewer side by side with resizable divider (HSplitView)
6. **Toggle mode** - Viewer overlays the grid
7. **Copy/Move/Delete** - File management with confirmation dialogs
8. **Quick copy** - Pre-set destination folder, no dialog needed (C key in viewer)
9. **EXIF orientation** - Automatic correction for photos via ImageIO
10. **Video playback** - AVPlayer-based playback with controls
11. **Video thumbnails** - First frame extracted via AVAssetImageGenerator
12. **Video rotation** - Track header metadata detection (tkhd box parsing)
13. **Filter toggles** - Independent photo/video toggle buttons (both active by default)
14. **iPhone import** - Placeholder for ImageCaptureCore (macOS equivalent of MTP)
15. **Keyboard shortcuts** - Full keyboard navigation matching Windows version
16. **Modern dark theme** - Warm amber/terracotta design matching Windows redesign
17. **Icon-only toolbar** - SF Symbols with tooltips throughout
18. **Filename display** - File names shown on thumbnails with gradient overlay

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| Cmd+O | Open/add folder |
| Cmd+A | Select all |
| Cmd+D | Deselect all |
| Delete | Delete selected (move to Trash) |
| Left/Right | Navigate viewer |
| +/- | Zoom in/out |
| 0 | Reset zoom |
| F | Fit to screen |
| Tab | Toggle Split/Toggle mode |
| C | Quick copy current photo |
| Esc | Close viewer |
| Space | Play/pause video |
| Double-click | Close overlay viewer |
| Scroll wheel | Zoom in viewer |
| Drag | Pan when zoomed |

## Differences from Windows Version

| Feature | Windows (WPF/.NET 8) | macOS (SwiftUI) |
|---------|----------------------|-----------------|
| UI Framework | WPF with XAML | SwiftUI |
| MVVM | CommunityToolkit.Mvvm | @Observable macro |
| Image decoding | BitmapImage/BitmapDecoder | ImageIO (CGImageSource) |
| Video player | MediaElement | AVPlayer/VideoPlayer |
| Device import | MediaDevices (MTP/WPD) | ImageCaptureCore (placeholder) |
| Thumbnail cache | JPEG via BitmapEncoder | JPEG via NSBitmapImageRep |
| EXIF reading | Manual JPEG byte parsing | ImageIO built-in transform |
| Video rotation | Manual tkhd box parsing | Manual tkhd box parsing (same algorithm) |
| File dialogs | OpenFolderDialog | NSOpenPanel |
| Async model | Task + Dispatcher.Invoke | async/await + @MainActor |
| Grid layout | WrapPanel + VirtualizingPanel | LazyVGrid |
| Split view | Grid columns + GridSplitter | HSplitView |
| Modifier keys | Ctrl+click, Shift+click | Cmd+click, Shift+click |

## License

Same license as the parent project.
