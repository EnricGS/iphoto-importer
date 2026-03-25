using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Windows.Media.Imaging;

namespace iPhotoImporter.Models;

/// <summary>
/// Representa una foto o vídeo, tant d'un dispositiu MTP com d'una carpeta local.
/// </summary>
public class PhotoItem : INotifyPropertyChanged
{
    private bool _isSelected;
    private BitmapSource? _thumbnail;
    private bool _isHighlighted;

    /// <summary>Ruta completa (local o MTP)</summary>
    public required string FullPath { get; init; }

    /// <summary>Nom del fitxer (ex: IMG_20240101.jpg)</summary>
    public required string FileName { get; init; }

    /// <summary>Data de captura de la foto</summary>
    public DateTime? DateTaken { get; set; }

    /// <summary>Mida del fitxer en bytes</summary>
    public long SizeBytes { get; init; }

    /// <summary>Indica si és un fitxer local (true) o MTP (false)</summary>
    public bool IsLocal { get; init; }

    /// <summary>Amplada de la imatge original (si disponible)</summary>
    public int PixelWidth { get; set; }

    /// <summary>Alçada de la imatge original (si disponible)</summary>
    public int PixelHeight { get; set; }

    /// <summary>Seleccionat per l'usuari a la UI</summary>
    public bool IsSelected
    {
        get => _isSelected;
        set => SetField(ref _isSelected, value);
    }

    /// <summary>Ressaltat visualment (ex: element actiu al visor)</summary>
    public bool IsHighlighted
    {
        get => _isHighlighted;
        set => SetField(ref _isHighlighted, value);
    }

    /// <summary>Miniatura de la foto (pot ser null si no disponible)</summary>
    public BitmapSource? Thumbnail
    {
        get => _thumbnail;
        set => SetField(ref _thumbnail, value);
    }

    /// <summary>Indica si és un vídeo</summary>
    public bool IsVideo => FileName.EndsWith(".mp4", StringComparison.OrdinalIgnoreCase)
                        || FileName.EndsWith(".mov", StringComparison.OrdinalIgnoreCase)
                        || FileName.EndsWith(".avi", StringComparison.OrdinalIgnoreCase)
                        || FileName.EndsWith(".mkv", StringComparison.OrdinalIgnoreCase);

    public event PropertyChangedEventHandler? PropertyChanged;

    protected void OnPropertyChanged([CallerMemberName] string? propertyName = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));

    private bool SetField<T>(ref T field, T value, [CallerMemberName] string? propertyName = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value)) return false;
        field = value;
        OnPropertyChanged(propertyName);
        return true;
    }
}
