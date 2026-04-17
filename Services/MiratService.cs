using System.IO;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Windows.Media.Imaging;
using ImageMagick;
using iPhotoImporter.Models;

namespace iPhotoImporter.Services;

/// <summary>
/// Client HTTP per comunicar-se amb l'API externa de Mirat (/api/external/*).
///
/// - Llista grups i àlbums amb una API key.
/// - Puja fotos amb una sola crida multipart (foto + thumbnail + preview + metadades).
///
/// Ús típic:
///   var svc = new MiratService(dest);
///   var grups = await svc.ListGroupsAsync();
///   var result = await svc.UploadPhotoAsync(photo, progress, ct);
/// </summary>
public class MiratService : IDisposable
{
    private readonly HttpClient _http;
    private readonly MiratDestination _dest;
    private static readonly JsonSerializerOptions _jsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };


    public MiratService(MiratDestination dest)
    {
        _dest = dest;
        _http = new HttpClient
        {
            BaseAddress = new Uri(dest.BaseUrl.TrimEnd('/') + "/"),
            Timeout = TimeSpan.FromMinutes(5),
        };
        _http.DefaultRequestHeaders.Add("X-API-Key", dest.ApiKey);
    }

    /// <summary>Comprova que BaseUrl + ApiKey funcionen (fa GET /api/external/grups).</summary>
    public async Task<bool> TestConnectionAsync(CancellationToken ct = default)
    {
        try
        {
            var resp = await _http.GetAsync("api/external/grups", ct);
            return resp.IsSuccessStatusCode;
        }
        catch
        {
            return false;
        }
    }

    public async Task<List<MiratGrup>> ListGroupsAsync(CancellationToken ct = default)
    {
        var resp = await _http.GetAsync("api/external/grups", ct);
        resp.EnsureSuccessStatusCode();
        return await resp.Content.ReadFromJsonAsync<List<MiratGrup>>(_jsonOptions, ct) ?? [];
    }

    public async Task<List<MiratAlbum>> ListAlbumsAsync(string grupId, CancellationToken ct = default)
    {
        var resp = await _http.GetAsync($"api/external/albums?grup_id={Uri.EscapeDataString(grupId)}", ct);
        resp.EnsureSuccessStatusCode();
        return await resp.Content.ReadFromJsonAsync<List<MiratAlbum>>(_jsonOptions, ct) ?? [];
    }

    /// <summary>
    /// Puja una foto a Mirat en una sola crida. Genera thumbnail + preview si cal,
    /// calcula SHA-256, construeix metadades, envia multipart.
    /// </summary>
    public async Task<MiratUploadResult> UploadPhotoAsync(
        PhotoItem photo,
        IProgress<double>? progress = null,
        CancellationToken ct = default)
    {
        if (!File.Exists(photo.FullPath))
            return MiratUploadResult.Fail("El fitxer ja no existeix localment");

        var mime = MimeTypeFromExtension(Path.GetExtension(photo.FullPath));

        // 1. SHA-256 del fitxer complet — Mirat dedupa per hash_fitxer
        progress?.Report(0.05);
        var sha256 = await ComputeSha256Async(photo.FullPath, ct);

        // 2. Generar thumbnail 200px JPEG i preview 2048px JPEG
        progress?.Report(0.20);
        var (thumbBytes, previewBytes, width, height) = await Task.Run(
            () => GenerateThumbAndPreview(photo.FullPath), ct);

        // 3. Metadades
        var meta = new Dictionary<string, object?>
        {
            ["mime_type"] = mime,
            ["hash_fitxer"] = sha256,
        };
        if (width > 0) meta["amplada"] = width;
        if (height > 0) meta["alcada"] = height;
        if (photo.DateTaken.HasValue)
            meta["data_original"] = photo.DateTaken.Value.ToUniversalTime().ToString("o");
        if (_dest.PujatPer != null)
            meta["pujat_per"] = _dest.PujatPer;
        // TODO: afegir GPS i dades càmera quan PhotoItem les exposi

        // 4. Multipart
        progress?.Report(0.35);
        using var form = new MultipartFormDataContent();

        // BUG .NET: MultipartFormDataContent afegeix cometes dobles al boundary
        // ("boundary=\"...\"") i alguns parsers (Next.js/undici) les rebutgen amb
        // "Failed to parse body as FormData". Cal treure-les manualment.
        var ctParam = form.Headers.ContentType?.Parameters
            .FirstOrDefault(p => p.Name == "boundary");
        if (ctParam?.Value != null)
            ctParam.Value = ctParam.Value.Trim('"');

        form.Add(new StringContent(_dest.GrupId), "grup_id");
        if (!string.IsNullOrEmpty(_dest.AlbumId))
            form.Add(new StringContent(_dest.AlbumId), "album_id");

        var metaJson = JsonSerializer.Serialize(meta, _jsonOptions);
        form.Add(new StringContent(metaJson), "metadades");

        // Original
        var fotoStream = new FileStream(photo.FullPath, FileMode.Open, FileAccess.Read, FileShare.Read);
        try
        {
            var fotoContent = new StreamContent(fotoStream);
            fotoContent.Headers.ContentType = new MediaTypeHeaderValue(mime);
            // Nom de fitxer ASCII-safe — undici/fetch de Next.js peta amb noms amb espais
            // o caràcters no-ASCII si no estan codificats amb RFC 5987 (filename*=utf-8''...).
            var safeName = AsciiSafe(Path.GetFileName(photo.FullPath));
            form.Add(fotoContent, "foto", safeName);

            // Thumbnail (sempre JPEG)
            var thumbContent = new ByteArrayContent(thumbBytes);
            thumbContent.Headers.ContentType = new MediaTypeHeaderValue("image/jpeg");
            form.Add(thumbContent, "thumbnail", "thumbnail.jpg");

            // Preview (opcional si falla la generació)
            if (previewBytes.Length > 0)
            {
                var prevContent = new ByteArrayContent(previewBytes);
                prevContent.Headers.ContentType = new MediaTypeHeaderValue("image/jpeg");
                form.Add(prevContent, "preview", "preview.jpg");
            }

            progress?.Report(0.50);
            // Materialitzar el buffer: sense això, .NET pot usar Transfer-Encoding:
            // chunked i alguns parsers HTTP/2 el gestionen malament.
            await form.LoadIntoBufferAsync();

            HttpResponseMessage resp;
            try
            {
                resp = await _http.PostAsync("api/external/upload", form, ct);
            }
            catch (Exception ex)
            {
                return MiratUploadResult.Fail($"Error de xarxa: {ex.Message}");
            }
            progress?.Report(0.95);

            var body = await resp.Content.ReadAsStringAsync(ct);
            if (!resp.IsSuccessStatusCode)
                return MiratUploadResult.Fail($"HTTP {(int)resp.StatusCode}: {body}");

            using var doc = JsonDocument.Parse(body);
            var id = doc.RootElement.GetProperty("id").GetString() ?? "";
            var duplicat = doc.RootElement.TryGetProperty("duplicat", out var d) && d.GetBoolean();

            progress?.Report(1.0);
            return MiratUploadResult.Ok(id, duplicat);
        }
        finally
        {
            fotoStream.Dispose();
        }
    }

    // ---- helpers ----

    private static async Task<string> ComputeSha256Async(string path, CancellationToken ct)
    {
        using var sha = SHA256.Create();
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read, 65536, useAsync: true);
        var hash = await sha.ComputeHashAsync(stream, ct);
        return Convert.ToHexString(hash).ToLowerInvariant();
    }

    /// <summary>
    /// Genera thumbnail 200px q70 i preview 2048px q80 via Magick.NET.
    /// Retorna dimensions de l'original (amplada/alçada). Si falla la conversió,
    /// retorna arrays buits (l'upload pot continuar sense preview).
    /// </summary>
    private static (byte[] thumb, byte[] preview, int width, int height) GenerateThumbAndPreview(string path)
    {
        try
        {
            using var image = new MagickImage(path);
            var width = (int)image.Width;
            var height = (int)image.Height;

            // Respectar EXIF orientation
            image.AutoOrient();

            // Preview 2048px long-side
            byte[] previewBytes;
            using (var preview = image.Clone())
            {
                preview.Resize(new MagickGeometry(2048, 2048) { Greater = true });
                preview.Format = MagickFormat.Jpeg;
                preview.Quality = 80;
                preview.Strip(); // treu EXIF per reduir mida
                previewBytes = preview.ToByteArray();
            }

            // Thumbnail 200px
            byte[] thumbBytes;
            using (var thumb = image.Clone())
            {
                thumb.Resize(new MagickGeometry(200, 200) { Greater = true });
                thumb.Format = MagickFormat.Jpeg;
                thumb.Quality = 70;
                thumb.Strip();
                thumbBytes = thumb.ToByteArray();
            }

            return (thumbBytes, previewBytes, width, height);
        }
        catch
        {
            return (Array.Empty<byte>(), Array.Empty<byte>(), 0, 0);
        }
    }

    /// <summary>
    /// Converteix un nom de fitxer a ASCII-safe per al filename del Content-Disposition.
    /// Substitueix espais i caràcters no-ASCII per '_'.
    /// </summary>
    private static string AsciiSafe(string name)
    {
        var sb = new System.Text.StringBuilder(name.Length);
        foreach (var c in name)
        {
            if (c is (>= '0' and <= '9') or (>= 'A' and <= 'Z') or (>= 'a' and <= 'z')
                or '.' or '-' or '_')
                sb.Append(c);
            else
                sb.Append('_');
        }
        return sb.Length == 0 ? "file.bin" : sb.ToString();
    }

    private static string MimeTypeFromExtension(string ext)
    {
        ext = ext.ToLowerInvariant();
        return ext switch
        {
            ".jpg" or ".jpeg" => "image/jpeg",
            ".png" => "image/png",
            ".webp" => "image/webp",
            ".heic" => "image/heic",
            ".heif" => "image/heif",
            ".avif" => "image/avif",
            ".tif" or ".tiff" => "image/tiff",
            ".dng" => "image/x-adobe-dng",
            ".cr2" => "image/x-canon-cr2",
            ".cr3" => "image/x-canon-cr3",
            ".nef" => "image/x-nikon-nef",
            ".arw" => "image/x-sony-arw",
            ".raf" => "image/x-fuji-raf",
            ".mp4" or ".m4v" => "video/mp4",
            ".mov" => "video/quicktime",
            ".avi" => "video/x-msvideo",
            ".mkv" => "video/x-matroska",
            ".webm" => "video/webm",
            _ => "application/octet-stream",
        };
    }

    public void Dispose()
    {
        _http.Dispose();
        GC.SuppressFinalize(this);
    }
}

// ---- DTOs ----

public record MiratGrup(string Id, string Nom, string? Slug);

public record MiratAlbum(string Id, string Nom, string? Descripcio, bool Privat);

public class MiratUploadResult
{
    public bool Success { get; init; }
    public string? FotoId { get; init; }
    public bool Duplicat { get; init; }
    public string? ErrorMessage { get; init; }

    public static MiratUploadResult Ok(string id, bool duplicat) =>
        new() { Success = true, FotoId = id, Duplicat = duplicat };

    public static MiratUploadResult Fail(string msg) =>
        new() { Success = false, ErrorMessage = msg };
}
