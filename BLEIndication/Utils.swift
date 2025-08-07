//
//  Utils.swift
//  BLEIndication
//
//  Created by Piotr Dankowski on 07/08/2025.
//

import Foundation

func decodeBytes(bytes: Data) -> Event {
  let autoIncrement = doseEventAutoincrementToInt([bytes[0], bytes[1], bytes[2], bytes[3]])
  let typeBytes = (UInt16(bytes[5]) << 8) | UInt16(bytes[4])
  let type = EventType.allCases.first(where: { $0.hex == typeBytes }) ?? .Unknown
  let resetCounter = Int(UInt8(bytes[6]))
  let eventTimestamp =
  Int(bytes[10]) << 24 | Int(bytes[9]) << 16 | Int(bytes[8]) << 8 | Int(bytes[7])
  
  switch type {
  case .DuNo, .Injection:
    return Event(
      autoIncrement: autoIncrement,
      type: type,
      resetCounter: resetCounter,
      deviceTimestamp: eventTimestamp,
      additionalData: InjectionAD(
        status: InjectionStatus.allCases.first(where: {
          $0.hex?.contains { $0 == UInt16(bytes[12]) } ?? false
        }) ?? .Unknown,
        units: Int(bytes[11]),
        temp: Int(bytes[13]),
        voltage: calcVoltage(Int(bytes[14]))
      )
    )
  case .AdjustedInjection:
    return Event(
      autoIncrement: autoIncrement,
      type: type,
      resetCounter: resetCounter,
      deviceTimestamp: eventTimestamp,
      additionalData: AdjustedInjectionAD(
        previousAmount: Int(bytes[11]),
        adjustedAmount: Int(bytes[12]),
        status: AdjustedInjectionStatus.allCases.first(where: { $0.hex == UInt16(bytes[13]) })
        ?? .Unknown
      )
    )
  case .Battery:
    return Event(
      autoIncrement: autoIncrement,
      type: type,
      resetCounter: resetCounter,
      deviceTimestamp: eventTimestamp,
      additionalData: BatteryEventAD(
        status: BatteryStatus.allCases.first(where: { $0.hex == UInt16(bytes[11]) })
        ?? .Unknown,
        voltage: calcVoltage(Int(bytes[12])),
        isCharging: Int(bytes[13]) == 1
      )
    )
  case .WakeUp:
    let status = WakeUpStatus.allCases.first(where: { $0.hex == UInt16(bytes[11]) }) ?? .Unknown
    let state = WakeUpState.allCases.first(where: { $0.hex == UInt16(bytes[12]) }) ?? .Unknown
    let keep = WakeUpKeep.allCases.first(where: { $0.hex == UInt16(bytes[13]) }) ?? .Unknown
    let ignoreStateAndKeep: Bool = status == .SleepEvent || status == .ForceSleep
    let ignoreState = keep == .BLEKeepAwake || keep == .ChargingKeepAwake
    
    return Event(
      autoIncrement: autoIncrement,
      type: type,
      resetCounter: resetCounter,
      deviceTimestamp: eventTimestamp,
      additionalData: WakeUpEventAD(
        status: status,
        state: ignoreStateAndKeep || ignoreState ? .Unknown : state,
        keep: ignoreStateAndKeep ? .Unknown : keep
      )
    )
  case .WakeUpSource:
    return Event(
      autoIncrement: autoIncrement,
      type: type,
      resetCounter: resetCounter,
      deviceTimestamp: eventTimestamp,
      additionalData: WakeUpSourceEventAD(
        source: WakeUpSource.allCases.first(where: { $0.payload == Int(bytes[11]) }) ?? .Move,
        sensitivity: Int(bytes[12])
      )
    )
  case .Mounting:
    return Event(
      autoIncrement: autoIncrement,
      type: type,
      resetCounter: resetCounter,
      deviceTimestamp: eventTimestamp,
      additionalData: MountingEventAD(
        status: MountingStatus.allCases.first(where: { $0.hex == UInt16(bytes[11]) }) ?? .Unknown
      )
    )
  case .SystemError:
    return Event(
      autoIncrement: autoIncrement,
      type: type,
      resetCounter: resetCounter,
      deviceTimestamp: eventTimestamp,
      additionalData: SystemErrorEventAD(
        status: SystemErrorStatus.allCases.first(where: { $0.hex == UInt16(bytes[11]) })
        ?? .Unknown,
        voltage: calcVoltage(Int(bytes[12])),
        isCharging: Int(bytes[13]) == 1
      )
    )
  case .SystemReset:
    return Event(
      autoIncrement: autoIncrement,
      type: type,
      resetCounter: resetCounter,
      deviceTimestamp: eventTimestamp,
      additionalData: SystemResetEventAD(
        status: SystemResetStatus.allCases.first(where: { $0.hex == UInt16(bytes[11]) })
        ?? .Unknown,
        voltage: calcVoltage(Int(bytes[12])),
        isCharging: Int(bytes[13]) == 1
      )
    )
  case .TemperatureWarning:
    return Event(
      autoIncrement: autoIncrement,
      type: type,
      resetCounter: resetCounter,
      deviceTimestamp: eventTimestamp,
      additionalData: TemperatureWarningEventAD(
        status: TemperatureWarningStatus.allCases.first(where: { $0.hex == UInt16(bytes[11]) })
        ?? .Unknown,
        currentTemp: Int(bytes[12]),
        threshold: TemperatureThreshold(
          high: Int(bytes[13]),
          low: Int(bytes[14])
        )
      )
    )
  case .FailedRead:
    return Event(
      autoIncrement: autoIncrement,
      type: type,
      resetCounter: resetCounter,
      deviceTimestamp: eventTimestamp,
      additionalData: FailedReadEventAD(
        status: FailedReadStatus.allCases.first(where: { $0.hex == UInt16(bytes[11]) })
        ?? .Unknown
      )
    )
    
  case .DFUEvent:
    return Event(
      autoIncrement: autoIncrement,
      type: type,
      resetCounter: resetCounter,
      deviceTimestamp: eventTimestamp,
      additionalData: DFUEventAD(
        status: DFUStatus.allCases.first(where: { $0.hex == UInt16(bytes[11]) }) ?? .Unknown
      )
    )
  case .ModeChange:
    return Event(
      autoIncrement: autoIncrement,
      type: type,
      resetCounter: resetCounter,
      deviceTimestamp: eventTimestamp,
      additionalData: ModeChangeEventAD(
        status: ModeChangeStatus.allCases.first(where: { $0.hex == UInt16(bytes[11]) })
        ?? .Unknown
      )
    )
  case .Logging:
    return Event(
      autoIncrement: autoIncrement,
      type: type,
      resetCounter: resetCounter,
      deviceTimestamp: eventTimestamp,
      additionalData: LoggingEventAD(
        status: LoggingStatus.allCases.first(where: { $0.hex == UInt16(bytes[11]) }) ?? .Unknown,
        fileId: Int((UInt16(bytes[12]) << 8) | UInt16(bytes[13])),
        voltage: calcVoltage(Int(bytes[14]))
      )
    )
  case .Saturation:
    return Event(
      autoIncrement: autoIncrement,
      type: type,
      resetCounter: resetCounter,
      deviceTimestamp: eventTimestamp,
      additionalData: SaturationEventAD(
        status: SaturationStatus.allCases.first(where: { $0.hex == UInt16(bytes[11]) })
        ?? .Unknown
      )
    )
  case .KwikPenCalibration:
    return Event(
      autoIncrement: autoIncrement,
      type: type,
      resetCounter: resetCounter,
      deviceTimestamp: eventTimestamp,
      additionalData: KwikpenCalibrationEventAD(
        shaftIR: Int((UInt16(bytes[11]) << 8) | UInt16(bytes[12])),
        knobIR: Int((UInt16(bytes[13]) << 8) | UInt16(bytes[14]))
      )
    )
  case .IncorrectMountingError:
    return Event(
      autoIncrement: autoIncrement,
      type: type,
      resetCounter: resetCounter,
      deviceTimestamp: eventTimestamp,
      additionalData: IncorrectMountingErrorEventAD(
        status: IncorrentMountingErrorStatus.allCases.first(where: { $0.hex == UInt16(bytes[11]) }
                                                           ) ?? .Unknown
      )
    )
  case .PenSelect:
    return Event(
      autoIncrement: autoIncrement,
      type: type,
      resetCounter: resetCounter,
      deviceTimestamp: eventTimestamp,
      additionalData: PenSelectEventAD(
        penType: Int(bytes[11]),
        majorVersion: Int(bytes[12]),
        minorVersion: Int(bytes[13])
      )
    )
    
  default:
    return Event(
      autoIncrement: autoIncrement,
      type: type,
      resetCounter: resetCounter,
      deviceTimestamp: eventTimestamp,
      additionalData: EmptyAD()
    )
  }
}
