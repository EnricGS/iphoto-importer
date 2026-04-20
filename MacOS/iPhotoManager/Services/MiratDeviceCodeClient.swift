import Foundation

// MARK: - DTOs

struct DeviceCodeResponse: Codable, Sendable {
    let deviceCode: String
    let userCode: String
    let verificationUrl: String
    let verificationUrlComplete: String
    let expiresIn: Int
    let interval: Int

    var expiresAt: Date {
        Date().addingTimeInterval(TimeInterval(expiresIn))
    }

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationUrl = "verification_url"
        case verificationUrlComplete = "verification_url_complete"
        case expiresIn = "expires_in"
        case interval
    }
}

struct TokenResponse: Codable, Sendable {
    let status: String
    let accessToken: String?
    let user: TokenUser?
    let grup: TokenGrup?

    enum CodingKeys: String, CodingKey {
        case status
        case accessToken = "access_token"
        case user
        case grup
    }
}

struct TokenUser: Codable, Sendable {
    let id: String
    let name: String?
    let email: String?
}

struct TokenGrup: Codable, Sendable {
    let id: String
    let nom: String?
    let slug: String?
}

enum AuthorizationResult: Sendable {
    case authorized(TokenResponse)
    case expired
    case revoked
    case cancelled
}

enum PollStatus: Sendable {
    case pending
    case authorized
}

/// Client del device-code flow de Mirat (POST /api/desktop/*).
///
/// Flux:
///   1. `requestDeviceCode()` → retorna user_code (ABCD-1234) + device_code + URL
///   2. L'usuari obre `verificationUrlComplete` al navegador i autoritza
///   3. `pollForToken()` fa polling fins rebre un access_token
///
/// L'access_token rebut és un token opac (prefix `mkd_`) que s'envia com
/// `Authorization: Bearer` a totes les crides posteriors. A partir d'aquí,
/// el servidor sap qui és l'usuari i a quin grup afegir les fotos.
///
/// Aquest client és independent de `MiratService` perquè s'utilitza abans que
/// tinguem cap destí configurat (sense grup_id ni token).
final class MiratDeviceCodeClient: Sendable {

    let baseUrl: String
    private let session: URLSession

    init(baseUrl: String) {
        self.baseUrl = baseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/ \n\r\t"))
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }

    /// Pas 1: obté un device_code + user_code del servidor.
    func requestDeviceCode(deviceName: String) async throws -> DeviceCodeResponse {
        guard let url = URL(string: "\(baseUrl)/api/desktop/device-code") else {
            throw MiratError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(
            withJSONObject: ["device_name": deviceName],
            options: []
        )
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8) ?? ""
            throw MiratError.httpError(status: status, body: body)
        }
        let decoder = JSONDecoder()
        return try decoder.decode(DeviceCodeResponse.self, from: data)
    }

    /// Pas 2: polling fins que l'usuari autoritzi o caduqui el codi.
    ///
    /// - Parameter onProgress: callback (main actor) per actualitzar UI
    /// - Parameter task: la tasca es cancel·la automàticament a expiresAt o si el
    ///   caller crida `.cancel()` al Task que envolta aquesta crida.
    func pollForToken(
        deviceCode: String,
        intervalSeconds: Int,
        expiresAt: Date,
        onProgress: (@Sendable (PollStatus) -> Void)? = nil
    ) async -> AuthorizationResult {
        let interval = UInt64(max(intervalSeconds, 1)) * 1_000_000_000

        while !Task.isCancelled {
            if Date() >= expiresAt {
                return .expired
            }

            let outcome = await pollOnce(deviceCode: deviceCode)
            switch outcome {
            case .authorized(let token):
                onProgress?(.authorized)
                return .authorized(token)
            case .expired:
                return .expired
            case .revoked:
                return .revoked
            case .cancelled:
                return .cancelled
            case nil:
                // Pending o error transitori — continuem
                onProgress?(.pending)
            }

            do {
                try await Task.sleep(nanoseconds: interval)
            } catch {
                return .cancelled
            }
        }

        return .cancelled
    }

    /// Un sol poll. Retorna un `AuthorizationResult` terminal, o `nil` si cal continuar
    /// (pending / slow_down / error transitori).
    private func pollOnce(deviceCode: String) async -> AuthorizationResult? {
        guard let url = URL(string: "\(baseUrl)/api/desktop/token") else {
            return .expired
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            req.httpBody = try JSONSerialization.data(
                withJSONObject: ["device_code": deviceCode],
                options: []
            )
        } catch {
            return .expired
        }

        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await session.data(for: req)
        } catch is CancellationError {
            return .cancelled
        } catch {
            // Error transitori — retornem nil per re-intentar
            return nil
        }

        guard let http = resp as? HTTPURLResponse else { return nil }

        switch http.statusCode {
        case 200:
            do {
                let decoder = JSONDecoder()
                let token = try decoder.decode(TokenResponse.self, from: data)
                guard let access = token.accessToken, !access.isEmpty else {
                    return .expired
                }
                return .authorized(token)
            } catch {
                return .expired
            }

        case 202, 429:
            // Pending o slow_down — continuem
            return nil

        case 410:
            // Expired o revoked
            if let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let status = body["status"] as? String,
               status == "revoked" {
                return .revoked
            }
            return .expired

        case 404:
            // device_code desconegut
            return .expired

        default:
            // Error inesperat — retry
            return nil
        }
    }
}
