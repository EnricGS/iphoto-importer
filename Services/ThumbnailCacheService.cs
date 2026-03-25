using System.Collections.Concurrent;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Windows.Media.Imaging;

namespace iPhotoImporter.Services;

/// <summary>
/// Servei de cache de miniatures persistent a disc.
/// Emmagatzema les miniatures com a JPEG al 85% de qualitat, 512px màxim.
/// </summary>
public class ThumbnailCacheService
{
    private readonly string _cacheFolder;
    private readonly ConcurrentDictionary<string, BitmapSource?> _memoryCache = new();

    /// <summary>Mida màxim de la miniatura en píxels</summary>
    public int ThumbnailMaxSize { get; set; } = 512;

    /// <summary>Qualitat JPEG (1-100)</summary>
    public int JpegQuality { get; set; } = 85;

    public ThumbnailCacheService()
    {
        // Carpeta de cache a AppData
        _cacheFolder = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "iPhotoImporter", "ThumbnailCache");

        Directory.CreateDirectory(_cacheFolder);
    }

    /// <summary>
    /// Obté una miniatura, primer de memòria, després de disc, i si no existeix la genera.
    /// </summary>
    public async Task<BitmapSource?> GetThumbnailAsync(string filePath, CancellationToken ct = default)
    {
        // 1. Cache en memòria
        if (_memoryCache.TryGetValue(filePath, out var cached))
            return cached;

        // 2. Cache a disc
        var cacheKey = GetCacheKey(filePath);
        var cachePath = Path.Combine(_cacheFolder, cacheKey + ".jpg");

        BitmapSource? thumbnail = null;

        if (File.Exists(cachePath))
        {
            thumbnail = await Task.Run(() => LoadFromDisk(cachePath), ct);
            if (thumbnail != null)
            {
                _memoryCache[filePath] = thumbnail;
                return thumbnail;
            }
        }

        // 3. Generar nova miniatura
        thumbnail = await Task.Run(() =>
        {
            ct.ThrowIfCancellationRequested();
            var thumb = FileService.GenerateThumbnail(filePath, ThumbnailMaxSize);
            if (thumb != null)
                SaveToDisk(thumb, cachePath);
            return thumb;
        }, ct);

        _memoryCache[filePath] = thumbnail;
        return thumbnail;
    }

    /// <summary>
    /// Neteja la cache en memòria (la cache a disc es manté).
    /// </summary>
    public void ClearMemoryCache()
    {
        _memoryCache.Clear();
    }

    /// <summary>
    /// Carrega una miniatura des del disc.
    /// </summary>
    private static BitmapSource? LoadFromDisk(string path)
    {
        try
        {
            var bitmap = new BitmapImage();
            bitmap.BeginInit();
            bitmap.CacheOption = BitmapCacheOption.OnLoad;
            bitmap.UriSource = new Uri(path, UriKind.Absolute);
            bitmap.EndInit();
            bitmap.Freeze();
            return bitmap;
        }
        catch
        {
            return null;
        }
    }

    /// <summary>
    /// Desa una miniatura a disc com a JPEG.
    /// </summary>
    private void SaveToDisk(BitmapSource source, string path)
    {
        try
        {
            var encoder = new JpegBitmapEncoder { QualityLevel = JpegQuality };
            encoder.Frames.Add(BitmapFrame.Create(source));

            using var fs = File.Create(path);
            encoder.Save(fs);
        }
        catch
        {
            // Si no es pot desar, no és crític
        }
    }

    /// <summary>
    /// Genera una clau de cache basada en el camí i la data de modificació.
    /// </summary>
    private static string GetCacheKey(string filePath)
    {
        var fileInfo = new FileInfo(filePath);
        var raw = $"{filePath}|{fileInfo.Length}|{fileInfo.LastWriteTimeUtc.Ticks}";
        var hash = SHA256.HashData(Encoding.UTF8.GetBytes(raw));
        return Convert.ToHexString(hash)[..32];
    }
}
