using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Windows.Media.Imaging;

namespace iPhotoImporter.Models;

/// <summary>
/// Representa una foto o vídeo trobat al dispositiu mòbil.
/// </summary>
public class PhotoItem : INotifyPropertyChanged
{
    private bool _isSelected;
    private BitmapImage? _thumbnail;

    /// <summary>Ruta completa al dispositiu MTP (ex: \Internal storage\DCIM\photo.jpg)</summary>
    public required string FullPath { get; init; }

    /// <summary>Nom del fitxer (ex: IMG_20240101.jpg)</summary>
    public required string FileName { get; init; }

    /// <summary>Data de captura de la foto</summary>
    public DateTime? DateTaken { get; init; }

    /// <summary>Mida del fitxer en bytes</summary>
    public long SizeBytes { get; init; }

    /// <summary>Seleccionat per l'usuari a la UI</summary>
    public bool IsSelected
    {
        get => _isSelected;
        set
        {
            if (_isSelected == value) return;
            _isSelected = value;
            OnPropertyChanged();
        }
    }

    /// <summary>Miniatura de la foto (pot ser null si no disponible)</summary>
    public BitmapImage? Thumbnail
    {
        get => _thumbnail;
        set
        {
            if (_thumbnail == value) return;
            _thumbnail = value;
            OnPropertyChanged();
        }
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }
}
