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
    // Client SENSE auth ni BaseAddress per als PUT a URLs presignades de MinIO. No pot
    // dur els nostres headers (Bearer/X-API-Key): la petició ja va signada a la URL i
    // MinIO rebutjaria capçaleres d'auth alienes. Timeout ample per a parts grans
    // (Traefik readTimeout del servidor és 1800s).
    private readonly HttpClient _presignedHttp;
    private readonly MiratDestination _dest;
    private readonly ThumbnailCacheService? _thumbCache;
    private static readonly JsonSerializerOptions _jsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };


    public MiratService(MiratDestination dest, ThumbnailCacheService? thumbCache = null)
    {
        _dest = dest;
        _thumbCache = thumbCache;
        _http = new HttpClient
        {
            BaseAddress = new Uri(dest.BaseUrl.TrimEnd('/') + "/"),
            Timeout = TimeSpan.FromMinutes(5),
        };
        // Prioritza l'access token (device-code flow). Mantenim X-API-Key com a
        // fallback per configuracions legacy creades abans del flow per-usuari.
        if (!string.IsNullOrEmpty(dest.AccessToken))
        {
            _http.DefaultRequestHeaders.Authorization =
                new AuthenticationHeaderValue("Bearer", dest.AccessToken);
        }
        else if (!string.IsNullOrEmpty(dest.ApiKey))
        {
            _http.DefaultRequestHeaders.Add("X-API-Key", dest.ApiKey);
        }

        _presignedHttp = new HttpClient { Timeout = TimeSpan.FromMinutes(30) };
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
        // Decidim vídeo per la llista AUTORITATIVA d'extensions (no pel MIME): així cap
        // vídeo (.mts/.m2ts/.ts/.3gp inclosos) s'escapa al camí presignat i acaba pujant
        // pel pod (→ 502/503 amb fitxers grans).
        var isVideo = PhotoItem.VideoExtensions.Contains(Path.GetExtension(photo.FullPath));
        byte[] thumbBytes;
        byte[] previewBytes;
        int width = 0;
        int height = 0;
        if (isVideo)
        {
            // Reaprofita la miniatura ja generada per la UI (Shell COM via
            // ThumbnailCacheService) i la reescala a 200px per al camp 'thumbnail'.
            // Si encara no està al cache, GetThumbnailBytesAsync la dispara.
            // No enviem 'preview' per a vídeos (el servidor l'accepta opcional
            // per a MIME video/* — fix server-side acd46d6 al repo mirat).
            thumbBytes = await GetVideoThumbnailFromCacheAsync(photo.FullPath, ct);
            previewBytes = Array.Empty<byte>();
        }
        else
        {
            (thumbBytes, previewBytes, width, height) = await Task.Run(
                () => GenerateThumbAndPreview(photo.FullPath), ct);
        }

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
        // GPS — del PhotoItem (poblat a l'escaneig) o, si no, extret del fitxer.
        // Sense això cap foto pujada amb iPhoto Manager arribava amb ubicació a Mirat.
        (double lat, double lon)? coords =
            (photo.GpsLatitude.HasValue && photo.GpsLongitude.HasValue)
                ? (photo.GpsLatitude.Value, photo.GpsLongitude.Value)
                : FileService.ExtractGpsLocation(photo.FullPath);
        if (coords.HasValue)
        {
            meta["latitud"] = coords.Value.lat;
            meta["longitud"] = coords.Value.lon;
        }
        if (!string.IsNullOrEmpty(photo.Location))
            meta["nom_lloc"] = photo.Location;

        // Vídeos: pujada MULTIPART presignada directa a MinIO (init → PUT de parts →
        // complete), evitant que el fitxer passi pel pod web (requestTimeout de Node →
        // 502) i sense dependre d'un sol timeout. Les fotos segueixen pel multipart-form.
        if (isVideo)
            return await UploadVideoPresignedAsync(photo, mime, thumbBytes, previewBytes, meta, progress, ct);

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

            // Thumbnail (opcional — Magick.NET no genera thumbnail per a vídeos
            // i retorna bytes buits. El servidor accepta uploads sense thumbnail
            // per a MIME video/*; per a imatges segueix sent obligatori al
            // servidor i hauria d'arribar sempre.)
            if (thumbBytes.Length > 0)
            {
                var thumbContent = new ByteArrayContent(thumbBytes);
                thumbContent.Headers.ContentType = new MediaTypeHeaderValue("image/jpeg");
                form.Add(thumbContent, "thumbnail", "thumbnail.jpg");
            }

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

    /// <summary>
    /// Puja un VÍDEO amb pujada MULTIPART presignada: demana URLs a
    /// /upload-init-multipart, puja el fitxer per PARTS directament a MinIO (cada part és
    /// un PUT presignat independent i reintentable), puja thumb/preview, i registra amb
    /// /upload-complete-multipart. Evita que el fitxer passi pel pod (502 del
    /// requestTimeout de Node); un error transitori (p.ex. 503 SlowDown del NAS) només
    /// costa tornar a pujar UNA part.
    /// </summary>
    private async Task<MiratUploadResult> UploadVideoPresignedAsync(
        PhotoItem photo, string mime, byte[] thumbBytes, byte[] previewBytes,
        Dictionary<string, object?> meta, IProgress<double>? progress, CancellationToken ct)
    {
        var hasThumb = thumbBytes.Length > 0;
        var hasPreview = previewBytes.Length > 0;

        long mida;
        try { mida = new FileInfo(photo.FullPath).Length; }
        catch { return MiratUploadResult.Fail("No s'ha pogut llegir la mida del fitxer"); }
        if (mida <= 0) return MiratUploadResult.Fail("El fitxer és buit");

        // 1. init-multipart — dedup + uploadId + URL presignada de cada part
        var initBody = new Dictionary<string, object?>
        {
            ["mime_type"] = mime,
            ["mida"] = mida,
            ["has_thumbnail"] = hasThumb,
            ["has_preview"] = hasPreview,
            ["grup_id"] = _dest.GrupId,
        };
        if (meta.TryGetValue("hash_fitxer", out var h) && h is string hs)
            initBody["hash_fitxer"] = hs;

        JsonDocument initDoc;
        try
        {
            initDoc = await PostJsonAsync("api/external/upload-init-multipart", initBody, ct);
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested) { throw; }
        catch (Exception ex) { return MiratUploadResult.Fail($"Error iniciant la pujada: {ex.Message}"); }

        using (initDoc)
        {
            var init = initDoc.RootElement;

            // Duplicat detectat pel servidor abans de pujar cap byte
            if (init.TryGetProperty("duplicat", out var dup) && dup.ValueKind == JsonValueKind.True
                && init.TryGetProperty("id", out var dupId))
                return MiratUploadResult.Ok(dupId.GetString() ?? "", duplicat: true);

            if (!init.TryGetProperty("fotoId", out var fotoIdEl) ||
                !init.TryGetProperty("uploadId", out var uploadIdEl) ||
                !init.TryGetProperty("partSize", out var partSizeEl) ||
                !init.TryGetProperty("parts", out var partsEl) || partsEl.ValueKind != JsonValueKind.Array)
                return MiratUploadResult.Fail("Resposta d'init inesperada");

            var fotoId = fotoIdEl.GetString() ?? "";
            var uploadId = uploadIdEl.GetString() ?? "";
            var partSize = partSizeEl.GetInt64();
            var parts = partsEl.EnumerateArray().ToList();
            if (partSize <= 0 || parts.Count == 0)
                return MiratUploadResult.Fail("Resposta d'init inesperada");

            // 2. PUT de cada PART (seqüencial: una escriptura gran alhora) llegint el tros
            //    corresponent del fitxer; captura l'ETag de cada part per al complete.
            var etags = new List<Dictionary<string, object>>();
            try
            {
                using var fs = new FileStream(photo.FullPath, FileMode.Open, FileAccess.Read, FileShare.Read);
                for (var i = 0; i < parts.Count; i++)
                {
                    ct.ThrowIfCancellationRequested();
                    var partNumber = parts[i].GetProperty("partNumber").GetInt32();
                    var url = parts[i].GetProperty("url").GetString();
                    if (string.IsNullOrEmpty(url))
                        return MiratUploadResult.Fail("Part invàlida a la resposta");

                    var offset = (partNumber - 1) * partSize;
                    var toRead = (int)Math.Min(partSize, mida - offset);
                    var chunk = new byte[toRead];
                    fs.Seek(offset, SeekOrigin.Begin);
                    await fs.ReadExactlyAsync(chunk, 0, toRead, ct);

                    // Les parts d'UploadPart NO van signades amb Content-Type → no l'enviem.
                    using var resp = await PutWithRetryAsync(url, chunk, contentType: null, ct,
                        $"part {partNumber}/{parts.Count}");
                    var etag = resp.Headers.TryGetValues("ETag", out var vals) ? vals.FirstOrDefault() : null;
                    if (string.IsNullOrEmpty(etag))
                        return MiratUploadResult.Fail($"Part {partNumber} sense ETag");
                    etags.Add(new Dictionary<string, object> { ["partNumber"] = partNumber, ["etag"] = etag });

                    progress?.Report(0.35 + 0.5 * (i + 1) / parts.Count);
                }
            }
            catch (OperationCanceledException) when (ct.IsCancellationRequested) { throw; }
            catch (Exception ex) { return MiratUploadResult.Fail($"Error pujant a l'emmagatzematge: {ex.Message}"); }

            // 2b. thumb + preview (PUT simple presignat)
            try
            {
                if (hasThumb && init.TryGetProperty("thumb_url", out var tu) && tu.ValueKind == JsonValueKind.String)
                    await PutPresignedAsync(tu.GetString()!, thumbBytes, "image/jpeg", ct);
                if (hasPreview && init.TryGetProperty("preview_url", out var pu) && pu.ValueKind == JsonValueKind.String)
                    await PutPresignedAsync(pu.GetString()!, previewBytes, "image/jpeg", ct);
            }
            catch (OperationCanceledException) when (ct.IsCancellationRequested) { throw; }
            catch (Exception ex) { return MiratUploadResult.Fail($"Error pujant la miniatura: {ex.Message}"); }

            // 3. complete-multipart — tanca el multipart (amb els ETags) i registra la foto
            var completeBody = new Dictionary<string, object?>
            {
                ["fotoId"] = fotoId,
                ["uploadId"] = uploadId,
                ["parts"] = etags,
                ["mime_type"] = mime,
                ["mida"] = mida,
                ["metadades"] = meta,
                ["has_thumbnail"] = hasThumb,
                ["has_preview"] = hasPreview,
                ["grup_id"] = _dest.GrupId,
            };
            if (!string.IsNullOrEmpty(_dest.AlbumId))
                completeBody["album_id"] = _dest.AlbumId;

            try
            {
                using var completeDoc = await PostJsonAsync("api/external/upload-complete-multipart", completeBody, ct);
                if (!completeDoc.RootElement.TryGetProperty("id", out var idEl))
                    return MiratUploadResult.Fail("Resposta de complete inesperada");
                progress?.Report(1.0);
                return MiratUploadResult.Ok(idEl.GetString() ?? "", duplicat: false);
            }
            catch (OperationCanceledException) when (ct.IsCancellationRequested) { throw; }
            catch (Exception ex) { return MiratUploadResult.Fail($"Error registrant la foto: {ex.Message}"); }
        }
    }

    /// <summary>
    /// POST amb body JSON + auth; retorna el JsonDocument de resposta (el crida el
    /// disposa). Llança si no és 2xx.
    /// </summary>
    private async Task<JsonDocument> PostJsonAsync(string path, object body, CancellationToken ct)
    {
        var json = JsonSerializer.Serialize(body, _jsonOptions);
        using var content = new StringContent(json, System.Text.Encoding.UTF8, "application/json");
        var resp = await _http.PostAsync(path, content, ct);
        var respBody = await resp.Content.ReadAsStringAsync(ct);
        if (!resp.IsSuccessStatusCode)
            throw new MiratHttpException($"HTTP {(int)resp.StatusCode}: {respBody}");
        return JsonDocument.Parse(respBody);
    }

    /// <summary>
    /// PUT a una URL presignada amb REINTENTS i backoff exponencial + jitter per a errors
    /// transitoris (5xx/429/xarxa). Cas típic: MinIO retorna 503 SlowDown. Els 4xx (error
    /// permanent) fallen immediatament. Retorna la resposta HTTP (per llegir l'ETag de les
    /// parts). <paramref name="contentType"/> null → no s'envia Content-Type (les parts
    /// d'UploadPart no la porten signada). Cada intent reconstrueix el contingut: un
    /// HttpContent només es pot enviar un cop.
    /// </summary>
    private async Task<HttpResponseMessage> PutWithRetryAsync(
        string url, byte[] data, string? contentType, CancellationToken ct, string label)
    {
        const int maxAttempts = 5;
        for (var attempt = 1; attempt <= maxAttempts; attempt++)
        {
            try
            {
                var content = new ByteArrayContent(data);
                if (contentType != null)
                    content.Headers.ContentType = new MediaTypeHeaderValue(contentType);
                var resp = await _presignedHttp.PutAsync(url, content, ct);
                if (resp.IsSuccessStatusCode)
                    return resp;

                var status = (int)resp.StatusCode;
                var respBody = await resp.Content.ReadAsStringAsync(ct);
                resp.Dispose();
                var retriable = status >= 500 || status == 429;
                if (!retriable || attempt == maxAttempts)
                    throw new MiratHttpException($"PUT {label} HTTP {status}: {respBody}");
                // retriable → cau al backoff
            }
            catch (MiratHttpException) { throw; }                          // 4xx permanent o últim intent
            catch (OperationCanceledException) when (ct.IsCancellationRequested) { throw; }  // cancel·lació d'usuari
            catch (Exception) when (attempt == maxAttempts) { throw; }     // xarxa/timeout a l'últim intent
            catch (Exception) { /* xarxa/timeout transitori → retry */ }

            // backoff exponencial amb jitter: ~1s, 2s, 4s, 8s (+0–500ms)
            var delayMs = (1000 << (attempt - 1)) + Random.Shared.Next(0, 500);
            await Task.Delay(delayMs, ct);
        }
        throw new MiratHttpException($"Esgotats els intents de PUT ({label})");
    }

    /// <summary>PUT simple presignat (thumb/preview): reusa PutWithRetryAsync i descarta la resposta.</summary>
    private async Task PutPresignedAsync(string url, byte[] data, string contentType, CancellationToken ct)
    {
        (await PutWithRetryAsync(url, data, contentType, ct, "fitxer")).Dispose();
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
    /// Obté la miniatura d'un vídeo del <see cref="ThumbnailCacheService"/> (que la
    /// genera via Shell COM si encara no està al cache) i la reescala a 200px JPEG
    /// q70 per enviar-la com a camp 'thumbnail'. Retorna bytes buits si no hi ha
    /// cache injectat o el vídeo no genera miniatura (l'upload continua sense
    /// thumbnail; el servidor accepta video/* sense aquest camp).
    /// </summary>
    private async Task<byte[]> GetVideoThumbnailFromCacheAsync(string path, CancellationToken ct)
    {
        if (_thumbCache == null)
            return Array.Empty<byte>();

        var cacheBytes = await _thumbCache.GetThumbnailBytesAsync(path, ct);
        if (cacheBytes == null || cacheBytes.Length == 0)
            return Array.Empty<byte>();

        try
        {
            using var image = new MagickImage(cacheBytes);
            image.Resize(new MagickGeometry(200, 200) { Greater = true });
            image.Format = MagickFormat.Jpeg;
            image.Quality = 70;
            image.Strip();
            return image.ToByteArray();
        }
        catch
        {
            return Array.Empty<byte>();
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
            ".3gp" => "video/3gpp",
            ".mts" or ".m2ts" or ".ts" => "video/mp2t",
            _ => "application/octet-stream",
        };
    }

    public void Dispose()
    {
        _http.Dispose();
        _presignedHttp.Dispose();
        GC.SuppressFinalize(this);
    }
}

/// <summary>
/// Error HTTP permanent (no reintentable) durant la pujada. Ens permet distingir, al
/// retry del PUT, un 4xx que hem llançat expressament d'un error de xarxa (que a .NET
/// també és HttpRequestException) i que sí volem reintentar.
/// </summary>
internal sealed class MiratHttpException : Exception
{
    public MiratHttpException(string message) : base(message) { }
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
