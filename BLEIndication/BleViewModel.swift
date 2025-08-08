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
    private var userDisconnectedPeripherals: Set<UUID> = []
    private let restoreIdentifier = "someuniquevalue"
    
    // Target service and characteristic UUIDs
    nonisolated private let targetServiceUUID = CBUUID(string: "1ace5966-d918-451f-a7bd-b04d8533a219")
    nonisolated private let targetCharacteristicUUID = CBUUID(string: "d8be3fb7-6244-4f13-803d-ce083fd9d89e")
    
    // UserDefaults key for persisting connected peripherals
//    private let persistedPeripheralsKey = "PersistedPeripherals"
    
    override init() {
        super.init()
        
        let options: [String: Any] = [
            CBCentralManagerOptionRestoreIdentifierKey: restoreIdentifier
        ]
        
        centralManager = CBCentralManager(
            delegate: self,
            queue: DispatchQueue.main,
            options: options
        )
        
//        loadPersistedPeripherals()
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
    
    private func shouldReconnect(_ peripheral: CBPeripheral) -> Bool {
        return !userDisconnectedPeripherals.contains(peripheral.identifier)
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
            bluetoothState = central.state

            switch central.state {
            case .poweredOn:
                print("Bluetooth powered on")

            case .poweredOff:
                showError("Bluetooth is turned off. Please enable Bluetooth in Settings.")

            case .unauthorized:
                showError("Bluetooth access denied. Please enable Bluetooth permissions in Settings.")

            case .unsupported:
                showError("Bluetooth Low Energy is not supported on this device.")

            case .resetting:
                print("Bluetooth is resetting. Please wait...")

            case .unknown:
                showError("Bluetooth state is unknown. Please try again.")

            @unknown default:
                showError("Unknown Bluetooth state.")
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
        guard peripheralName.lowercased().contains("izdose") else { return }
        
        Task { @MainActor in
            discoveredPeripherals[peripheral.identifier] = peripheral
            
            let state: ConnectionState = connectedPeripherals[peripheral.identifier] != nil ? .connected : .disconnected
            addOrUpdatePeripheral(
                id: peripheral.identifier,
                name: peripheralName,
                rssi: RSSI.intValue,
                state: state
            )
        }
    }
    
    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            connectedPeripherals[peripheral.identifier] = peripheral
            peripheral.delegate = self
            updatePeripheralState(peripheral.identifier, to: .connected)
                
            print("Starting service discovery...")
            peripheral.discoverServices(nil)
        }
    }
    
    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            updatePeripheralState(peripheral.identifier, to: .disconnected)
            let peripheralName = peripheral.name ?? "Unknown Device"
            
            if let error = error {
                print("Failed to connect to \(peripheralName): \(error.localizedDescription)")
                
            } else {
                print("Connection failed to \(peripheralName) with no error details")

            }
        }
    }
    
    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            connectedPeripherals.removeValue(forKey: peripheral.identifier)
            updatePeripheralState(peripheral.identifier, to: .disconnected)
            
            if shouldReconnect(peripheral) {
                discoveredPeripherals[peripheral.identifier] = peripheral
                print("Device disconnected")
                centralManager.connect(peripheral, options: nil)
            }
        }
    }
    
    nonisolated func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        Task { @MainActor in
            if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
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
            
            if dict[CBCentralManagerRestoredStateScanServicesKey] != nil {
                startScanning()
            }
        }
    }
}

// MARK: - CBPeripheralDelegate
extension BleViewModel: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            print("Service discovery failed: \(error.localizedDescription)")
            return
        }
        
        guard let services = peripheral.services else {
            print("No services found")
            return
        }
        
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            print("Characteristic discovery failed for service \(service.uuid): \(error.localizedDescription)")
            return
        }
        
        guard let characteristics = service.characteristics else {
            return
        }
        
        for characteristic in characteristics {
            if service.uuid == targetServiceUUID && characteristic.uuid == targetCharacteristicUUID {
                print("Found target characteristic! Enabling indications...")
                peripheral.setNotifyValue(true, for: characteristic)
              print(characteristic.properties.description)
            }
        }
    }
    
    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("Failed to update notification state for \(characteristic.uuid): \(error.localizedDescription)")
            return
        }
        
        if characteristic.service?.uuid == targetServiceUUID && characteristic.uuid == targetCharacteristicUUID {
            if characteristic.isNotifying {
                print("Successfully enabled indications for target characteristic")
            } else {
                print("Indications disabled for target characteristic")
            }
        }
    }
    
    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("Error reading characteristic value: \(error.localizedDescription)")
            return
        }
        
        if characteristic.service?.uuid == targetServiceUUID && characteristic.uuid == targetCharacteristicUUID {
            if let data = characteristic.value {
                let formatter = DateFormatter()
                formatter.timeStyle = .medium
                formatter.dateStyle = .none
                
                if data.count >= 15 {
                  let event = decodeBytes(bytes: data)
                  print("Auto Increment: \(event.autoIncrement) Type: \(event.type)")
                }
                
            } else {
                print("Received indication with no data")
            }
        }
    }
}
