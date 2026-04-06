using System.Collections.Concurrent;
using System.Net.Http;
using System.Text.Json;

namespace iPhotoImporter.Services;

/// <summary>
/// Servei de geocodificació inversa via Nominatim (OpenStreetMap).
/// Converteix coordenades GPS a noms de lloc en català.
/// </summary>
public class GeocodingService : IDisposable
{
    private readonly HttpClient _http;
    private readonly ConcurrentDictionary<string, string> _cache = new();
    private readonly SemaphoreSlim _rateLimiter = new(1, 1);
    private static readonly TimeSpan RateLimit = TimeSpan.FromMilliseconds(1100);

    // Províncies de Catalunya
    private static readonly HashSet<string> CatalunyaProvinces = new(StringComparer.OrdinalIgnoreCase)
    {
        "Barcelona", "Girona", "Lleida", "Tarragona"
    };

    public GeocodingService()
    {
        _http = new HttpClient();
        _http.DefaultRequestHeaders.Add("User-Agent", "iPhotoManager/1.0");
        _http.DefaultRequestHeaders.Add("Accept-Language", "ca");
    }

    /// <summary>
    /// Geocodifica unes coordenades a un nom de lloc.
    /// Retorna "Localitat, Regió" o null si no es pot geocodificar.
    /// </summary>
    public async Task<string?> ReverseGeocodeAsync(double lat, double lon, CancellationToken ct = default)
    {
        // Arrodonir coordenades per cache (~100m de precisió)
        var key = $"{Math.Round(lat, 3):F3},{Math.Round(lon, 3):F3}";
        if (_cache.TryGetValue(key, out var cached))
            return cached;

        await _rateLimiter.WaitAsync(ct);
        try
        {
            // Rate limit: esperar entre crides
            await Task.Delay(RateLimit, ct);

            var url = $"https://nominatim.openstreetmap.org/reverse?format=json&lat={lat:F6}&lon={lon:F6}&zoom=14&addressdetails=1&accept-language=ca";
            var response = await _http.GetStringAsync(url, ct);
            var doc = JsonDocument.Parse(response);

            if (!doc.RootElement.TryGetProperty("address", out var address))
                return null;

            var city = GetJsonString(address, "city")
                    ?? GetJsonString(address, "town")
                    ?? GetJsonString(address, "village")
                    ?? GetJsonString(address, "municipality");

            var state = GetJsonString(address, "state");
            var province = GetJsonString(address, "province")
                        ?? GetJsonString(address, "county");
            var country = GetJsonString(address, "country_code");

            // Regla especial Catalunya: si és Espanya i província catalana
            string? region;
            if (country == "es" && province != null && CatalunyaProvinces.Contains(province))
                region = "Catalunya";
            else
                region = state;

            string? result = null;
            if (city != null && region != null)
                result = $"{city}, {region}";
            else if (city != null)
                result = city;
            else if (region != null)
                result = region;

            if (result != null)
                _cache[key] = result;

            return result;
        }
        catch
        {
            return null;
        }
        finally
        {
            _rateLimiter.Release();
        }
    }

    private static string? GetJsonString(JsonElement element, string property)
    {
        return element.TryGetProperty(property, out var value) ? value.GetString() : null;
    }

    public void Dispose()
    {
        _http.Dispose();
        _rateLimiter.Dispose();
        GC.SuppressFinalize(this);
    }
}
