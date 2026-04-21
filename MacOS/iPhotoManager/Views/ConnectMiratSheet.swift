import SwiftUI
import AppKit

/// Sheet amb el flux complet de vincular iPhoto Manager a Mirat via device-code.
///
/// Passos:
///   1. En obrir-se, crida automàticament /api/desktop/device-code
///   2. Mostra user_code i obre el navegador a /vincular
///   3. Polling fins rebre access_token o expiració
///   4. Crea un MiratDestination i el desa al ViewModel
///
/// L'usuari mai veu ni enganxa cap clau API ni URL.
struct ConnectMiratSheet: View {
    @Bindable var viewModel: MainViewModel
    @Binding var isPresented: Bool

    /// Host públic de Mirat. Es podria fer configurable via variable d'entorn
    /// o ajust futur si calgués self-hosted, però per defecte és el públic.
    private static let miratBaseUrl = "https://www.miratfotos.com"

    private enum Stage {
        case waiting    // mostrant user_code i fent polling
        case success    // autoritzat
        case error(String)
    }

    @State private var stage: Stage = .waiting
    @State private var deviceCode: DeviceCodeResponse?
    @State private var pollTask: Task<Void, Never>?
    @State private var authorizedToken: TokenResponse?

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                switch stage {
                case .waiting:
                    waitingSection
                case .success:
                    successSection
                case .error(let message):
                    errorSection(message: message)
                }
            }
            .frame(maxHeight: .infinity)

            Divider().padding(.vertical, 12)

            footer
        }
        .padding(20)
        .frame(width: 480, height: 440)
        .background(Color.bgBase)
        .task {
            await beginFlow()
        }
        .onDisappear {
            pollTask?.cancel()
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Vincular amb Mirat")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
            Text("Connecta iPhoto Manager amb el teu compte de Mirat.")
                .font(.system(size: 12))
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 14)
    }

    private var waitingSection: some View {
        VStack(spacing: 16) {
            if let dc = deviceCode {
                Text("Entra aquest codi al navegador")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textSecondary)

                Text(dc.userCode)
                    .font(.system(size: 36, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.textPrimary)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 24)
                    .background(Color.bgSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                Text("El navegador s'hauria d'haver obert automàticament. Si no, obre:")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)

                Button {
                    if let url = URL(string: dc.verificationUrlComplete) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Text(dc.verificationUrl)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.accentColor)
                        .underline()
                }
                .buttonStyle(.plain)

                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.6)
                    Text("Esperant autorització...")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textDim)
                }
                .padding(.top, 8)
            } else {
                ProgressView()
                    .padding(.top, 40)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 20)
    }

    private var successSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.successColor)

            Text("Dispositiu vinculat")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.textPrimary)

            if let token = authorizedToken {
                if let user = token.user {
                    Text(user.name ?? user.email ?? "")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textSecondary)
                }
                if let grup = token.grup, let nom = grup.nom {
                    Text("Fotos pujades a: \(nom)")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textDim)
                }
            }

            Text("Ja pots tancar aquesta finestra i començar a pujar fotos.")
                .font(.system(size: 11))
                .foregroundStyle(Color.textDim)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 30)
    }

    private func errorSection(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.dangerColor)

            Text("No s'ha pogut vincular")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.textPrimary)

            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)

            Button {
                Task { await beginFlow() }
            } label: {
                Text("Tornar a provar")
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 20)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button {
                pollTask?.cancel()
                isPresented = false
            } label: {
                Text(isSuccessStage ? "Tancar" : "Cancel·lar")
            }
            .buttonStyle(ToolbarButtonStyle())
        }
    }

    private var isSuccessStage: Bool {
        if case .success = stage { return true }
        return false
    }

    // MARK: - Flow

    @MainActor
    private func beginFlow() async {
        pollTask?.cancel()
        stage = .waiting
        deviceCode = nil
        authorizedToken = nil

        let deviceName = Self.currentDeviceName()
        let client = MiratDeviceCodeClient(baseUrl: Self.miratBaseUrl)

        do {
            let dc = try await client.requestDeviceCode(deviceName: deviceName)
            deviceCode = dc

            // Obre el navegador a la pàgina de vinculació amb el codi
            if let openUrl = URL(string: dc.verificationUrlComplete) {
                NSWorkspace.shared.open(openUrl)
            }

            // Polling en background
            pollTask = Task { @MainActor in
                let result = await client.pollForToken(
                    deviceCode: dc.deviceCode,
                    intervalSeconds: dc.interval,
                    expiresAt: dc.expiresAt
                )
                await handleResult(result, deviceName: deviceName)
            }
        } catch {
            stage = .error(error.localizedDescription)
        }
    }

    @MainActor
    private func handleResult(_ result: AuthorizationResult, deviceName: String) async {
        switch result {
        case .authorized(let token):
            authorizedToken = token
            guard let access = token.accessToken, let grup = token.grup else {
                stage = .error("Resposta incompleta del servidor.")
                return
            }
            var dest = MiratDestination()
            dest.baseUrl = Self.miratBaseUrl
            dest.accessToken = access
            dest.apiKey = ""
            dest.grupId = grup.id
            dest.grupNom = grup.nom ?? ""
            dest.userId = token.user?.id
            dest.userName = token.user?.name
            dest.nom = token.user?.name.map { "\($0) · \(grup.nom ?? "")" } ?? (grup.nom ?? deviceName)
            viewModel.addOrUpdateMiratDestination(dest)
            if viewModel.activeMiratDestination == nil {
                viewModel.selectMiratDestination(dest)
            }
            stage = .success

        case .expired:
            stage = .error("El codi ha caducat. Torna a provar.")
        case .revoked:
            stage = .error("La sessió s'ha revocat abans d'utilitzar-la.")
        case .cancelled:
            // L'usuari ha cancel·lat — no modifiquem l'estat
            break
        }
    }

    private static func currentDeviceName() -> String {
        Host.current().localizedName ?? "Mac"
    }
}
