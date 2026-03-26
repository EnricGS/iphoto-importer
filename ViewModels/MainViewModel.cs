using System.Collections.ObjectModel;
using System.ComponentModel;
using System.IO;
using System.Windows;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using iPhotoImporter.Models;
using iPhotoImporter.Services;
using Microsoft.Win32;

namespace iPhotoImporter.ViewModels;

/// <summary>
/// ViewModel principal de l'aplicació. Gestiona el visor d'imatges,
/// la graella de miniatures, i les operacions de gestió de fitxers.
/// </summary>
public partial class MainViewModel : ObservableObject
{
    private readonly FileService _fileService = new();
    private readonly ThumbnailCacheService _thumbnailCache = new();
    private readonly ImageCacheService _imageCache = new(20);
    private CancellationTokenSource? _thumbnailCts;
    private CancellationTokenSource? _prefetchCts;

    // === Propietats d'estat general ===

    [ObservableProperty]
    private string _statusMessage = "Obre una carpeta per començar a visualitzar imatges.";

    [ObservableProperty]
    private bool _hasError;

    [ObservableProperty]
    private bool _isLoading;

    [ObservableProperty]
    private bool _isCopying;

    [ObservableProperty]
    private double _copyProgress;

    [ObservableProperty]
    private string? _currentFolderPath;

    // === Propietats de la graella ===

    /// <summary>Col·lecció central de fotos carregades</summary>
    public ObservableCollection<PhotoItem> Photos { get; } = [];

    /// <summary>Conjunt de fotos seleccionades</summary>
    public ObservableCollection<PhotoItem> SelectedPhotos { get; } = [];

    [ObservableProperty]
    private int _selectedPhotosCount;

    [ObservableProperty]
    private double _totalSelectedSizeMB;

    /// <summary>Mida de les miniatures (controlada per l'slider)</summary>
    [ObservableProperty]
    private double _thumbnailSize = 150;

    // === Propietats del visor ===

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(HasViewerImage))]
    [NotifyPropertyChangedFor(nameof(IsOverlayViewerVisible))]
    private bool _isViewerOpen;

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsSplitViewerVisible))]
    private PhotoItem? _viewerCurrentItem;

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(HasViewerImage))]
    private System.Windows.Media.Imaging.BitmapSource? _viewerImage;

    [ObservableProperty]
    private int _viewerIndex;

    [ObservableProperty]
    private double _viewerZoom = 1.0;

    [ObservableProperty]
    private double _viewerOffsetX;

    [ObservableProperty]
    private double _viewerOffsetY;

    [ObservableProperty]
    private string _viewerInfoText = "";

    /// <summary>Indica si hi ha una imatge al visor</summary>
    public bool HasViewerImage => IsViewerOpen && ViewerImage != null;

    // === Propietats del panell d'importació ===

    [ObservableProperty]
    private bool _isImportPanelOpen;

    [ObservableProperty]
    private string _importStatusMessage = "";

    [ObservableProperty]
    private double _importProgress;

    [ObservableProperty]
    private bool _isImporting;

    // === Carpeta de destí ===

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(HasDestinationFolder))]
    private string? _destinationFolder;

    /// <summary>Indica si s'ha definit una carpeta de destí.</summary>
    public bool HasDestinationFolder => !string.IsNullOrEmpty(DestinationFolder);

    // === Mode de visualització ===

    [ObservableProperty]
    private bool _showActionBar;

    /// <summary>Mode dividit (split): graella + visor al costat. Si és false, mode alternat (toggle/overlay).</summary>
    [ObservableProperty]
    private bool _isSplitMode;

    /// <summary>Text descriptiu del mode actual per mostrar a la UI.</summary>
    public string ViewModeLabel => IsSplitMode ? "Split" : "Toggle";

    /// <summary>Indica si el visor lateral (split) ha de ser visible.</summary>
    public bool IsSplitViewerVisible => IsSplitMode && ViewerCurrentItem != null;

    /// <summary>Indica si el visor overlay (toggle) ha de ser visible.</summary>
    public bool IsOverlayViewerVisible => !IsSplitMode && IsViewerOpen;

    /// <summary>Event per notificar al code-behind que cal fer scroll a la miniatura activa.</summary>
    public event Action<int>? ScrollToThumbnailRequested;

    // === Constructor ===

    public MainViewModel()
    {
        SelectedPhotos.CollectionChanged += (_, _) => UpdateSelectionStats();
    }

    /// <summary>
    /// Quan canvia el mode split, actualitzem les propietats derivades de visibilitat.
    /// </summary>
    partial void OnIsSplitModeChanged(bool value)
    {
        OnPropertyChanged(nameof(ViewModeLabel));
        OnPropertyChanged(nameof(IsSplitViewerVisible));
        OnPropertyChanged(nameof(IsOverlayViewerVisible));

        if (value)
        {
            // Canviar a mode split: si el visor overlay estava obert, mantenir la imatge
            // però tancar l'overlay i mostrar-la al panell lateral
            if (IsViewerOpen)
            {
                IsViewerOpen = false;
                // ViewerCurrentItem i ViewerImage ja estan carregats
                OnPropertyChanged(nameof(IsSplitViewerVisible));
                OnPropertyChanged(nameof(IsOverlayViewerVisible));
            }
        }
        else
        {
            // Canviar a mode toggle: si hi ha imatge al visor split, obrir l'overlay
            if (ViewerCurrentItem != null)
            {
                IsViewerOpen = true;
                OnPropertyChanged(nameof(IsOverlayViewerVisible));
            }
            OnPropertyChanged(nameof(IsSplitViewerVisible));
        }
    }

    /// <summary>
    /// Comanda per alternar entre mode split i toggle (Tab o F5).
    /// </summary>
    [RelayCommand]
    private void ToggleViewMode()
    {
        IsSplitMode = !IsSplitMode;
    }

    // === Comandes de carpeta ===

    [RelayCommand]
    private async Task OpenFolderAsync()
    {
        var dialog = new OpenFolderDialog
        {
            Title = "Selecciona una carpeta d'imatges"
        };

        if (dialog.ShowDialog() != true) return;

        await LoadFolderAsync(dialog.FolderName);
    }

    /// <summary>
    /// Carrega les imatges d'una carpeta al visor.
    /// </summary>
    public async Task LoadFolderAsync(string folderPath)
    {
        // Cancel·lar operacions anteriors
        _thumbnailCts?.Cancel();
        _prefetchCts?.Cancel();

        IsLoading = true;
        HasError = false;
        StatusMessage = "Escanejant carpeta...";
        CurrentFolderPath = folderPath;

        // Tancar el visor si estava obert
        CloseViewer();

        Photos.Clear();
        SelectedPhotos.Clear();

        try
        {
            var progress = new Progress<(int scanned, int found, string currentFile)>(info =>
            {
                StatusMessage = $"Escanejant... {info.found} imatges trobades — {info.currentFile}";
            });

            var items = await _fileService.ScanFolderAsync(folderPath, progress);

            // Ordenar per data (més recents primer)
            items.Sort((a, b) => (b.DateTaken ?? DateTime.MinValue).CompareTo(a.DateTaken ?? DateTime.MinValue));

            foreach (var item in items)
            {
                item.PropertyChanged += OnPhotoPropertyChanged;
                Photos.Add(item);
            }

            StatusMessage = $"{Photos.Count} imatge(s) trobada(es) a {Path.GetFileName(folderPath)}";

            // Carregar miniatures en segon pla
            _ = LoadThumbnailsAsync();
        }
        catch (Exception ex)
        {
            HasError = true;
            StatusMessage = $"Error escanejant carpeta: {ex.Message}";
        }
        finally
        {
            IsLoading = false;
        }
    }

    // === Carregar miniatures ===

    private async Task LoadThumbnailsAsync()
    {
        _thumbnailCts?.Cancel();
        _thumbnailCts = new CancellationTokenSource();
        var ct = _thumbnailCts.Token;

        var photosCopy = Photos.ToList();
        var batchSize = 4; // Paral·lelisme controlat

        try
        {
            // Processar en lots per no saturar el sistema
            for (var i = 0; i < photosCopy.Count; i += batchSize)
            {
                ct.ThrowIfCancellationRequested();

                var batch = photosCopy.Skip(i).Take(batchSize);
                var tasks = batch.Select(async photo =>
                {
                    if (photo.Thumbnail != null) return;
                    var thumb = await _thumbnailCache.GetThumbnailAsync(photo.FullPath, ct);
                    if (thumb != null)
                    {
                        Application.Current?.Dispatcher.Invoke(() =>
                        {
                            photo.Thumbnail = thumb;
                        });
                    }
                });

                await Task.WhenAll(tasks);
            }
        }
        catch (OperationCanceledException)
        {
            // Cancel·lat, no fer res
        }
    }

    // === Visor d'imatges ===

    [RelayCommand]
    private void OpenViewer(PhotoItem? item)
    {
        if (item == null || Photos.Count == 0) return;

        var index = Photos.IndexOf(item);
        if (index < 0) return;

        ViewerIndex = index;

        if (IsSplitMode)
        {
            // En mode split, no obrim overlay; carreguem la imatge al panell lateral
            LoadViewerImage(item);
            OnPropertyChanged(nameof(IsSplitViewerVisible));
        }
        else
        {
            // Mode toggle: obrir visor com a overlay
            IsViewerOpen = true;
            LoadViewerImage(item);
        }
    }

    [RelayCommand]
    private void CloseViewer()
    {
        _prefetchCts?.Cancel();
        IsViewerOpen = false;
        ViewerImage = null;
        ViewerCurrentItem = null;
        ViewerZoom = 1.0;
        ViewerOffsetX = 0;
        ViewerOffsetY = 0;
        ViewerInfoText = "";

        // Treure el ressaltat de tots els elements
        foreach (var p in Photos)
            p.IsHighlighted = false;

        OnPropertyChanged(nameof(IsSplitViewerVisible));
        OnPropertyChanged(nameof(IsOverlayViewerVisible));
    }

    [RelayCommand]
    private void ViewerNext()
    {
        if (Photos.Count == 0) return;
        var newIndex = (ViewerIndex + 1) % Photos.Count;
        NavigateViewer(newIndex);
    }

    [RelayCommand]
    private void ViewerPrevious()
    {
        if (Photos.Count == 0) return;
        var newIndex = (ViewerIndex - 1 + Photos.Count) % Photos.Count;
        NavigateViewer(newIndex);
    }

    private void NavigateViewer(int index)
    {
        if (index < 0 || index >= Photos.Count) return;

        // Treure ressaltat anterior
        if (ViewerCurrentItem != null)
            ViewerCurrentItem.IsHighlighted = false;

        ViewerIndex = index;
        ViewerZoom = 1.0;
        ViewerOffsetX = 0;
        ViewerOffsetY = 0;

        LoadViewerImage(Photos[index]);

        // En mode split, notificar que cal fer scroll a la miniatura
        if (IsSplitMode)
            ScrollToThumbnailRequested?.Invoke(index);
    }

    private void LoadViewerImage(PhotoItem item)
    {
        ViewerCurrentItem = item;
        item.IsHighlighted = true;

        // 1. Mostrar miniatura immediatament (render progressiu)
        if (item.Thumbnail != null)
            ViewerImage = item.Thumbnail;

        // 2. Intentar la cache LRU
        var cached = _imageCache.Get(item.FullPath);
        if (cached != null)
        {
            ViewerImage = cached;
            UpdateViewerInfo(item);
            _ = PrefetchNeighbors();
            return;
        }

        // 3. Carregar a resolució completa en segon pla
        _ = LoadFullImageAsync(item);
    }

    private async Task LoadFullImageAsync(PhotoItem item)
    {
        try
        {
            var image = await Task.Run(() => FileService.LoadFullImage(item.FullPath));
            if (image != null && ViewerCurrentItem == item)
            {
                _imageCache.Put(item.FullPath, image);
                Application.Current?.Dispatcher.Invoke(() =>
                {
                    ViewerImage = image;
                    // Actualitzar dimensions de la foto si no les tenia
                    if (item.PixelWidth == 0)
                    {
                        item.PixelWidth = image.PixelWidth;
                        item.PixelHeight = image.PixelHeight;
                    }
                    UpdateViewerInfo(item);
                });
            }

            // Prefetch dels veïns
            await PrefetchNeighbors();
        }
        catch
        {
            // Error carregant imatge, mantenir la miniatura
        }
    }

    /// <summary>
    /// Precarrega les imatges veïnes (N±2) per navegació ràpida.
    /// </summary>
    private async Task PrefetchNeighbors()
    {
        _prefetchCts?.Cancel();
        _prefetchCts = new CancellationTokenSource();
        var ct = _prefetchCts.Token;

        var currentIndex = ViewerIndex;
        var offsets = new[] { 1, -1, 2, -2 };

        foreach (var offset in offsets)
        {
            if (ct.IsCancellationRequested) break;

            var idx = (currentIndex + offset + Photos.Count) % Photos.Count;
            if (idx == currentIndex) continue;

            var photo = Photos[idx];
            if (_imageCache.Contains(photo.FullPath)) continue;

            try
            {
                var image = await Task.Run(() => FileService.LoadFullImage(photo.FullPath), ct);
                if (image != null)
                    _imageCache.Put(photo.FullPath, image);
            }
            catch (OperationCanceledException)
            {
                break;
            }
            catch
            {
                // Error de prefetch, no crític
            }
        }
    }

    private void UpdateViewerInfo(PhotoItem item)
    {
        var parts = new List<string>
        {
            $"{ViewerIndex + 1} / {Photos.Count}",
            item.FileName
        };

        if (item.PixelWidth > 0)
            parts.Add($"{item.PixelWidth} x {item.PixelHeight}");

        if (item.DateTaken.HasValue)
            parts.Add(item.DateTaken.Value.ToString("dd/MM/yyyy HH:mm"));

        if (item.SizeBytes > 0)
        {
            var sizeMB = item.SizeBytes / (1024.0 * 1024.0);
            parts.Add($"{sizeMB:N1} MB");
        }

        ViewerInfoText = string.Join("  |  ", parts);
    }

    // === Zoom i pan ===

    [RelayCommand]
    private void ViewerZoomIn()
    {
        ViewerZoom = Math.Min(ViewerZoom * 1.25, 10.0);
    }

    [RelayCommand]
    private void ViewerZoomOut()
    {
        ViewerZoom = Math.Max(ViewerZoom / 1.25, 0.1);
    }

    [RelayCommand]
    private void ViewerZoomReset()
    {
        ViewerZoom = 1.0;
        ViewerOffsetX = 0;
        ViewerOffsetY = 0;
    }

    [RelayCommand]
    private void ViewerFitToScreen()
    {
        ViewerZoom = 1.0;
        ViewerOffsetX = 0;
        ViewerOffsetY = 0;
    }

    // === Selecció ===

    [RelayCommand]
    private void ToggleSelection(PhotoItem? item)
    {
        if (item == null) return;
        item.IsSelected = !item.IsSelected;
    }

    [RelayCommand]
    private void SelectAll()
    {
        foreach (var p in Photos)
            p.IsSelected = true;
    }

    [RelayCommand]
    private void DeselectAll()
    {
        foreach (var p in Photos)
            p.IsSelected = false;
    }

    private void OnPhotoPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName != nameof(PhotoItem.IsSelected)) return;
        if (sender is not PhotoItem photo) return;

        if (photo.IsSelected)
        {
            if (!SelectedPhotos.Contains(photo))
                SelectedPhotos.Add(photo);
        }
        else
        {
            SelectedPhotos.Remove(photo);
        }
    }

    private void UpdateSelectionStats()
    {
        SelectedPhotosCount = SelectedPhotos.Count;
        TotalSelectedSizeMB = Math.Round(SelectedPhotos.Sum(p => p.SizeBytes) / (1024.0 * 1024.0), 2);
        ShowActionBar = SelectedPhotosCount > 0;
    }

    // === Accions de gestió (Phase 4) ===

    [RelayCommand]
    private void SetDestinationFolder()
    {
        var dialog = new OpenFolderDialog
        {
            Title = "Selecciona la carpeta de destí per defecte"
        };
        if (dialog.ShowDialog() == true)
        {
            DestinationFolder = dialog.FolderName;
            StatusMessage = $"Carpeta de destí: {DestinationFolder}";
        }
    }

    [RelayCommand]
    private void ClearDestinationFolder()
    {
        DestinationFolder = null;
        StatusMessage = "Carpeta de destí eliminada.";
    }

    /// <summary>
    /// Resol la carpeta de destí: si ja n'hi ha una definida, la retorna directament.
    /// Si no, obre el selector de carpetes. Retorna null si l'usuari cancel·la.
    /// </summary>
    private string? ResolveDestinationFolder()
    {
        if (!string.IsNullOrEmpty(DestinationFolder))
            return DestinationFolder;

        var dialog = new OpenFolderDialog
        {
            Title = "Selecciona la carpeta de destí per copiar"
        };
        return dialog.ShowDialog() == true ? dialog.FolderName : null;
    }

    [RelayCommand]
    private async Task CopySelectedAsync()
    {
        if (SelectedPhotos.Count == 0) return;

        var dest = ResolveDestinationFolder();
        if (dest == null) return;

        await CopyFilesAsync(SelectedPhotos.ToList(), dest);
    }

    [RelayCommand]
    private async Task CopyCurrentPhotoAsync()
    {
        if (ViewerCurrentItem == null) return;

        var dest = ResolveDestinationFolder();
        if (dest == null) return;

        await CopyFilesAsync([ViewerCurrentItem], dest);
    }

    private async Task CopyFilesAsync(List<PhotoItem> files, string destination)
    {
        IsLoading = true;
        IsCopying = true;
        HasError = false;
        CopyProgress = 0;

        var progress = new Progress<(int current, int total, string fileName)>(report =>
        {
            CopyProgress = (double)report.current / report.total * 100;
            StatusMessage = $"Copiant {report.current}/{report.total}: {report.fileName}";
        });

        try
        {
            var copied = await _fileService.CopyFilesAsync(files, destination, progress);
            CopyProgress = 100;
            StatusMessage = $"{copied} fitxer(s) copiat(s) a {destination}";
        }
        catch (Exception ex)
        {
            HasError = true;
            StatusMessage = $"Error copiant: {ex.Message}";
        }
        finally
        {
            IsCopying = false;
            IsLoading = false;
        }
    }

    [RelayCommand]
    private async Task MoveSelectedAsync()
    {
        if (SelectedPhotos.Count == 0) return;

        var dialog = new OpenFolderDialog
        {
            Title = "Selecciona la carpeta de destí per moure"
        };

        if (dialog.ShowDialog() != true) return;

        var result = MessageBox.Show(
            $"Vols moure {SelectedPhotos.Count} fitxer(s) a:\n{dialog.FolderName}\n\nAquesta acció no es pot desfer.",
            "Confirmar moviment",
            MessageBoxButton.YesNo,
            MessageBoxImage.Warning);

        if (result != MessageBoxResult.Yes) return;

        IsLoading = true;
        IsCopying = true;
        HasError = false;
        CopyProgress = 0;

        var filesToMove = SelectedPhotos.ToList();

        var progress = new Progress<(int current, int total, string fileName)>(report =>
        {
            CopyProgress = (double)report.current / report.total * 100;
            StatusMessage = $"Movent {report.current}/{report.total}: {report.fileName}";
        });

        try
        {
            var moved = await _fileService.MoveFilesAsync(filesToMove, dialog.FolderName, progress);
            CopyProgress = 100;

            // Eliminar els elements moguts de la llista
            foreach (var item in filesToMove)
            {
                Photos.Remove(item);
                SelectedPhotos.Remove(item);
            }

            StatusMessage = $"{moved} fitxer(s) mogut(s) correctament a {dialog.FolderName}";
        }
        catch (Exception ex)
        {
            HasError = true;
            StatusMessage = $"Error movent: {ex.Message}";
        }
        finally
        {
            IsCopying = false;
            IsLoading = false;
        }
    }

    [RelayCommand]
    private async Task DeleteSelectedAsync()
    {
        if (SelectedPhotos.Count == 0) return;

        var result = MessageBox.Show(
            $"Vols eliminar {SelectedPhotos.Count} fitxer(s)?\n\nAquesta acció no es pot desfer!",
            "Confirmar eliminació",
            MessageBoxButton.YesNo,
            MessageBoxImage.Warning);

        if (result != MessageBoxResult.Yes) return;

        IsLoading = true;
        HasError = false;

        var filesToDelete = SelectedPhotos.ToList();

        var progress = new Progress<(int current, int total, string fileName)>(report =>
        {
            StatusMessage = $"Eliminant {report.current}/{report.total}: {report.fileName}";
        });

        try
        {
            var deleted = await _fileService.DeleteFilesAsync(filesToDelete, progress);

            // Eliminar els elements de la llista
            foreach (var item in filesToDelete)
            {
                Photos.Remove(item);
                SelectedPhotos.Remove(item);
            }

            StatusMessage = $"{deleted} fitxer(s) eliminat(s) correctament.";
        }
        catch (Exception ex)
        {
            HasError = true;
            StatusMessage = $"Error eliminant: {ex.Message}";
        }
        finally
        {
            IsLoading = false;
        }
    }

    // === Panell d'importació MTP (Phase 5) ===

    private DeviceService? _deviceService;
    private readonly ObservableCollection<MediaDevices.MediaDevice> _devices = [];

    public ObservableCollection<MediaDevices.MediaDevice> Devices => _devices;

    [ObservableProperty]
    private MediaDevices.MediaDevice? _selectedDevice;

    [RelayCommand]
    private void ToggleImportPanel()
    {
        IsImportPanelOpen = !IsImportPanelOpen;
        if (IsImportPanelOpen)
        {
            _deviceService ??= new DeviceService();
            ImportStatusMessage = "Panell d'importació obert. Prem 'Detectar' per buscar dispositius.";
        }
    }

    [RelayCommand]
    private async Task DetectDevicesAsync()
    {
        if (_deviceService == null)
            _deviceService = new DeviceService();

        IsLoading = true;
        ImportStatusMessage = "Cercant dispositius...";

        try
        {
            var devices = await _deviceService.GetConnectedDevicesAsync();
            Devices.Clear();
            foreach (var d in devices)
                Devices.Add(d);

            SelectedDevice = Devices.FirstOrDefault();
            ImportStatusMessage = $"{Devices.Count} dispositiu(s) detectat(s).";
        }
        catch (InvalidOperationException)
        {
            Devices.Clear();
            SelectedDevice = null;
            ImportStatusMessage = "Cap dispositiu detectat. Connecta un iPhone o dispositiu MTP via USB.";
        }
        catch (Exception ex)
        {
            ImportStatusMessage = $"Error: {ex.Message}";
        }
        finally
        {
            IsLoading = false;
        }
    }

    [RelayCommand]
    private async Task ImportFromDeviceAsync()
    {
        if (SelectedDevice == null || _deviceService == null) return;

        var dialog = new OpenFolderDialog
        {
            Title = "Selecciona la carpeta de destí per la importació"
        };

        if (dialog.ShowDialog() != true) return;

        IsImporting = true;
        ImportProgress = 0;
        ImportStatusMessage = "Escanejant dispositiu...";

        try
        {
            // Escanejar fotos del dispositiu
            var mtpPhotos = new List<PhotoItem>();
            var scanProgress = new Progress<(string folder, int scanned, int found)>(info =>
            {
                ImportStatusMessage = $"Escanejant... {info.found} fotos — {info.folder}";
            });

            await _deviceService.GetPhotosAsync(SelectedDevice, photo =>
            {
                photo.IsSelected = true;
                Application.Current.Dispatcher.Invoke(() => mtpPhotos.Add(photo));
            }, scanProgress);

            if (mtpPhotos.Count == 0)
            {
                ImportStatusMessage = "No s'han trobat fotos al dispositiu.";
                return;
            }

            ImportStatusMessage = $"Copiant {mtpPhotos.Count} foto(s)...";

            // Copiar amb generació de miniatures
            var copyProgress = new Progress<(int current, int total, string fileName)>(report =>
            {
                ImportProgress = (double)report.current / report.total * 100;
                ImportStatusMessage = $"Copiant {report.current}/{report.total}: {report.fileName}";
            });

            var copied = await _deviceService.CopyPhotosAsync(
                SelectedDevice, mtpPhotos, dialog.FolderName, copyProgress);

            ImportProgress = 100;
            ImportStatusMessage = $"{copied} foto(s) importada(es) correctament.";

            // Preguntar si vol obrir la carpeta al visor
            var result = MessageBox.Show(
                $"S'han importat {copied} foto(s) a:\n{dialog.FolderName}\n\nVols obrir la carpeta al visor?",
                "Importació completada",
                MessageBoxButton.YesNo,
                MessageBoxImage.Information);

            if (result == MessageBoxResult.Yes)
            {
                IsImportPanelOpen = false;
                await LoadFolderAsync(dialog.FolderName);
            }
        }
        catch (Exception ex)
        {
            ImportStatusMessage = $"Error d'importació: {ex.Message}";
        }
        finally
        {
            IsImporting = false;
        }
    }

    // === Utilitats ===

    /// <summary>
    /// Gestiona clics a la graella amb modificadors (Shift/Ctrl per selecció múltiple).
    /// </summary>
    public void HandleGridClick(PhotoItem item, bool isCtrlPressed, bool isShiftPressed)
    {
        if (isCtrlPressed)
        {
            // Ctrl+click: alternar selecció individual
            item.IsSelected = !item.IsSelected;
        }
        else if (isShiftPressed && Photos.Count > 0)
        {
            // Shift+click: seleccionar rang
            var lastSelectedIndex = -1;
            for (var i = Photos.Count - 1; i >= 0; i--)
            {
                if (Photos[i].IsHighlighted || Photos[i].IsSelected)
                {
                    lastSelectedIndex = i;
                    break;
                }
            }

            var clickedIndex = Photos.IndexOf(item);
            if (lastSelectedIndex >= 0 && clickedIndex >= 0)
            {
                var start = Math.Min(lastSelectedIndex, clickedIndex);
                var end = Math.Max(lastSelectedIndex, clickedIndex);
                for (var i = start; i <= end; i++)
                    Photos[i].IsSelected = true;
            }
            else
            {
                item.IsSelected = true;
            }
        }
        else
        {
            // Clic simple sense modificador: obrir al visor (tant en split com en toggle)
            OpenViewer(item);
        }
    }
}
