import Foundation
import CryptoKit
import ImageIO
import UniformTypeIdentifiers
import AppKit

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

        let metaJson: String
        if let data = try? JSONSerialization.data(withJSONObject: meta, options: []),
           let str = String(data: data, encoding: .utf8) {
            metaJson = str
        } else {
            metaJson = "{}"
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
        req.setValue(destination.apiKey, forHTTPHeaderField: "X-API-Key")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue("\(body.count)", forHTTPHeaderField: "Content-Length")
        req.httpBody = body

        do {
            let (data, resp) = try await session.data(for: req)
            let http = resp as? HTTPURLResponse
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            guard let status = http?.statusCode, (200...299).contains(status) else {
                return .fail("HTTP \(http?.statusCode ?? 0): \(bodyText)")
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = json["id"] as? String else {
                return .fail("Resposta inesperada: \(bodyText)")
            }
            let duplicat = (json["duplicat"] as? Bool) ?? false
            return .ok(id: id, duplicat: duplicat)
        } catch {
            return .fail("Error de xarxa: \(error.localizedDescription)")
        }
    }

    // MARK: - HTTP helpers

    private func get(path: String) async throws -> (Data, URLResponse) {
        guard let url = Self.buildURL(base: destination.baseUrl, path: path) else {
            throw MiratError.invalidURL
        }
        var req = URLRequest(url: url)
        req.setValue(destination.apiKey, forHTTPHeaderField: "X-API-Key")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await session.data(for: req)
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

    /// Genera thumbnail ~200px q70 i preview ~2048px q80 via ImageIO.
    /// Respecta l'orientació EXIF amb `kCGImageSourceCreateThumbnailWithTransform`.
    /// Si falla la conversió, retorna arrays buits (l'upload pot continuar sense preview).
    nonisolated static func generateThumbAndPreview(path: String) -> (thumb: Data, preview: Data, width: Int, height: Int) {
        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return (Data(), Data(), 0, 0)
        }

        // Dimensions originals, aplicant rotació segons EXIF (5..8 = rotada 90°/270°)
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
