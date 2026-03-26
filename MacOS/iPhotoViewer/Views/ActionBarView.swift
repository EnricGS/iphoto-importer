import SwiftUI

/// Bottom action bar shown when items are selected.
/// Provides Copy, Move, and Delete actions with selection info.
struct ActionBarView: View {
    @Bindable var viewModel: MainViewModel

    var body: some View {
        HStack(spacing: 16) {
            // Selection info
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accent)

                Text("\(viewModel.selectedPhotosCount) selected")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.textPrimary)

                Text("(\(String(format: "%.1f", viewModel.totalSelectedSizeMB)) MB)")
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

            // Action buttons
            Button {
                Task { await viewModel.copySelected() }
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .buttonStyle(ToolbarButtonStyle())
            .disabled(viewModel.isCopying)

            Button {
                Task { await viewModel.moveSelected() }
            } label: {
                Label("Move", systemImage: "folder")
            }
            .buttonStyle(ToolbarButtonStyle())
            .disabled(viewModel.isCopying)

            Button {
                Task { await viewModel.deleteSelected() }
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .buttonStyle(DangerButtonStyle())
            .disabled(viewModel.isCopying)
            .keyboardShortcut(.delete, modifiers: [])

            // Deselect all
            Button {
                viewModel.deselectAll()
            } label: {
                Image(systemName: "xmark.circle")
                    .foregroundStyle(Color.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Deselect all")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.bgMedium)
        .overlay(alignment: .top) {
            Divider()
        }
    }
}
