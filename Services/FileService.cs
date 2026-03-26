using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using iPhotoImporter.Models;

namespace iPhotoImporter.Services;

/// <summary>
/// Servei per gestionar fitxers locals: escanejar carpetes, generar miniatures,
/// carregar imatges a resolució completa, i operacions de fitxers (copiar, moure, eliminar).
/// </summary>
public class FileService
{
    /// <summary>Extensions d'imatge suportades</summary>
    private static readonly HashSet<string> ImageExtensions = new(StringComparer.OrdinalIgnoreCase)
    {
        ".jpg", ".jpeg", ".png", ".bmp", ".gif", ".webp", ".tiff", ".tif"
    };

    /// <summary>Extensions de vídeo suportades</summary>
    private static readonly HashSet<string> VideoExtensions = new(StringComparer.OrdinalIgnoreCase)
    {
        ".mp4", ".mov", ".avi", ".mkv"
    };

    /// <summary>Totes les extensions suportades</summary>
    public static readonly HashSet<string> AllExtensions = new(
        ImageExtensions.Concat(VideoExtensions), StringComparer.OrdinalIgnoreCase);

    /// <summary>
    /// Escaneja una carpeta local i retorna els fitxers d'imatge/vídeo trobats.
    /// </summary>
    public async Task<List<PhotoItem>> ScanFolderAsync(
        string folderPath,
        IProgress<(int scanned, int found, string currentFile)>? progress = null,
        CancellationToken ct = default)
    {
        var results = new List<PhotoItem>();
        var scanned = 0;

        await Task.Run(() =>
        {
            var dir = new DirectoryInfo(folderPath);
            if (!dir.Exists) return;

            // Escanejar recursivament
            foreach (var file in dir.EnumerateFiles("*.*", SearchOption.AllDirectories))
            {
                ct.ThrowIfCancellationRequested();

                if (!AllExtensions.Contains(file.Extension)) continue;
                scanned++;

                var photo = new PhotoItem
                {
                    FullPath = file.FullName,
                    FileName = file.Name,
                    DateTaken = file.LastWriteTime,
                    SizeBytes = file.Length,
                    IsLocal = true
                };

                results.Add(photo);

                if (scanned % 50 == 0)
                    progress?.Report((scanned, results.Count, file.Name));
            }
        }, ct);

        progress?.Report((scanned, results.Count, "Completat"));
        return results;
    }

    /// <summary>
    /// Genera una miniatura d'una imatge local amb la mida especificada.
    /// </summary>
    public static BitmapSource? GenerateThumbnail(string filePath, int maxPixelSize = 256)
    {
        try
        {
            var bitmap = new BitmapImage();
            bitmap.BeginInit();
            bitmap.CacheOption = BitmapCacheOption.OnLoad;
            bitmap.UriSource = new Uri(filePath, UriKind.Absolute);
            bitmap.DecodePixelWidth = maxPixelSize;
            bitmap.EndInit();
            bitmap.Freeze();
            return ApplyExifRotation(bitmap, filePath);
        }
        catch
        {
            return null;
        }
    }

    /// <summary>
    /// Carrega una imatge a resolució completa.
    /// </summary>
    public static BitmapSource? LoadFullImage(string filePath, int? maxPixelWidth = null)
    {
        try
        {
            var bitmap = new BitmapImage();
            bitmap.BeginInit();
            bitmap.CacheOption = BitmapCacheOption.OnLoad;
            bitmap.UriSource = new Uri(filePath, UriKind.Absolute);
            if (maxPixelWidth.HasValue)
                bitmap.DecodePixelWidth = maxPixelWidth.Value;
            bitmap.EndInit();
            bitmap.Freeze();
            return ApplyExifRotation(bitmap, filePath);
        }
        catch
        {
            return null;
        }
    }

    /// <summary>
    /// Llegeix l'orientació EXIF d'una imatge i aplica la rotació/flip corresponent.
    /// Retorna el bitmap original si no cal rotar o si no es pot llegir l'EXIF.
    /// </summary>
    private static BitmapSource ApplyExifRotation(BitmapSource source, string filePath)
    {
        try
        {
            using var stream = new FileStream(filePath, FileMode.Open, FileAccess.Read, FileShare.Read);
            var frame = BitmapFrame.Create(stream, BitmapCreateOptions.DelayCreation, BitmapCacheOption.None);
            var metadata = frame.Metadata as BitmapMetadata;
            if (metadata == null) return source;

            var orientationObj = metadata.GetQuery("System.Photo.Orientation")
                              ?? metadata.GetQuery("/app1/ifd/{ushort=274}");
            if (orientationObj == null) return source;

            var orientation = Convert.ToUInt16(orientationObj);

            Transform? transform = orientation switch
            {
                2 => new ScaleTransform(-1, 1),     // Flip horitzontal
                3 => new RotateTransform(180),       // Rotar 180°
                4 => new ScaleTransform(1, -1),      // Flip vertical
                5 => CombineTransforms(new RotateTransform(90), new ScaleTransform(-1, 1)),
                6 => new RotateTransform(90),        // Rotar 90° horari
                7 => CombineTransforms(new RotateTransform(270), new ScaleTransform(-1, 1)),
                8 => new RotateTransform(270),       // Rotar 270° horari
                _ => null
            };

            if (transform == null) return source;

            var rotated = new TransformedBitmap(source, transform);
            rotated.Freeze();
            return rotated;
        }
        catch
        {
            return source;
        }
    }

    private static Transform CombineTransforms(Transform t1, Transform t2)
    {
        var group = new TransformGroup();
        group.Children.Add(t1);
        group.Children.Add(t2);
        return group;
    }

    /// <summary>
    /// Copia fitxers a una carpeta de destí.
    /// </summary>
    public async Task<int> CopyFilesAsync(
        IList<PhotoItem> files,
        string destinationFolder,
        IProgress<(int current, int total, string fileName)>? progress = null,
        CancellationToken ct = default)
    {
        if (!Directory.Exists(destinationFolder))
            Directory.CreateDirectory(destinationFolder);

        var copied = 0;
        for (var i = 0; i < files.Count; i++)
        {
            ct.ThrowIfCancellationRequested();
            var file = files[i];
            progress?.Report((i + 1, files.Count, file.FileName));

            var destPath = GetUniqueDestinationPath(destinationFolder, file.FileName);
            await Task.Run(() => File.Copy(file.FullPath, destPath, false), ct);
            copied++;
        }
        return copied;
    }

    /// <summary>
    /// Mou fitxers a una carpeta de destí.
    /// </summary>
    public async Task<int> MoveFilesAsync(
        IList<PhotoItem> files,
        string destinationFolder,
        IProgress<(int current, int total, string fileName)>? progress = null,
        CancellationToken ct = default)
    {
        if (!Directory.Exists(destinationFolder))
            Directory.CreateDirectory(destinationFolder);

        var moved = 0;
        for (var i = 0; i < files.Count; i++)
        {
            ct.ThrowIfCancellationRequested();
            var file = files[i];
            progress?.Report((i + 1, files.Count, file.FileName));

            var destPath = GetUniqueDestinationPath(destinationFolder, file.FileName);
            await Task.Run(() => File.Move(file.FullPath, destPath), ct);
            moved++;
        }
        return moved;
    }

    /// <summary>
    /// Elimina fitxers (els envia a la paperera si és possible).
    /// </summary>
    public async Task<int> DeleteFilesAsync(
        IList<PhotoItem> files,
        IProgress<(int current, int total, string fileName)>? progress = null,
        CancellationToken ct = default)
    {
        var deleted = 0;
        for (var i = 0; i < files.Count; i++)
        {
            ct.ThrowIfCancellationRequested();
            var file = files[i];
            progress?.Report((i + 1, files.Count, file.FileName));

            await Task.Run(() =>
            {
                if (File.Exists(file.FullPath))
                    File.Delete(file.FullPath);
            }, ct);
            deleted++;
        }
        return deleted;
    }

    /// <summary>
    /// Genera un camí de destí únic per evitar sobreescriptures.
    /// </summary>
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
}
