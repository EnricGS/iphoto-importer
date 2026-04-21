import SwiftUI

/// Sheet de configuració de destins Mirat.
///
/// UX simplificada: l'única manera de crear un destí és via el device-code
/// flow (botó "Vincular amb Mirat"), que obre el navegador i autoritza
/// l'usuari sense demanar claus API. Des d'aquí només es pot veure la llista
/// de destins ja vinculats i eliminar-los.
///
/// Els destins legacy creats amb API key manual (abans del device-code flow)
/// es llegeixen i es mostren igual — es poden eliminar com qualsevol altre.
struct MiratSettingsView: View {
    @Bindable var viewModel: MainViewModel
    @Binding var isPresented: Bool

    @State private var showConnectSheet: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Capçalera
            VStack(alignment: .leading, spacing: 4) {
                Text("Destins Mirat")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                Text("Vincula iPhoto Manager amb el teu compte de Mirat per pujar fotos.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(.bottom, 18)

            // Botó primari de vinculació
            Button {
                showConnectSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "link.badge.plus")
                    Text("Vincular amb Mirat")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.bottom, 18)

            // Llista de destins existents
            Text("Dispositius vinculats")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.textSecondary)
                .padding(.bottom, 8)

            existingDestinations

            Spacer(minLength: 0)

            Divider().padding(.vertical, 12)

            // Peu
            HStack {
                Spacer()
                Button("Tancar") { isPresented = false }
                    .buttonStyle(ToolbarButtonStyle())
            }
        }
        .padding(20)
        .frame(width: 480, height: 440)
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
                VStack(spacing: 4) {
                    Text("Cap destí configurat")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.textSecondary)
                    Text("Clica \"Vincular amb Mirat\" per començar.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textDim)
                }
                Spacer()
            }
            .padding(.vertical, 24)
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
                    if !dest.displayLabel.isEmpty {
                        Text("—")
                        Text(dest.displayLabel).lineLimit(1)
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(Color.textDim)
            }
            Spacer()

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
}
