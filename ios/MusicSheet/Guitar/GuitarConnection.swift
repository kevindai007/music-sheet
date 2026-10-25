@preconcurrency import CoreBluetooth
import MusicSheetKit
import Observation

/// Connects to a LiberLive C2 over Bluetooth LE and reports the held chord each time a pick is played.
/// Read-only: it subscribes to the guitar's events and never writes a command.
@MainActor
@Observable
final class GuitarConnection: NSObject {
    enum State: Equatable {
        case idle
        case unavailable(String)
        case scanning
        case connecting(String)
        case connected(String)
    }

    struct Press: Equatable {
        let id = UUID()
        let chord: Chord
    }

    private(set) var state: State = .idle
    /// The latest strum; observe its `id` to react to every one, including repeats of the same chord.
    private(set) var lastPress: Press?

    @ObservationIgnored private var central: CBCentralManager?
    @ObservationIgnored private var peripheral: CBPeripheral?
    @ObservationIgnored private var wantsConnection = false

    var isConnected: Bool {
        if case .connected = state { true } else { false }
    }

    /// Starts scanning for the guitar and connects to the first one found. The first call asks for Bluetooth permission.
    func connect() {
        wantsConnection = true
        guard let central else {
            // Creating the manager triggers the permission prompt; scanning starts once it powers on.
            central = CBCentralManager(delegate: self, queue: .main)
            return
        }
        startScanning(central)
    }

    func disconnect() {
        wantsConnection = false
        central?.stopScan()
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        peripheral = nil
        state = .idle
    }

    private func startScanning(_ central: CBCentralManager) {
        guard central.state == .poweredOn else {
            updateAvailability(central)
            return
        }
        // A guitar still connected from earlier doesn't advertise, so look for it first.
        if let known = central.retrieveConnectedPeripherals(withServices: [Self.service]).first {
            attach(known, central: central)
            return
        }
        state = .scanning
        central.scanForPeripherals(withServices: [Self.service])
    }

    private func attach(_ peripheral: CBPeripheral, central: CBCentralManager) {
        central.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        state = .connecting(peripheral.name ?? "LiberLive")
        central.connect(peripheral)
    }

    private func updateAvailability(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOff: state = .unavailable("蓝牙已关闭")
        case .unauthorized: state = .unavailable("没有蓝牙权限，请在设置里允许")
        case .unsupported: state = .unavailable("这台设备不支持蓝牙")
        default: break
        }
    }

    private static let service = CBUUID(string: LiberLive.serviceUUID)
    private static let events = CBUUID(string: LiberLive.notifyUUID)
}

// CoreBluetooth calls these on the main queue (see `CBCentralManager(delegate:queue:)`).
extension GuitarConnection: CBCentralManagerDelegate, CBPeripheralDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            if central.state == .poweredOn {
                if wantsConnection, peripheral == nil { startScanning(central) }
            } else {
                peripheral = nil
                updateAvailability(central)
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber
    ) {
        MainActor.assumeIsolated {
            guard self.peripheral == nil else { return }
            attach(peripheral, central: central)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            state = .connected(peripheral.name ?? "LiberLive")
            peripheral.discoverServices([Self.service])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: (any Error)?) {
        MainActor.assumeIsolated {
            self.peripheral = nil
            state = .unavailable("连接失败：\(error?.localizedDescription ?? "未知错误")")
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: (any Error)?) {
        MainActor.assumeIsolated {
            self.peripheral = nil
            state = .idle
            // The guitar went away (switched off, out of range): look for it again.
            if wantsConnection { startScanning(central) }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        MainActor.assumeIsolated {
            for service in peripheral.services ?? [] where service.uuid == Self.service {
                peripheral.discoverCharacteristics([Self.events], for: service)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: (any Error)?) {
        MainActor.assumeIsolated {
            for characteristic in service.characteristics ?? [] where characteristic.uuid == Self.events {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        guard let value = characteristic.value, let frame = LiberLive.Frame(value), let press = LiberLive.ChordPress(frame) else { return }
        let chord = press.chord
        MainActor.assumeIsolated { lastPress = Press(chord: chord) }
    }
}
