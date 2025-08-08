# BLE Indications Test App

This iOS app tests Bluetooth Low Energy (BLE) indications reliability with automatic reconnection functionality.

## Running the App on iPhone

### Prerequisites
- Mac with Xcode 16.0 or later
- iPhone running iOS 18.0 or later
- Apple ID for code signing

### Step-by-Step Installation

#### 1. Setup Code Signing in Xcode
1. Open `BLEIndication.xcodeproj` in Xcode
2. Select the project root in the navigator
3. Select the `BLEIndication` target
4. Go to the **"Signing & Capabilities"** tab
5. Check **"Automatically manage signing"**
6. In the **"Team"** dropdown, select your personal Apple ID team
   - If not listed, click "Add Account..." and sign in with your Apple ID
7. Ensure the **Bundle Identifier** is unique (e.g., `com.yourname.BLEIndication`)

#### 2. Connect and Select Your iPhone
1. Connect your iPhone to your Mac via USB cable
2. Trust the computer if prompted on your iPhone
3. In Xcode, select your iPhone from the device dropdown (next to the play button)
4. If your device doesn't appear, ensure:
   - iPhone is unlocked
   - "Trust This Computer" was selected
   - Developer mode is enabled (iOS 16+)

#### 3. Build and Install
1. Click the **Play button** (▶️) or press `Cmd+R` to build and run
2. Wait for the build to complete and install on your iPhone

#### 4. Trust the App on iPhone
**Important**: The app won't launch initially due to security restrictions.

1. On your iPhone, go to **Settings** > **General** > **VPN & Device Management**
2. Under **"Developer App"**, find your Apple ID
3. Tap on your Apple ID
4. Tap **"Trust [Your Apple ID]"**
5. Tap **"Trust"** in the confirmation dialog

#### 5. Launch the App
1. Find the **BLEIndication** app on your iPhone home screen
2. Tap to launch the app
3. Grant Bluetooth permissions when prompted

### Usage
1. Ensure your IzDose device is powered on and advertising
2. Tap **"Start Scanning"** to discover devices
3. Tap **"Connect"** next to your IzDose device
4. The app will automatically connect to the device and enable indications
5. View real-time indication data in Xcode console or device logs

## Problem Statement

**Issue**: BLE indications are lost during automatic reconnection after connection drops, even though the device correctly resends them and iOS acknowledges them at the radio layer.

## Experimental Setup

### Device Under Test
- **Target Service**: `1ace5966-d918-451f-a7bd-b04d8533a219`  
- **Target Characteristic**: `d8be3fb7-6244-4f13-803d-ce083fd9d89e`
- **Data Pattern**: 15-byte indications with auto-increment counter

### Test Procedure
1. **Initial Connection**: Connect iOS app to device
2. **Baseline Verification**: Trigger one indication to confirm working connection (logged in app.log)
3. **Force Disconnection**: Move device out of range until "Device disconnected" appears in log
4. **Generate Missed Data**: Trigger multiple indications while out of range (device buffers these)
5. **Reconnection**: Return device to range and wait for automatic reconnection
6. **Monitor Recovery**: Observe "Starting service discovery..." → "Found target characteristic! Enabling indications..." → "Successfully enabled indications for target characteristic"
7. **Data Reception**: Monitor timestamped indication data reception

## Device Behavior (Per Hardware Team)

### Standard BLE Compliance
- **CCCD Persistence**: Device maintains Client Characteristic Configuration Descriptor (CCCD) with indication-enabled state across reconnections
- **Resume Point**: Device resends indications starting from the last unacknowledged indication before disconnection
- **No Custom Logic**: Follows standard BLE specification for indication reliability

### Expected Behavior
- **Complete Data Recovery**: All buffered indications should be delivered after reconnection

## Observed Problem

### Symptom
**Indication Loss**: On each reconnection, some indications are lost despite proper BLE protocol compliance at radio layer.

### Evidence
- **Radio Layer Success**: Wireshark packet capture shows all indications are sent by device and acknowledged by iOS
- **Application Layer Failure**: `didUpdateValueFor` delegate method receives fewer indications than sent
- **Timing Issue**: Device sends indications faster than iOS can deliver them to the application layer

## Investigation Data

### Log Analysis Setup
- **app.log**: Application-level logs with precise timestamps
- **debugIndications.log**: PacketLogger capture from Xcode toolbox  
- **Wireshark Analysis**: Convert PacketLogger to Wireshark format

### Wireshark Filtering
```
btatt.handle == 0x0028 || bthci_evt.code == 0x05
```
- `handle 0x0028`: Shows indications and acknowledgments for target characteristic
- `bthci_evt.code == 0x05`: Shows disconnect events for test phase identification

### Timestamp Synchronization
- **Time Shift**: Wireshark timestamps need -4:00:00 offset to match app.log
- **Precision Difference**: Millisecond-level variance between logs

## Key Finding

### Radio vs Application Layer Discrepancy
**Consistent Pattern**: Wireshark captures show MORE indications than app.log receives, with ALL indications properly acknowledged at the BLE protocol level.

**Conclusion**: There exists a **timing window** where iOS CoreBluetooth stack can receive and acknowledge indications at the radio layer, but fails to deliver them to the application's `didUpdateValueFor` callback.

## Technical Analysis Request

**Root Cause**: What causes this gap between radio-layer acknowledgment and application-layer delivery in iOS CoreBluetooth?
**Solution Needed**: How to ensure reliable delivery of all acknowledged indications to the application layer during reconnection scenarios?


