namespace iPhotoImporter.Models;

/// <summary>
/// Configuració d'un destí Mirat (https://miratfotos.com o instància self-hosted).
///
/// Un destí identifica inequívocament on pujar fotos: servidor + credencials + grup +
/// opcionalment un àlbum concret. Es persisteix a disc (JSON) per poder tenir múltiples
/// destins configurats (ex: "Família X / Àlbum Vacances", "Família Y / General").
/// </summary>
public class MiratDestination
{
    /// <summary>Identificador intern (UUID local, per distingir a la llista).</summary>
    public string Id { get; set; } = Guid.NewGuid().ToString();

    /// <summary>Nom llegible que es mostra al selector de destí.</summary>
    public string Nom { get; set; } = "";

    /// <summary>URL base del servidor Mirat, sense slash final. Ex: "https://www.miratfotos.com".</summary>
    public string BaseUrl { get; set; } = "https://www.miratfotos.com";

    /// <summary>API key compartida (MIRAT_API_KEY del servidor). Enviada com X-API-Key.</summary>
    public string ApiKey { get; set; } = "";

    /// <summary>UUID del grup Mirat de destí.</summary>
    public string GrupId { get; set; } = "";

    /// <summary>Nom del grup (només per mostrar a la UI).</summary>
    public string GrupNom { get; set; } = "";

    /// <summary>UUID d'àlbum dins el grup, o null per pujar sense associar.</summary>
    public string? AlbumId { get; set; }

    /// <summary>Nom de l'àlbum (només per mostrar).</summary>
    public string? AlbumNom { get; set; }

    /// <summary>
    /// UUID d'usuari (Mirat) que queda registrat com a "pujat per". Opcional — si és null,
    /// les fotos tenen pujat_per=null (sistema/API).
    /// </summary>
    public string? PujatPer { get; set; }

    /// <summary>Etiqueta completa pel selector: "Grup / Àlbum" o just "Grup".</summary>
    public string DisplayLabel =>
        string.IsNullOrEmpty(AlbumNom) ? GrupNom : $"{GrupNom} / {AlbumNom}";
}
