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
    private readonly GeocodingService _geocodingService = new();
    private CancellationTokenSource? _thumbnailCts;
    private CancellationTokenSource? _prefetchCts;
    private CancellationTokenSource? _locationCts;

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

    /// <summary>Llista de carpetes obertes</summary>
    public ObservableCollection<string> OpenFolders { get; } = [];

    /// <summary>Carpetes que s'escanegen recursivament</summary>
    private readonly HashSet<string> _recursiveFolders = new(StringComparer.OrdinalIgnoreCase);

    /// <summary>Nombre de carpetes obertes (per binding)</summary>
    [ObservableProperty]
    private int _openFolderCount;

    // === Propietats de la graella ===

    /// <summary>Col·lecció central de totes les fotos carregades (sense filtrar)</summary>
    private readonly List<PhotoItem> _allPhotos = [];

    /// <summary>Col·lecció filtrada de fotos mostrades a la graella</summary>
    public ObservableCollection<PhotoItem> Photos { get; } = [];

    /// <summary>Conjunt de fotos seleccionades</summary>
    public ObservableCollection<PhotoItem> SelectedPhotos { get; } = [];

    /// <summary>Filtre: mostrar fotos</summary>
    [ObservableProperty]
    private bool _filterPhotos = true;

    /// <summary>Filtre: mostrar vídeos</summary>
    [ObservableProperty]
    private bool _filterVideos = true;

    /// <summary>Filtre de tipus (compat interna): 0=Tot, 1=Fotos, 2=Vídeos</summary>
    public int FilterType
    {
        get
        {
            if (FilterPhotos && FilterVideos) return 0;
            if (FilterPhotos) return 1;
            if (FilterVideos) return 2;
            return 0; // Si no hi ha cap, mostrar tot
        }
        set
        {
            // Mantenir compat amb code-behind existent
            switch (value)
            {
                case 0: FilterPhotos = true; FilterVideos = true; break;
                case 1: FilterPhotos = true; FilterVideos = false; break;
                case 2: FilterPhotos = false; FilterVideos = true; break;
            }
        }
    }

    /// <summary>Ordre ascendent (true = més antic primer, false = més nou primer)</summary>
    [ObservableProperty]
    private bool _sortAscending;

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

    [ObservableProperty]
    private bool _isViewingVideo;

    [ObservableProperty]
    private string? _viewerVideoPath;

    [ObservableProperty]
    private int _viewerVideoRotation;

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

    /// <summary>Comptadors per tipus (per mostrar a la UI)</summary>
    [ObservableProperty]
    private int _photoCount;

    [ObservableProperty]
    private int _videoCount;

    // === Timeline ===

    /// <summary>Mode timeline actiu</summary>
    [ObservableProperty]
    private bool _isTimelineMode;

    /// <summary>Agrupació actual del timeline</summary>
    [ObservableProperty]
    private TimelineGrouping _timelineGrouping = TimelineGrouping.Month;

    /// <summary>Grups de fotos per timeline</summary>
    public ObservableCollection<TimelineGroup> GroupedPhotos { get; } = [];

    /// <summary>Grups col·lapsats</summary>
    private readonly HashSet<string> _collapsedGroups = [];

    // === Disk Scanner ===

    /// <summary>Indica si s'està escanejant el disc</summary>
    [ObservableProperty]
    private bool _isScanningDisk;

    /// <summary>Progrés de l'escaneig de disc</summary>
    [ObservableProperty]
    private string _diskScanStatus = "";

    /// <summary>Mostra el panell de resultats</summary>
    [ObservableProperty]
    private bool _showDiskScanPanel;

    /// <summary>Resultats de l'escaneig de disc (carpeta, count)</summary>
    public ObservableCollection<DiskScanResult> DiskScanResults { get; } = [];

    private CancellationTokenSource? _diskScanCts;

    private static readonly string[] CatalanMonths =
        ["Gener", "Febrer", "Març", "Abril", "Maig", "Juny",
         "Juliol", "Agost", "Setembre", "Octubre", "Novembre", "Desembre"];

    // === Constructor ===

    public MainViewModel()
    {
        SelectedPhotos.CollectionChanged += (_, _) => UpdateSelectionStats();
    }

    /// <summary>
    /// Quan canvia el filtre, actualitzem la col·lecció visible.
    /// </summary>
    partial void OnFilterExactDuplicatesChanged(bool value)
    {
        ApplyFilter();
        _ = LoadThumbnailsAsync();
    }

    partial void OnFilterSimilarDuplicatesChanged(bool value)
    {
        ApplyFilter();
        _ = LoadThumbnailsAsync();
    }

    partial void OnFilterPhotosChanged(bool value)
    {
        // Si cap filtre actiu, activar l'altre
        if (!value && !FilterVideos)
        {
            FilterVideos = true;
            return; // OnFilterVideosChanged ja farà ApplyFilter
        }
        OnPropertyChanged(nameof(FilterType));
        ApplyFilter();
    }

    partial void OnFilterVideosChanged(bool value)
    {
        // Si cap filtre actiu, activar l'altre
        if (!value && !FilterPhotos)
        {
            FilterPhotos = true;
            return; // OnFilterPhotosChanged ja farà ApplyFilter
        }
        OnPropertyChanged(nameof(FilterType));
        ApplyFilter();
    }

    /// <summary>
    /// Aplica el filtre de tipus a la col·lecció Photos.
    /// </summary>
    private void ApplyFilter()
    {
        Photos.Clear();
        SelectedPhotos.Clear();

        var filtered = (FilterPhotos, FilterVideos) switch
        {
            (true, true) => _allPhotos.AsEnumerable(),
            (true, false) => _allPhotos.Where(p => !p.IsVideo),
            (false, true) => _allPhotos.Where(p => p.IsVideo),
            _ => _allPhotos.AsEnumerable()
        };

        // Filtre de duplicats
        if (FilterExactDuplicates || FilterSimilarDuplicates)
        {
            filtered = filtered.Where(p =>
            {
                if (p.DuplicateGroupId == null) return false;
                if (FilterExactDuplicates && p.DuplicateGroupId.StartsWith("md5-")) return true;
                if (FilterSimilarDuplicates && (p.DuplicateGroupId.StartsWith("phash-") || p.DuplicateGroupId.StartsWith("exif-"))) return true;
                return false;
            });
        }

        // Ordenar per data
        var sorted = SortAscending
            ? filtered.OrderBy(p => p.DateTaken ?? DateTime.MaxValue)
            : filtered.OrderByDescending(p => p.DateTaken ?? DateTime.MinValue);

        foreach (var item in sorted)
        {
            item.PropertyChanged -= OnPhotoPropertyChanged;
            item.PropertyChanged += OnPhotoPropertyChanged;
            item.IsSelected = false;
            Photos.Add(item);
        }

        UpdateStatusMessage();

        if (IsTimelineMode)
            RebuildGroups();
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

    // === Propietats de deduplicació ===

    /// <summary>Filtre: mostrar duplicats exactes</summary>
    [ObservableProperty]
    private bool _filterExactDuplicates;

    /// <summary>Filtre: mostrar duplicats similars</summary>
    [ObservableProperty]
    private bool _filterSimilarDuplicates;

    /// <summary>Nombre de duplicats exactes trobats</summary>
    [ObservableProperty]
    private int _exactDuplicateCount;

    /// <summary>Nombre de duplicats similars trobats</summary>
    [ObservableProperty]
    private int _similarDuplicateCount;

    /// <summary>Està escanejant duplicats exactes</summary>
    [ObservableProperty]
    private bool _isScanningExact;

    /// <summary>Està escanejant duplicats similars</summary>
    [ObservableProperty]
    private bool _isScanningSimilar;

    private CancellationTokenSource? _dupScanCts;

    /// <summary>
    /// Comanda per alternar l'ordre de classificació.
    /// </summary>
    [RelayCommand]
    private void ToggleSortOrder()
    {
        SortAscending = !SortAscending;
        ApplyFilter();
        _ = LoadThumbnailsAsync();
    }

    /// <summary>
    /// Comanda per alternar el filtre de duplicats exactes.
    /// </summary>
    [RelayCommand]
    private void ToggleFilterExactDuplicates()
    {
        FilterExactDuplicates = !FilterExactDuplicates;
        ApplyFilter();
        _ = LoadThumbnailsAsync();
    }

    /// <summary>
    /// Comanda per alternar el filtre de duplicats similars.
    /// </summary>
    [RelayCommand]
    private void ToggleFilterSimilarDuplicates()
    {
        FilterSimilarDuplicates = !FilterSimilarDuplicates;
        ApplyFilter();
        _ = LoadThumbnailsAsync();
    }

    /// <summary>
    /// Comanda per alternar el mode timeline.
    /// </summary>
    [RelayCommand]
    private void ToggleTimelineMode()
    {
        IsTimelineMode = !IsTimelineMode;
        if (IsTimelineMode)
            RebuildGroups();
    }

    /// <summary>
    /// Comanda per canviar l'agrupació del timeline.
    /// </summary>
    [RelayCommand]
    private void SetTimelineGrouping(string grouping)
    {
        TimelineGrouping = grouping switch
        {
            "Day" => TimelineGrouping.Day,
            "Month" => TimelineGrouping.Month,
            "Year" => TimelineGrouping.Year,
            _ => TimelineGrouping.Month
        };
        if (IsTimelineMode) RebuildGroups();
    }

    /// <summary>
    /// Col·lapsar/expandir un grup del timeline.
    /// </summary>
    [RelayCommand]
    private void ToggleGroupCollapse(string groupKey)
    {
        if (!_collapsedGroups.Remove(groupKey))
            _collapsedGroups.Add(groupKey);

        var group = GroupedPhotos.FirstOrDefault(g => g.Key == groupKey);
        if (group != null)
            group.IsCollapsed = _collapsedGroups.Contains(groupKey);
    }

    /// <summary>
    /// Reconstrueix els grups del timeline a partir de Photos filtrades.
    /// </summary>
    private void RebuildGroups()
    {
        GroupedPhotos.Clear();

        var groups = Photos
            .GroupBy(p => GetGroupKey(p.DateTaken, TimelineGrouping))
            .OrderByDescending(g => g.First().DateTaken ?? DateTime.MinValue);

        foreach (var group in groups)
        {
            var tg = new TimelineGroup
            {
                Key = group.Key,
                IsCollapsed = _collapsedGroups.Contains(group.Key)
            };
            foreach (var photo in SortAscending ? group.OrderBy(p => p.DateTaken) : group.OrderByDescending(p => p.DateTaken))
                tg.Photos.Add(photo);
            GroupedPhotos.Add(tg);
        }
    }

    /// <summary>
    /// Genera la clau de grup per una data segons l'agrupació.
    /// </summary>
    private static string GetGroupKey(DateTime? date, TimelineGrouping grouping)
    {
        if (date == null) return "Sense data";
        var d = date.Value;
        return grouping switch
        {
            TimelineGrouping.Day => d.ToString("dd/MM/yyyy"),
            TimelineGrouping.Month => $"{CatalanMonths[d.Month - 1]} {d.Year}",
            TimelineGrouping.Year => d.Year.ToString(),
            _ => d.ToString("dd/MM/yyyy")
        };
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

        await AddFolderAsync(dialog.FolderName);
    }

    /// <summary>
    /// Afegeix una carpeta al visor, acumulant les fotos amb les ja existents.
    /// </summary>
    public async Task AddFolderAsync(string folderPath)
    {
        // Si la carpeta ja està oberta, no fer res
        if (OpenFolders.Contains(folderPath))
        {
            StatusMessage = $"La carpeta ja està oberta: {Path.GetFileName(folderPath)}";
            return;
        }

        // Cancel·lar operacions anteriors de miniatures
        _thumbnailCts?.Cancel();
        _prefetchCts?.Cancel();

        IsLoading = true;
        HasError = false;
        StatusMessage = "Escanejant carpeta...";
        CurrentFolderPath = folderPath;

        // Tancar el visor si estava obert
        CloseViewer();

        try
        {
            var progress = new Progress<(int scanned, int found, string currentFile)>(info =>
            {
                StatusMessage = $"Escanejant... {info.found} imatges trobades — {info.currentFile}";
            });

            // Per defecte, les noves carpetes s'escanegen recursivament
            _recursiveFolders.Add(folderPath);
            var items = await _fileService.ScanFolderAsync(folderPath, recursive: true, progress: progress);

            // Afegir la carpeta a la llista
            OpenFolders.Add(folderPath);
            OpenFolderCount = OpenFolders.Count;

            // Afegir les noves fotos
            _allPhotos.AddRange(items);

            // Reordenar tota la llista per data (més recents primer)
            _allPhotos.Sort((a, b) => (b.DateTaken ?? DateTime.MinValue).CompareTo(a.DateTaken ?? DateTime.MinValue));

            PhotoCount = _allPhotos.Count(p => !p.IsVideo);
            VideoCount = _allPhotos.Count(p => p.IsVideo);

            // Aplicar el filtre actual
            ApplyFilter();

            UpdateStatusMessage();

            // Carregar miniatures en segon pla
            _ = LoadThumbnailsAsync();

            // Escanejar duplicats i localitzacions en segon pla
            _ = ScanForDuplicatesAsync();
            _ = LoadLocationsAsync();
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

    /// <summary>
    /// Carrega les imatges d'una carpeta al visor (substitueix tot, per compatibilitat amb importació MTP).
    /// </summary>
    public async Task LoadFolderAsync(string folderPath)
    {
        // Netejar tot primer i després afegir
        ClearAllFolders();
        await AddFolderAsync(folderPath);
    }

    /// <summary>
    /// Elimina una carpeta i les seves fotos de la vista.
    /// </summary>
    [RelayCommand]
    private void RemoveFolder(string? folderPath)
    {
        if (string.IsNullOrEmpty(folderPath) || !OpenFolders.Contains(folderPath)) return;

        CloseViewer();
        _allPhotos.RemoveAll(p => p.FullPath.StartsWith(folderPath, StringComparison.OrdinalIgnoreCase));
        OpenFolders.Remove(folderPath);
        _recursiveFolders.Remove(folderPath);
        OpenFolderCount = OpenFolders.Count;
        CurrentFolderPath = OpenFolders.Count > 0 ? OpenFolders[^1] : null;
        PhotoCount = _allPhotos.Count(p => !p.IsVideo);
        VideoCount = _allPhotos.Count(p => p.IsVideo);
        ApplyFilter();
        UpdateStatusMessage();
    }

    /// <summary>
    /// Alterna l'escaneig recursiu d'una carpeta. Re-escaneja amb el nou setting.
    /// </summary>
    [RelayCommand]
    private async Task ToggleRecursiveAsync(string? folderPath)
    {
        if (string.IsNullOrEmpty(folderPath) || !OpenFolders.Contains(folderPath)) return;

        var isNowRecursive = !_recursiveFolders.Contains(folderPath);
        if (isNowRecursive)
            _recursiveFolders.Add(folderPath);
        else
            _recursiveFolders.Remove(folderPath);

        // Treure fotos d'aquesta carpeta i re-escanejar
        _allPhotos.RemoveAll(p => p.FullPath.StartsWith(folderPath, StringComparison.OrdinalIgnoreCase));

        IsLoading = true;
        try
        {
            var items = await _fileService.ScanFolderAsync(folderPath, recursive: isNowRecursive);
            _allPhotos.AddRange(items);
            _allPhotos.Sort((a, b) => (b.DateTaken ?? DateTime.MinValue).CompareTo(a.DateTaken ?? DateTime.MinValue));
            PhotoCount = _allPhotos.Count(p => !p.IsVideo);
            VideoCount = _allPhotos.Count(p => p.IsVideo);
            ApplyFilter();
            UpdateStatusMessage();
            _ = LoadThumbnailsAsync();
        }
        catch (Exception ex)
        {
            StatusMessage = $"Error re-escanejant: {ex.Message}";
            HasError = true;
        }
        finally
        {
            IsLoading = false;
        }
    }

    /// <summary>
    /// Indica si una carpeta s'escaneja recursivament.
    /// </summary>
    public bool IsFolderRecursive(string folderPath)
        => _recursiveFolders.Contains(folderPath);

    /// <summary>
    /// Neteja totes les carpetes i fotos.
    /// </summary>
    [RelayCommand]
    private void ClearAllFolders()
    {
        _thumbnailCts?.Cancel();
        _prefetchCts?.Cancel();

        CloseViewer();

        OpenFolders.Clear();
        OpenFolderCount = 0;
        _allPhotos.Clear();
        Photos.Clear();
        SelectedPhotos.Clear();
        CurrentFolderPath = null;
        PhotoCount = 0;
        VideoCount = 0;

        StatusMessage = "Obre una carpeta per començar a visualitzar imatges.";
    }

    /// <summary>
    /// Actualitza el missatge d'estat amb el recompte de carpetes i imatges.
    /// </summary>
    private void UpdateStatusMessage()
    {
        if (OpenFolders.Count == 0)
        {
            StatusMessage = "Obre una carpeta per començar a visualitzar imatges.";
        }
        else if (OpenFolders.Count == 1)
        {
            StatusMessage = $"{_allPhotos.Count} imatge(s) de {Path.GetFileName(OpenFolders[0])}";
        }
        else
        {
            StatusMessage = $"{_allPhotos.Count} imatge(s) de {OpenFolders.Count} carpetes";
        }
    }

    // === Disk Scanner ===

    /// <summary>
    /// Obre/tanca el panell de disk scan.
    /// </summary>
    [RelayCommand]
    private void ToggleDiskScanPanel()
    {
        ShowDiskScanPanel = !ShowDiskScanPanel;
    }

    /// <summary>
    /// Escaneja llocs típics del disc per trobar carpetes amb fotos.
    /// </summary>
    [RelayCommand]
    private async Task StartDiskScanAsync()
    {
        _diskScanCts?.Cancel();
        _diskScanCts = new CancellationTokenSource();
        var ct = _diskScanCts.Token;

        IsScanningDisk = true;
        DiskScanResults.Clear();
        DiskScanStatus = "Escanejant...";

        try
        {
            var roots = new List<string>();

            // Llocs típics
            var pictures = Environment.GetFolderPath(Environment.SpecialFolder.MyPictures);
            var desktop = Environment.GetFolderPath(Environment.SpecialFolder.Desktop);
            var docs = Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments);
            var downloads = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads");

            if (Directory.Exists(pictures)) roots.Add(pictures);
            if (Directory.Exists(desktop)) roots.Add(desktop);
            if (Directory.Exists(docs)) roots.Add(docs);
            if (Directory.Exists(downloads)) roots.Add(downloads);

            // Drives extraïbles
            foreach (var drive in DriveInfo.GetDrives())
            {
                if (drive.IsReady && drive.DriveType == DriveType.Removable)
                    roots.Add(drive.RootDirectory.FullName);
            }

            var results = new List<DiskScanResult>();

            await Task.Run(() =>
            {
                foreach (var root in roots)
                {
                    ct.ThrowIfCancellationRequested();
                    ScanDirectoryForPhotos(root, results, ct, maxDepth: 5);
                }
            }, ct);

            foreach (var result in results.OrderByDescending(r => r.FileCount))
                DiskScanResults.Add(result);

            DiskScanStatus = $"Trobades {DiskScanResults.Count} carpetes amb fotos.";
        }
        catch (OperationCanceledException)
        {
            DiskScanStatus = "Escaneig cancel·lat.";
        }
        catch (Exception ex)
        {
            DiskScanStatus = $"Error: {ex.Message}";
        }
        finally
        {
            IsScanningDisk = false;
        }
    }

    private static void ScanDirectoryForPhotos(string path, List<DiskScanResult> results,
        CancellationToken ct, int maxDepth, int currentDepth = 0)
    {
        if (currentDepth > maxDepth) return;
        ct.ThrowIfCancellationRequested();

        try
        {
            var dir = new DirectoryInfo(path);
            if (!dir.Exists) return;

            // Saltar carpetes del sistema
            if ((dir.Attributes & FileAttributes.System) != 0) return;
            if (dir.Name.StartsWith('.')) return;

            var count = 0;
            try
            {
                count = dir.EnumerateFiles("*.*", SearchOption.TopDirectoryOnly)
                    .Count(f => PhotoItem.AllExtensions.Contains(f.Extension));
            }
            catch { }

            if (count > 0)
            {
                results.Add(new DiskScanResult
                {
                    FolderPath = path,
                    FileCount = count,
                    IsSelected = false
                });
            }

            // Escanejar subdirectoris
            try
            {
                foreach (var subDir in dir.EnumerateDirectories())
                {
                    ct.ThrowIfCancellationRequested();
                    ScanDirectoryForPhotos(subDir.FullName, results, ct, maxDepth, currentDepth + 1);
                }
            }
            catch { }
        }
        catch { }
    }

    /// <summary>
    /// Cancel·la l'escaneig de disc.
    /// </summary>
    [RelayCommand]
    private void StopDiskScan()
    {
        _diskScanCts?.Cancel();
    }

    /// <summary>
    /// Selecciona/desselecciona tots els resultats del disk scan.
    /// </summary>
    [RelayCommand]
    private void SelectAllDiskScanResults()
    {
        var allSelected = DiskScanResults.All(r => r.IsSelected);
        foreach (var r in DiskScanResults)
            r.IsSelected = !allSelected;
    }

    /// <summary>
    /// Afegeix les carpetes seleccionades del disk scan.
    /// </summary>
    [RelayCommand]
    private async Task AddSelectedDiskScanResultsAsync()
    {
        var selected = DiskScanResults.Where(r => r.IsSelected).ToList();
        if (selected.Count == 0) return;

        ShowDiskScanPanel = false;

        foreach (var result in selected)
        {
            if (!OpenFolders.Contains(result.FolderPath))
                await AddFolderAsync(result.FolderPath);
        }
    }

    // === Localització GPS ===

    /// <summary>
    /// Extreu GPS d'EXIF i geocodifica progressivament totes les fotos locals.
    /// </summary>
    private async Task LoadLocationsAsync()
    {
        _locationCts?.Cancel();
        _locationCts = new CancellationTokenSource();
        var ct = _locationCts.Token;

        try
        {
            var localPhotos = _allPhotos
                .Where(p => p.IsLocal && !p.IsVideo && p.Location == null)
                .ToList();

            foreach (var item in localPhotos)
            {
                ct.ThrowIfCancellationRequested();

                // Extreure GPS en background
                var gps = await Task.Run(() => FileService.ExtractGpsLocation(item.FullPath), ct);
                if (gps == null) continue;

                item.GpsLatitude = gps.Value.lat;
                item.GpsLongitude = gps.Value.lon;

                // Geocodificar
                var location = await _geocodingService.ReverseGeocodeAsync(gps.Value.lat, gps.Value.lon, ct);
                if (location != null)
                {
                    Application.Current?.Dispatcher.Invoke(() =>
                    {
                        item.Location = location;
                    });
                }
            }
        }
        catch (OperationCanceledException) { }
        catch { }
    }

    // === Deduplicació ===

    /// <summary>
    /// Escaneja duplicats en 4 passos: mida → MD5 → pHash → EXIF.
    /// </summary>
    private async Task ScanForDuplicatesAsync()
    {
        _dupScanCts?.Cancel();
        _dupScanCts = new CancellationTokenSource();
        var ct = _dupScanCts.Token;

        // Reset comptadors
        ExactDuplicateCount = 0;
        SimilarDuplicateCount = 0;
        IsScanningExact = true;
        IsScanningSimilar = true;

        var localPhotos = _allPhotos.Where(p => p.IsLocal && !p.IsVideo).ToList();

        try
        {
            // Pas 1+2: Agrupar per mida → MD5 per fitxers amb mida idèntica
            await Task.Run(() =>
            {
                var bySize = localPhotos
                    .GroupBy(p => p.SizeBytes)
                    .Where(g => g.Count() > 1);

                var groupId = 0;
                foreach (var sizeGroup in bySize)
                {
                    ct.ThrowIfCancellationRequested();

                    // Computar MD5 per tots els del grup
                    foreach (var item in sizeGroup)
                        item.Md5Hash = FileService.ComputeMD5(item.FullPath);

                    // Agrupar per MD5
                    var byMd5 = sizeGroup
                        .Where(p => p.Md5Hash != null)
                        .GroupBy(p => p.Md5Hash!)
                        .Where(g => g.Count() > 1);

                    foreach (var md5Group in byMd5)
                    {
                        var id = $"md5-{groupId++}";
                        foreach (var item in md5Group)
                            item.DuplicateGroupId = id;
                    }
                }
            }, ct);

            // Actualitzar comptador exactes
            ExactDuplicateCount = _allPhotos.Count(p => p.DuplicateGroupId?.StartsWith("md5-") == true);
            IsScanningExact = false;

            // Pas 3: Perceptual hash (similars visuals)
            await Task.Run(() =>
            {
                // Calcular pHash per fotos sense grup de duplicats
                var unmarked = localPhotos.Where(p => p.DuplicateGroupId == null).ToList();
                foreach (var item in unmarked)
                {
                    ct.ThrowIfCancellationRequested();
                    item.PerceptualHash = FileService.ComputePerceptualHash(item.FullPath);
                }

                // Comparar O(n²) amb Hamming ≤ 5
                var withHash = unmarked.Where(p => p.PerceptualHash.HasValue).ToList();
                var groupId = 0;
                var visited = new HashSet<int>();

                for (var i = 0; i < withHash.Count; i++)
                {
                    ct.ThrowIfCancellationRequested();
                    if (visited.Contains(i)) continue;

                    var group = new List<int> { i };
                    for (var j = i + 1; j < withHash.Count; j++)
                    {
                        if (visited.Contains(j)) continue;
                        var dist = FileService.HammingDistance(
                            withHash[i].PerceptualHash!.Value,
                            withHash[j].PerceptualHash!.Value);
                        if (dist <= 5)
                            group.Add(j);
                    }

                    if (group.Count > 1)
                    {
                        var id = $"phash-{groupId++}";
                        foreach (var idx in group)
                        {
                            withHash[idx].DuplicateGroupId = id;
                            visited.Add(idx);
                        }
                    }
                }
            }, ct);

            // Pas 4: EXIF fingerprint per la resta
            await Task.Run(() =>
            {
                var remaining = localPhotos.Where(p => p.DuplicateGroupId == null).ToList();
                foreach (var item in remaining)
                {
                    ct.ThrowIfCancellationRequested();
                    item.ExifFingerprint = FileService.ComputeExifFingerprint(item.FullPath);
                }

                var groupId = 0;
                var byFp = remaining
                    .Where(p => p.ExifFingerprint != null)
                    .GroupBy(p => p.ExifFingerprint!)
                    .Where(g => g.Count() > 1);

                foreach (var fpGroup in byFp)
                {
                    var id = $"exif-{groupId++}";
                    foreach (var item in fpGroup)
                        item.DuplicateGroupId = id;
                }
            }, ct);

            SimilarDuplicateCount = _allPhotos.Count(p =>
                p.DuplicateGroupId?.StartsWith("phash-") == true ||
                p.DuplicateGroupId?.StartsWith("exif-") == true);
            IsScanningSimilar = false;
        }
        catch (OperationCanceledException) { }
        catch
        {
            IsScanningExact = false;
            IsScanningSimilar = false;
        }
    }

    // === Carregar miniatures ===

    private async Task LoadThumbnailsAsync()
    {
        _thumbnailCts?.Cancel();
        _thumbnailCts = new CancellationTokenSource();
        var ct = _thumbnailCts.Token;

        // Esperar un tick perquè la UI es refresqui
        await Task.Yield();

        var photosCopy = Photos.Where(p => p.IsLocal && p.Thumbnail == null).ToList();
        var batchSize = 4;

        try
        {
            for (var i = 0; i < photosCopy.Count; i += batchSize)
            {
                ct.ThrowIfCancellationRequested();

                var batch = photosCopy.Skip(i).Take(batchSize);
                var tasks = batch.Select(async photo =>
                {
                    try
                    {
                        var thumb = await _thumbnailCache.GetThumbnailAsync(photo.FullPath, ct);
                        if (thumb != null && !ct.IsCancellationRequested)
                        {
                            Application.Current?.Dispatcher.Invoke(() =>
                            {
                                photo.Thumbnail = thumb;
                            });
                        }
                    }
                    catch (OperationCanceledException) { throw; }
                    catch { /* thumbnail individual fallat, continuar */ }
                });

                await Task.WhenAll(tasks);
            }
        }
        catch (OperationCanceledException) { }
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
        IsViewingVideo = false;
        ViewerVideoPath = null;
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

        if (item.IsVideo)
        {
            IsViewingVideo = true;
            // Només llegir rotació de fitxers locals
            if (item.IsLocal && item.VideoRotation == 0)
                item.VideoRotation = FileService.GetVideoRotation(item.FullPath);
            ViewerVideoRotation = item.VideoRotation;
            ViewerVideoPath = item.IsLocal ? item.FullPath : null;
            ViewerImage = item.Thumbnail;
            UpdateViewerInfo(item);
            return;
        }

        // Imatge
        IsViewingVideo = false;
        ViewerVideoPath = null;
        ViewerVideoRotation = 0;

        // Nivell 1: Mostrar miniatura immediatament
        if (item.Thumbnail != null)
            ViewerImage = item.Thumbnail;

        // En mode dispositiu: descarregar fitxer temporal i carregar-lo
        if (!item.IsLocal)
        {
            UpdateViewerInfo(item);
            _ = LoadDeviceFullImageAsync(item);
            return;
        }

        // Cache LRU: si ja tenim la imatge completa, mostrar-la directament
        var cached = _imageCache.Get(item.FullPath);
        if (cached != null)
        {
            ViewerImage = cached;
            UpdateViewerInfo(item);
            _ = PrefetchNeighbors();
            return;
        }

        // Nivell 2 (RAW/HEIC): Quick preview embegut (~2048px, quasi instant)
        if (item.IsRaw || item.FileName.EndsWith(".heic", StringComparison.OrdinalIgnoreCase)
                       || item.FileName.EndsWith(".heif", StringComparison.OrdinalIgnoreCase))
        {
            _ = LoadQuickPreviewAsync(item);
        }

        // Nivell 3: Carregar a resolució completa en segon pla
        _ = LoadFullImageAsync(item);
    }

    /// <summary>
    /// Nivell 2 piràmide: quick preview per RAW/HEIC (~2048px, embegut si disponible).
    /// </summary>
    private async Task LoadQuickPreviewAsync(PhotoItem item)
    {
        try
        {
            var preview = await Task.Run(() => FileService.LoadRawQuickPreview(item.FullPath));
            if (preview != null && ViewerCurrentItem == item)
            {
                Application.Current?.Dispatcher.Invoke(() =>
                {
                    // Només actualitzar si encara no tenim la imatge completa
                    if (_imageCache.Get(item.FullPath) == null)
                        ViewerImage = preview;
                });
            }
        }
        catch { }
    }

    private async Task LoadFullImageAsync(PhotoItem item)
    {
        try
        {
            var isRaw = item.IsRaw
                     || item.FileName.EndsWith(".heic", StringComparison.OrdinalIgnoreCase)
                     || item.FileName.EndsWith(".heif", StringComparison.OrdinalIgnoreCase)
                     || PhotoItem.ModernExtensions.Contains(System.IO.Path.GetExtension(item.FileName));

            var image = await Task.Run(() =>
                isRaw ? FileService.LoadRawFullImage(item.FullPath)
                      : FileService.LoadFullImage(item.FullPath));

            if (image != null && ViewerCurrentItem == item)
            {
                _imageCache.Put(item.FullPath, image);
                Application.Current?.Dispatcher.Invoke(() =>
                {
                    ViewerImage = image;
                    if (item.PixelWidth == 0)
                    {
                        item.PixelWidth = image.PixelWidth;
                        item.PixelHeight = image.PixelHeight;
                    }
                    UpdateViewerInfo(item);
                });
            }

            await PrefetchNeighbors();
        }
        catch
        {
            // Error carregant imatge, mantenir la miniatura/preview
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

        if (!string.IsNullOrEmpty(item.Location))
            parts.Add(item.Location);

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
            $"Vols eliminar {SelectedPhotos.Count} fitxer(s)?\n\nS'enviaran a la paperera de reciclatge.",
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

    // === Importació MTP — Browse Mode (estil macOS) ===

    private DeviceService? _deviceService;
    private readonly ObservableCollection<MediaDevices.MediaDevice> _devices = [];

    public ObservableCollection<MediaDevices.MediaDevice> Devices => _devices;

    [ObservableProperty]
    private MediaDevices.MediaDevice? _selectedDevice;

    /// <summary>Indica si estem en mode browse del dispositiu (fotos del dispositiu a la graella).</summary>
    [ObservableProperty]
    private bool _isDeviceBrowseMode;

    /// <summary>Nom del dispositiu que estem navegant.</summary>
    [ObservableProperty]
    private string _browseDeviceName = "";

    /// <summary>Nombre de fitxers del dispositiu carregats.</summary>
    [ObservableProperty]
    private int _deviceFileCount;

    /// <summary>Està escanejant el dispositiu.</summary>
    [ObservableProperty]
    private bool _isBrowsingDevice;

    // Estat local guardat per restaurar al sortir del browse mode
    private List<PhotoItem> _savedLocalPhotos = [];
    private List<string> _savedOpenFolders = [];
    private string? _savedCurrentFolder;
    private CancellationTokenSource? _deviceThumbnailCts;

    [RelayCommand]
    private void ToggleImportPanel()
    {
        if (IsDeviceBrowseMode)
        {
            ExitDeviceBrowseMode();
            return;
        }

        IsImportPanelOpen = !IsImportPanelOpen;
        if (IsImportPanelOpen)
        {
            _deviceService ??= new DeviceService();
            ImportStatusMessage = "Connecta l'iPhone via USB i prem 'Detectar'.";
        }
    }

    [RelayCommand]
    private async Task DetectDevicesAsync()
    {
        _deviceService ??= new DeviceService();
        ImportStatusMessage = "Cercant dispositius...";

        try
        {
            var devices = await _deviceService.GetConnectedDevicesAsync();
            Devices.Clear();
            foreach (var d in devices)
                Devices.Add(d);

            SelectedDevice = Devices.FirstOrDefault();
            ImportStatusMessage = $"{Devices.Count} dispositiu(s) detectat(s).";

            // Auto-browse si només hi ha 1 dispositiu
            if (Devices.Count == 1)
                await BrowseDeviceAsync();
        }
        catch (InvalidOperationException)
        {
            Devices.Clear();
            SelectedDevice = null;
            ImportStatusMessage = "Cap dispositiu detectat. Assegura't que l'iPhone està desbloquejat i has premut 'Confiar'.";
        }
        catch (Exception ex)
        {
            ImportStatusMessage = $"Error: {ex.Message}";
        }
    }

    /// <summary>
    /// Entra en mode browse: escaneja el dispositiu i mostra les fotos a la graella principal.
    /// L'usuari pot seleccionar i importar les que vulgui.
    /// </summary>
    [RelayCommand]
    private async Task BrowseDeviceAsync()
    {
        if (SelectedDevice == null || _deviceService == null) return;

        IsBrowsingDevice = true;
        ImportStatusMessage = "Connectant al dispositiu...";

        try
        {
            // Guardar estat local
            _savedLocalPhotos = new List<PhotoItem>(_allPhotos);
            _savedOpenFolders = new List<string>(OpenFolders);
            _savedCurrentFolder = CurrentFolderPath;

            // Netejar graella
            CloseViewer();
            _allPhotos.Clear();
            Photos.Clear();
            SelectedPhotos.Clear();

            BrowseDeviceName = SelectedDevice.FriendlyName ?? "Dispositiu";
            ImportStatusMessage = $"Escanejant {BrowseDeviceName}...";

            // Escanejar fotos del dispositiu
            var devicePhotos = new List<PhotoItem>();
            var scanProgress = new Progress<(string folder, int scanned, int found)>(info =>
            {
                ImportStatusMessage = $"Escanejant... {info.found} fotos — {info.folder}";
                DeviceFileCount = info.found;
            });

            // Limitar al mes actual i l'anterior (iPhone és molt lent escanejant tot)
            var now = DateTime.Now;
            var minDate = new DateTime(now.Year, now.Month, 1).AddMonths(-1);

            await _deviceService.GetPhotosAsync(SelectedDevice, photo =>
            {
                Application.Current.Dispatcher.Invoke(() => devicePhotos.Add(photo));
            }, scanProgress, minDate: minDate);

            if (devicePhotos.Count == 0)
            {
                ImportStatusMessage = "No s'han trobat fotos al dispositiu.";
                IsBrowsingDevice = false;
                return;
            }

            // Ordenar per data i carregar a la graella
            devicePhotos.Sort((a, b) => (b.DateTaken ?? DateTime.MinValue).CompareTo(a.DateTaken ?? DateTime.MinValue));
            _allPhotos.AddRange(devicePhotos);
            PhotoCount = _allPhotos.Count(p => !p.IsVideo);
            VideoCount = _allPhotos.Count(p => p.IsVideo);

            // Entrar en browse mode
            IsDeviceBrowseMode = true;
            IsImportPanelOpen = false;
            DeviceFileCount = devicePhotos.Count;
            IsBrowsingDevice = false;

            ApplyFilter();
            ImportStatusMessage = $"{devicePhotos.Count} fitxers carregats de {BrowseDeviceName}.";
            UpdateStatusMessage();

            // Carregar thumbnails en segon pla
            _ = LoadDeviceThumbnailsAsync();
        }
        catch (Exception ex)
        {
            ImportStatusMessage = $"Error navegant dispositiu: {ex.Message}";
            IsBrowsingDevice = false;
            // Restaurar estat local si ha fallat
            if (_savedLocalPhotos.Count > 0)
            {
                _allPhotos.Clear();
                _allPhotos.AddRange(_savedLocalPhotos);
                ApplyFilter();
            }
        }
    }

    /// <summary>
    /// Carrega thumbnails del dispositiu en segon pla.
    /// </summary>
    private async Task LoadDeviceThumbnailsAsync()
    {
        if (SelectedDevice == null || _deviceService == null) return;

        _deviceThumbnailCts?.Cancel();
        _deviceThumbnailCts = new CancellationTokenSource();
        var ct = _deviceThumbnailCts.Token;

        try
        {
            // Carregar thumbnails per les fotos visibles primer, després la resta
            var items = Photos.ToList();
            foreach (var item in items)
            {
                ct.ThrowIfCancellationRequested();
                if (item.Thumbnail != null) continue;

                try
                {
                    var thumb = await _deviceService.GetThumbnailAsync(SelectedDevice, item.FullPath);
                    if (thumb != null && !ct.IsCancellationRequested)
                    {
                        Application.Current?.Dispatcher.Invoke(() =>
                        {
                            item.Thumbnail = thumb;
                        });
                    }
                }
                catch { }
            }
        }
        catch (OperationCanceledException) { }
    }

    /// <summary>
    /// Descarrega un fitxer del dispositiu a temp i el carrega al visor.
    /// </summary>
    private async Task LoadDeviceFullImageAsync(PhotoItem item)
    {
        if (SelectedDevice == null || _deviceService == null) return;
        if (item.IsVideo) return; // Vídeos no es descarreguen per previsualitzar

        try
        {
            StatusMessage = $"Descarregant {item.FileName}...";
            var tempPath = await _deviceService.DownloadTempFileAsync(SelectedDevice, item);
            if (tempPath == null || ViewerCurrentItem != item) return;

            // Carregar la imatge des del fitxer temporal
            var ext = System.IO.Path.GetExtension(tempPath);
            var isRaw = PhotoItem.RawExtensions.Contains(ext)
                     || PhotoItem.ModernExtensions.Contains(ext)
                     || ext.Equals(".heic", StringComparison.OrdinalIgnoreCase)
                     || ext.Equals(".heif", StringComparison.OrdinalIgnoreCase);

            var image = await Task.Run(() =>
                isRaw ? FileService.LoadRawFullImage(tempPath)
                      : FileService.LoadFullImage(tempPath));

            if (image != null && ViewerCurrentItem == item)
            {
                // Regenerar thumbnail amb orientació correcta des del fitxer temporal
                var thumb = await Task.Run(() =>
                    isRaw ? FileService.GenerateRawThumbnail(tempPath, 256)
                          : FileService.GenerateThumbnail(tempPath, 256));

                Application.Current?.Dispatcher.Invoke(() =>
                {
                    ViewerImage = image;
                    if (thumb != null)
                        item.Thumbnail = thumb;
                    if (item.PixelWidth == 0)
                    {
                        item.PixelWidth = image.PixelWidth;
                        item.PixelHeight = image.PixelHeight;
                    }
                    UpdateViewerInfo(item);
                    StatusMessage = "";
                });
            }
        }
        catch
        {
            StatusMessage = "";
        }
    }

    /// <summary>
    /// Importa les fotos seleccionades del dispositiu a una carpeta local.
    /// </summary>
    [RelayCommand]
    private async Task ImportSelectedFromDeviceAsync()
    {
        if (SelectedDevice == null || _deviceService == null || SelectedPhotos.Count == 0) return;

        // Escollir carpeta destí
        string destinationFolder;
        if (!string.IsNullOrEmpty(DestinationFolder))
        {
            destinationFolder = DestinationFolder;
        }
        else
        {
            var dialog = new OpenFolderDialog
            {
                Title = "Selecciona la carpeta de destí per la importació"
            };
            if (dialog.ShowDialog() != true) return;
            destinationFolder = dialog.FolderName;
        }

        var photosToImport = SelectedPhotos.ToList();
        IsImporting = true;
        ImportProgress = 0;
        ImportStatusMessage = $"Important {photosToImport.Count} fitxer(s)...";

        try
        {
            var copyProgress = new Progress<(int current, int total, string fileName)>(report =>
            {
                ImportProgress = (double)report.current / report.total * 100;
                ImportStatusMessage = $"Important {report.current}/{report.total}: {report.fileName}";
            });

            var copied = await _deviceService.CopyPhotosAsync(
                SelectedDevice, photosToImport, destinationFolder, copyProgress);

            ImportProgress = 100;
            ImportStatusMessage = $"{copied} fitxer(s) importat(s) a {Path.GetFileName(destinationFolder)}.";

            // Desseleccionar les importades
            foreach (var p in photosToImport)
                p.IsSelected = false;
            SelectedPhotos.Clear();
            SelectedPhotosCount = 0;
            ShowActionBar = false;
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

    // NOTA: Eliminar fotos de l'iPhone via MTP no és possible — DeleteFile es congela indefinidament.

    /// <summary>
    /// Surt del mode browse i restaura l'estat local anterior.
    /// </summary>
    [RelayCommand]
    private void ExitDeviceBrowseMode()
    {
        // Cancel·lar tasques de thumbnails
        _deviceThumbnailCts?.Cancel();

        // Tancar visor
        CloseViewer();

        // Restaurar estat local
        _allPhotos.Clear();
        _allPhotos.AddRange(_savedLocalPhotos);

        OpenFolders.Clear();
        foreach (var f in _savedOpenFolders)
            OpenFolders.Add(f);
        OpenFolderCount = OpenFolders.Count;
        CurrentFolderPath = _savedCurrentFolder;

        // Reset estat browse
        IsDeviceBrowseMode = false;
        IsImportPanelOpen = false;
        BrowseDeviceName = "";
        DeviceFileCount = 0;
        ImportStatusMessage = "";

        // Netejar estat guardat
        _savedLocalPhotos.Clear();
        _savedOpenFolders.Clear();
        _savedCurrentFolder = null;

        // Reaplicar filtres i comptadors
        PhotoCount = _allPhotos.Count(p => !p.IsVideo);
        VideoCount = _allPhotos.Count(p => p.IsVideo);
        ApplyFilter();
        UpdateStatusMessage();
        _ = LoadThumbnailsAsync();
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
