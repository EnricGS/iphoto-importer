import SwiftUI

/// Top toolbar with folder controls, view mode toggle, and import button.
struct ToolbarView: View {
    @Bindable var viewModel: MainViewModel

    var body: some View {
        HStack(spacing: 12) {
            // App icon and title
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 18))
                .foregroundStyle(Color.accent)

            Text("iPhoto Viewer")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.textPrimary)

            Spacer().frame(width: 8)

            // Open folder button
            Button {
                viewModel.openFolder()
            } label: {
                Label("Open Folder", systemImage: "folder.badge.plus")
            }
            .buttonStyle(PrimaryButtonStyle())
            .keyboardShortcut("o", modifiers: .command)

            // Destination folder button
            Button {
                viewModel.setDestinationFolder()
            } label: {
                Label("Destination", systemImage: "arrow.right.doc.on.clipboard")
            }
            .buttonStyle(ToolbarButtonStyle())

            // Destination folder indicator
            if viewModel.hasDestinationFolder {
                Text(viewModel.destinationFolder ?? "")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.successColor)
                    .italic()
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 200)
                    .help(viewModel.destinationFolder ?? "")

                Button {
                    viewModel.clearDestinationFolder()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Clear destination folder")
            }

            // Current folder path
            if let folderPath = viewModel.currentFolderPath {
                Text(folderPath)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 500)
            }

            Spacer()

            // Media filter picker
            Picker("Filter", selection: $viewModel.mediaFilter) {
                ForEach(MediaFilter.allCases, id: \.self) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 180)

            // View mode toggle
            Button {
                viewModel.toggleViewMode()
            } label: {
                Label(viewModel.viewMode.label, systemImage: viewModel.isSplitMode ? "rectangle.split.2x1" : "rectangle")
            }
            .buttonStyle(ToolbarButtonStyle())
            .help("Toggle Split/Toggle mode (Tab)")

            // Import button
            Button {
                viewModel.toggleImportPanel()
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(ToolbarButtonStyle())
            .help("Import from device (MTP)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.bgMedium)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

// MARK: - Button Styles

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.accent)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .opacity(configuration.isPressed ? 0.85 : 1.0)
    }
}

struct ToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12))
            .foregroundStyle(Color.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.bgLight)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .opacity(configuration.isPressed ? 0.85 : 1.0)
    }
}

struct DangerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.dangerColor)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .opacity(configuration.isPressed ? 0.85 : 1.0)
    }
}
