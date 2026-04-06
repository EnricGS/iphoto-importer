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
    private string? _duplicateGroupId;
    private string? _location;

    // === Extensions centralitzades (matching macOS) ===

    /// <summary>Extensions d'imatge estàndard</summary>
    public static readonly HashSet<string> ImageExtensions = new(StringComparer.OrdinalIgnoreCase)
    {
        ".jpg", ".jpeg", ".png", ".bmp", ".gif", ".webp", ".tiff", ".tif", ".heic", ".heif"
    };

    /// <summary>Extensions RAW de càmera</summary>
    public static readonly HashSet<string> RawExtensions = new(StringComparer.OrdinalIgnoreCase)
    {
        ".cr2", ".cr3", ".nef", ".arw", ".dng", ".raf", ".orf", ".rw2", ".pef", ".srw", ".rwl"
    };

    /// <summary>Extensions de formats moderns</summary>
    public static readonly HashSet<string> ModernExtensions = new(StringComparer.OrdinalIgnoreCase)
    {
        ".avif", ".jxl", ".psd"
    };

    /// <summary>Extensions de vídeo</summary>
    public static readonly HashSet<string> VideoExtensions = new(StringComparer.OrdinalIgnoreCase)
    {
        ".mp4", ".mov", ".avi", ".mkv", ".m4v", ".webm", ".3gp", ".mts", ".m2ts"
    };

    /// <summary>Totes les extensions suportades</summary>
    public static readonly HashSet<string> AllExtensions = new(
        ImageExtensions
            .Concat(RawExtensions)
            .Concat(ModernExtensions)
            .Concat(VideoExtensions),
        StringComparer.OrdinalIgnoreCase);

    // === Propietats bàsiques ===

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

    /// <summary>Rotació del vídeo en graus (0, 90, 180, 270)</summary>
    public int VideoRotation { get; set; }

    // === Propietats de deduplicació ===

    /// <summary>Hash MD5 del fitxer complet</summary>
    public string? Md5Hash { get; set; }

    /// <summary>Hash perceptual (8x8 grayscale average hash)</summary>
    public ulong? PerceptualHash { get; set; }

    /// <summary>Fingerprint EXIF (SHA256 de datetime+camera+dimensions)</summary>
    public string? ExifFingerprint { get; set; }

    /// <summary>ID del grup de duplicats (prefix: md5-, phash-, exif-)</summary>
    public string? DuplicateGroupId
    {
        get => _duplicateGroupId;
        set => SetField(ref _duplicateGroupId, value);
    }

    // === Propietats GPS/Localització ===

    /// <summary>Latitud GPS des d'EXIF</summary>
    public double? GpsLatitude { get; set; }

    /// <summary>Longitud GPS des d'EXIF</summary>
    public double? GpsLongitude { get; set; }

    /// <summary>Localització geocodificada (ex: "Barcelona, Catalunya")</summary>
    public string? Location
    {
        get => _location;
        set => SetField(ref _location, value);
    }

    // === Propietats UI (observables) ===

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

    // === Propietats computades ===

    /// <summary>Indica si és un vídeo</summary>
    public bool IsVideo
    {
        get
        {
            var ext = System.IO.Path.GetExtension(FileName);
            return VideoExtensions.Contains(ext);
        }
    }

    /// <summary>Indica si és un format RAW</summary>
    public bool IsRaw
    {
        get
        {
            var ext = System.IO.Path.GetExtension(FileName);
            return RawExtensions.Contains(ext);
        }
    }

    /// <summary>Indica si és una imatge (no vídeo)</summary>
    public bool IsImage => !IsVideo;

    // === INotifyPropertyChanged ===

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
