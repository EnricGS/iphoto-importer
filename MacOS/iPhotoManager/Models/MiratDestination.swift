import Foundation

/// Configuració d'un destí Mirat (https://miratfotos.com o instància self-hosted).
///
/// Un destí identifica inequívocament on pujar fotos: servidor + credencials + grup +
/// opcionalment un àlbum concret. Es persisteix a disc (JSON) per poder tenir múltiples
/// destins configurats (ex: "Família X / Àlbum Vacances", "Família Y / General").
struct MiratDestination: Codable, Identifiable, Hashable {

    /// Identificador intern (UUID local, per distingir a la llista).
    var id: String = UUID().uuidString

    /// Nom llegible que es mostra al selector de destí.
    var nom: String = ""

    /// URL base del servidor Mirat, sense slash final. Ex: "https://www.miratfotos.com".
    var baseUrl: String = "https://www.miratfotos.com"

    /// API key compartida (MIRAT_API_KEY del servidor). Enviada com X-API-Key.
    var apiKey: String = ""

    /// UUID del grup Mirat de destí.
    var grupId: String = ""

    /// Nom del grup (només per mostrar a la UI).
    var grupNom: String = ""

    /// UUID d'àlbum dins el grup, o nil per pujar sense associar.
    var albumId: String?

    /// Nom de l'àlbum (només per mostrar).
    var albumNom: String?

    /// UUID d'usuari (Mirat) que queda registrat com a "pujat per". Opcional — si és nil,
    /// les fotos tenen pujat_per=null (sistema/API).
    var pujatPer: String?

    /// Etiqueta completa pel selector: "Grup / Àlbum" o just "Grup".
    var displayLabel: String {
        if let albumNom, !albumNom.isEmpty { return "\(grupNom) / \(albumNom)" }
        return grupNom
    }
}
