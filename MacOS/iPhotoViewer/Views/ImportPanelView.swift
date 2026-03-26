import SwiftUI

/// Side panel for device import (MTP / ImageCaptureCore).
/// Slides in from the right side of the window.
struct ImportPanelView: View {
    @Bindable var viewModel: MainViewModel

    var body: some View {
        HStack(spacing: 0) {
            Spacer()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Image(systemName: "square.and.arrow.down")
                        .foregroundStyle(Color.accent)
                    Text("Import from Device")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)

                    Spacer()

                    Button {
                        viewModel.toggleImportPanel()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
                .background(Color.bgMedium)
                .overlay(alignment: .bottom) { Divider() }

                // Content
                VStack(alignment: .leading, spacing: 16) {
                    // Detect devices
                    Button {
                        Task { await viewModel.detectDevices() }
                    } label: {
                        Label("Detect Devices", systemImage: "antenna.radiowaves.left.and.right")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(viewModel.deviceService.isScanning)

                    // Device list
                    if viewModel.deviceService.devices.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "iphone.slash")
                                .font(.system(size: 32))
                                .foregroundStyle(Color.textDim)

                            Text("No devices detected")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.textSecondary)

                            Text("Connect an iPhone or camera via USB and press Detect.")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.textDim)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    } else {
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
                                    ? Color.accent.opacity(0.1)
                                    : Color.clear
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .onTapGesture {
                                viewModel.deviceService.selectedDevice = device
                            }
                        }
                    }

                    // Import button
                    if viewModel.deviceService.selectedDevice != nil {
                        Button {
                            Task { await viewModel.importFromDevice() }
                        } label: {
                            Label("Import Photos", systemImage: "square.and.arrow.down.on.square")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }

                    Spacer()

                    // Status message
                    Text(viewModel.deviceService.statusMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.leading)

                    // Platform note
                    VStack(alignment: .leading, spacing: 4) {
                        Text("macOS Note")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.textSecondary)
                        Text("Device import on macOS uses ImageCaptureCore framework instead of Windows MTP. Full implementation requires running on macOS with Xcode.")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.textDim)
                    }
                    .padding(8)
                    .background(Color.bgLight)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .padding(16)
            }
            .frame(width: 320)
            .background(Color.bgDark)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color.borderColor)
                    .frame(width: 1)
            }
        }
    }
}
