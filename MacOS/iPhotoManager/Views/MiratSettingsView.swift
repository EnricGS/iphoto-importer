import SwiftUI

/// Sheet de configuració de destins Mirat.
///
/// Flux d'afegir destí:
///   1. URL base + API Key
///   2. "Provar connexió" → llista grups
///   3. Seleccionar grup → llista àlbums
///   4. (opcional) Seleccionar àlbum
///   5. Nom descriptiu → "Desar"
struct MiratSettingsView: View {
    @Bindable var viewModel: MainViewModel
    @Binding var isPresented: Bool

    // Formulari d'afegir/editar
    @State private var editing: MiratDestination = MiratDestination()
    @State private var baseUrl: String = "https://www.miratfotos.com"
    @State private var apiKey: String = ""
    @State private var nom: String = ""

    // Catàlegs carregats del servidor
    @State private var grups: [MiratGrup] = []
    @State private var albums: [MiratAlbum] = []
    @State private var selectedGrupId: String = ""
    @State private var selectedAlbumId: String = ""  // "" = sense àlbum

    // Estat UI
    @State private var isConnecting: Bool = false
    @State private var isLoadingAlbums: Bool = false
    @State private var statusText: String = ""
    @State private var statusColor: Color = Color.textSecondary
    @State private var canSave: Bool = false

    // Sheet del device-code flow (mètode recomanat)
    @State private var showConnectSheet: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Capçalera
            VStack(alignment: .leading, spacing: 4) {
                Text("Destins Mirat")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                Text("Configura on pujar fotos des d'iPhoto Manager. Pots tenir-ne diversos.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(.bottom, 14)

            // Botó destacat per mètode recomanat
            Button {
                showConnectSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "link.badge.plus")
                    Text("Vincular amb Mirat (recomanat)")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.bottom, 12)

            // Llista de destins existents
            existingDestinations
                .frame(minHeight: 80, maxHeight: 170)

            Text("Afegir manualment (avançat)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.textSecondary)
                .padding(.top, 18)
                .padding(.bottom, 10)

            // Formulari
            ScrollView {
                form
            }
            .frame(maxHeight: .infinity)

            Divider().padding(.vertical, 12)

            // Peu
            HStack {
                Spacer()
                Button("Tancar") { isPresented = false }
                    .buttonStyle(ToolbarButtonStyle())
                Button {
                    saveDestination()
                } label: {
                    Text("Desar destí")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canSave)
                .opacity(canSave ? 1.0 : 0.5)
            }
        }
        .padding(20)
        .frame(width: 560, height: 700)
        .background(Color.bgBase)
        .sheet(isPresented: $showConnectSheet) {
            ConnectMiratSheet(viewModel: viewModel, isPresented: $showConnectSheet)
        }
    }

    // MARK: - Llista existent

    @ViewBuilder
    private var existingDestinations: some View {
        if viewModel.miratDestinations.isEmpty {
            HStack {
                Spacer()
                Text("Encara no tens cap destí configurat.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textDim)
                Spacer()
            }
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity)
            .background(Color.bgSurface)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(viewModel.miratDestinations) { dest in
                        destinationRow(dest)
                    }
                }
                .padding(4)
            }
            .background(Color.bgSurface)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private func destinationRow(_ dest: MiratDestination) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(dest.nom.isEmpty ? dest.displayLabel : dest.nom)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(dest.baseUrl).lineLimit(1)
                    Text("—")
                    Text(dest.displayLabel).lineLimit(1)
                }
                .font(.system(size: 10))
                .foregroundStyle(Color.textDim)
            }
            Spacer()

            Button {
                editDestination(dest)
            } label: {
                Text("Editar").font(.system(size: 10))
            }
            .buttonStyle(ToolbarButtonStyle())

            Button {
                viewModel.removeMiratDestination(dest)
            } label: {
                Text("Eliminar").font(.system(size: 10))
            }
            .buttonStyle(DangerButtonStyle())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Formulari

    @ViewBuilder
    private var form: some View {
        VStack(alignment: .leading, spacing: 10) {
            fieldLabel("URL base del servidor")
            TextField("", text: $baseUrl)
                .textFieldStyle(.plain)
                .padding(8)
                .background(Color.bgSurface)
                .foregroundStyle(Color.textPrimary)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.borderSubtle))
                .font(.system(size: 12))

            fieldLabel("API Key (X-API-Key)")
            SecureField("", text: $apiKey)
                .textFieldStyle(.plain)
                .padding(8)
                .background(Color.bgSurface)
                .foregroundStyle(Color.textPrimary)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.borderSubtle))
                .font(.system(size: 12))

            Button {
                Task { await connect() }
            } label: {
                HStack(spacing: 6) {
                    if isConnecting {
                        ProgressView().scaleEffect(0.6)
                    } else {
                        Image(systemName: "link")
                    }
                    Text("Provar connexió")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(isConnecting || baseUrl.trimmingCharacters(in: .whitespaces).isEmpty || apiKey.isEmpty)

            fieldLabel("Grup")
            Picker("", selection: $selectedGrupId) {
                Text("— Selecciona grup —").tag("")
                ForEach(grups) { grup in
                    if let slug = grup.slug, !slug.isEmpty {
                        Text("\(grup.nom) (\(slug))").tag(grup.id)
                    } else {
                        Text(grup.nom).tag(grup.id)
                    }
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .disabled(grups.isEmpty)
            .onChange(of: selectedGrupId) { _, newId in
                handleGrupChange(newId)
            }

            fieldLabel("Àlbum (opcional)")
            Picker("", selection: $selectedAlbumId) {
                Text("(Sense àlbum)").tag("")
                ForEach(albums) { album in
                    Text(album.nom).tag(album.id)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .disabled(selectedGrupId.isEmpty || isLoadingAlbums)

            fieldLabel("Nom descriptiu")
            TextField("Ex: Família Gardela / Vacances 2026", text: $nom)
                .textFieldStyle(.plain)
                .padding(8)
                .background(Color.bgSurface)
                .foregroundStyle(Color.textPrimary)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.borderSubtle))
                .font(.system(size: 12))

            if !statusText.isEmpty {
                Text(statusText)
                    .font(.system(size: 11))
                    .foregroundStyle(statusColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(Color.textSecondary)
    }

    // MARK: - Accions

    private func connect() async {
        let url = baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = apiKey
        guard !url.isEmpty, !key.isEmpty else {
            setStatus("Cal URL i API Key.", color: Color.dangerColor)
            return
        }

        isConnecting = true
        setStatus("Connectant…", color: Color.textSecondary)

        editing.baseUrl = url
        editing.apiKey = key

        let svc = MiratService(destination: editing)
        do {
            let fetchedGrups = try await svc.listGroups()
            grups = fetchedGrups
            albums = []
            selectedGrupId = ""
            selectedAlbumId = ""
            setStatus("\(fetchedGrups.count) grup(s) trobats. Selecciona'n un.",
                      color: Color.successColor)
        } catch {
            grups = []
            setStatus("Error: \(error.localizedDescription)", color: Color.dangerColor)
        }
        isConnecting = false
        updateCanSave()
    }

    private func handleGrupChange(_ newId: String) {
        guard !newId.isEmpty, let grup = grups.first(where: { $0.id == newId }) else {
            albums = []
            selectedAlbumId = ""
            updateCanSave()
            return
        }
        editing.grupId = grup.id
        // Etiqueta "Nom (slug)" si n'hi ha slug — el camp 'nom' a la BD sol ser "Família"
        // per defecte, el slug és l'identificador real visible a la URL.
        editing.grupNom = (grup.slug?.isEmpty == false) ? "\(grup.nom) (\(grup.slug!))" : grup.nom

        // Pre-omplir nom descriptiu amb el slug (més descriptiu que "Família")
        if nom.trimmingCharacters(in: .whitespaces).isEmpty {
            nom = (grup.slug?.isEmpty == false) ? grup.slug! : grup.nom
        }

        // Carregar àlbums del grup
        selectedAlbumId = ""
        albums = []
        isLoadingAlbums = true
        Task {
            let svc = MiratService(destination: editing)
            do {
                albums = try await svc.listAlbums(grupId: grup.id)
            } catch {
                setStatus("Error carregant àlbums: \(error.localizedDescription)",
                          color: Color.dangerColor)
            }
            isLoadingAlbums = false
            updateCanSave()
        }
        updateCanSave()
    }

    private func saveDestination() {
        // Escriure valors finals a l'editing
        if selectedAlbumId.isEmpty {
            editing.albumId = nil
            editing.albumNom = nil
        } else {
            editing.albumId = selectedAlbumId
            editing.albumNom = albums.first(where: { $0.id == selectedAlbumId })?.nom
        }
        let trimmedNom = nom.trimmingCharacters(in: .whitespaces)
        editing.nom = trimmedNom.isEmpty ? editing.displayLabel : trimmedNom

        viewModel.addOrUpdateMiratDestination(editing)

        // Si és el primer, activa'l automàticament
        if viewModel.activeMiratDestination == nil {
            viewModel.selectMiratDestination(editing)
        }

        setStatus("Desat: \(editing.displayLabel)", color: Color.successColor)
        resetForm()
    }

    private func editDestination(_ dest: MiratDestination) {
        editing = dest
        baseUrl = dest.baseUrl
        apiKey = dest.apiKey
        nom = dest.nom
        grups = []
        albums = []
        selectedGrupId = ""
        selectedAlbumId = ""
        setStatus("Editant \(dest.displayLabel). Torna a Provar connexió per actualitzar grups/àlbums.",
                  color: Color.textSecondary)
        updateCanSave()
    }

    private func resetForm() {
        editing = MiratDestination()
        baseUrl = "https://www.miratfotos.com"
        apiKey = ""
        nom = ""
        grups = []
        albums = []
        selectedGrupId = ""
        selectedAlbumId = ""
        updateCanSave()
    }

    private func setStatus(_ text: String, color: Color) {
        statusText = text
        statusColor = color
    }

    private func updateCanSave() {
        // Cal com a mínim haver seleccionat grup per poder desar
        canSave = !selectedGrupId.isEmpty
    }
}
