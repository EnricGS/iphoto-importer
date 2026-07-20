import SwiftUI

/// Bottom action bar shown when items are selected.
/// Provides Copy, Move, and Delete actions with selection info.
struct ActionBarView: View {
    @Bindable var viewModel: MainViewModel

    var body: some View {
        HStack(spacing: 16) {
            // Selection info
            HStack(spacing: 8) {
                Text("\(viewModel.selectedPhotosCount)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                HStack(spacing: 2) {
                    Text("seleccionats")
                    Text("  ·  ")
                    Text(String(format: "%.1f", viewModel.totalSelectedSizeMB))
                    Text("MB")
                }
                .font(.system(size: 12))
                .foregroundStyle(Color.textSecondary)
            }

            Spacer()

            // Progress
            if viewModel.isCopying || viewModel.deviceService.isImporting {
                ProgressView(value: viewModel.isDeviceBrowseMode ? viewModel.deviceService.importProgress : viewModel.copyProgress, total: 100)
                    .frame(width: 120)
                    .tint(Color.accent)
            }

            if viewModel.isDeviceBrowseMode {
                // Device browse mode actions
                Button {
                    Task { await viewModel.importSelectedFromDevice() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 14))
                        Text("Importar seleccionades")
                            .font(.system(size: 12, weight: .medium))
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(viewModel.deviceService.isImporting)
                .help("Importa les seleccionades a una carpeta local")

                // Enviar directament a Mirat (només si hi ha un destí vinculat).
                if viewModel.hasActiveMiratDestination {
                    Button {
                        Task { await viewModel.uploadSelectedDeviceToMirat() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "icloud.and.arrow.up")
                                .font(.system(size: 14))
                            Text("Enviar a Mirat")
                                .font(.system(size: 12, weight: .medium))
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(viewModel.deviceService.isImporting || viewModel.isUploadingToMirat)
                    .help("Envia les seleccionades directament a Mirat (\(viewModel.activeMiratLabel))")
                }

                Button {
                    Task { await viewModel.deleteSelectedFromDevice() }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                }
                .buttonStyle(DangerButtonStyle())
                .disabled(viewModel.deviceService.isImporting)
                .help("Elimina les seleccionades del dispositiu (permanent, sense desfer)")
            } else {
                // Local file actions.
                // Amb un destí Mirat actiu, Copiar/Moure pugen al núvol: fem-ho
                // visible al punt d'acció (píndola + icona de núvol al botó).
                if viewModel.hasActiveMiratDestination {
                    HStack(spacing: 5) {
                        Image(systemName: "icloud.and.arrow.up")
                            .font(.system(size: 10))
                        Text("→ \(viewModel.activeMiratLabel)")
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .foregroundStyle(Color.accent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color.accentSubtle)
                    .clipShape(Capsule())
                    .frame(maxWidth: 240)
                    .help("Destí Mirat actiu: «Copiar» puja a Mirat i «Moure» puja i esborra el fitxer local. Desactiva'l amb la X del capdamunt per tornar a copiar/moure a carpetes.")
                }

                Button {
                    Task { await viewModel.copySelected() }
                } label: {
                    Image(systemName: viewModel.hasActiveMiratDestination ? "icloud.and.arrow.up" : "doc.on.doc")
                        .font(.system(size: 14))
                }
                .buttonStyle(ToolbarIconButtonStyle())
                .disabled(viewModel.isCopying)
                .help(viewModel.hasActiveMiratDestination
                      ? "Pujar les seleccionades a Mirat"
                      : "Copiar les seleccionades a una altra carpeta")

                Button {
                    Task { await viewModel.moveSelected() }
                } label: {
                    Image(systemName: viewModel.hasActiveMiratDestination ? "icloud.and.arrow.up.fill" : "folder")
                        .font(.system(size: 14))
                }
                .buttonStyle(ToolbarIconButtonStyle())
                .disabled(viewModel.isCopying)
                .help(viewModel.hasActiveMiratDestination
                      ? "Moure a Mirat: puja les seleccionades i mou el fitxer local a la Paperera"
                      : "Moure les seleccionades a una altra carpeta")

                Button {
                    // Amb el visor obert, Delete elimina NOMÉS la foto del visor
                    // (la drecera .delete segueix activa sota l'overlay del visor).
                    if viewModel.isViewerOpen {
                        Task { await viewModel.deleteCurrentViewerPhoto() }
                    } else {
                        Task { await viewModel.deleteSelected() }
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                }
                .buttonStyle(DangerButtonStyle())
                .disabled(viewModel.isCopying)
                .keyboardShortcut(.delete, modifiers: [])
                .help("Eliminar les seleccionades (Supr)")
            }

            Divider()
                .frame(height: 20)

            // Deselect all
            Button {
                viewModel.deselectAll()
            } label: {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textPrimary)
            }
            .buttonStyle(.plain)
            .help("Desseleccionar-ho tot (⌘D)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.bgSurface.opacity(0.95))
        .overlay(alignment: .top) {
            Rectangle().fill(Color.accent).frame(height: 2)
        }
    }
}
