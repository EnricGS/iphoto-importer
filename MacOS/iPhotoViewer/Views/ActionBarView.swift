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
                    Text("selected")
                    Text("  ·  ")
                    Text(String(format: "%.1f", viewModel.totalSelectedSizeMB))
                    Text("MB")
                }
                .font(.system(size: 12))
                .foregroundStyle(Color.textSecondary)
            }

            Spacer()

            // Copy progress
            if viewModel.isCopying {
                ProgressView(value: viewModel.copyProgress, total: 100)
                    .frame(width: 120)
                    .tint(Color.accent)
            }

            // Action buttons (icon only with tooltips)
            Button {
                Task { await viewModel.copySelected() }
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 14))
            }
            .buttonStyle(ToolbarIconButtonStyle())
            .disabled(viewModel.isCopying)
            .help("Copy selected to another folder")

            Button {
                Task { await viewModel.moveSelected() }
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 14))
            }
            .buttonStyle(ToolbarIconButtonStyle())
            .disabled(viewModel.isCopying)
            .help("Move selected to another folder")

            Button {
                Task { await viewModel.deleteSelected() }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14))
            }
            .buttonStyle(DangerButtonStyle())
            .disabled(viewModel.isCopying)
            .keyboardShortcut(.delete, modifiers: [])
            .help("Delete selected (Del)")

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
            .help("Deselect all (Cmd+D)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.bgSurface.opacity(0.95))
        .overlay(alignment: .top) {
            Rectangle().fill(Color.accent).frame(height: 2)
        }
    }
}
