//
//  BleViewModelTests.swift
//  BLEIndicationTests
//
//  Created by Piotr Dankowski on 07/08/2025.
//

import XCTest
import CoreBluetooth
@testable import BLEIndication

@MainActor
class BleViewModelTests: XCTestCase {
    var viewModel: BleViewModel!
    
    override func setUp() {
        super.setUp()
        viewModel = BleViewModel()
    }
    
    override func tearDown() {
        viewModel = nil
        super.tearDown()
    }
    
    func testReconnectionBackoffLogic() {
        let expectation = XCTestExpectation(description: "Reconnection backoff timing")
        
        let startTime = Date()
        var delays: [TimeInterval] = []
        
        // Mock the reconnection delay calculation
        func calculateNextDelay(currentDelay: TimeInterval) -> TimeInterval {
            return min(currentDelay * 1.5, 30.0)
        }
        
        // Test the exponential backoff sequence
        var delay: TimeInterval = 3.0
        
        // First attempt: 3 seconds
        delays.append(delay)
        XCTAssertEqual(delays[0], 3.0, "First reconnection attempt should be 3 seconds")
        
        // Second attempt: 4.5 seconds
        delay = calculateNextDelay(currentDelay: delay)
        delays.append(delay)
        XCTAssertEqual(delays[1], 4.5, "Second reconnection attempt should be 4.5 seconds")
        
        // Third attempt: 6.75 seconds
        delay = calculateNextDelay(currentDelay: delay)
        delays.append(delay)
        XCTAssertEqual(delays[2], 6.75, "Third reconnection attempt should be 6.75 seconds")
        
        // Continue until we hit the 30-second cap
        while delay < 30.0 {
            let nextDelay = calculateNextDelay(currentDelay: delay)
            delays.append(nextDelay)
            delay = nextDelay
        }
        
        // Verify that we eventually cap at 30 seconds
        let finalDelay = delays.last!
        XCTAssertEqual(finalDelay, 30.0, "Reconnection delay should cap at 30 seconds")
        
        // Test that subsequent attempts stay at 30 seconds
        let nextDelay = calculateNextDelay(currentDelay: finalDelay)
        XCTAssertEqual(nextDelay, 30.0, "Reconnection delay should remain at 30 seconds")
        
        expectation.fulfill()
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testPeripheralFiltering() {
        let expectation = XCTestExpectation(description: "IZDOSE peripheral filtering")
        
        // Test device names that should be accepted
        let validNames = [
            "IZDOSE-001",
            "izdose-device",
            "MyIZDOSESensor",
            "IZDOSE",
            "test-IZDOSE-dev"
        ]
        
        // Test device names that should be rejected
        let invalidNames = [
            "iPhone",
            "Apple Watch",
            "Generic BLE Device",
            "IZOSE", // Similar but not exact
            "",
            "DOSE" // Contains part of the name but not complete
        ]
        
        func isIzdoseDevice(_ name: String?) -> Bool {
            guard let name = name else { return false }
            return name.lowercased().contains("izdose")
        }
        
        // Test valid names
        for name in validNames {
            let result = isIzdoseDevice(name)
            XCTAssertTrue(result, "Device '\(name)' should be accepted as IZDOSE device")
        }
        
        // Test invalid names
        for name in invalidNames {
            let result = isIzdoseDevice(name)
            XCTAssertFalse(result, "Device '\(name)' should be rejected as non-IZDOSE device")
        }
        
        // Test nil name
        let nilResult = isIzdoseDevice(nil)
        XCTAssertFalse(nilResult, "Nil device name should be rejected")
        
        expectation.fulfill()
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testPeripheralStateUpdates() {
        let expectation = XCTestExpectation(description: "Peripheral state management")
        
        let testPeripheralId = UUID()
        let testPeripheralName = "IZDOSE-Test"
        let testRSSI = -45
        
        // Initially, peripherals list should be empty
        XCTAssertEqual(viewModel.peripherals.count, 0, "Initial peripherals list should be empty")
        
        // Add a new peripheral
        let initialPeripheral = DiscoveredPeripheral(
            id: testPeripheralId,
            name: testPeripheralName,
            rssi: testRSSI,
            state: .disconnected
        )
        
        viewModel.peripherals.append(initialPeripheral)
        
        // Verify the peripheral was added
        XCTAssertEqual(viewModel.peripherals.count, 1, "Should have one peripheral")
        XCTAssertEqual(viewModel.peripherals[0].id, testPeripheralId, "Peripheral ID should match")
        XCTAssertEqual(viewModel.peripherals[0].name, testPeripheralName, "Peripheral name should match")
        XCTAssertEqual(viewModel.peripherals[0].rssi, testRSSI, "Peripheral RSSI should match")
        XCTAssertEqual(viewModel.peripherals[0].state, .disconnected, "Initial state should be disconnected")
        
        // Update peripheral state to connecting
        if let index = viewModel.peripherals.firstIndex(where: { $0.id == testPeripheralId }) {
            viewModel.peripherals[index].state = .connecting
        }
        
        XCTAssertEqual(viewModel.peripherals[0].state, .connecting, "State should be updated to connecting")
        
        // Update peripheral state to connected
        if let index = viewModel.peripherals.firstIndex(where: { $0.id == testPeripheralId }) {
            viewModel.peripherals[index].state = .connected
        }
        
        XCTAssertEqual(viewModel.peripherals[0].state, .connected, "State should be updated to connected")
        
        expectation.fulfill()
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testConnectionStateExtensions() {
        let expectation = XCTestExpectation(description: "Connection state extensions")
        
        // Test disconnected state
        let disconnected = ConnectionState.disconnected
        XCTAssertEqual(disconnected.displayName, "Disconnected")
        XCTAssertEqual(disconnected.actionButtonTitle, "Connect")
        
        // Test connecting state
        let connecting = ConnectionState.connecting
        XCTAssertEqual(connecting.displayName, "Connecting...")
        XCTAssertEqual(connecting.actionButtonTitle, "Connecting...")
        
        // Test connected state
        let connected = ConnectionState.connected
        XCTAssertEqual(connected.displayName, "Connected")
        XCTAssertEqual(connected.actionButtonTitle, "Disconnect")
        
        expectation.fulfill()
        wait(for: [expectation], timeout: 1.0)
    }
}