//
//  BleViewModel.swift
//  BLEIndication
//
//  Created by Piotr Dankowski on 07/08/2025.
//

import Foundation
import CoreBluetooth
import Combine
import SwiftUI

// MARK: - Data Models
enum ConnectionState {
    case disconnected
    case connecting
    case connected
}

struct DiscoveredPeripheral: Identifiable, Hashable {
    let id: UUID
    let name: String
    var rssi: Int
    var state: ConnectionState
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: DiscoveredPeripheral, rhs: DiscoveredPeripheral) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - BLE View Model
@MainActor
class BleViewModel: NSObject, ObservableObject {
    @Published var peripherals: [DiscoveredPeripheral] = []
    @Published var isScanning = false
    @Published var bluetoothState: CBManagerState = .unknown
    @Published var showAlert = false
    @Published var alertMessage = ""
    
    private var centralManager: CBCentralManager!
    private var connectedPeripherals: [UUID: CBPeripheral] = [:]
    private var reconnectionTasks: [UUID: Task<Void, Never>] = [:]
    private var userDisconnectedPeripherals: Set<UUID> = []
    private let restoreIdentifier = "context7"
    
    // UserDefaults key for persisting connected peripherals
    private let persistedPeripheralsKey = "PersistedPeripherals"
    
    override init() {
        super.init()
        
        let options: [String: Any] = [
            CBCentralManagerOptionRestoreIdentifierKey: restoreIdentifier
        ]
        
        centralManager = CBCentralManager(
            delegate: self,
            queue: DispatchQueue.global(qos: .userInitiated),
            options: options
        )
        
        loadPersistedPeripherals()
    }
    
    // MARK: - Public Methods
    func startScanning() {
        guard centralManager.state == .poweredOn else {
            showError("Bluetooth must be turned on to scan for devices")
            return
        }
        
        let options: [String: Any] = [
            CBCentralManagerScanOptionAllowDuplicatesKey: true
        ]
        
        centralManager.scanForPeripherals(withServices: nil, options: options)
        isScanning = true
    }
    
    func stopScanning() {
        centralManager.stopScan()
        isScanning = false
    }
    
    func connect(to peripheral: DiscoveredPeripheral) {
        guard let cbPeripheral = findCBPeripheral(with: peripheral.id) else { return }
        
        updatePeripheralState(peripheral.id, to: .connecting)
        userDisconnectedPeripherals.remove(peripheral.id)
        
        centralManager.connect(cbPeripheral, options: nil)
    }
    
    func disconnect(from peripheral: DiscoveredPeripheral) {
        guard let cbPeripheral = connectedPeripherals[peripheral.id] else { return }
        
        userDisconnectedPeripherals.insert(peripheral.id)
        cancelReconnection(for: peripheral.id)
        centralManager.cancelPeripheralConnection(cbPeripheral)
    }
    
    // MARK: - Private Methods
    private func findCBPeripheral(with id: UUID) -> CBPeripheral? {
        if let peripheral = connectedPeripherals[id] {
            return peripheral
        }
        
        return centralManager.retrievePeripherals(withIdentifiers: [id]).first
    }
    
    private func updatePeripheralState(_ id: UUID, to state: ConnectionState) {
        if let index = peripherals.firstIndex(where: { $0.id == id }) {
            peripherals[index].state = state
        }
    }
    
    private func addOrUpdatePeripheral(
        id: UUID,
        name: String,
        rssi: Int,
        state: ConnectionState = .disconnected
    ) {
        if let index = peripherals.firstIndex(where: { $0.id == id }) {
            peripherals[index].rssi = rssi
            if peripherals[index].state == .disconnected {
                peripherals[index].state = state
            }
        } else {
            let newPeripheral = DiscoveredPeripheral(
                id: id,
                name: name,
                rssi: rssi,
                state: state
            )
            peripherals.append(newPeripheral)
        }
    }
    
    private func scheduleReconnection(for peripheralId: UUID, delay: TimeInterval = 3.0) {
        guard !userDisconnectedPeripherals.contains(peripheralId) else { return }
        
        let task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            
            guard !Task.isCancelled,
                  let self = self,
                  !self.userDisconnectedPeripherals.contains(peripheralId) else { return }
            
            await MainActor.run { [weak self] in
                guard let self = self,
                      let cbPeripheral = self.findCBPeripheral(with: peripheralId) else { return }
                
                self.centralManager.connect(cbPeripheral, options: nil)
                self.updatePeripheralState(peripheralId, to: .connecting)
                
                let nextDelay = min(delay * 1.5, 30.0)
                self.scheduleReconnection(for: peripheralId, delay: nextDelay)
            }
        }
        
        reconnectionTasks[peripheralId] = task
    }
    
    private func cancelReconnection(for peripheralId: UUID) {
        reconnectionTasks[peripheralId]?.cancel()
        reconnectionTasks.removeValue(forKey: peripheralId)
    }
    
    private func savePersistedPeripherals() {
        let connectedIds = Array(connectedPeripherals.keys).map { $0.uuidString }
        UserDefaults.standard.set(connectedIds, forKey: persistedPeripheralsKey)
    }
    
    private func loadPersistedPeripherals() {
        guard let savedIds = UserDefaults.standard.array(forKey: persistedPeripheralsKey) as? [String] else {
            return
        }
        
        let uuids = savedIds.compactMap { UUID(uuidString: $0) }
        let peripherals = centralManager?.retrievePeripherals(withIdentifiers: uuids) ?? []
        
        for peripheral in peripherals {
            if peripheral.state == .connected {
                connectedPeripherals[peripheral.identifier] = peripheral
                peripheral.delegate = self
                
                let name = peripheral.name ?? "Unknown Device"
                if name.lowercased().contains("izdose") {
                    addOrUpdatePeripheral(
                        id: peripheral.identifier,
                        name: name,
                        rssi: -50,
                        state: .connected
                    )
                }
            }
        }
    }
    
    private func showError(_ message: String) {
        alertMessage = message
        showAlert = true
    }
    
    private func isIzdoseDevice(_ name: String?) -> Bool {
        guard let name = name else { return false }
        return name.lowercased().contains("izdose")
    }
}

// MARK: - CBCentralManagerDelegate
extension BleViewModel: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            self.bluetoothState = central.state
            
            switch central.state {
            case .poweredOn:
                break
            case .poweredOff:
                self.showError("Bluetooth is turned off. Please enable Bluetooth in Settings.")
            case .unauthorized:
                self.showError("Bluetooth access denied. Please enable Bluetooth permissions in Settings.")
            case .unsupported:
                self.showError("Bluetooth Low Energy is not supported on this device.")
            case .resetting:
                self.showError("Bluetooth is resetting. Please wait.")
            case .unknown:
                self.showError("Bluetooth state is unknown. Please try again.")
            @unknown default:
                self.showError("Unknown Bluetooth state.")
            }
        }
    }
    
    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let peripheralName = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "Unknown Device"
        
        // Check if device name contains "izdose" (case-insensitive)
        guard peripheralName.lowercased().contains("izdose") else { return }
        
        Task { @MainActor in
            let state: ConnectionState = self.connectedPeripherals[peripheral.identifier] != nil ? .connected : .disconnected
            self.addOrUpdatePeripheral(
                id: peripheral.identifier,
                name: peripheralName,
                rssi: RSSI.intValue,
                state: state
            )
        }
    }
    
    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            self.connectedPeripherals[peripheral.identifier] = peripheral
            peripheral.delegate = self
            self.updatePeripheralState(peripheral.identifier, to: .connected)
            self.cancelReconnection(for: peripheral.identifier)
            self.savePersistedPeripherals()
        }
    }
    
    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            self.updatePeripheralState(peripheral.identifier, to: .disconnected)
            
            if let error = error {
                self.showError("Failed to connect: \(error.localizedDescription)")
            }
            
            // Retry connection if not user-initiated disconnect
            if !self.userDisconnectedPeripherals.contains(peripheral.identifier) {
                self.scheduleReconnection(for: peripheral.identifier)
            }
        }
    }
    
    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            self.connectedPeripherals.removeValue(forKey: peripheral.identifier)
            self.updatePeripheralState(peripheral.identifier, to: .disconnected)
            self.savePersistedPeripherals()
            
            // Only attempt reconnection if not user-initiated
            if !self.userDisconnectedPeripherals.contains(peripheral.identifier) {
                self.scheduleReconnection(for: peripheral.identifier)
            }
        }
    }
    
    nonisolated func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        Task { @MainActor in
            if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
                for peripheral in peripherals {
                    if peripheral.state == .connected {
                        self.connectedPeripherals[peripheral.identifier] = peripheral
                        peripheral.delegate = self
                        
                        let name = peripheral.name ?? "Unknown Device"
                        if name.lowercased().contains("izdose") {
                            self.addOrUpdatePeripheral(
                                id: peripheral.identifier,
                                name: name,
                                rssi: -50,
                                state: .connected
                            )
                        }
                    }
                }
            }
            
            // Resume scanning if it was active
            if dict[CBCentralManagerRestoredStateScanServicesKey] != nil {
                self.startScanning()
            }
        }
    }
}

// MARK: - CBPeripheralDelegate
extension BleViewModel: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        // Implementation for service discovery if needed
    }
    
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        // Implementation for characteristic discovery if needed
    }
}