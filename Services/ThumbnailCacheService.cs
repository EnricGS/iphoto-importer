using System.Collections.Concurrent;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Windows.Media.Imaging;
using iPhotoImporter.Models;

namespace iPhotoImporter.Services;

/// <summary>
/// Servei de cache de miniatures persistent a disc.
/// Emmagatzema les miniatures com a JPEG al 85% de qualitat, 1024px màxim.
/// </summary>
public class ThumbnailCacheService
{
    private readonly string _cacheFolder;
    private readonly ConcurrentDictionary<string, BitmapSource?> _memoryCache = new();

    /// <summary>
    /// Versió del cache. S'inclou a la clau per invalidar entrades vellles
    /// quan es canvia la mida o el format. Les entrades antigues queden
    /// orfes al disc (es poden netejar manualment).
    /// </summary>
    private const string CacheVersion = "v2";

    /// <summary>Mida màxim de la miniatura en píxels</summary>
    public int ThumbnailMaxSize { get; set; } = 1024;

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

        // 3. Generar nova miniatura (fotos o vídeos)
        thumbnail = await Task.Run(() =>
        {
            ct.ThrowIfCancellationRequested();
            var ext = Path.GetExtension(filePath);
            var isVideo = PhotoItem.VideoExtensions.Contains(ext);
            var isRaw = PhotoItem.RawExtensions.Contains(ext)
                     || PhotoItem.ModernExtensions.Contains(ext)
                     || ext.Equals(".heic", StringComparison.OrdinalIgnoreCase)
                     || ext.Equals(".heif", StringComparison.OrdinalIgnoreCase);

            BitmapSource? thumb;
            if (isVideo)
            {
                // COM interop requereix thread STA
                BitmapSource? videoThumb = null;
                var t = new Thread(() =>
                {
                    videoThumb = FileService.GenerateVideoThumbnail(filePath, ThumbnailMaxSize);
                });
                t.SetApartmentState(ApartmentState.STA);
                t.Start();
                t.Join();
                thumb = videoThumb;
            }
            else if (isRaw)
            {
                thumb = FileService.GenerateRawThumbnail(filePath, ThumbnailMaxSize);
            }
            else
            {
                thumb = FileService.GenerateThumbnail(filePath, ThumbnailMaxSize);
            }

            if (thumb != null)
                SaveToDisk(thumb, cachePath);
            return thumb;
        }, ct);

        _memoryCache[filePath] = thumbnail;
        return thumbnail;
    }

    /// <summary>
    /// Retorna els bytes JPEG de la miniatura tal com estan desats a disc.
    /// Si encara no s'han generat, dispara la generació (via <see cref="GetThumbnailAsync"/>)
    /// i després llegeix el fitxer. Retorna <c>null</c> si no s'ha pogut generar
    /// (per exemple, vídeo amb format no suportat pel Shell).
    ///
    /// Ús previst: reaprofitar la miniatura ja cachejada per la UI quan cal pujar
    /// una foto/vídeo a un servei extern, evitant regenerar-la i sense afegir
    /// dependències extra a aquell servei.
    /// </summary>
    public async Task<byte[]?> GetThumbnailBytesAsync(string filePath, CancellationToken ct = default)
    {
        var cachePath = Path.Combine(_cacheFolder, GetCacheKey(filePath) + ".jpg");

        if (!File.Exists(cachePath))
        {
            // Força la generació (popula també el memory cache amb el BitmapSource).
            _ = await GetThumbnailAsync(filePath, ct);
            if (!File.Exists(cachePath))
                return null;
        }

        try
        {
            return await File.ReadAllBytesAsync(cachePath, ct);
        }
        catch
        {
            return null;
        }
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
        var raw = $"{CacheVersion}|{filePath}|{fileInfo.Length}|{fileInfo.LastWriteTimeUtc.Ticks}";
        var hash = SHA256.HashData(Encoding.UTF8.GetBytes(raw));
        return Convert.ToHexString(hash)[..32];
    }
}
