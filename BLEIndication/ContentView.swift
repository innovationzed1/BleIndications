//
//  BleScannerView.swift
//  BLEIndication
//
//  Created by Piotr Dankowski on 07/08/2025.
//

import SwiftUI
import CoreBluetooth

struct BleScannerView: View {
    @EnvironmentObject private var viewModel: BleViewModel
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Scan Button
                Button(action: {
                    if viewModel.isScanning {
                        viewModel.stopScanning()
                    } else {
                        viewModel.startScanning()
                    }
                }) {
                    HStack {
                        Image(systemName: viewModel.isScanning ? "stop.circle.fill" : "magnifyingglass.circle.fill")
                        Text(viewModel.isScanning ? "Stop Scan" : "Start Scan")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(viewModel.isScanning ? Color.red : Color.blue)
                    .cornerRadius(12)
                }
                .disabled(viewModel.bluetoothState != .poweredOn)
                .padding(.horizontal)
                
                // Status Info
                HStack {
                    Circle()
                        .fill(bluetoothStatusColor)
                        .frame(width: 12, height: 12)
                    Text("Bluetooth: \(bluetoothStatusText)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    if viewModel.isScanning {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
                .padding(.horizontal)
                
                // Peripherals List
                if viewModel.peripherals.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "antenna.radiowaves.left.and.right.slash")
                            .font(.system(size: 50))
                            .foregroundColor(.gray)
                        Text("No IZDOSE devices found")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text(viewModel.isScanning ? "Scanning..." : "Tap 'Start Scan' to search for devices")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    Spacer()
                } else {
                    List(viewModel.peripherals) { peripheral in
                        PeripheralRowView(peripheral: peripheral) {
                            handlePeripheralAction(peripheral)
                        }
                    }
                    .listStyle(PlainListStyle())
                }
                
                Spacer()
            }
            .navigationTitle("BLE Scanner")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Bluetooth Error", isPresented: $viewModel.showAlert) {
                Button("OK") { }
            } message: {
                Text(viewModel.alertMessage)
            }
        }
    }
    
    private var bluetoothStatusColor: Color {
        switch viewModel.bluetoothState {
        case .poweredOn: return .green
        case .poweredOff: return .red
        case .unauthorized: return .orange
        default: return .gray
        }
    }
    
    private var bluetoothStatusText: String {
        switch viewModel.bluetoothState {
        case .poweredOn: return "On"
        case .poweredOff: return "Off"
        case .unauthorized: return "Unauthorized"
        case .unsupported: return "Unsupported"
        case .resetting: return "Resetting"
        case .unknown: return "Unknown"
        @unknown default: return "Unknown"
        }
    }
    
    private func handlePeripheralAction(_ peripheral: DiscoveredPeripheral) {
        switch peripheral.state {
        case .disconnected:
            viewModel.connect(to: peripheral)
        case .connecting:
            break
        case .connected:
            viewModel.disconnect(from: peripheral)
        }
    }
}

struct PeripheralRowView: View {
    let peripheral: DiscoveredPeripheral
    let action: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Device Info
            VStack(alignment: .leading, spacing: 4) {
                Text(peripheral.name)
                    .font(.headline)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "wifi")
                            .font(.caption)
                        Text(peripheral.rssi.formattedRSSI)
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                    
                    ConnectionStatusBadge(state: peripheral.state)
                }
            }
            
            Spacer()
            
            // Action Button
            Button(action: action) {
                Text(peripheral.state.actionButtonTitle)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(peripheral.state.actionButtonColor)
                    .foregroundColor(.white)
                    .cornerRadius(20)
            }
            .disabled(peripheral.state == .connecting)
        }
        .padding(.vertical, 8)
    }
}

struct ConnectionStatusBadge: View {
    let state: ConnectionState
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(state.statusColor)
                .frame(width: 8, height: 8)
            
            Text(state.displayName)
                .font(.caption2)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(state.statusColor.opacity(0.1))
        .cornerRadius(8)
    }
}

#Preview {
    BleScannerView()
        .environmentObject({
            let vm = BleViewModel()
            return vm
        }()
        )
}
