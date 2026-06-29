import Foundation
import CryptoKit
import ImageIO
import UniformTypeIdentifiers
import AppKit
import AVFoundation
import os.log

private let videoThumbLog = Logger(subsystem: "com.iphotomanager.app", category: "video-thumbs")
private let uploadLog = Logger(subsystem: "com.iphotomanager.app", category: "upload")

// MARK: - DTOs

struct MiratGrup: Codable, Identifiable, Hashable {
    let id: String
    let nom: String
    let slug: String?
}

struct MiratAlbum: Codable, Identifiable, Hashable {
    let id: String
    let nom: String
    let descripcio: String?
    let privat: Bool
}

struct MiratUploadResult {
    let success: Bool
    let fotoId: String?
    let duplicat: Bool
    let errorMessage: String?

    static func ok(id: String, duplicat: Bool) -> Self {
        .init(success: true, fotoId: id, duplicat: duplicat, errorMessage: nil)
    }

    static func fail(_ message: String) -> Self {
        .init(success: false, fotoId: nil, duplicat: false, errorMessage: message)
    }
}

enum MiratError: Error, LocalizedError {
    case invalidURL
    case httpError(status: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "URL invàlida"
        case .httpError(let status, let body): return "HTTP \(status): \(body)"
        }
    }
}

/// Client HTTP per comunicar-se amb l'API externa de Mirat (/api/external/*).
///
/// - Llista grups i àlbums amb una API key.
/// - Puja fotos amb una sola crida multipart (foto + thumbnail + preview + metadades).
///
/// Ús típic:
///   let svc = MiratService(destination: dest)
///   let grups = try await svc.listGroups()
///   let result = await svc.uploadPhoto(photo)
final class MiratService {

    private let destination: MiratDestination
    private let session: URLSession

    init(destination: MiratDestination) {
        self.destination = destination
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 600
        self.session = URLSession(configuration: config)
    }

    // MARK: - API calls

    /// Comprova que BaseUrl + ApiKey funcionen (fa GET /api/external/grups).
    func testConnection() async -> Bool {
        do { _ = try await listGroups(); return true } catch { return false }
    }

    func listGroups() async throws -> [MiratGrup] {
        let (data, resp) = try await get(path: "api/external/grups")
        try Self.ensureOk(data: data, resp: resp)
        return try JSONDecoder().decode([MiratGrup].self, from: data)
    }

    func listAlbums(grupId: String) async throws -> [MiratAlbum] {
        let escaped = grupId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? grupId
        let (data, resp) = try await get(path: "api/external/albums?grup_id=\(escaped)")
        try Self.ensureOk(data: data, resp: resp)
        return try JSONDecoder().decode([MiratAlbum].self, from: data)
    }

    /// Puja una foto a Mirat en una sola crida. Genera thumbnail + preview si cal,
    /// calcula SHA-256, construeix metadades, envia multipart.
    func uploadPhoto(_ photo: PhotoItem) async -> MiratUploadResult {
        guard FileManager.default.fileExists(atPath: photo.fullPath) else {
            return .fail("El fitxer ja no existeix localment")
        }
        let fileURL = URL(fileURLWithPath: photo.fullPath)
        let mime = Self.mimeType(forExtension: fileURL.pathExtension)

        // 1. SHA-256 del fitxer complet — Mirat dedupa per hash_fitxer
        let sha256: String
        do {
            sha256 = try await Self.sha256(of: fileURL)
        } catch {
            return .fail("Error calculant SHA-256: \(error.localizedDescription)")
        }

        // 2. Generar thumbnail 200px JPEG i preview 2048px JPEG (respectant orientació EXIF)
        let (thumbBytes, previewBytes, width, height) = await Task.detached(priority: .utility) {
            Self.generateThumbAndPreview(path: photo.fullPath)
        }.value

        // 3. Metadades
        var meta: [String: Any] = [
            "mime_type": mime,
            "hash_fitxer": sha256,
        ]
        if width > 0 { meta["amplada"] = width }
        if height > 0 { meta["alcada"] = height }
        if let date = photo.dateTaken {
            meta["data_original"] = Self.iso8601Formatter.string(from: date)
        }
        if let pujatPer = destination.pujatPer { meta["pujat_per"] = pujatPer }

        // GPS — extret directament del fitxer en pujar. Per a fotos locals
        // `photo.gpsLatitude/Longitude` sovint són nil (loadLocations() només
        // omple `location` en background), així que el llegim aquí. Sense això,
        // cap foto pujada amb iPhoto Manager arribava amb ubicació a Mirat.
        if let coords = FileService.extractGPSLocation(at: photo.fullPath) {
            meta["latitud"] = coords.latitude
            meta["longitud"] = coords.longitude
        } else if let lat = photo.gpsLatitude, let lon = photo.gpsLongitude {
            // Fallback per a items de càmera (gpsLatitude ja poblat, sense fitxer EXIF llegible)
            meta["latitud"] = lat
            meta["longitud"] = lon
        }
        // Si ja tenim el nom del lloc, l'enviem i estalviem el geocode al servidor
        if let loc = photo.location, !loc.isEmpty { meta["nom_lloc"] = loc }

        let metaJson: String
        if let data = try? JSONSerialization.data(withJSONObject: meta, options: []),
           let str = String(data: data, encoding: .utf8) {
            metaJson = str
        } else {
            metaJson = "{}"
        }

        // Vídeos: pujada PRESIGNADA directa a MinIO (init → PUT → complete), evitant
        // que el fitxer passi pel pod web. Així no peta el requestTimeout de Node
        // (300s) amb vídeos grans → adéu als 502. Les fotos segueixen pel multipart.
        if mime.hasPrefix("video/") {
            return await uploadVideoPresigned(
                fileURL: fileURL, mime: mime,
                thumbBytes: thumbBytes, previewBytes: previewBytes, meta: meta)
        }

        // 4. Multipart — boundary simple sense cometes (evitem el bug .NET del client Windows)
        let boundary = "mirat-\(UUID().uuidString)"
        var body = Data()

        func appendField(_ name: String, _ value: String) {
            body.append(Self.utf8("--\(boundary)\r\n"))
            body.append(Self.utf8("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n"))
            body.append(Self.utf8("\(value)\r\n"))
        }

        func appendFile(_ name: String, filename: String, contentType: String, data: Data) {
            body.append(Self.utf8("--\(boundary)\r\n"))
            body.append(Self.utf8("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n"))
            body.append(Self.utf8("Content-Type: \(contentType)\r\n\r\n"))
            body.append(data)
            body.append(Self.utf8("\r\n"))
        }

        appendField("grup_id", destination.grupId)
        if let albumId = destination.albumId, !albumId.isEmpty {
            appendField("album_id", albumId)
        }
        appendField("metadades", metaJson)

        // Original
        do {
            let fotoData = try Data(contentsOf: fileURL, options: .mappedIfSafe)
            // Nom ASCII-safe — alguns parsers multipart (undici/fetch de Next.js) peten
            // amb noms amb espais o caràcters no-ASCII sense RFC 5987.
            let safeName = Self.asciiSafe(fileURL.lastPathComponent)
            appendFile("foto", filename: safeName, contentType: mime, data: fotoData)
        } catch {
            return .fail("No s'ha pogut llegir el fitxer: \(error.localizedDescription)")
        }

        if !thumbBytes.isEmpty {
            appendFile("thumbnail", filename: "thumbnail.jpg", contentType: "image/jpeg", data: thumbBytes)
        }
        if !previewBytes.isEmpty {
            appendFile("preview", filename: "preview.jpg", contentType: "image/jpeg", data: previewBytes)
        }

        body.append(Self.utf8("--\(boundary)--\r\n"))

        guard let url = Self.buildURL(base: destination.baseUrl, path: "api/external/upload") else {
            return .fail("URL invàlida")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        applyAuth(to: &req)
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue("\(body.count)", forHTTPHeaderField: "Content-Length")
        // No assignem httpBody — usem upload(for:from:) que fa streaming
        // i funciona millor amb bodies grans en macOS (evita l'error
        // "Internet connection appears to be offline" amb fitxers >5MB).

        // Reintent automàtic per a errors transitoris (xarxa / 5xx / 429).
        // Una sola pujada genera 5+ operacions backend (MinIO + DB + fire-and-forget
        // ia-pipeline) — amb 3 uploads concurrents pot saturar el granja i alguna
        // tanda fallar amb timeout/503. Un sol retry resol ~tot.
        let filename = fileURL.lastPathComponent
        let maxAttempts = 2
        for attempt in 1...maxAttempts {
            do {
                let (data, resp) = try await session.upload(for: req, from: body)
                let http = resp as? HTTPURLResponse
                let status = http?.statusCode ?? 0
                let bodyText = String(data: data, encoding: .utf8) ?? ""

                if (200...299).contains(status) {
                    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let id = json["id"] as? String else {
                        uploadLog.error("Resposta no JSON per \(filename, privacy: .public): \(bodyText.prefix(200), privacy: .public)")
                        return .fail("Resposta inesperada: \(bodyText)")
                    }
                    let duplicat = (json["duplicat"] as? Bool) ?? false
                    if attempt > 1 {
                        uploadLog.notice("Recuperat al retry #\(attempt) — \(filename, privacy: .public)")
                    }
                    return .ok(id: id, duplicat: duplicat)
                }

                // Decideix si reintentar segons codi HTTP
                let isRetriable = status == 0 || status >= 500 || status == 429
                uploadLog.error("HTTP \(status) intent \(attempt)/\(maxAttempts) — \(filename, privacy: .public): \(bodyText.prefix(300), privacy: .public)")
                if !isRetriable || attempt == maxAttempts {
                    return .fail("HTTP \(status): \(bodyText)")
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)  // 2s backoff
            } catch {
                uploadLog.error("Error de xarxa intent \(attempt)/\(maxAttempts) — \(filename, privacy: .public): \(error.localizedDescription, privacy: .public)")
                if attempt == maxAttempts {
                    return .fail("Error de xarxa: \(error.localizedDescription)")
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
        return .fail("Esgotats els reintents")
    }

    /// Puja un VÍDEO amb el flux presignat: demana URLs a /upload-init, puja el
    /// fitxer (i thumb/preview) DIRECTAMENT a MinIO, i registra amb /upload-complete.
    /// Evita fer passar el vídeo pel pod web (requestTimeout de Node → 502 amb grans).
    private func uploadVideoPresigned(
        fileURL: URL, mime: String,
        thumbBytes: Data, previewBytes: Data, meta: [String: Any]
    ) async -> MiratUploadResult {
        let filename = fileURL.lastPathComponent
        let hasThumb = !thumbBytes.isEmpty
        let hasPreview = !previewBytes.isEmpty

        // 1. init — dedup + URLs presignades
        var initBody: [String: Any] = [
            "mime_type": mime,
            "has_thumbnail": hasThumb,
            "has_preview": hasPreview,
            "grup_id": destination.grupId,
        ]
        if let h = meta["hash_fitxer"] as? String { initBody["hash_fitxer"] = h }

        let initResp: [String: Any]
        do {
            initResp = try await postJSON(path: "api/external/upload-init", body: initBody)
        } catch {
            uploadLog.error("init presignat fallit — \(filename, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return .fail("Error iniciant la pujada: \(error.localizedDescription)")
        }

        if (initResp["duplicat"] as? Bool) == true, let id = initResp["id"] as? String {
            return .ok(id: id, duplicat: true)
        }
        guard let fotoId = initResp["fotoId"] as? String,
              let fotoUrlStr = initResp["foto_url"] as? String,
              let fotoUrl = URL(string: fotoUrlStr) else {
            return .fail("Resposta d'init inesperada")
        }

        // 2. PUT directe a MinIO (vídeo + thumb + preview)
        let mida: Int
        do {
            let fotoData = try Data(contentsOf: fileURL, options: .mappedIfSafe)
            mida = fotoData.count
            try await putToPresigned(url: fotoUrl, data: fotoData, contentType: mime)
            if hasThumb, let s = initResp["thumb_url"] as? String, let u = URL(string: s) {
                try await putToPresigned(url: u, data: thumbBytes, contentType: "image/jpeg")
            }
            if hasPreview, let s = initResp["preview_url"] as? String, let u = URL(string: s) {
                try await putToPresigned(url: u, data: previewBytes, contentType: "image/jpeg")
            }
        } catch {
            uploadLog.error("PUT presignat fallit — \(filename, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return .fail("Error pujant a l'emmagatzematge: \(error.localizedDescription)")
        }

        // 3. complete — registra la foto (insert + àlbum + pipeline)
        var completeBody: [String: Any] = [
            "fotoId": fotoId,
            "mime_type": mime,
            "mida": mida,
            "metadades": meta,
            "has_thumbnail": hasThumb,
            "has_preview": hasPreview,
            "grup_id": destination.grupId,
        ]
        if let albumId = destination.albumId, !albumId.isEmpty {
            completeBody["album_id"] = albumId
        }

        do {
            let resp = try await postJSON(path: "api/external/upload-complete", body: completeBody)
            guard let id = resp["id"] as? String else { return .fail("Resposta de complete inesperada") }
            return .ok(id: id, duplicat: false)
        } catch {
            uploadLog.error("complete presignat fallit — \(filename, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return .fail("Error registrant la foto: \(error.localizedDescription)")
        }
    }

    // MARK: - HTTP helpers

    /// POST amb body JSON + auth; retorna el JSON de resposta. Llança si no és 2xx.
    private func postJSON(path: String, body: [String: Any]) async throws -> [String: Any] {
        guard let url = Self.buildURL(base: destination.baseUrl, path: path) else {
            throw MiratError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        applyAuth(to: &req)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        let (data, resp) = try await session.data(for: req)
        try Self.ensureOk(data: data, resp: resp)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    /// PUT de dades a una URL presignada (auto-autenticada; cap capçalera d'auth nostra).
    /// Llança si no és 2xx.
    private func putToPresigned(url: URL, data: Data, contentType: String) async throws {
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue(contentType, forHTTPHeaderField: "Content-Type")
        let (respData, resp) = try await session.upload(for: req, from: data)
        try Self.ensureOk(data: respData, resp: resp)
    }

    private func get(path: String) async throws -> (Data, URLResponse) {
        guard let url = Self.buildURL(base: destination.baseUrl, path: path) else {
            throw MiratError.invalidURL
        }
        var req = URLRequest(url: url)
        applyAuth(to: &req)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await session.data(for: req)
    }

    /// Aplica l'auth correcte a una request. Prioritza l'access token (device-code flow);
    /// fallback a X-API-Key per configuracions legacy.
    private func applyAuth(to request: inout URLRequest) {
        if let token = destination.accessToken, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else if !destination.apiKey.isEmpty {
            request.setValue(destination.apiKey, forHTTPHeaderField: "X-API-Key")
        }
    }

    private static func buildURL(base: String, path: String) -> URL? {
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: "\(trimmed)/\(path)")
    }

    private static func ensureOk(data: Data, resp: URLResponse) throws {
        guard let http = resp as? HTTPURLResponse else {
            throw MiratError.httpError(status: 0, body: "Sense resposta")
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw MiratError.httpError(status: http.statusCode, body: body)
        }
    }

    // MARK: - SHA-256 (streaming, async)

    nonisolated static func sha256(of url: URL) async throws -> String {
        try await Task.detached(priority: .utility) {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var hasher = SHA256()
            while true {
                let chunk = try handle.read(upToCount: 65_536) ?? Data()
                if chunk.isEmpty { break }
                hasher.update(data: chunk)
            }
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        }.value
    }

    // MARK: - Thumbnail + preview (ImageIO)

    /// Genera thumbnail ~200px q70 i preview ~2048px q80.
    /// Per a imatges fa servir ImageIO i respecta l'orientació EXIF.
    /// Per a vídeos extreu un frame amb AVAssetImageGenerator (t=1s) i el
    /// converteix a JPEG. Si tot falla, retorna arrays buits (el servidor
    /// accepta thumbnail nul per a vídeos).
    nonisolated static func generateThumbAndPreview(path: String) -> (thumb: Data, preview: Data, width: Int, height: Int) {
        let url = URL(fileURLWithPath: path)
        // Discriminem per extensió, NO per qui pot obrir el fitxer. Alguns
        // .MOV de l'iPhone tenen un poster embedded i ImageIO els obre
        // sense problemes — però el contingut útil és el vídeo, no el poster.
        let ext = url.pathExtension.lowercased()
        if PhotoItem.videoExtensions.contains(ext) {
            return generateFromVideo(url: url)
        }
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
            return generateFromImageSource(source)
        }
        videoThumbLog.error("Fitxer ni vídeo ni imatge reconeguda: \(url.lastPathComponent, privacy: .public)")
        return (Data(), Data(), 0, 0)
    }

    private nonisolated static func generateFromImageSource(_ source: CGImageSource) -> (thumb: Data, preview: Data, width: Int, height: Int) {
        var width = 0
        var height = 0
        if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] {
            width = props[kCGImagePropertyPixelWidth as String] as? Int ?? 0
            height = props[kCGImagePropertyPixelHeight as String] as? Int ?? 0
            if let orientation = props[kCGImagePropertyOrientation as String] as? Int,
               (5...8).contains(orientation) {
                let tmp = width; width = height; height = tmp
            }
        }
        let thumb = createJPEG(source: source, maxPixel: 200, quality: 0.70) ?? Data()
        let preview = createJPEG(source: source, maxPixel: 2048, quality: 0.80) ?? Data()
        return (thumb, preview, width, height)
    }

    /// Genera thumb + preview per a un vídeo reusant `FileService.generateVideoThumbnail`,
    /// que és el mateix camí que ja s'usa a la graella d'iPhoto Manager i sabem
    /// que funciona per a MP4, MOV, M4V, AVI, MKV. Converteix l'NSImage resultant
    /// a JPEG via NSBitmapImageRep (mateixa via que ThumbnailCacheService).
    private nonisolated static func generateFromVideo(url: URL) -> (thumb: Data, preview: Data, width: Int, height: Int) {
        let fs = FileService()
        let path = url.path

        // Preview 2048px (frame 0 — sempre vàlid, sense problemes de keyframes)
        guard let previewImage = fs.generateVideoThumbnail(for: path, maxSize: 2048) else {
            videoThumbLog.error("FileService.generateVideoThumbnail returned nil for \(url.lastPathComponent, privacy: .public)")
            return (Data(), Data(), 0, 0)
        }
        let width = Int(previewImage.size.width)
        let height = Int(previewImage.size.height)

        let previewData = nsImageToJPEG(previewImage, quality: 0.80) ?? Data()

        // Thumb 200px — segona crida, AVFoundation aprofita el descodificador en cache
        let thumbImage = fs.generateVideoThumbnail(for: path, maxSize: 200) ?? previewImage
        let thumbData = nsImageToJPEG(thumbImage, quality: 0.70) ?? Data()

        return (thumbData, previewData, width, height)
    }

    /// Converteix un NSImage a JPEG bytes. Mateixa via que
    /// `ThumbnailCacheService.saveToDisk`, que sabem que funciona amb els
    /// thumbnails de la graella (provat amb totes les extensions suportades).
    private nonisolated static func nsImageToJPEG(_ image: NSImage, quality: Double) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: NSNumber(value: quality)])
        else {
            videoThumbLog.error("NSBitmapImageRep JPEG conversion failed")
            return nil
        }
        return jpeg
    }

    private nonisolated static func createJPEG(source: CGImageSource, maxPixel: Int, quality: Double) -> Data? {
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        // No li passem les propietats originals — això equival al `Strip()` de Windows
        // (descarrega EXIF/GPS de les miniatures/previsualitzacions)
        let props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(dest, cgImage, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    // MARK: - String/MIME helpers

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private nonisolated static func utf8(_ s: String) -> Data {
        s.data(using: .utf8) ?? Data()
    }

    /// Converteix el nom d'un fitxer a ASCII-safe per al filename del Content-Disposition.
    /// Substitueix espais i caràcters no-ASCII per '_'.
    private nonisolated static func asciiSafe(_ name: String) -> String {
        var out = ""
        out.reserveCapacity(name.count)
        for scalar in name.unicodeScalars {
            let v = scalar.value
            let isDigit = (0x30...0x39).contains(v)
            let isUpper = (0x41...0x5A).contains(v)
            let isLower = (0x61...0x7A).contains(v)
            let isOther = v == 0x2E || v == 0x2D || v == 0x5F // . - _
            if isDigit || isUpper || isLower || isOther {
                out.unicodeScalars.append(scalar)
            } else {
                out.append("_")
            }
        }
        return out.isEmpty ? "file.bin" : out
    }

    private nonisolated static func mimeType(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "webp": return "image/webp"
        case "heic": return "image/heic"
        case "heif": return "image/heif"
        case "avif": return "image/avif"
        case "tif", "tiff": return "image/tiff"
        case "dng": return "image/x-adobe-dng"
        case "cr2": return "image/x-canon-cr2"
        case "cr3": return "image/x-canon-cr3"
        case "nef": return "image/x-nikon-nef"
        case "arw": return "image/x-sony-arw"
        case "raf": return "image/x-fuji-raf"
        case "mp4", "m4v": return "video/mp4"
        case "mov": return "video/quicktime"
        case "avi": return "video/x-msvideo"
        case "mkv": return "video/x-matroska"
        case "webm": return "video/webm"
        default: return "application/octet-stream"
        }
    }
}
