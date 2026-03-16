using System.Collections.Concurrent;
using System.IO;
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
    /// Escaneja un dispositiu i retorna les fotos/vídeos ordenats per data.
    /// </summary>
    public Task<List<PhotoItem>> GetPhotosAsync(MediaDevice device)
    {
        return RunOnSta(() =>
        {
            EnsureConnected(device);

            var photos = new List<PhotoItem>();
            var drives = device.GetDrives();

            foreach (var drive in drives)
            {
                if (!drive.IsReady) continue;
                ScanDirectory(device, drive.RootDirectory.FullName, photos);
            }

            return photos.OrderByDescending(p => p.DateTaken).ToList();
        });
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

    private void ScanDirectory(MediaDevice device, string path, List<PhotoItem> results)
    {
        try
        {
            var files = device.EnumerateFiles(path);
            foreach (var filePath in files)
            {
                var ext = Path.GetExtension(filePath).ToLowerInvariant();
                if (!PhotoExtensions.Contains(ext)) continue;

                try
                {
                    var info = device.GetFileInfo(filePath);
                    results.Add(new PhotoItem
                    {
                        FullPath = filePath,
                        FileName = info.Name,
                        DateTaken = info.DateAuthored ?? info.LastWriteTime,
                        SizeBytes = (long)info.Length,
                    });
                }
                catch
                {
                    // Fitxer inaccessible, saltar
                }
            }

            var dirs = device.EnumerateDirectories(path);
            foreach (var dir in dirs)
            {
                ScanDirectory(device, dir, results);
            }
        }
        catch
        {
            // Directori inaccessible, saltar
        }
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
