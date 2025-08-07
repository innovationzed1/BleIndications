//
//  DataStructures.swift
//  BLEIndication
//
//  Created by Claude on 07/08/2025.
//

import Foundation

// MARK: - Event Structure
struct Event {
    let autoIncrement: Int
    let type: EventType
    let resetCounter: Int
    let deviceTimestamp: Int
    let additionalData: AdditionalData
}

// MARK: - Additional Data Protocol
protocol AdditionalData {}

// MARK: - Event Types
enum EventType: UInt16, CaseIterable {
    case DuNo = 0x0001
    case Injection = 0x0002
    case AdjustedInjection = 0x0003
    case Battery = 0x0004
    case WakeUp = 0x0005
    case WakeUpSource = 0x0006
    case Mounting = 0x0007
    case SystemError = 0x0008
    case SystemReset = 0x0009
    case TemperatureWarning = 0x000A
    case FailedRead = 0x000B
    case DFUEvent = 0x000C
    case ModeChange = 0x000D
    case Logging = 0x000E
    case Saturation = 0x000F
    case KwikPenCalibration = 0x0010
    case IncorrectMountingError = 0x0011
    case PenSelect = 0x0012
    case Unknown = 0xFFFF
    
    var hex: UInt16 {
        return self.rawValue
    }
}

// MARK: - Empty Additional Data
struct EmptyAD: AdditionalData {}

// MARK: - Injection Status
enum InjectionStatus: UInt16, CaseIterable {
    case Success = 0x01
    case InProgress = 0x02
    case Failed = 0x03
    case Cancelled = 0x04
    case Unknown = 0xFF
    
    var hex: [UInt16]? {
        return [self.rawValue]
    }
}

struct InjectionAD: AdditionalData {
    let status: InjectionStatus
    let units: Int
    let temp: Int
    let voltage: Double
}

// MARK: - Adjusted Injection Status
enum AdjustedInjectionStatus: UInt16, CaseIterable {
    case Success = 0x01
    case Failed = 0x02
    case Unknown = 0xFF
    
    var hex: UInt16 {
        return self.rawValue
    }
}

struct AdjustedInjectionAD: AdditionalData {
    let previousAmount: Int
    let adjustedAmount: Int
    let status: AdjustedInjectionStatus
}

// MARK: - Battery Status
enum BatteryStatus: UInt16, CaseIterable {
    case Normal = 0x01
    case Low = 0x02
    case Critical = 0x03
    case Charging = 0x04
    case Unknown = 0xFF
    
    var hex: UInt16 {
        return self.rawValue
    }
}

struct BatteryEventAD: AdditionalData {
    let status: BatteryStatus
    let voltage: Double
    let isCharging: Bool
}

// MARK: - Wake Up Status
enum WakeUpStatus: UInt16, CaseIterable {
    case WakeUp = 0x01
    case SleepEvent = 0x02
    case ForceSleep = 0x03
    case Unknown = 0xFF
    
    var hex: UInt16 {
        return self.rawValue
    }
}

enum WakeUpState: UInt16, CaseIterable {
    case Active = 0x01
    case Idle = 0x02
    case Sleep = 0x03
    case Unknown = 0xFF
    
    var hex: UInt16 {
        return self.rawValue
    }
}

enum WakeUpKeep: UInt16, CaseIterable {
    case None = 0x00
    case BLEKeepAwake = 0x01
    case ChargingKeepAwake = 0x02
    case Unknown = 0xFF
    
    var hex: UInt16 {
        return self.rawValue
    }
}

struct WakeUpEventAD: AdditionalData {
    let status: WakeUpStatus
    let state: WakeUpState
    let keep: WakeUpKeep
}

// MARK: - Wake Up Source
enum WakeUpSource: Int, CaseIterable {
    case Move = 0x01
    case Button = 0x02
    case Timer = 0x03
    case BLE = 0x04
    case Charging = 0x05
    case Unknown = 0xFF
    
    var payload: Int {
        return self.rawValue
    }
}

struct WakeUpSourceEventAD: AdditionalData {
    let source: WakeUpSource
    let sensitivity: Int
}

// MARK: - Mounting Status
enum MountingStatus: UInt16, CaseIterable {
    case Mounted = 0x01
    case Unmounted = 0x02
    case Error = 0x03
    case Unknown = 0xFF
    
    var hex: UInt16 {
        return self.rawValue
    }
}

struct MountingEventAD: AdditionalData {
    let status: MountingStatus
}

// MARK: - System Error Status
enum SystemErrorStatus: UInt16, CaseIterable {
    case MemoryError = 0x01
    case HardwareError = 0x02
    case SoftwareError = 0x03
    case CommunicationError = 0x04
    case Unknown = 0xFF
    
    var hex: UInt16 {
        return self.rawValue
    }
}

struct SystemErrorEventAD: AdditionalData {
    let status: SystemErrorStatus
    let voltage: Double
    let isCharging: Bool
}

// MARK: - System Reset Status
enum SystemResetStatus: UInt16, CaseIterable {
    case PowerOn = 0x01
    case SoftwareReset = 0x02
    case HardwareReset = 0x03
    case WatchdogReset = 0x04
    case Unknown = 0xFF
    
    var hex: UInt16 {
        return self.rawValue
    }
}

struct SystemResetEventAD: AdditionalData {
    let status: SystemResetStatus
    let voltage: Double
    let isCharging: Bool
}

// MARK: - Temperature Warning Status
enum TemperatureWarningStatus: UInt16, CaseIterable {
    case HighTemperature = 0x01
    case LowTemperature = 0x02
    case Normal = 0x03
    case Unknown = 0xFF
    
    var hex: UInt16 {
        return self.rawValue
    }
}

struct TemperatureThreshold {
    let high: Int
    let low: Int
}

struct TemperatureWarningEventAD: AdditionalData {
    let status: TemperatureWarningStatus
    let currentTemp: Int
    let threshold: TemperatureThreshold
}

// MARK: - Failed Read Status
enum FailedReadStatus: UInt16, CaseIterable {
    case SensorError = 0x01
    case CommunicationError = 0x02
    case TimeoutError = 0x03
    case Unknown = 0xFF
    
    var hex: UInt16 {
        return self.rawValue
    }
}

struct FailedReadEventAD: AdditionalData {
    let status: FailedReadStatus
}

// MARK: - DFU Status
enum DFUStatus: UInt16, CaseIterable {
    case Started = 0x01
    case InProgress = 0x02
    case Completed = 0x03
    case Failed = 0x04
    case Cancelled = 0x05
    case Unknown = 0xFF
    
    var hex: UInt16 {
        return self.rawValue
    }
}

struct DFUEventAD: AdditionalData {
    let status: DFUStatus
}

// MARK: - Mode Change Status
enum ModeChangeStatus: UInt16, CaseIterable {
    case NormalMode = 0x01
    case CalibrationMode = 0x02
    case TestMode = 0x03
    case MaintenanceMode = 0x04
    case Unknown = 0xFF
    
    var hex: UInt16 {
        return self.rawValue
    }
}

struct ModeChangeEventAD: AdditionalData {
    let status: ModeChangeStatus
}

// MARK: - Logging Status
enum LoggingStatus: UInt16, CaseIterable {
    case Started = 0x01
    case Stopped = 0x02
    case Error = 0x03
    case FileCreated = 0x04
    case FileClosed = 0x05
    case Unknown = 0xFF
    
    var hex: UInt16 {
        return self.rawValue
    }
}

struct LoggingEventAD: AdditionalData {
    let status: LoggingStatus
    let fileId: Int
    let voltage: Double
}

// MARK: - Saturation Status
enum SaturationStatus: UInt16, CaseIterable {
    case Normal = 0x01
    case Saturated = 0x02
    case Recovering = 0x03
    case Unknown = 0xFF
    
    var hex: UInt16 {
        return self.rawValue
    }
}

struct SaturationEventAD: AdditionalData {
    let status: SaturationStatus
}

// MARK: - KwikPen Calibration
struct KwikpenCalibrationEventAD: AdditionalData {
    let shaftIR: Int
    let knobIR: Int
}

// MARK: - Incorrect Mounting Error Status
enum IncorrentMountingErrorStatus: UInt16, CaseIterable {
    case WrongOrientation = 0x01
    case PartialMount = 0x02
    case Loose = 0x03
    case NotDetected = 0x04
    case Unknown = 0xFF
    
    var hex: UInt16 {
        return self.rawValue
    }
}

struct IncorrectMountingErrorEventAD: AdditionalData {
    let status: IncorrentMountingErrorStatus
}

// MARK: - Pen Select
struct PenSelectEventAD: AdditionalData {
    let penType: Int
    let majorVersion: Int
    let minorVersion: Int
}

// MARK: - Helper Functions
func doseEventAutoincrementToInt(_ bytes: [UInt8]) -> Int {
    guard bytes.count >= 4 else { return 0 }
    return Int(bytes[0]) | (Int(bytes[1]) << 8) | (Int(bytes[2]) << 16) | (Int(bytes[3]) << 24)
}

func calcVoltage(_ rawValue: Int) -> Double {
    // Convert raw ADC value to voltage
    // Assuming 12-bit ADC with 3.3V reference
    let adcResolution = 4096.0 // 12-bit ADC
    let referenceVoltage = 3.3
    let voltageDividerRatio = 2.0 // Common voltage divider for battery monitoring
    
    return (Double(rawValue) / adcResolution) * referenceVoltage * voltageDividerRatio
}
