using System.Collections.Concurrent;
using System.Globalization;
using System.IO;
using System.Text.RegularExpressions;
using System.Windows.Media.Imaging;
using iPhotoImporter.Models;
using MediaDevices;

namespace iPhotoImporter.Services;

/// <summary>
/// Servei per interactuar amb dispositius MTP (mòbils, càmeres)
/// a través de la llibreria MediaDevices.
/// Totes les operacions COM/WPD s'executen en un únic thread STA dedicat.
/// </summary>
public class DeviceService : IDisposable
{
    private static readonly string[] PhotoExtensions =
        [".jpg", ".jpeg", ".png", ".heic", ".heif", ".webp", ".bmp", ".gif", ".mp4", ".mov", ".avi", ".mkv"];

    private readonly BlockingCollection<Action> _workQueue = new();
    private readonly Thread _staThread;

    public DeviceService()
    {
        _staThread = new Thread(StaWorker)
        {
            IsBackground = true,
            Name = "MTP-STA"
        };
        _staThread.SetApartmentState(ApartmentState.STA);
        _staThread.Start();
    }

    private void StaWorker()
    {
        foreach (var action in _workQueue.GetConsumingEnumerable())
            action();
    }

    private Task<T> RunOnSta<T>(Func<T> func)
    {
        var tcs = new TaskCompletionSource<T>();
        _workQueue.Add(() =>
        {
            try { tcs.SetResult(func()); }
            catch (Exception ex) { tcs.SetException(ex); }
        });
        return tcs.Task;
    }

    private Task RunOnSta(Action action)
    {
        return RunOnSta(() => { action(); return true; });
    }

    /// <summary>
    /// Retorna la llista de dispositius MTP connectats.
    /// </summary>
    public Task<List<MediaDevice>> GetConnectedDevicesAsync()
    {
        return RunOnSta(() =>
        {
            var devices = MediaDevice.GetDevices().ToList();
            if (devices.Count == 0)
                throw new InvalidOperationException("No s'ha trobat cap dispositiu connectat.");
            return devices;
        });
    }

    /// <summary>
    /// Escaneja un dispositiu i reporta fotos/vídeos incrementalment via callback.
    /// Retorna el total de fotos trobades.
    /// </summary>
    public async Task<int> GetPhotosAsync(MediaDevice device, Action<PhotoItem> onPhotoFound,
        IProgress<(string folder, int scanned, int found)>? scanProgress = null,
        DateTime? minDate = null, DateTime? maxDate = null)
    {
        var photos = new List<PhotoItem>();
        int[] scannedCount = [0];

        await RunOnSta(() =>
        {
            EnsureConnected(device);
            var drives = device.GetDrives();

            foreach (var drive in drives)
            {
                if (!drive.IsReady) continue;
                ScanDirectory(device, drive.RootDirectory.FullName, photos, onPhotoFound,
                    scanProgress, minDate, maxDate, scannedCount);
            }
        });

        return photos.Count;
    }

    /// <summary>
    /// Copia les fotos seleccionades del dispositiu a la carpeta de destí.
    /// </summary>
    public async Task<int> CopyPhotosAsync(
        MediaDevice device,
        List<PhotoItem> photos,
        string destinationFolder,
        IProgress<(int current, int total, string fileName)>? progress = null)
    {
        if (photos.Count == 0) return 0;

        if (!Directory.Exists(destinationFolder))
            Directory.CreateDirectory(destinationFolder);

        var copied = 0;
        var total = photos.Count;

        for (var i = 0; i < total; i++)
        {
            var photo = photos[i];
            progress?.Report((i + 1, total, photo.FileName));

            var destPath = GetUniqueDestinationPath(destinationFolder, photo.FileName);

            try
            {
                await RunOnSta(() =>
                {
                    EnsureConnected(device);
                    using var fs = File.Create(destPath);
                    device.DownloadFile(photo.FullPath, fs);
                });
                copied++;
            }
            catch (IOException ex)
            {
                throw new IOException($"Error copiant '{photo.FileName}': {ex.Message}", ex);
            }
        }

        return copied;
    }

    /// <summary>
    /// Obté la miniatura d'una foto del dispositiu com a BitmapImage.
    /// </summary>
    public Task<BitmapImage?> GetThumbnailAsync(MediaDevice device, string fullPath)
    {
        return RunOnSta(() =>
        {
            EnsureConnected(device);

            try
            {
                using var ms = new MemoryStream();
                device.DownloadThumbnail(fullPath, ms);

                if (ms.Length == 0) return null;

                ms.Position = 0;
                var bitmap = new BitmapImage();
                bitmap.BeginInit();
                bitmap.CacheOption = BitmapCacheOption.OnLoad;
                bitmap.StreamSource = ms;
                bitmap.DecodePixelWidth = 120;
                bitmap.EndInit();
                bitmap.Freeze();
                return bitmap;
            }
            catch
            {
                return null;
            }
        });
    }

    private void ScanDirectory(MediaDevice device, string path, List<PhotoItem> results,
        Action<PhotoItem>? onPhotoFound, IProgress<(string folder, int scanned, int found)>? scanProgress,
        DateTime? minDate, DateTime? maxDate, int[] scannedCount)
    {
        try
        {
            var folderName = Path.GetFileName(path);

            // Extreure data de la carpeta (ex: "202602__" → febrer 2026)
            var folderDate = ParseDateFromFolderName(folderName);

            // Optimització: saltar carpetes senceres si el nom conté YYYYMM
            // i el mes és anterior al filtre (ex: "202103__" → març 2021)
            if (minDate.HasValue && CanSkipDirectoryByName(folderName, minDate.Value, maxDate))
            {
                scanProgress?.Report(($"[saltat] {folderName}", scannedCount[0], results.Count));
                return;
            }

            scanProgress?.Report((folderName, scannedCount[0], results.Count));

            var files = device.EnumerateFiles(path);
            foreach (var filePath in files)
            {
                var ext = Path.GetExtension(filePath).ToLowerInvariant();
                if (!PhotoExtensions.Contains(ext)) continue;

                scannedCount[0]++;

                try
                {
                    var info = device.GetFileInfo(filePath);
                    var name = info.Name;

                    // Prioritat de dates: nom fitxer > nom carpeta > MTP metadata
                    // (les dates MTP de l'iPhone sovint són incorrectes)
                    var date = ParseDateFromFileName(name)
                              ?? folderDate
                              ?? info.DateAuthored
                              ?? info.LastWriteTime;

                    // Filtrar per rang de dates (fotos sense data s'inclouen sempre)
                    if (date.HasValue && minDate.HasValue && date.Value < minDate.Value)
                        continue;
                    if (date.HasValue && maxDate.HasValue && date.Value > maxDate.Value)
                        continue;

                    var photo = new PhotoItem
                    {
                        FullPath = filePath,
                        FileName = name,
                        DateTaken = date,
                        SizeBytes = (long)info.Length,
                    };
                    results.Add(photo);
                    onPhotoFound?.Invoke(photo);
                }
                catch
                {
                    // Fitxer inaccessible, saltar
                }

                // Reportar progrés cada 100 fitxers escanejats
                if (scannedCount[0] % 100 == 0)
                    scanProgress?.Report((folderName, scannedCount[0], results.Count));
            }

            var dirs = device.EnumerateDirectories(path);
            foreach (var dir in dirs)
            {
                ScanDirectory(device, dir, results, onPhotoFound, scanProgress, minDate, maxDate, scannedCount);
            }
        }
        catch
        {
            // Directori inaccessible, saltar
        }
    }

    /// <summary>
    /// Extreu una data aproximada del nom d'una carpeta (ex: "202602__" → 1 febrer 2026).
    /// </summary>
    private static DateTime? ParseDateFromFolderName(string folderName)
    {
        var match = Regex.Match(folderName, @"(20\d{2})([-_]?)(\d{2})");
        if (!match.Success) return null;

        if (!int.TryParse(match.Groups[1].Value, out var year) ||
            !int.TryParse(match.Groups[3].Value, out var month))
            return null;

        if (month < 1 || month > 12) return null;

        return new DateTime(year, month, 1);
    }

    /// <summary>
    /// Determina si es pot saltar un directori sencer basant-se en el nom.
    /// Detecta patrons com "202103__", "2021_03", "202103" que indiquen any/mes.
    /// </summary>
    private static bool CanSkipDirectoryByName(string folderName, DateTime minDate, DateTime? maxDate)
    {
        // Patró YYYYMM al nom de la carpeta
        var match = Regex.Match(folderName, @"(20\d{2})([-_]?)(\d{2})");
        if (!match.Success) return false;

        if (!int.TryParse(match.Groups[1].Value, out var year) ||
            !int.TryParse(match.Groups[3].Value, out var month))
            return false;

        if (month < 1 || month > 12) return false;

        // Últim dia del mes de la carpeta
        var folderEnd = new DateTime(year, month, DateTime.DaysInMonth(year, month), 23, 59, 59);
        // Primer dia del mes de la carpeta
        var folderStart = new DateTime(year, month, 1);

        // Saltar si tota la carpeta és anterior al filtre mínim
        if (folderEnd < minDate)
            return true;

        // Saltar si tota la carpeta és posterior al filtre màxim
        if (maxDate.HasValue && folderStart > maxDate.Value)
            return true;

        return false;
    }

    /// <summary>
    /// Intenta extreure la data d'una foto a partir del nom del fitxer.
    /// Patrons suportats: IMG_20240315_123456, 20240315_123456, IMG_1234 (no date).
    /// </summary>
    private static DateTime? ParseDateFromFileName(string fileName)
    {
        // Patró: ...YYYYMMDD_HHMMSS... o ...YYYYMMDD-HHMMSS... o ...YYYY-MM-DD...
        var match = Regex.Match(fileName, @"(\d{4})([-_]?)(\d{2})\2(\d{2})[-_](\d{2})(\d{2})(\d{2})");
        if (match.Success &&
            int.TryParse(match.Groups[1].Value, out var y) &&
            int.TryParse(match.Groups[3].Value, out var m) &&
            int.TryParse(match.Groups[4].Value, out var d) &&
            int.TryParse(match.Groups[5].Value, out var hh) &&
            int.TryParse(match.Groups[6].Value, out var mm) &&
            int.TryParse(match.Groups[7].Value, out var ss) &&
            y >= 2000 && y <= 2100 && m >= 1 && m <= 12 && d >= 1 && d <= 31)
        {
            try { return new DateTime(y, m, d, hh, mm, ss); }
            catch { /* data invàlida */ }
        }

        // Patró més simple: ...YYYYMMDD... (sense hora)
        match = Regex.Match(fileName, @"(\d{4})([-_]?)(\d{2})\2(\d{2})");
        if (match.Success &&
            int.TryParse(match.Groups[1].Value, out y) &&
            int.TryParse(match.Groups[3].Value, out m) &&
            int.TryParse(match.Groups[4].Value, out d) &&
            y >= 2000 && y <= 2100 && m >= 1 && m <= 12 && d >= 1 && d <= 31)
        {
            try { return new DateTime(y, m, d); }
            catch { /* data invàlida */ }
        }

        return null;
    }

    private static void EnsureConnected(MediaDevice device)
    {
        if (device.IsConnected) return;

        try
        {
            device.Connect();
        }
        catch (Exception ex)
        {
            throw new InvalidOperationException(
                $"No s'ha pogut connectar al dispositiu '{device.FriendlyName}'. "
                + "Assegura't que està desbloquejat i autoritza l'accés.", ex);
        }
    }

    private static string GetUniqueDestinationPath(string folder, string fileName)
    {
        var destPath = Path.Combine(folder, fileName);
        if (!File.Exists(destPath)) return destPath;

        var name = Path.GetFileNameWithoutExtension(fileName);
        var ext = Path.GetExtension(fileName);
        var counter = 1;

        do
        {
            destPath = Path.Combine(folder, $"{name}_{counter}{ext}");
            counter++;
        } while (File.Exists(destPath));

        return destPath;
    }

    public void Dispose()
    {
        _workQueue.CompleteAdding();
        GC.SuppressFinalize(this);
    }
}
