using System.Net;
using System.Net.Http;
using System.Net.Http.Json;
using System.Text.Json.Serialization;

namespace iPhotoImporter.Services;

/// <summary>
/// Client del device-code flow de Mirat (POST /api/desktop/*).
///
/// Flux:
///   1. <see cref="RequestDeviceCodeAsync"/> → retorna user_code (ABCD-1234) + device_code + URL
///   2. L'usuari obre <c>verification_url_complete</c> al navegador i autoritza
///   3. <see cref="PollForTokenAsync"/> fa polling fins rebre un access_token
///
/// L'access_token rebut és un token opac (prefix <c>mkd_</c>) que s'envia com
/// <c>Authorization: Bearer</c> a totes les crides posteriors. A partir d'aquí,
/// el servidor sap qui és l'usuari i a quin grup ha d'afegir les fotos.
///
/// Aquest client és deliberadament independent de <see cref="MiratService"/>
/// perquè s'utilitza abans que tinguem cap destí configurat (sense grup_id).
/// </summary>
public sealed class MiratDeviceCodeClient : IDisposable
{
    private readonly HttpClient _http;

    public MiratDeviceCodeClient(string baseUrl)
    {
        _http = new HttpClient
        {
            BaseAddress = new Uri(baseUrl.TrimEnd('/') + "/"),
            Timeout = TimeSpan.FromSeconds(30),
        };
    }

    /// <summary>
    /// Pas 1: obté un device_code + user_code del servidor. El user_code (format
    /// ABCD-1234) és el que l'usuari ha d'introduir a la pantalla web.
    /// </summary>
    public async Task<DeviceCodeResponse> RequestDeviceCodeAsync(
        string deviceName,
        CancellationToken ct = default)
    {
        var body = new { device_name = deviceName };
        var resp = await _http.PostAsJsonAsync("api/desktop/device-code", body, ct);
        resp.EnsureSuccessStatusCode();
        var result = await resp.Content.ReadFromJsonAsync<DeviceCodeResponse>(
            cancellationToken: ct);
        return result ?? throw new InvalidOperationException(
            "Resposta buida del servidor en crear device-code.");
    }

    /// <summary>
    /// Pas 2: polling fins que l'usuari autoritzi o caduqui el codi.
    ///
    /// Retorna el resultat final (<see cref="AuthorizationResult.Authorized"/>,
    /// <see cref="AuthorizationResult.Expired"/>, <see cref="AuthorizationResult.Revoked"/>
    /// o <see cref="AuthorizationResult.Cancelled"/>).
    /// </summary>
    /// <param name="deviceCode">El device_code rebut al pas 1.</param>
    /// <param name="intervalSeconds">Interval de polling (recomanat pel servidor).</param>
    /// <param name="expiresAt">Quan caduca el codi — limita la duració del polling.</param>
    /// <param name="onProgress">Callback opcional per mostrar "esperant..." a la UI.</param>
    /// <param name="ct">Cancel·lació (p.ex. l'usuari tanca el diàleg).</param>
    public async Task<AuthorizationResult> PollForTokenAsync(
        string deviceCode,
        int intervalSeconds,
        DateTimeOffset expiresAt,
        IProgress<PollStatus>? onProgress = null,
        CancellationToken ct = default)
    {
        var interval = TimeSpan.FromSeconds(Math.Max(intervalSeconds, 1));

        while (!ct.IsCancellationRequested)
        {
            if (DateTimeOffset.UtcNow >= expiresAt)
            {
                return AuthorizationResult.Expired();
            }

            HttpResponseMessage resp;
            try
            {
                resp = await _http.PostAsJsonAsync(
                    "api/desktop/token",
                    new { device_code = deviceCode },
                    ct);
            }
            catch (OperationCanceledException)
            {
                return AuthorizationResult.Cancelled();
            }
            catch (HttpRequestException)
            {
                // Error de xarxa transitori — reintenta després d'un interval
                onProgress?.Report(PollStatus.Pending);
                await DelaySafe(interval, ct);
                continue;
            }

            switch ((int)resp.StatusCode)
            {
                case 200:
                    // Autoritzada
                    var token = await resp.Content.ReadFromJsonAsync<TokenResponse>(
                        cancellationToken: ct);
                    if (token is null || string.IsNullOrEmpty(token.AccessToken))
                    {
                        // Resposta malformada — tractem com expirada per no bloquejar
                        return AuthorizationResult.Expired();
                    }
                    onProgress?.Report(PollStatus.Authorized);
                    return AuthorizationResult.Authorized(token);

                case 202:
                    // Pending — continuem polling
                    onProgress?.Report(PollStatus.Pending);
                    break;

                case 410:
                    // Expired o revoked
                    var body = await resp.Content.ReadFromJsonAsync<ErrorResponse>(
                        cancellationToken: ct);
                    if (body?.Status == "revoked")
                        return AuthorizationResult.Revoked();
                    return AuthorizationResult.Expired();

                case 429:
                    // Slow down — l'interval ja hauria de ser correcte, però esperem una
                    // mica més per estar segurs.
                    onProgress?.Report(PollStatus.Pending);
                    break;

                case 404:
                    // device_code desconegut — probablement mai emès o purgat. Aturem.
                    return AuthorizationResult.Expired();

                default:
                    // Error inesperat — tractem com a retry
                    onProgress?.Report(PollStatus.Pending);
                    break;
            }

            await DelaySafe(interval, ct);
        }

        return AuthorizationResult.Cancelled();
    }

    private static async Task DelaySafe(TimeSpan delay, CancellationToken ct)
    {
        try { await Task.Delay(delay, ct); }
        catch (OperationCanceledException) { /* propaga via while */ }
    }

    public void Dispose()
    {
        _http.Dispose();
    }
}

// ---- DTOs ----

public sealed record DeviceCodeResponse(
    [property: JsonPropertyName("device_code")] string DeviceCode,
    [property: JsonPropertyName("user_code")] string UserCode,
    [property: JsonPropertyName("verification_url")] string VerificationUrl,
    [property: JsonPropertyName("verification_url_complete")] string VerificationUrlComplete,
    [property: JsonPropertyName("expires_in")] int ExpiresIn,
    [property: JsonPropertyName("interval")] int Interval)
{
    public DateTimeOffset ExpiresAt => DateTimeOffset.UtcNow.AddSeconds(ExpiresIn);
}

public sealed record TokenResponse(
    [property: JsonPropertyName("status")] string Status,
    [property: JsonPropertyName("access_token")] string AccessToken,
    [property: JsonPropertyName("user")] TokenUser? User,
    [property: JsonPropertyName("grup")] TokenGrup? Grup);

public sealed record TokenUser(
    [property: JsonPropertyName("id")] string Id,
    [property: JsonPropertyName("name")] string? Name,
    [property: JsonPropertyName("email")] string? Email);

public sealed record TokenGrup(
    [property: JsonPropertyName("id")] string Id,
    [property: JsonPropertyName("nom")] string? Nom,
    [property: JsonPropertyName("slug")] string? Slug);

public sealed record ErrorResponse(
    [property: JsonPropertyName("status")] string? Status,
    [property: JsonPropertyName("error")] string? Error);

public enum PollStatus { Pending, Authorized }

public sealed class AuthorizationResult
{
    public enum Outcome { Authorized, Expired, Revoked, Cancelled }

    public Outcome Kind { get; init; }
    public TokenResponse? Token { get; init; }

    public static AuthorizationResult Authorized(TokenResponse token) =>
        new() { Kind = Outcome.Authorized, Token = token };
    public static AuthorizationResult Expired() => new() { Kind = Outcome.Expired };
    public static AuthorizationResult Revoked() => new() { Kind = Outcome.Revoked };
    public static AuthorizationResult Cancelled() => new() { Kind = Outcome.Cancelled };
}
