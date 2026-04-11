import SwiftUI

/// Bottom status bar showing current status message and loading indicator.
struct StatusBarView: View {
    @Bindable var viewModel: MainViewModel

    var body: some View {
        HStack(spacing: 8) {
            // Loading indicator
            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            // Error indicator
            if viewModel.hasError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.dangerColor)
                    .font(.system(size: 12))
            }

            // Status message
            Text(viewModel.statusMessage)
                .font(.system(size: 11))
                .foregroundStyle(viewModel.hasError ? Color.dangerColor : Color.textDim)
                .fontWeight(viewModel.hasError ? .semibold : .regular)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            // Undo button — visible quan hi ha una eliminació recent per desfer
            if viewModel.canUndoDelete {
                Button {
                    Task { await viewModel.undoLastDelete() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 11))
                        Text("Desfer")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentSubtle)
                    .foregroundStyle(Color.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Desfer l'última eliminació (Cmd+Z)")
            }

            // Copy progress bar
            if viewModel.isCopying {
                ProgressView(value: viewModel.copyProgress, total: 100)
                    .frame(width: 120)
                    .tint(Color.accent)

                Text("\(Int(viewModel.copyProgress))%")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color.bgSurface)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.borderSubtle).frame(height: 1)
        }
    }
}
