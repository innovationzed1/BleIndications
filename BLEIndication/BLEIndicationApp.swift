//
//  BleApp.swift
//  BLEIndication
//
//  Created by Piotr Dankowski on 07/08/2025.
//

import SwiftUI

@main
struct BleApp: App {
    @StateObject private var bleViewModel = BleViewModel()
    
    var body: some Scene {
        WindowGroup {
            BleScannerView()
                .environmentObject(bleViewModel)
        }
    }
}
