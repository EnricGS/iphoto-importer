using System.IO;
using System.Text.Json;
using iPhotoImporter.Models;

namespace iPhotoImporter.Services;

/// <summary>
/// Persistència a disc de la llista de destins Mirat configurats.
/// Fitxer: %LocalAppData%\iPhotoImporter\mirat-destinations.json
/// </summary>
public class MiratDestinationStore
{
    private readonly string _filePath;
    private static readonly JsonSerializerOptions _jsonOptions = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
    };

    public MiratDestinationStore()
    {
        var folder = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "iPhotoImporter");
        Directory.CreateDirectory(folder);
        _filePath = Path.Combine(folder, "mirat-destinations.json");
    }

    /// <summary>Carrega la llista (buida si el fitxer no existeix o està malmès).</summary>
    public List<MiratDestination> Load()
    {
        if (!File.Exists(_filePath)) return [];
        try
        {
            var json = File.ReadAllText(_filePath);
            var items = JsonSerializer.Deserialize<List<MiratDestination>>(json, _jsonOptions);
            return items ?? [];
        }
        catch
        {
            return [];
        }
    }

    /// <summary>Desa la llista sencera (reemplaça el fitxer).</summary>
    public void Save(IEnumerable<MiratDestination> destinations)
    {
        try
        {
            var json = JsonSerializer.Serialize(destinations, _jsonOptions);
            File.WriteAllText(_filePath, json);
        }
        catch (Exception ex)
        {
            // No és crític: es perdrà la configuració però l'app continuarà.
            System.Diagnostics.Debug.WriteLine($"[MiratDestinationStore] Save failed: {ex.Message}");
        }
    }
}
