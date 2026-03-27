import SwiftUI

/// Top toolbar with folder controls, open folder list, and destination indicator.
/// Split/Import buttons are now in the ThumbnailGridView (above grid only).
struct ToolbarView: View {
    @Bindable var viewModel: MainViewModel

    var body: some View {
        HStack(spacing: 12) {
            // App icon and title
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentSubtle)
                    .frame(width: 32, height: 32)
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.accent)
            }

            Text("iPhoto Viewer")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
                .opacity(0.9)

            Spacer().frame(width: 8)

            // Folder buttons group
            HStack(spacing: 2) {
                // Add source folder
                Button {
                    viewModel.openFolder()
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 14))
                }
                .buttonStyle(ToolbarIconButtonStyle())
                .help("Add source folder (Cmd+O)")
                .keyboardShortcut("o", modifiers: .command)

                Divider()
                    .frame(height: 18)
                    .padding(.horizontal, 2)

                // Set destination folder
                Button {
                    viewModel.setDestinationFolder()
                } label: {
                    Image(systemName: "arrow.right.doc.on.clipboard")
                        .font(.system(size: 14))
                }
                .buttonStyle(ToolbarIconButtonStyle())
                .help("Set destination folder for copies")
            }
            .padding(2)
            .background(Color.bgElevated)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Clear all folders button
            if viewModel.openFolderCount > 0 {
                Button {
                    viewModel.clearAllFolders()
                } label: {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textDim)
                }
                .buttonStyle(.plain)
                .help("Clear all folders")
            }

            // Separator
            if viewModel.openFolderCount > 0 {
                Divider()
                    .frame(height: 20)
            }

            // Open folders list
            if viewModel.openFolderCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textPrimary)

                    ForEach(viewModel.openFolders, id: \.self) { folder in
                        HStack(spacing: 4) {
                            Text((folder as NSString).lastPathComponent)
                                .font(.system(size: 10))
                                .foregroundStyle(Color.textSecondary)
                                .lineLimit(1)
                                .frame(maxWidth: 160)
                                .help(folder)

                            Button {
                                viewModel.removeFolder(folder)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8))
                                    .foregroundStyle(Color.textDim)
                            }
                            .buttonStyle(.plain)
                            .help("Remove folder")
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.bgElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }

            // Destination folder indicator
            if viewModel.hasDestinationFolder {
                Divider()
                    .frame(height: 20)

                HStack(spacing: 4) {
                    Image(systemName: "arrow.right.doc.on.clipboard")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.successColor)

                    Text((viewModel.destinationFolder ?? "") as String)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.successColor)
                        .italic()
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 180)
                        .help(viewModel.destinationFolder ?? "")

                    Button {
                        viewModel.clearDestinationFolder()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.textDim)
                    }
                    .buttonStyle(.plain)
                    .help("Clear destination folder")
                }
            }

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
