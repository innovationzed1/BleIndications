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
    private var discoveredPeripherals: [UUID: CBPeripheral] = [:]
    private var reconnectionTasks: [UUID: Task<Void, Never>] = [:]
    private var userDisconnectedPeripherals: Set<UUID> = []
    private let restoreIdentifier = "context7"
    
    // Target service and characteristic UUIDs
    private let targetServiceUUID = CBUUID(string: "1ace5966-d918-451f-a7bd-b04d8533a219")
    private let targetCharacteristicUUID = CBUUID(string: "d8be3fb7-6244-4f13-803d-ce083fd9d89e")
    
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
        
        if let peripheral = discoveredPeripherals[id] {
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
        // Don't reconnect if user explicitly disconnected
        guard !userDisconnectedPeripherals.contains(peripheralId) else {
            print("🚫 Skipping reconnection for \(peripheralId.uuidString.prefix(8)) - user disconnected")
            return
        }
        
        // Don't reconnect if Bluetooth is not available
        guard centralManager.state == .poweredOn else {
            print("⚠️ Bluetooth not ready for reconnection, will retry when available")
            return
        }
        
        // Cancel existing reconnection task for this peripheral
        cancelReconnection(for: peripheralId)
        
        print("⏳ Scheduling reconnection for \(peripheralId.uuidString.prefix(8)) in \(delay)s")
        
        let task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            
            guard !Task.isCancelled else { 
                print("❌ Reconnection task cancelled for \(peripheralId.uuidString.prefix(8))")
                return 
            }
            
            await MainActor.run { [weak self] in
                guard let self = self else { return }
                
                // Double-check conditions before attempting reconnection
                guard !self.userDisconnectedPeripherals.contains(peripheralId),
                      self.centralManager.state == .poweredOn else {
                    print("⚠️ Conditions not met for reconnection")
                    return
                }
                
                // Find the peripheral - try multiple sources
                var cbPeripheral = self.findCBPeripheral(with: peripheralId)
                
                if cbPeripheral == nil {
                    // If not found in caches, try retrieving from system
                    let retrievedPeripherals = self.centralManager.retrievePeripherals(withIdentifiers: [peripheralId])
                    cbPeripheral = retrievedPeripherals.first
                }
                
                guard let peripheral = cbPeripheral else {
                    print("❌ Could not find peripheral for reconnection: \(peripheralId.uuidString.prefix(8))")
                    // Schedule another attempt with longer delay
                    let nextDelay = min(delay * 2.0, 60.0)
                    if nextDelay < 60.0 {
                        self.scheduleReconnection(for: peripheralId, delay: nextDelay)
                    }
                    return
                }
                
                // Check if already connected
                if peripheral.state == .connected {
                    print("✅ Peripheral already connected: \(peripheral.name ?? "Unknown")")
                    self.connectedPeripherals[peripheralId] = peripheral
                    peripheral.delegate = self
                    self.updatePeripheralState(peripheralId, to: .connected)
                    return
                }
                
                // Check if already connecting
                if peripheral.state == .connecting {
                    print("🔄 Peripheral already connecting, waiting...")
                    // Schedule a check in a shorter time
                    self.scheduleReconnection(for: peripheralId, delay: 5.0)
                    return
                }
                
                print("🔄 Attempting reconnection to \(peripheral.name ?? "Unknown Device")")
                
                // Store peripheral reference before attempting connection
                self.discoveredPeripherals[peripheralId] = peripheral
                
                // Attempt connection
                self.centralManager.connect(peripheral, options: nil)
                self.updatePeripheralState(peripheralId, to: .connecting)
                
                // Don't immediately schedule next reconnection here
                // Let didConnect or didFailToConnect handle it
            }
        }
        
        reconnectionTasks[peripheralId] = task
    }
    
    private func cancelReconnection(for peripheralId: UUID) {
        reconnectionTasks[peripheralId]?.cancel()
        reconnectionTasks.removeValue(forKey: peripheralId)
    }
    
    private func cancelAllReconnections() {
        print("🚫 Cancelling all reconnection attempts")
        for task in reconnectionTasks.values {
            task.cancel()
        }
        reconnectionTasks.removeAll()
    }
    
    private func resumePendingReconnections() {
        // Resume reconnections for peripherals that should be connected but aren't
        let disconnectedPeripherals = peripherals.filter { peripheral in
            peripheral.state == .disconnected && 
            !userDisconnectedPeripherals.contains(peripheral.id) &&
            reconnectionTasks[peripheral.id] == nil
        }
        
        if !disconnectedPeripherals.isEmpty {
            print("🔄 Resuming reconnection for \(disconnectedPeripherals.count) peripherals")
            for peripheral in disconnectedPeripherals {
                scheduleReconnection(for: peripheral.id, delay: 1.0) // Start quickly
            }
        }
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
                print("✅ Bluetooth powered on - resuming reconnection attempts")
                // Resume any pending reconnections when Bluetooth becomes available
                self.resumePendingReconnections()
                
            case .poweredOff:
                self.showError("Bluetooth is turned off. Please enable Bluetooth in Settings.")
                // Cancel all reconnection attempts
                self.cancelAllReconnections()
                
            case .unauthorized:
                self.showError("Bluetooth access denied. Please enable Bluetooth permissions in Settings.")
                self.cancelAllReconnections()
                
            case .unsupported:
                self.showError("Bluetooth Low Energy is not supported on this device.")
                self.cancelAllReconnections()
                
            case .resetting:
                print("⚠️ Bluetooth is resetting. Please wait...")
                // Don't show error for resetting as it's temporary
                
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
            // Store peripheral reference to prevent deallocation
            self.discoveredPeripherals[peripheral.identifier] = peripheral
            
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
            
            print("✅ Connected to \(peripheral.name ?? "Unknown Device") (\(peripheral.identifier))")
            print("🔍 Starting service discovery...")
            
            // Start service discovery
            peripheral.discoverServices(nil)
        }
    }
    
    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            self.updatePeripheralState(peripheral.identifier, to: .disconnected)
            
            let peripheralName = peripheral.name ?? "Unknown Device"
            
            if let error = error {
                print("❌ Failed to connect to \(peripheralName): \(error.localizedDescription)")
                
                // Determine reconnection delay based on error type
                let reconnectionDelay: TimeInterval
                if let cbError = error as? CBError {
                    switch cbError.code {
                    case .connectionTimeout:
                        reconnectionDelay = 5.0  // Quick retry for timeout
                    case .peripheralDisconnected:
                        reconnectionDelay = 3.0  // Medium retry for disconnection
                    case .connectionFailed:
                        reconnectionDelay = 10.0 // Longer delay for connection failure
                    default:
                        reconnectionDelay = 3.0  // Default delay
                    }
                } else {
                    reconnectionDelay = 3.0
                }
                
                // Retry connection if not user-initiated disconnect
                if !self.userDisconnectedPeripherals.contains(peripheral.identifier) {
                    print("🔄 Will retry connection to \(peripheralName) in \(reconnectionDelay)s")
                    self.scheduleReconnection(for: peripheral.identifier, delay: reconnectionDelay)
                }
            } else {
                print("❌ Connection failed to \(peripheralName) with no error details")
                
                // Retry with default delay
                if !self.userDisconnectedPeripherals.contains(peripheral.identifier) {
                    self.scheduleReconnection(for: peripheral.identifier)
                }
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
        if let error = error {
            print("❌ Service discovery failed: \(error.localizedDescription)")
            return
        }
        
        guard let services = peripheral.services else {
            print("⚠️ No services found")
            return
        }
        
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            print("❌ Characteristic discovery failed for service \(service.uuid): \(error.localizedDescription)")
            return
        }
        
        guard let characteristics = service.characteristics else {
            return
        }
        
        for characteristic in characteristics {
            // Check if this is our target characteristic for indications
            if service.uuid == targetServiceUUID && characteristic.uuid == targetCharacteristicUUID {
                print("🎯 Found target characteristic! Enabling indications...")
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }
    
    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("❌ Failed to update notification state for \(characteristic.uuid): \(error.localizedDescription)")
            return
        }
        
        if characteristic.service?.uuid == targetServiceUUID && characteristic.uuid == targetCharacteristicUUID {
            if characteristic.isNotifying {
                print("✅ Successfully enabled indications for target characteristic")
            } else {
                print("⚠️ Indications disabled for target characteristic")
            }
        }
    }
    
    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("❌ Error reading characteristic value: \(error.localizedDescription)")
            return
        }
        
        // Check if this is our target characteristic
        if characteristic.service?.uuid == targetServiceUUID && characteristic.uuid == targetCharacteristicUUID {
            if let data = characteristic.value {
                let timestamp = Date()
                let formatter = DateFormatter()
                formatter.timeStyle = .medium
                formatter.dateStyle = .none
                
                if data.count >= 15 { // Minimum required bytes for event structure
                  let event = decodeBytes(bytes: data)
                  print("Auto Increment: \(event.autoIncrement) Type: \(event.type)")
                }
                
            } else {
                print("📨 Received indication with no data")
            }
        }
    }
}
