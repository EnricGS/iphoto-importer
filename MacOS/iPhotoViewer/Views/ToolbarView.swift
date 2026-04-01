import SwiftUI

/// Top toolbar with title, folder controls, open folder names, destination, and iPhone import.
struct ToolbarView: View {
    @Bindable var viewModel: MainViewModel
    @State private var showAbout = false

    var body: some View {
        HStack(spacing: 12) {
            // App icon and title
            Button {
                showAbout = true
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.accentSubtle)
                        .frame(width: 32, height: 32)
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.accent)
                }
            }
            .buttonStyle(.plain)
            .help("Sobre iPhoto Manager")
            .sheet(isPresented: $showAbout) {
                VStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.accentSubtle)
                            .frame(width: 64, height: 64)
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 28))
                            .foregroundStyle(Color.accent)
                    }

                    Text("iPhoto Manager")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.textPrimary)

                    Text("Gestor de fotos ultra ràpid")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.textSecondary)

                    Text("Versió 1.0 — Abril 2026")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textDim)

                    Divider()
                        .frame(width: 120)

                    Text("Un producte de EnricGS")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.textSecondary)

                    Button("Tancar") { showAbout = false }
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.accent)
                        .padding(.top, 4)
                }
                .padding(32)
                .frame(width: 280)
                .background(Color.bgBase)
            }

            Text("iPhoto Manager")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
                .opacity(0.9)

            Spacer().frame(width: 8)

            // Add folder button
            Button {
                viewModel.openFolder()
            } label: {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 14))
            }
            .buttonStyle(ToolbarIconButtonStyle())
            .help("Afegir carpeta origen (Cmd+O)")
            .keyboardShortcut("o", modifiers: .command)

            // Open folders dropdown
            if viewModel.openFolderCount > 0 {
                FolderDropdown(viewModel: viewModel)
            }

            // Destination folder button (folder with arrow exiting right)
            Button {
                viewModel.setDestinationFolder()
            } label: {
                ZStack {
                    Image(systemName: "folder")
                        .font(.system(size: 14))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 8, weight: .bold))
                        .offset(x: 11, y: 0)
                }
                .overlay(alignment: .topTrailing) {
                    // Show green dot when destination is set
                    if viewModel.hasDestinationFolder {
                        Circle()
                            .fill(Color.successColor)
                            .frame(width: 6, height: 6)
                            .offset(x: 3, y: -3)
                    }
                }
            }
            .buttonStyle(ToolbarIconButtonStyle())
            .help(viewModel.hasDestinationFolder
                ? "Destí: \(viewModel.destinationFolder ?? "")"
                : "Establir carpeta destí")

            // Destination folder name indicator
            if viewModel.hasDestinationFolder {
                HStack(spacing: 4) {
                    Text(((viewModel.destinationFolder ?? "") as NSString).lastPathComponent)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.successColor)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 140)
                        .help(viewModel.destinationFolder ?? "")

                    Button {
                        viewModel.clearDestinationFolder()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8))
                            .foregroundStyle(Color.textDim)
                    }
                    .buttonStyle(.plain)
                    .help("Treure carpeta destí")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.bgElevated)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // iPhone import button
            Button {
                viewModel.toggleImportPanel()
            } label: {
                Image(systemName: "iphone")
                    .font(.system(size: 18))
            }
            .buttonStyle(ToolbarIconButtonStyle())
            .help("Importar des del dispositiu (iPhone)")

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.bgSurface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.borderSubtle).frame(height: 1)
        }
    }
}

// MARK: - Button Styles

struct ToolbarIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.textPrimary)
            .padding(8)
            .background(Color.bgElevated)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.textOnAccent)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Color.accent)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .opacity(configuration.isPressed ? 0.85 : 1.0)
    }
}

struct PrimaryIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.textOnAccent)
            .padding(8)
            .background(Color.accent)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .opacity(configuration.isPressed ? 0.85 : 1.0)
    }
}

struct ToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12))
            .foregroundStyle(Color.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.bgElevated)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .opacity(configuration.isPressed ? 0.85 : 1.0)
    }
}

struct DangerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.dangerColor)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .opacity(configuration.isPressed ? 0.85 : 1.0)
    }
}

struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.textPrimary)
            .padding(6)
            .background(configuration.isPressed ? Color.bgHover : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Folder Dropdown

struct FolderDropdown: View {
    @Bindable var viewModel: MainViewModel
    @State private var isOpen = false

    var body: some View {
        Button {
            isOpen.toggle()
        } label: {
            HStack(spacing: 4) {
                Text(viewModel.openFolderCount == 1
                    ? (viewModel.openFolders[0] as NSString).lastPathComponent
                    : "\(viewModel.openFolderCount) carpetes")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.accent)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7))
                    .foregroundStyle(Color.accent.opacity(0.7))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.accentSubtle)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(viewModel.openFolders, id: \.self) { folder in
                    HStack(spacing: 8) {
                        Text((folder as NSString).lastPathComponent)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .help(folder)

                        Button {
                            viewModel.toggleRecursive(for: folder)
                        } label: {
                            Image(systemName: viewModel.recursiveFolders.contains(folder)
                                ? "rectangle.stack.fill" : "rectangle.stack")
                                .font(.system(size: 11))
                                .foregroundStyle(viewModel.recursiveFolders.contains(folder)
                                    ? Color.accent : Color.textDim)
                        }
                        .buttonStyle(.plain)
                        .help(viewModel.recursiveFolders.contains(folder)
                            ? "Subcarpetes actives (clic per desactivar)"
                            : "Incloure subcarpetes")

                        Button {
                            viewModel.removeFolder(folder)
                            if viewModel.openFolderCount == 0 { isOpen = false }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9))
                                .foregroundStyle(Color.textDim)
                        }
                        .buttonStyle(.plain)
                        .help("Treure carpeta")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
            }
            .frame(minWidth: 220)
            .padding(.vertical, 4)
        }
    }
}
