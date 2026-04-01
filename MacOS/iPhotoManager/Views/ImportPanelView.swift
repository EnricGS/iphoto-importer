import SwiftUI

/// Modal dialog for device import (ImageCaptureCore on macOS).
/// Centered overlay with dimmed background.
/// Shows device detection, connection progress, browse status, and import progress.
struct ImportPanelView: View {
    @Bindable var viewModel: MainViewModel

    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture {
                    // Don't close if browsing or importing
                    if !viewModel.isDeviceBrowseMode && !viewModel.deviceService.isImporting {
                        viewModel.isImportPanelOpen = false
                    }
                }

            // Modal card
            VStack(spacing: 0) {
                // Header
                HStack {
                    Image(systemName: "iphone.and.arrow.forward")
                        .foregroundStyle(Color.accent)
                    Text("Importar des del dispositiu")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)

                    Spacer()

                    if !viewModel.isDeviceBrowseMode && !viewModel.deviceService.isImporting {
                        Button {
                            viewModel.isImportPanelOpen = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.textDim)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
                .background(Color.bgElevated)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.borderSubtle).frame(height: 1)
                }

                // Content
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

                            Text("Connecta un iPhone o càmera per USB i desbloqueja'l.")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.textDim)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)

                        Button {
                            Task { await viewModel.detectDevices() }
                        } label: {
                            HStack {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                Text("Detectar dispositius")
                            }
                        }
                        .buttonStyle(ToolbarButtonStyle())
                        .frame(maxWidth: .infinity)
                    }

                    // ── Device list ──
                    if !viewModel.deviceService.devices.isEmpty && !viewModel.isDeviceBrowseMode {
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
                            .padding(10)
                            .background(
                                viewModel.deviceService.selectedDevice == device
                                    ? Color.accentSubtle
                                    : Color.bgElevated
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .onTapGesture {
                                viewModel.deviceService.selectedDevice = device
                            }
                        }

                        if viewModel.deviceService.selectedDevice != nil && !viewModel.deviceService.isBrowsing {
                            Button {
                                Task { await viewModel.browseDevice() }
                            } label: {
                                HStack {
                                    Image(systemName: "eye")
                                    Text("Navegar fotos")
                                }
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            .frame(maxWidth: .infinity)
                        }
                    }

                    // ── Connection / Browse progress ──
                    if viewModel.deviceService.isBrowsing && !viewModel.isDeviceBrowseMode {
                        if let device = viewModel.deviceService.selectedDevice {
                            HStack(spacing: 8) {
                                Image(systemName: "iphone")
                                    .foregroundStyle(Color.accent)
                                Text(device.name)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Color.textPrimary)
                                Spacer()
                            }
                            .padding(10)
                            .background(Color.accentSubtle)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 10) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text(viewModel.deviceService.statusMessage)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.textSecondary)
                            }
                            if viewModel.deviceService.browseProgress > 0 && viewModel.deviceService.browseProgress < 100 {
                                ProgressView(value: viewModel.deviceService.browseProgress, total: 100)
                                    .tint(Color.accent)
                            }
                        }
                    }

                    // ── Browse mode info ──
                    if viewModel.isDeviceBrowseMode {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.successColor)
                            Text("\(viewModel.photos.count) fitxers carregats")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.textPrimary)
                        }

                        Text("Selecciona fotos a la graella i utilitza la barra inferior per importar o eliminar.")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.textDim)

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

                        HStack(spacing: 12) {
                            Button {
                                viewModel.isImportPanelOpen = false
                            } label: {
                                Text("D'acord")
                                    .font(.system(size: 13, weight: .medium))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(PrimaryButtonStyle())

                            Button {
                                viewModel.exitDeviceBrowseMode()
                                viewModel.isImportPanelOpen = false
                            } label: {
                                Text("Desconnectar")
                                    .font(.system(size: 13))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(ToolbarButtonStyle())
                        }
                    }

                    // Status message
                    if !viewModel.isDeviceBrowseMode {
                        Text(viewModel.deviceService.statusMessage)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.textSecondary)
                            .multilineTextAlignment(.leading)
                    }
                }
                .padding(20)
            }
            .frame(width: 420)
            .background(Color.bgBase)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
        }
    }
}
