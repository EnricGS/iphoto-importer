# iPhoto Viewer - macOS

Native macOS version of the iPhoto Viewer application for browsing, managing, and importing photos and videos.

## Progress Log

- 2026-03-26 - Phase 1: Project structure, models, services (FileService, ThumbnailCacheService, ImageCacheService, DeviceImportService)
- 2026-03-26 - Phase 2: MainViewModel with full MVVM architecture, all business logic
- 2026-03-26 - Phase 3: SwiftUI views (ContentView, ToolbarView, ThumbnailGridView, ViewerOverlayView, ViewerPanelView, VideoPlayerView, ActionBarView, StatusBarView, ImportPanelView)
- 2026-03-26 - Phase 4: App entry point, keyboard shortcuts, menu commands, README

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
    ViewMode.swift               -- ViewMode (split/toggle) and MediaFilter enums
  ViewModels/
    MainViewModel.swift          -- Main ViewModel: grid, viewer, selection, file ops
  Services/
    FileService.swift            -- Folder scanning, thumbnail gen, full image loading, file ops
    ThumbnailCacheService.swift  -- Persistent disk + memory thumbnail cache (JPEG 85%, 512px)
    ImageCacheService.swift      -- LRU in-memory cache for full-res images (~20 entries)
    DeviceImportService.swift    -- Device import placeholder (ImageCaptureCore on macOS)
  Views/
    ContentView.swift            -- Root view, layout orchestration, keyboard handler
    ToolbarView.swift            -- Top toolbar (folder, filter, view mode, import)
    ThumbnailGridView.swift      -- LazyVGrid thumbnail grid with size slider
    ViewerOverlayView.swift      -- Full-screen overlay viewer (toggle mode)
    ViewerPanelView.swift        -- Side panel viewer (split mode)
    VideoPlayerView.swift        -- AVPlayer wrapper for video playback
    ActionBarView.swift          -- Bottom action bar (copy, move, delete)
    StatusBarView.swift          -- Bottom status bar with progress
    ImportPanelView.swift        -- Right-side import panel
  Resources/
    placeholder.txt              -- Placeholder for app resources
```

### Performance Architecture

| Feature | Implementation |
|---------|---------------|
| Image decoding | ImageIO (CGImageSource) with EXIF transform |
| Video thumbnails | AVAssetImageGenerator with orientation |
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

1. **Folder browsing** - Open folder and scan recursively for images/videos
2. **Thumbnail grid** - Adaptive grid with size slider (S to XL, 80-400px)
3. **Multi-selection** - Cmd+click (individual), Shift+click (range)
4. **Full-screen viewer** - Overlay viewer with zoom/pan (toggle mode)
5. **Split mode** - Grid + viewer side by side (Lightroom style)
6. **Toggle mode** - Viewer overlays the grid
7. **Copy/Move/Delete** - File management with confirmation dialogs
8. **Quick copy** - Pre-set destination folder, no dialog needed
9. **EXIF orientation** - Automatic correction for photos and video thumbnails
10. **Video playback** - AVPlayer-based playback with controls
11. **Video thumbnails** - First frame extracted via AVAssetImageGenerator
12. **Media filter** - Filter by All/Photos/Videos
13. **iPhone import** - Placeholder for ImageCaptureCore (macOS equivalent of MTP)
14. **Keyboard shortcuts** - Full keyboard navigation
15. **Dark theme** - Modern dark design matching the Windows version aesthetic

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| Cmd+O | Open folder |
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
| File dialogs | OpenFolderDialog | NSOpenPanel |
| Async model | Task + Dispatcher.Invoke | async/await + @MainActor |
| Grid layout | WrapPanel + VirtualizingPanel | LazyVGrid |
| Split view | Grid columns + GridSplitter | HSplitView |

## License

Same license as the parent project.
