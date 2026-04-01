import SwiftUI

/// Side panel for device import (ImageCaptureCore on macOS).
/// Slides in from the right side of the window.
/// Shows device detection, connection progress, and browse status.
struct ImportPanelView: View {
    @Bindable var viewModel: MainViewModel

    var body: some View {
        HStack(spacing: 0) {
            Spacer()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Image(systemName: "iphone.and.arrow.forward")
                        .foregroundStyle(Color.accent)
                    Text("Importar des del dispositiu")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)

                    Spacer()

                    Button {
                        viewModel.isImportPanelOpen = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.textDim)
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
                .background(Color.bgElevated)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.borderSubtle).frame(height: 1)
                }

                // Content
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {

                        // ── Scanning / No devices ──
                        if viewModel.deviceService.isScanning {
                            HStack(spacing: 10) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Cercant dispositius...")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.textSecondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)

                        } else if viewModel.deviceService.devices.isEmpty && !viewModel.isDeviceBrowseMode {
                            VStack(spacing: 12) {
                                Image(systemName: "iphone.slash")
                                    .font(.system(size: 32))
                                    .foregroundStyle(Color.textDim)

                                Text("No s'han trobat dispositius")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.textSecondary)

                                Text("Connecta un iPhone o càmera per USB.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.textDim)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)

                            Button {
                                Task { await viewModel.detectDevices() }
                            } label: {
                                HStack {
                                    Image(systemName: "antenna.radiowaves.left.and.right")
                                    Text("Detectar dispositius")
                                }
                            }
                            .buttonStyle(ToolbarButtonStyle())
                        }

                        // ── Device list (when multiple or manual selection needed) ──
                        if viewModel.deviceService.devices.count > 1 && !viewModel.isDeviceBrowseMode {
                            Text("DISPOSITIUS")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color.textDim)

                            ForEach(viewModel.deviceService.devices) { device in
                                HStack {
                                    Image(systemName: device.type == .iPhone ? "iphone" : "camera")
                                        .foregroundStyle(Color.accent)
                                    Text(device.name)
                                        .foregroundStyle(Color.textPrimary)
                                    Spacer()
                                    if viewModel.deviceService.selectedDevice == device {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Color.accent)
                                    }
                                }
                                .padding(8)
                                .background(
                                    viewModel.deviceService.selectedDevice == device
                                        ? Color.accentSubtle
                                        : Color.clear
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .onTapGesture {
                                    viewModel.deviceService.selectedDevice = device
                                }
                            }

                            if viewModel.deviceService.selectedDevice != nil {
                                Button {
                                    Task { await viewModel.browseDevice() }
                                } label: {
                                    HStack {
                                        Image(systemName: "eye")
                                        Text("Navegar fotos")
                                    }
                                }
                                .buttonStyle(PrimaryButtonStyle())
                                .disabled(viewModel.deviceService.isBrowsing)
                            }
                        }

                        // ── Connection / Browse progress ──
                        if viewModel.deviceService.isBrowsing || viewModel.isDeviceBrowseMode {
                            if let device = viewModel.deviceService.selectedDevice {
                                HStack(spacing: 8) {
                                    Image(systemName: "iphone")
                                        .foregroundStyle(Color.accent)
                                    Text(device.name)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(Color.textPrimary)
                                    Spacer()
                                    if viewModel.isDeviceBrowseMode {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Color.successColor)
                                            .font(.system(size: 14))
                                    }
                                }
                                .padding(10)
                                .background(Color.accentSubtle)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }

                            if viewModel.deviceService.isBrowsing && !viewModel.isDeviceBrowseMode {
                                HStack(spacing: 10) {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text(viewModel.deviceService.statusMessage)
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.textSecondary)
                                }
                            }
                        }

                        // ── Browse mode info ──
                        if viewModel.isDeviceBrowseMode {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 6) {
                                    Image(systemName: "photo.on.rectangle")
                                        .foregroundStyle(Color.accent)
                                    Text("\(viewModel.photos.count) fitxers")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(Color.textPrimary)
                                }

                                if viewModel.selectedPhotosCount > 0 {
                                    Text("\(viewModel.selectedPhotosCount) seleccionat(s) · \(String(format: "%.1f", viewModel.totalSelectedSizeMB)) MB")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.accent)
                                }

                                Text("Selecciona fotos a la graella i utilitza la barra inferior per importar o eliminar.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.textDim)
                            }
                            .padding(10)
                            .background(Color.bgElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                            // Import progress
                            if viewModel.deviceService.isImporting {
                                VStack(alignment: .leading, spacing: 6) {
                                    ProgressView(value: viewModel.deviceService.importProgress, total: 100)
                                        .tint(Color.accent)
                                    Text(viewModel.deviceService.statusMessage)
                                        .font(.system(size: 10))
                                        .foregroundStyle(Color.textDim)
                                }
                            }

                            Button {
                                viewModel.exitDeviceBrowseMode()
                            } label: {
                                HStack {
                                    Image(systemName: "xmark.circle")
                                    Text("Desconnectar")
                                }
                            }
                            .buttonStyle(ToolbarButtonStyle())
                        }

                        Spacer()

                        // Status message (always visible)
                        Text(viewModel.deviceService.statusMessage)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.textSecondary)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(16)
                }
            }
            .frame(width: 300)
            .background(Color.bgBase)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color.borderSubtle)
                    .frame(width: 1)
            }
        }
    }
}
