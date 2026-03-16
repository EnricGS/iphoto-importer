using System.Collections.ObjectModel;
using System.ComponentModel;
using System.IO;
using System.Globalization;
using System.Windows;
using System.Windows.Data;
using System.Windows.Input;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using iPhotoImporter.Models;
using iPhotoImporter.Services;
using MediaDevices;
using Microsoft.Win32;

namespace iPhotoImporter.ViewModels;

/// <summary>
/// Representa un mes/any per al selector de rang de dates.
/// </summary>
public class MonthYearOption
{
    public required string Label { get; init; }
    public int Year { get; init; }
    public int Month { get; init; }

    public DateTime FirstDay => new(Year, Month, 1);
    public DateTime LastDay => new(Year, Month, DateTime.DaysInMonth(Year, Month), 23, 59, 59);
}

/// <summary>
/// ViewModel principal de l'aplicació. Gestiona l'estat de la UI
/// i coordina les operacions entre serveis i la vista.
/// </summary>
public partial class MainViewModel : ObservableObject
{
    private readonly DeviceService _deviceService = new();

    [ObservableProperty]
    [NotifyCanExecuteChangedFor(nameof(LoadPhotosCommand))]
    [NotifyCanExecuteChangedFor(nameof(CopySelectedCommand))]
    private MediaDevice? _selectedDevice;

    [ObservableProperty]
    private int _selectedPhotosCount;

    [ObservableProperty]
    private double _totalSelectedSizeMB;

    [ObservableProperty]
    [NotifyCanExecuteChangedFor(nameof(LoadPhotosCommand))]
    [NotifyCanExecuteChangedFor(nameof(CopySelectedCommand))]
    [NotifyCanExecuteChangedFor(nameof(RefreshDevicesCommand))]
    private bool _isLoading;

    [ObservableProperty]
    private bool _isCopying;

    [ObservableProperty]
    private double _copyProgress;

    [ObservableProperty]
    private string _statusMessage = "Connecta un dispositiu per començar.";

    [ObservableProperty]
    private bool _hasError;

    [ObservableProperty]
    private MonthYearOption _selectedFromMonth = null!;

    [ObservableProperty]
    private MonthYearOption _selectedToMonth = null!;

    public ObservableCollection<MediaDevice> Devices { get; } = [];
    public ObservableCollection<PhotoItem> Photos { get; } = [];
    public List<MonthYearOption> MonthYearOptions { get; }

    /// <summary>Vista agrupada per mes/any sobre la col·lecció Photos.</summary>
    public ICollectionView PhotosView { get; }

    private static readonly string[] CatMonths =
        ["Gen", "Feb", "Mar", "Abr", "Mai", "Jun", "Jul", "Ago", "Set", "Oct", "Nov", "Des"];

    public MainViewModel()
    {
        // Generar opcions: des de gen 2015 fins al mes actual
        var now = DateTime.Now;
        var options = new List<MonthYearOption>();
        for (var y = now.Year; y >= 2015; y--)
        {
            var maxMonth = y == now.Year ? now.Month : 12;
            for (var m = maxMonth; m >= 1; m--)
                options.Add(new() { Label = $"{CatMonths[m - 1]} {y}", Year = y, Month = m });
        }
        MonthYearOptions = options;

        // Per defecte: últim mes
        SelectedFromMonth = MonthYearOptions.Count > 1 ? MonthYearOptions[1] : MonthYearOptions[0];
        SelectedToMonth = MonthYearOptions[0];

        PhotosView = CollectionViewSource.GetDefaultView(Photos);
        PhotosView.GroupDescriptions.Add(
            new PropertyGroupDescription(nameof(PhotoItem.DateTaken), new MonthYearConverter()));
    }

    [RelayCommand(CanExecute = nameof(CanRefreshDevices))]
    private async Task RefreshDevicesAsync()
    {
        IsLoading = true;
        HasError = false;
        StatusMessage = "Cercant dispositius...";

        try
        {
            var devices = await _deviceService.GetConnectedDevicesAsync();

            Devices.Clear();
            foreach (var d in devices)
                Devices.Add(d);

            SelectedDevice = Devices.FirstOrDefault();
            StatusMessage = $"{Devices.Count} dispositiu(s) trobat(s).";
        }
        catch (InvalidOperationException)
        {
            Devices.Clear();
            SelectedDevice = null;
            HasError = true;
            StatusMessage = "Cap dispositiu detectat. Connecta un iPhone o dispositiu MTP via USB.";
        }
        catch (Exception ex)
        {
            HasError = true;
            StatusMessage = $"Error: {ex.Message}";
        }
        finally
        {
            IsLoading = false;
        }
    }

    private bool CanRefreshDevices() => !IsLoading;

    [RelayCommand(CanExecute = nameof(CanLoadPhotos))]
    private async Task LoadPhotosAsync()
    {
        if (SelectedDevice is null) return;

        IsLoading = true;
        HasError = false;
        StatusMessage = "Escanejant fotos...";
        Photos.Clear();
        UpdateSelectionStats();

        try
        {
            var scanProgress = new Progress<(string folder, int scanned, int found)>(info =>
            {
                StatusMessage = $"Escanejant... {info.scanned} fitxers revisats, {info.found} coincideixen — {Path.GetFileName(info.folder)}";
            });

            var minDate = (DateTime?)SelectedFromMonth.FirstDay;
            var maxDate = (DateTime?)SelectedToMonth.LastDay;

            var total = await _deviceService.GetPhotosAsync(SelectedDevice, photo =>
            {
                photo.IsSelected = true;
                photo.PropertyChanged += OnPhotoSelectionChanged;
                Application.Current.Dispatcher.Invoke(() =>
                {
                    Photos.Add(photo);
                    if (Photos.Count % 50 == 0)
                        UpdateSelectionStats();
                });
            }, scanProgress, minDate, maxDate);

            if (total == 0)
            {
                StatusMessage = "No s'han trobat fotos ni vídeos al dispositiu.";
                return;
            }

            UpdateSelectionStats();
            StatusMessage = $"{Photos.Count} foto(s) trobada(es).";

            _ = LoadThumbnailsAsync();
        }
        catch (InvalidOperationException ex) when (ex.Message.Contains("desbloquejat"))
        {
            HasError = true;
            StatusMessage = "Desbloqueja l'iPhone i prem \"Confiar\" quan aparegui el missatge a la pantalla.";
        }
        catch (Exception ex)
        {
            HasError = true;
            StatusMessage = $"Error escanejant: {ex.Message}";
        }
        finally
        {
            IsLoading = false;
        }
    }

    private bool CanLoadPhotos() => SelectedDevice is not null && !IsLoading;

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

    [RelayCommand(CanExecute = nameof(CanCopySelected))]
    private async Task CopySelectedAsync()
    {
        if (SelectedDevice is null) return;

        var dialog = new OpenFolderDialog
        {
            Title = "Selecciona la carpeta de destí"
        };

        if (dialog.ShowDialog() != true) return;

        var selected = Photos.Where(p => p.IsSelected).ToList();
        if (selected.Count == 0)
        {
            HasError = true;
            StatusMessage = "Cap foto seleccionada.";
            return;
        }

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
            var copied = await _deviceService.CopyPhotosAsync(
                SelectedDevice, selected, dialog.FolderName, progress);

            CopyProgress = 100;
            StatusMessage = $"{copied} foto(s) copiada(es) correctament a {dialog.FolderName}";

            MessageBox.Show(
                $"S'han copiat {copied} foto(s) correctament.\n\nDestí: {dialog.FolderName}",
                "Còpia completada",
                MessageBoxButton.OK,
                MessageBoxImage.Information);
        }
        catch (Exception ex)
        {
            HasError = true;
            StatusMessage = $"Error copiant: {ex.Message}";

            MessageBox.Show(
                $"Error durant la còpia:\n{ex.Message}",
                "Error",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
        }
        finally
        {
            IsCopying = false;
            IsLoading = false;
        }
    }

    private bool CanCopySelected() => SelectedDevice is not null && !IsLoading;

    private void OnPhotoSelectionChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(PhotoItem.IsSelected))
            UpdateSelectionStats();
    }

    private void UpdateSelectionStats()
    {
        var selected = Photos.Where(p => p.IsSelected).ToList();
        SelectedPhotosCount = selected.Count;
        TotalSelectedSizeMB = Math.Round(selected.Sum(p => p.SizeBytes) / (1024.0 * 1024.0), 2);
        CopySelectedCommand.NotifyCanExecuteChanged();
    }

    private async Task LoadThumbnailsAsync()
    {
        if (SelectedDevice is null) return;

        foreach (var photo in Photos.ToList())
        {
            if (photo.Thumbnail is not null) continue;
            photo.Thumbnail = await _deviceService.GetThumbnailAsync(SelectedDevice, photo.FullPath);
        }
    }
}

/// <summary>
/// Converter per agrupar dates per mes/any (ex: "Gener 2024").
/// </summary>
internal class MonthYearConverter : IValueConverter
{
    private static readonly string[] MonthNames =
        ["Gener", "Febrer", "Març", "Abril", "Maig", "Juny",
         "Juliol", "Agost", "Setembre", "Octubre", "Novembre", "Desembre"];

    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        if (value is DateTime dt)
            return $"{MonthNames[dt.Month - 1]} {dt.Year}";
        return "Sense data";
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
        => throw new NotSupportedException();
}

/// <summary>
/// Converter: null → false, no-null → true. Per a l'indicador de connexió.
/// </summary>
internal class NullToBoolConverter : IValueConverter
{
    public static readonly NullToBoolConverter Instance = new();

    public object Convert(object? value, Type targetType, object parameter, CultureInfo culture)
        => value is not null;

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
        => throw new NotSupportedException();
}

/// <summary>
/// Converter: bool → Visibility. Per al spinner de càrrega.
/// </summary>
internal class BoolToVisibilityConverter : IValueConverter
{
    public static readonly BoolToVisibilityConverter Instance = new();

    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
        => value is true ? Visibility.Visible : Visibility.Collapsed;

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
        => throw new NotSupportedException();
}

/// <summary>
/// Converter: 0 → Visible, altres → Collapsed. Per al missatge buit.
/// </summary>
internal class ZeroToVisibilityConverter : IValueConverter
{
    public static readonly ZeroToVisibilityConverter Instance = new();

    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
        => value is 0 ? Visibility.Visible : Visibility.Collapsed;

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
        => throw new NotSupportedException();
}

/// <summary>
/// Command estàtic per alternar la selecció d'una foto amb un clic.
/// </summary>
internal class ToggleSelectionCommand : ICommand
{
    public static readonly ToggleSelectionCommand Instance = new();

    public event EventHandler? CanExecuteChanged { add { } remove { } }

    public bool CanExecute(object? parameter) => parameter is PhotoItem;

    public void Execute(object? parameter)
    {
        if (parameter is PhotoItem photo)
            photo.IsSelected = !photo.IsSelected;
    }
}
