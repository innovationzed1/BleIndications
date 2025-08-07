//
//  Extensions.swift
//  BLEIndication
//
//  Created by Piotr Dankowski on 07/08/2025.
//

import SwiftUI
import Foundation

// MARK: - Connection State Extensions
extension ConnectionState {
    var displayName: String {
        switch self {
        case .disconnected:
            return "Disconnected"
        case .connecting:
            return "Connecting..."
        case .connected:
            return "Connected"
        }
    }
    
    var statusColor: Color {
        switch self {
        case .disconnected:
            return .gray
        case .connecting:
            return .orange
        case .connected:
            return .green
        }
    }
    
    var actionButtonTitle: String {
        switch self {
        case .disconnected:
            return "Connect"
        case .connecting:
            return "Connecting..."
        case .connected:
            return "Disconnect"
        }
    }
    
    var actionButtonColor: Color {
        switch self {
        case .disconnected:
            return .blue
        case .connecting:
            return .orange
        case .connected:
            return .red
        }
    }
}

// MARK: - RSSI Formatting
extension Int {
    var formattedRSSI: String {
        return "\(self) dBm"
    }
}

// MARK: - UUID Extensions
extension UUID {
    var shortString: String {
        let uuidString = self.uuidString
        return String(uuidString.prefix(8))
    }
}