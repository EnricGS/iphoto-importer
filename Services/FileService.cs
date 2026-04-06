using System.IO;
using System.Numerics;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using ImageMagick;
using iPhotoImporter.Models;

namespace iPhotoImporter.Services;

/// <summary>
/// Servei per gestionar fitxers locals: escanejar carpetes, generar miniatures,
/// carregar imatges a resolució completa, i operacions de fitxers (copiar, moure, eliminar).
/// </summary>
public class FileService
{
    // Extensions centralitzades a PhotoItem — usar PhotoItem.AllExtensions, etc.

    /// <summary>
    /// Escaneja una carpeta local i retorna els fitxers d'imatge/vídeo trobats.
    /// </summary>
    public async Task<List<PhotoItem>> ScanFolderAsync(
        string folderPath,
        bool recursive = true,
        IProgress<(int scanned, int found, string currentFile)>? progress = null,
        CancellationToken ct = default)
    {
        var results = new List<PhotoItem>();
        var scanned = 0;

        await Task.Run(() =>
        {
            var dir = new DirectoryInfo(folderPath);
            if (!dir.Exists) return;

            var searchOption = recursive ? SearchOption.AllDirectories : SearchOption.TopDirectoryOnly;
            foreach (var file in dir.EnumerateFiles("*.*", searchOption))
            {
                ct.ThrowIfCancellationRequested();

                if (!PhotoItem.AllExtensions.Contains(file.Extension)) continue;
                scanned++;

                var isVideo = PhotoItem.VideoExtensions.Contains(file.Extension);
                var photo = new PhotoItem
                {
                    FullPath = file.FullName,
                    FileName = file.Name,
                    DateTaken = file.LastWriteTime,
                    SizeBytes = file.Length,
                    IsLocal = true
                };

                // Llegir la rotació del vídeo durant l'escaneig
                if (isVideo)
                    photo.VideoRotation = GetVideoRotation(file.FullName);

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
            var rotation = GetExifRotation(filePath);
            var bitmap = new BitmapImage();
            bitmap.BeginInit();
            bitmap.CacheOption = BitmapCacheOption.OnLoad;
            bitmap.UriSource = new Uri(filePath, UriKind.Absolute);
            bitmap.DecodePixelWidth = maxPixelSize;
            bitmap.Rotation = rotation;
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
    /// Carrega una imatge a resolució completa.
    /// </summary>
    public static BitmapSource? LoadFullImage(string filePath, int? maxPixelWidth = null)
    {
        try
        {
            var rotation = GetExifRotation(filePath);
            var bitmap = new BitmapImage();
            bitmap.BeginInit();
            bitmap.CacheOption = BitmapCacheOption.OnLoad;
            bitmap.UriSource = new Uri(filePath, UriKind.Absolute);
            if (maxPixelWidth.HasValue)
                bitmap.DecodePixelWidth = maxPixelWidth.Value;
            bitmap.Rotation = rotation;
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
    /// Llegeix l'orientació EXIF directament dels bytes del fitxer JPEG.
    /// Retorna la rotació WPF corresponent. Molt més fiable que BitmapMetadata.
    /// </summary>
    private static Rotation GetExifRotation(string filePath)
    {
        try
        {
            using var stream = new FileStream(filePath, FileMode.Open, FileAccess.Read, FileShare.Read);
            // Llegim només els primers 64KB, suficient per a l'EXIF header
            var buffer = new byte[Math.Min(65536, stream.Length)];
            _ = stream.Read(buffer, 0, buffer.Length);

            // Buscar el marcador EXIF APP1 (0xFFE1)
            int offset = 0;
            if (buffer.Length < 4 || buffer[0] != 0xFF || buffer[1] != 0xD8) // No és JPEG
                return Rotation.Rotate0;

            offset = 2;
            while (offset < buffer.Length - 4)
            {
                if (buffer[offset] != 0xFF) break;
                byte marker = buffer[offset + 1];
                if (marker == 0xE1) // APP1 = EXIF
                {
                    offset += 2;
                    int segmentLen = (buffer[offset] << 8) | buffer[offset + 1];
                    offset += 2;

                    // Verificar "Exif\0\0"
                    if (offset + 6 > buffer.Length) return Rotation.Rotate0;
                    if (buffer[offset] != 0x45 || buffer[offset + 1] != 0x78 ||
                        buffer[offset + 2] != 0x69 || buffer[offset + 3] != 0x66)
                        return Rotation.Rotate0;

                    int tiffStart = offset + 6;
                    if (tiffStart + 8 > buffer.Length) return Rotation.Rotate0;

                    // Endianness
                    bool littleEndian = buffer[tiffStart] == 0x49; // "II"

                    int ReadUInt16(int pos)
                    {
                        if (pos + 2 > buffer.Length) return 0;
                        return littleEndian
                            ? buffer[pos] | (buffer[pos + 1] << 8)
                            : (buffer[pos] << 8) | buffer[pos + 1];
                    }

                    int ReadUInt32(int pos)
                    {
                        if (pos + 4 > buffer.Length) return 0;
                        return littleEndian
                            ? buffer[pos] | (buffer[pos + 1] << 8) | (buffer[pos + 2] << 16) | (buffer[pos + 3] << 24)
                            : (buffer[pos] << 24) | (buffer[pos + 1] << 16) | (buffer[pos + 2] << 8) | buffer[pos + 3];
                    }

                    int ifdOffset = ReadUInt32(tiffStart + 4);
                    int ifdPos = tiffStart + ifdOffset;
                    if (ifdPos + 2 > buffer.Length) return Rotation.Rotate0;

                    int entryCount = ReadUInt16(ifdPos);
                    ifdPos += 2;

                    for (int i = 0; i < entryCount; i++)
                    {
                        int entryPos = ifdPos + i * 12;
                        if (entryPos + 12 > buffer.Length) break;

                        int tag = ReadUInt16(entryPos);
                        if (tag == 0x0112) // Orientation tag
                        {
                            int value = ReadUInt16(entryPos + 8);
                            return value switch
                            {
                                3 => Rotation.Rotate180,
                                6 => Rotation.Rotate90,
                                8 => Rotation.Rotate270,
                                _ => Rotation.Rotate0
                            };
                        }
                    }
                    return Rotation.Rotate0;
                }

                // Saltar segment
                offset += 2;
                if (offset + 2 > buffer.Length) break;
                int len = (buffer[offset] << 8) | buffer[offset + 1];
                offset += len;
            }
        }
        catch { }
        return Rotation.Rotate0;
    }

    /// <summary>
    /// Llegeix la rotació d'un fitxer de vídeo MP4/MOV des de la matriu de transformació
    /// del track header (tkhd) dins l'estructura de boxes del fitxer.
    /// Retorna els graus de rotació (0, 90, 180, 270).
    /// </summary>
    public static int GetVideoRotation(string filePath)
    {
        try
        {
            using var stream = new FileStream(filePath, FileMode.Open, FileAccess.Read, FileShare.Read);
            // Llegim fins a 256KB per trobar el tkhd box
            var bufferSize = (int)Math.Min(262144, stream.Length);
            var buffer = new byte[bufferSize];
            _ = stream.Read(buffer, 0, buffer.Length);

            // Buscar el box 'tkhd' (track header) que conté la matriu de rotació
            // Format MP4: cada box té 4 bytes mida + 4 bytes tipus
            return FindTkhdRotation(buffer);
        }
        catch
        {
            return 0;
        }
    }

    /// <summary>
    /// Busca el box tkhd dins el buffer i extreu la rotació de la matriu de transformació.
    /// La matriu és 3x3 de fixed-point 16.16, situada a l'offset 40 (v0) o 48 (v1) del tkhd.
    /// </summary>
    private static int FindTkhdRotation(byte[] buffer)
    {
        // Buscar "tkhd" dins el buffer (pot estar anidat dins moov/trak)
        for (int i = 0; i < buffer.Length - 4; i++)
        {
            if (buffer[i] == (byte)'t' && buffer[i + 1] == (byte)'k' &&
                buffer[i + 2] == (byte)'h' && buffer[i + 3] == (byte)'d')
            {
                // El tipus està als bytes i-4..i-1 (mida) i i..i+3 (tipus)
                // Però aquí estem al tipus directament.
                // Versió del tkhd: byte a offset i+4
                int tkhdStart = i + 4; // Inici del contingut del tkhd (després del tipus)
                if (tkhdStart + 84 > buffer.Length) continue;

                byte version = buffer[tkhdStart];
                // La matriu comença a offset 40 (v0) o 52 (v1) des del tkhdStart
                int matrixOffset = tkhdStart + (version == 0 ? 40 : 52);
                if (matrixOffset + 36 > buffer.Length) continue;

                // La matriu és 3x3 de 32 bits (fixed-point 16.16)
                // a = matrix[0], b = matrix[1], c = matrix[3], d = matrix[4]
                // Rotació es dedueix de a i b
                int a = ReadBigEndianInt32(buffer, matrixOffset);        // matrix[0][0]
                int b = ReadBigEndianInt32(buffer, matrixOffset + 4);    // matrix[0][1]

                // Convertir de fixed-point 16.16 a double
                double aVal = a / 65536.0;
                double bVal = b / 65536.0;

                // Calcular l'angle de rotació
                double angle = Math.Atan2(bVal, aVal) * (180.0 / Math.PI);
                int rotation = ((int)Math.Round(angle) + 360) % 360;

                // Normalitzar a 0, 90, 180, 270
                if (rotation >= 45 && rotation < 135) return 90;
                if (rotation >= 135 && rotation < 225) return 180;
                if (rotation >= 225 && rotation < 315) return 270;
                return 0;
            }
        }
        return 0;
    }

    /// <summary>Llegeix un int32 big-endian des d'un buffer.</summary>
    private static int ReadBigEndianInt32(byte[] buffer, int offset)
    {
        return (buffer[offset] << 24) | (buffer[offset + 1] << 16) |
               (buffer[offset + 2] << 8) | buffer[offset + 3];
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
    /// Elimina fitxers enviant-los a la paperera de reciclatge de Windows.
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
                    SendToRecycleBin(file.FullPath);
            }, ct);
            deleted++;
        }
        return deleted;
    }

    /// <summary>
    /// Envia un fitxer a la paperera de reciclatge via SHFileOperation.
    /// </summary>
    private static void SendToRecycleBin(string filePath)
    {
        var fileOp = new SHFILEOPSTRUCT
        {
            wFunc = FO_DELETE,
            pFrom = filePath + '\0' + '\0', // Doble null-terminated
            fFlags = FOF_ALLOWUNDO | FOF_NOCONFIRMATION | FOF_NOERRORUI | FOF_SILENT
        };
        SHFileOperation(ref fileOp);
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern int SHFileOperation(ref SHFILEOPSTRUCT fileOp);

    private const int FO_DELETE = 0x0003;
    private const int FOF_ALLOWUNDO = 0x0040;
    private const int FOF_NOCONFIRMATION = 0x0010;
    private const int FOF_NOERRORUI = 0x0400;
    private const int FOF_SILENT = 0x0004;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct SHFILEOPSTRUCT
    {
        public IntPtr hwnd;
        public int wFunc;
        [MarshalAs(UnmanagedType.LPWStr)]
        public string pFrom;
        [MarshalAs(UnmanagedType.LPWStr)]
        public string? pTo;
        public ushort fFlags;
        [MarshalAs(UnmanagedType.Bool)]
        public bool fAnyOperationsAborted;
        public IntPtr hNameMappings;
        [MarshalAs(UnmanagedType.LPWStr)]
        public string? lpszProgressTitle;
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

    // === Suport RAW via Magick.NET ===

    /// <summary>
    /// Genera una miniatura d'un fitxer RAW/HEIC/AVIF/PSD.
    /// Primer intenta extreure el preview JPEG embegut (instant, estil Photo Mechanic).
    /// Si no n'hi ha, fa decode complet amb downscale.
    /// </summary>
    public static BitmapSource? GenerateRawThumbnail(string filePath, int maxPixelSize = 512)
    {
        try
        {
            // 1. Intentar extreure el preview JPEG embegut (molt ràpid)
            var embedded = ExtractEmbeddedPreview(filePath, maxPixelSize);
            if (embedded != null) return embedded;

            // 2. Fallback: decode complet amb downscale
            using var image = new MagickImage(filePath);
            image.AutoOrient();
            var geo = new MagickGeometry((uint)maxPixelSize, (uint)maxPixelSize)
            {
                IgnoreAspectRatio = false,
                Greater = true
            };
            image.Resize(geo);
            return ConvertToBitmapSource(image);
        }
        catch
        {
            return null;
        }
    }

    /// <summary>
    /// Extreu el preview JPEG embegut dins un fitxer RAW/HEIC.
    /// La majoria de càmeres incrusten un JPEG dins els RAW.
    /// </summary>
    public static BitmapSource? ExtractEmbeddedPreview(string filePath, int minSize = 200)
    {
        try
        {
            using var image = new MagickImage(filePath);
            var profile = image.GetExifProfile();
            var thumbData = profile?.CreateThumbnail();
            if (thumbData == null) return null;

            using var thumbStream = new MemoryStream(thumbData.ToByteArray());
            var bitmap = new BitmapImage();
            bitmap.BeginInit();
            bitmap.CacheOption = BitmapCacheOption.OnLoad;
            bitmap.StreamSource = thumbStream;
            bitmap.EndInit();
            bitmap.Freeze();

            // Verificar que el preview és prou gran
            if (bitmap.PixelWidth < minSize && bitmap.PixelHeight < minSize)
                return null;

            return bitmap;
        }
        catch
        {
            return null;
        }
    }

    /// <summary>
    /// Carrega una imatge RAW a resolució completa via Magick.NET.
    /// </summary>
    public static BitmapSource? LoadRawFullImage(string filePath, int? maxPixelWidth = null)
    {
        try
        {
            using var image = new MagickImage(filePath);
            image.AutoOrient();
            if (maxPixelWidth.HasValue && image.Width > maxPixelWidth.Value)
            {
                var geo = new MagickGeometry((uint)maxPixelWidth.Value, 0)
                {
                    IgnoreAspectRatio = false,
                    Greater = true
                };
                image.Resize(geo);
            }
            return ConvertToBitmapSource(image);
        }
        catch
        {
            return null;
        }
    }

    /// <summary>
    /// Carrega un quick preview RAW (nivell 2 piràmide, ~2048px).
    /// </summary>
    public static BitmapSource? LoadRawQuickPreview(string filePath, int maxSize = 2048)
    {
        try
        {
            // Primer intentar preview embegut gran
            var embedded = ExtractEmbeddedPreview(filePath, 400);
            if (embedded != null && embedded.PixelWidth >= 1000)
                return embedded;

            // Sinó, decode complet amb downscale
            using var image = new MagickImage(filePath);
            image.AutoOrient();
            if (image.Width > maxSize || image.Height > maxSize)
            {
                var geo = new MagickGeometry((uint)maxSize, (uint)maxSize)
                {
                    IgnoreAspectRatio = false,
                    Greater = true
                };
                image.Resize(geo);
            }
            return ConvertToBitmapSource(image);
        }
        catch
        {
            return null;
        }
    }

    /// <summary>
    /// Converteix un MagickImage a BitmapSource WPF.
    /// </summary>
    private static BitmapSource ConvertToBitmapSource(MagickImage image)
    {
        var bytes = image.ToByteArray(MagickFormat.Bmp);
        using var ms = new MemoryStream(bytes);
        var bitmap = new BitmapImage();
        bitmap.BeginInit();
        bitmap.CacheOption = BitmapCacheOption.OnLoad;
        bitmap.StreamSource = ms;
        bitmap.EndInit();
        bitmap.Freeze();
        return bitmap;
    }

    // === GPS ===

    /// <summary>
    /// Extreu les coordenades GPS des de les metadades EXIF d'un fitxer.
    /// </summary>
    public static (double lat, double lon)? ExtractGpsLocation(string filePath)
    {
        try
        {
            using var image = new MagickImage(filePath);
            var exif = image.GetExifProfile();
            if (exif == null) return null;

            var latRef = exif.GetValue(ExifTag.GPSLatitudeRef)?.Value;
            var latValues = exif.GetValue(ExifTag.GPSLatitude)?.Value;
            var lonRef = exif.GetValue(ExifTag.GPSLongitudeRef)?.Value;
            var lonValues = exif.GetValue(ExifTag.GPSLongitude)?.Value;

            if (latValues == null || lonValues == null || latValues.Length < 3 || lonValues.Length < 3)
                return null;

            static double ToDegrees(Rational[] values)
            {
                return values[0].ToDouble() + values[1].ToDouble() / 60.0 + values[2].ToDouble() / 3600.0;
            }

            var lat = ToDegrees(latValues);
            var lon = ToDegrees(lonValues);

            if (latRef == "S") lat = -lat;
            if (lonRef == "W") lon = -lon;

            if (lat == 0 && lon == 0) return null;
            return (lat, lon);
        }
        catch { return null; }
    }

    // === Deduplicació: hashing ===

    /// <summary>
    /// Computa el hash MD5 d'un fitxer (per chunks de 64KB per eficiència).
    /// </summary>
    public static string? ComputeMD5(string filePath)
    {
        try
        {
            using var stream = new FileStream(filePath, FileMode.Open, FileAccess.Read, FileShare.Read, 65536);
            var hash = MD5.HashData(stream);
            return Convert.ToHexString(hash);
        }
        catch { return null; }
    }

    /// <summary>
    /// Computa un hash perceptual (average hash 8x8 grayscale, 64 bits).
    /// Dues imatges amb Hamming distance ≤ 5 es consideren duplicats visuals.
    /// </summary>
    public static ulong? ComputePerceptualHash(string filePath)
    {
        try
        {
            var ext = Path.GetExtension(filePath);
            bool needsMagick = PhotoItem.RawExtensions.Contains(ext)
                            || PhotoItem.ModernExtensions.Contains(ext)
                            || ext.Equals(".heic", StringComparison.OrdinalIgnoreCase)
                            || ext.Equals(".heif", StringComparison.OrdinalIgnoreCase);

            if (needsMagick)
            {
                using var image = new MagickImage(filePath);
                image.Resize(8, 8);
                image.ColorSpace = ColorSpace.Gray;
                var bytes = image.ToByteArray(MagickFormat.Gray);
                if (bytes.Length < 64) return null;
                return ComputeAverageHash(bytes);
            }

            // WPF decode directe per formats estàndard (més ràpid)
            var bitmap = new BitmapImage();
            bitmap.BeginInit();
            bitmap.CacheOption = BitmapCacheOption.OnLoad;
            bitmap.UriSource = new Uri(filePath, UriKind.Absolute);
            bitmap.DecodePixelWidth = 8;
            bitmap.DecodePixelHeight = 8;
            bitmap.EndInit();
            bitmap.Freeze();

            // Convertir a grayscale
            var gray = new FormatConvertedBitmap(bitmap, PixelFormats.Gray8, null, 0);
            gray.Freeze();
            var pixels = new byte[64];
            gray.CopyPixels(pixels, 8, 0);
            return ComputeAverageHash(pixels);
        }
        catch { return null; }
    }

    /// <summary>
    /// Computa l'average hash a partir de 64 bytes de grayscale.
    /// </summary>
    private static ulong ComputeAverageHash(byte[] pixels)
    {
        // Calcular la mitjana
        long sum = 0;
        var count = Math.Min(pixels.Length, 64);
        for (var i = 0; i < count; i++)
            sum += pixels[i];
        var avg = sum / count;

        // Generar hash: 1 si per sobre la mitjana, 0 si per sota
        ulong hash = 0;
        for (var i = 0; i < count; i++)
        {
            if (pixels[i] >= avg)
                hash |= 1UL << i;
        }
        return hash;
    }

    /// <summary>
    /// Computa un fingerprint EXIF: SHA256 de (DateTimeOriginal|Make|Model|Width|Height).
    /// </summary>
    public static string? ComputeExifFingerprint(string filePath)
    {
        try
        {
            using var image = new MagickImage(filePath);
            var exif = image.GetExifProfile();
            if (exif == null) return null;

            var dateTime = exif.GetValue(ExifTag.DateTimeOriginal)?.Value
                        ?? exif.GetValue(ExifTag.DateTime)?.Value;
            var make = exif.GetValue(ExifTag.Make)?.Value;
            var model = exif.GetValue(ExifTag.Model)?.Value;
            var width = image.Width;
            var height = image.Height;

            if (dateTime == null) return null;

            var raw = $"{dateTime}|{make}|{model}|{width}|{height}";
            var hash = SHA256.HashData(Encoding.UTF8.GetBytes(raw));
            return Convert.ToHexString(hash)[..32];
        }
        catch { return null; }
    }

    /// <summary>
    /// Distància Hamming entre dos hashes perceptuals.
    /// </summary>
    public static int HammingDistance(ulong a, ulong b)
        => BitOperations.PopCount(a ^ b);

    // === Miniatures de vídeo via Windows Shell (IShellItemImageFactory) ===

    /// <summary>
    /// Genera una miniatura d'un fitxer de vídeo usant la API de Windows Shell.
    /// Funciona sense dependències externes per a qualsevol format suportat per Windows.
    /// </summary>
    public static BitmapSource? GenerateVideoThumbnail(string filePath, int maxPixelSize = 256)
    {
        try
        {
            var hr = SHCreateItemFromParsingName(filePath, IntPtr.Zero,
                typeof(IShellItemImageFactory).GUID, out var factory);
            if (hr != 0 || factory == null) return null;

            try
            {
                var size = new NativeSize { Width = maxPixelSize, Height = maxPixelSize };
                hr = factory.GetImage(size, SIIGBF.SIIGBF_THUMBNAILONLY | SIIGBF.SIIGBF_BIGGERSIZEOK, out var hBitmap);

                // Si no hi ha thumbnail precalculat, provar amb resizeToFit
                if (hr != 0)
                    hr = factory.GetImage(size, SIIGBF.SIIGBF_RESIZETOFIT, out hBitmap);

                if (hr != 0) return null;

                try
                {
                    var source = Imaging.CreateBitmapSourceFromHBitmap(
                        hBitmap, IntPtr.Zero, Int32Rect.Empty,
                        BitmapSizeOptions.FromEmptyOptions());
                    source.Freeze();
                    return source;
                }
                finally
                {
                    DeleteObject(hBitmap);
                }
            }
            finally
            {
                Marshal.ReleaseComObject(factory);
            }
        }
        catch
        {
            return null;
        }
    }

    // COM Interop per IShellItemImageFactory

    [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = true)]
    private static extern int SHCreateItemFromParsingName(
        string pszPath, IntPtr pbc, [In] Guid riid, [MarshalAs(UnmanagedType.Interface)] out IShellItemImageFactory ppv);

    [DllImport("gdi32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DeleteObject(IntPtr hObject);

    [ComImport]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    [Guid("bcc18b79-ba16-442f-80c4-8a59c30c463b")]
    private interface IShellItemImageFactory
    {
        [PreserveSig]
        int GetImage(NativeSize size, SIIGBF flags, out IntPtr phbm);
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeSize
    {
        public int Width;
        public int Height;
    }

    [Flags]
    private enum SIIGBF
    {
        SIIGBF_RESIZETOFIT = 0x00000000,
        SIIGBF_BIGGERSIZEOK = 0x00000001,
        SIIGBF_THUMBNAILONLY = 0x00000004,
    }
}
