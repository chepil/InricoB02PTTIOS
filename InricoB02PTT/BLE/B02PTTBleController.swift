import Combine
import CoreBluetooth
import Foundation

/// Connection / PTT state for the demo UI and for integration into a host PTT app.
enum B02ConnectionState: String {
    case bluetoothOff = "Bluetooth off / unauthorized"
    case idle = "Idle"
    case scanning = "Scanning…"
    case connecting = "Connecting…"
    case discovering = "Discovering GATT…"
    case ready = "Connected — waiting for PTT"
    case reconnecting = "Reconnecting…"
}

/// Single-screen BLE central for Inrico B02PTT-FF01 (dual-mode headset: Classic audio + BLE PTT).
///
/// Hand this class (or its callbacks) to a host app developer:
/// - Observe `isPttPressed` / `onPttChanged`
/// - Call `start()` once (foreground + background via `bluetooth-central`)
final class B02PTTBleController: NSObject, ObservableObject {
    // MARK: - Published UI state

    @Published private(set) var connectionState: B02ConnectionState = .idle
    @Published private(set) var statusDetail: String = "Tap Scan to find B02PTT-FF01"
    @Published private(set) var deviceName: String = "—"
    @Published private(set) var deviceIdentifier: String = "—"
    @Published private(set) var rssi: Int = 0
    @Published private(set) var isPttPressed: Bool = false
    @Published private(set) var lastEventLog: String = "No PTT events yet"
    @Published private(set) var notifyCharacteristicInfo: String = "—"
    @Published var soundEnabled: Bool = true {
        didSet { PTTFeedback.shared.soundEnabled = soundEnabled }
    }

    /// Optional integration hook for a host walkie-talkie app.
    var onPttChanged: ((Bool) -> Void)?

    // MARK: - Private

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var subscribedCharacteristics: Set<CBUUID> = []
    private var preferredNotify: CBCharacteristic?
    private var pendingNotifyQueue: [CBCharacteristic] = []
    private var isScanningFlag = false
    private var shouldKeepAlive = false
    private var reconnectWorkItem: DispatchWorkItem?
    private let queue = DispatchQueue(label: "ru.chepil.InricoB02PTT.ble", qos: .userInitiated)

    private let defaultsKeyPeripheralUUID = "b02ptt.peripheral.uuid"

    override init() {
        super.init()
    }

    // MARK: - Public API

    func start() {
        BleLog.info("start()")
        shouldKeepAlive = true
        PTTFeedback.shared.soundEnabled = soundEnabled
        if central == nil {
            BleLog.info("Creating CBCentralManager (restore id \(B02PTTProtocol.centralRestoreIdentifier))")
            central = CBCentralManager(
                delegate: self,
                queue: queue,
                options: [
                    CBCentralManagerOptionRestoreIdentifierKey: B02PTTProtocol.centralRestoreIdentifier,
                    CBCentralManagerOptionShowPowerAlertKey: true
                ]
            )
        } else {
            handlePoweredOnIfNeeded()
        }
    }

    func stop() {
        BleLog.info("stop()")
        shouldKeepAlive = false
        reconnectWorkItem?.cancel()
        stopScan()
        if let peripheral {
            central?.cancelPeripheralConnection(peripheral)
        }
        publish {
            self.connectionState = .idle
            self.statusDetail = "Stopped"
            self.isPttPressed = false
        }
    }

    func scan() {
        BleLog.info("scan() requested")
        shouldKeepAlive = true
        guard let central, central.state == .poweredOn else {
            BleLog.error("scan aborted — Bluetooth not powered on")
            publish {
                self.connectionState = .bluetoothOff
                self.statusDetail = "Turn on Bluetooth and allow access"
            }
            return
        }
        if let peripheral, peripheral.state == .connected {
            BleLog.info("Already connected to \(deviceName)")
            publish { self.statusDetail = "Already connected to \(self.deviceName)" }
            return
        }
        startScan()
    }

    func disconnect() {
        BleLog.info("disconnect()")
        reconnectWorkItem?.cancel()
        stopScan()
        if let peripheral {
            central?.cancelPeripheralConnection(peripheral)
        }
        clearSavedPeripheral()
        publish {
            self.connectionState = .idle
            self.statusDetail = "Disconnected — tap Scan to find the button again"
            self.deviceName = "—"
            self.deviceIdentifier = "—"
            self.isPttPressed = false
            self.notifyCharacteristicInfo = "—"
        }
        self.peripheral = nil
        preferredNotify = nil
        subscribedCharacteristics.removeAll()
    }

    // MARK: - Scan / connect

    private func handlePoweredOnIfNeeded() {
        guard shouldKeepAlive, let central, central.state == .poweredOn else { return }

        if let peripheral, peripheral.state == .connected || peripheral.state == .connecting {
            publish {
                self.connectionState = peripheral.state == .connected ? .ready : .connecting
            }
            if peripheral.state == .connected {
                peripheral.delegate = self
                peripheral.discoverServices(nil)
            }
            return
        }

        if let uuidString = UserDefaults.standard.string(forKey: defaultsKeyPeripheralUUID),
           let uuid = UUID(uuidString: uuidString) {
            let known = central.retrievePeripherals(withIdentifiers: [uuid])
            if let saved = known.first {
                connect(to: saved, reason: "Restored saved peripheral")
                return
            }
        }

        startScan()
    }

    private func startScan() {
        guard let central, central.state == .poweredOn else { return }
        stopScan()
        isScanningFlag = true
        BleLog.info("BLE scan started (filter name B02PTT*)")
        publish {
            self.connectionState = .scanning
            self.statusDetail = "Looking for B02PTT* (BLE). Keep the mic powered / paired."
        }
        // Scan without service filter — B02 may advertise under a custom UUID or name only.
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    private func stopScan() {
        guard isScanningFlag else { return }
        isScanningFlag = false
        central?.stopScan()
        BleLog.info("BLE scan stopped")
    }

    private func connect(to peripheral: CBPeripheral, reason: String) {
        stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        savePeripheral(peripheral)
        BleLog.info("Connecting to \(peripheral.name ?? "?") \(peripheral.identifier.uuidString) — \(reason)")
        publish {
            self.connectionState = .connecting
            self.deviceName = peripheral.name ?? "B02PTT"
            self.deviceIdentifier = peripheral.identifier.uuidString
            self.statusDetail = reason
        }
        central.connect(peripheral, options: [
            CBConnectPeripheralOptionNotifyOnConnectionKey: true,
            CBConnectPeripheralOptionNotifyOnDisconnectionKey: true,
            CBConnectPeripheralOptionNotifyOnNotificationKey: true
        ])
    }

    private func scheduleReconnect() {
        guard shouldKeepAlive else { return }
        reconnectWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.publish { self.connectionState = .reconnecting }
            if let peripheral = self.peripheral {
                self.central?.connect(peripheral, options: nil)
            } else {
                self.startScan()
            }
        }
        reconnectWorkItem = work
        queue.asyncAfter(deadline: .now() + 2.0, execute: work)
    }

    private func savePeripheral(_ peripheral: CBPeripheral) {
        UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: defaultsKeyPeripheralUUID)
    }

    private func clearSavedPeripheral() {
        UserDefaults.standard.removeObject(forKey: defaultsKeyPeripheralUUID)
    }

    // MARK: - Notify subscription

    private func preferAndSubscribe(from services: [CBService]) {
        pendingNotifyQueue.removeAll()
        preferredNotify = nil

        for service in services {
            guard let characteristics = service.characteristics else { continue }
            for ch in characteristics {
                let canNotify = ch.properties.contains(.notify) || ch.properties.contains(.indicate)
                guard canNotify else { continue }

                if ch.uuid == B02PTTProtocol.preferredNotifyCharacteristic
                    || service.uuid == B02PTTProtocol.preferredService
                    || ch.uuid == B02PTTProtocol.fallbackNotifyCharacteristic
                    || service.uuid == B02PTTProtocol.fallbackService {
                    if preferredNotify == nil
                        || ch.uuid == B02PTTProtocol.preferredNotifyCharacteristic {
                        preferredNotify = ch
                    }
                }
                pendingNotifyQueue.append(ch)
            }
        }

        // Prefer FFE1 first, then every other notify characteristic (discovery / unknown firmwares).
        if let preferred = preferredNotify {
            pendingNotifyQueue.removeAll { $0.uuid == preferred.uuid }
            pendingNotifyQueue.insert(preferred, at: 0)
        }

        if pendingNotifyQueue.isEmpty {
            BleLog.error("No Notify characteristics found on device")
            publish {
                self.connectionState = .ready
                self.statusDetail = "Connected but no Notify characteristics found. Check GATT with nRF Connect."
                self.notifyCharacteristicInfo = "none"
            }
            return
        }

        BleLog.info("Will subscribe to \(pendingNotifyQueue.count) notify characteristic(s); preferred=\(preferredNotify?.uuid.uuidString ?? "none")")
        subscribeNext()
    }

    private func subscribeNext() {
        guard let peripheral, let next = pendingNotifyQueue.first else {
            BleLog.info("All notify subscriptions done — waiting for PTT")
            publish {
                self.connectionState = .ready
                self.statusDetail = "Subscribed — press and hold the Inrico PTT button"
            }
            return
        }
        pendingNotifyQueue.removeFirst()
        subscribedCharacteristics.insert(next.uuid)
        peripheral.setNotifyValue(true, for: next)
        let info = "\(next.uuid.uuidString) (svc \(next.service?.uuid.uuidString ?? "?"))"
        BleLog.info("Enabling notify on \(info)")
        publish {
            self.notifyCharacteristicInfo = info
            self.statusDetail = "Enabling notify on \(next.uuid.uuidString)"
            self.connectionState = .discovering
        }
    }

    private func handleNotify(characteristic: CBCharacteristic) {
        guard let data = characteristic.value else { return }
        let hex = B02PTTProtocol.hexString(from: data)
        let ascii = String(data: data, encoding: .utf8)?
            .replacingOccurrences(of: "\0", with: ".") ?? ""

        if let pressed = B02PTTProtocol.parsePttState(from: data) {
            applyPtt(pressed, source: "\(characteristic.uuid.uuidString) [\(hex)]")
            return
        }

        BleLog.info("Raw notify \(characteristic.uuid.uuidString) hex=[\(hex)] ascii=\"\(ascii)\"")
        publish {
            self.lastEventLog = "Raw \(hex)" + (ascii.isEmpty ? "" : " \"\(ascii)\"")
                + " @ \(Self.timeStamp())"
        }
    }

    private func applyPtt(_ pressed: Bool, source: String) {
        let was = isPttPressed
        BleLog.ptt((pressed ? "PTT DOWN" : "PTT UP") + " — \(source)")
        publish {
            self.isPttPressed = pressed
            self.connectionState = .ready
            self.lastEventLog = (pressed ? "PTT DOWN" : "PTT UP")
                + " — \(source) @ \(Self.timeStamp())"
            self.statusDetail = pressed ? "PTT pressed" : "PTT released"
        }

        if pressed != was {
            if pressed {
                PTTFeedback.shared.pttPressed()
            } else {
                PTTFeedback.shared.pttReleased()
            }
            onPttChanged?(pressed)
        }
    }

    private func publish(_ block: @escaping () -> Void) {
        DispatchQueue.main.async(execute: block)
    }

    private static func timeStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: Date())
    }
}

// MARK: - CBCentralManagerDelegate

extension B02PTTBleController: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        BleLog.info("CBCentralManager state=\(String(describing: central.state.rawValue))")
        switch central.state {
        case .poweredOn:
            publish {
                self.statusDetail = "Bluetooth ready"
            }
            handlePoweredOnIfNeeded()
        case .unauthorized:
            BleLog.error("Bluetooth unauthorized")
            publish {
                self.connectionState = .bluetoothOff
                self.statusDetail = "Bluetooth permission denied — enable in Settings"
            }
        case .poweredOff:
            BleLog.error("Bluetooth powered off")
            publish {
                self.connectionState = .bluetoothOff
                self.statusDetail = "Turn Bluetooth on"
                self.isPttPressed = false
            }
        case .resetting, .unknown:
            publish {
                self.connectionState = .bluetoothOff
                self.statusDetail = "Bluetooth unavailable (\(String(describing: central.state)))"
            }
        case .unsupported:
            BleLog.error("BLE unsupported on this device")
            publish {
                self.connectionState = .bluetoothOff
                self.statusDetail = "This device does not support BLE"
            }
        @unknown default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        BleLog.info("willRestoreState")
        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral],
           let first = peripherals.first {
            self.peripheral = first
            first.delegate = self
            BleLog.info("Restored peripheral \(first.name ?? "?") \(first.identifier.uuidString)")
            publish {
                self.deviceName = first.name ?? "B02PTT"
                self.deviceIdentifier = first.identifier.uuidString
                self.connectionState = first.state == .connected ? .discovering : .reconnecting
                self.statusDetail = "Restored BLE session from background"
            }
            // Defer discoverServices until poweredOn (avoids CBCentralManager API MISUSE).
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = advertisedName ?? peripheral.name
        guard B02PTTProtocol.matchesDeviceName(name) else { return }

        BleLog.info("Discovered \(name ?? "B02PTT") RSSI=\(RSSI.intValue)")
        publish {
            self.rssi = RSSI.intValue
            self.statusDetail = "Found \(name ?? "B02PTT") (RSSI \(RSSI.intValue))"
        }
        connect(to: peripheral, reason: "Connecting to \(name ?? "B02PTT")…")
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        BleLog.info("Connected to \(peripheral.name ?? "?")")
        publish {
            self.connectionState = .discovering
            self.deviceName = peripheral.name ?? self.deviceName
            self.statusDetail = "Connected — discovering services"
        }
        peripheral.discoverServices(nil)
        peripheral.readRSSI()
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        BleLog.error("Connect failed: \(error?.localizedDescription ?? "unknown")")
        publish {
            self.connectionState = .reconnecting
            self.statusDetail = "Connect failed: \(error?.localizedDescription ?? "unknown")"
        }
        scheduleReconnect()
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        BleLog.info("Disconnected: \(error?.localizedDescription ?? "clean")")
        publish {
            self.isPttPressed = false
            self.connectionState = .reconnecting
            self.statusDetail = "Disconnected — will retry"
                + (error.map { " (\($0.localizedDescription))" } ?? "")
        }
        if shouldKeepAlive {
            scheduleReconnect()
        }
    }
}

// MARK: - CBPeripheralDelegate

extension B02PTTBleController: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            BleLog.error("Service discovery: \(error.localizedDescription)")
            publish { self.statusDetail = "Service discovery error: \(error.localizedDescription)" }
            return
        }
        guard let services = peripheral.services, !services.isEmpty else {
            BleLog.error("No GATT services")
            publish { self.statusDetail = "No GATT services" }
            return
        }
        for service in services {
            BleLog.info("Service \(service.uuid.uuidString)")
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        if let error {
            BleLog.error("Characteristic discovery: \(error.localizedDescription)")
            publish { self.statusDetail = "Characteristic error: \(error.localizedDescription)" }
            return
        }
        for ch in service.characteristics ?? [] {
            BleLog.info("  Char \(ch.uuid.uuidString) props=\(ch.properties.rawValue)")
        }
        // Wait until every service has characteristics discovered.
        let pending = peripheral.services?.contains { $0.characteristics == nil } ?? true
        if pending { return }
        preferAndSubscribe(from: peripheral.services ?? [])
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error {
            BleLog.error("Notify enable failed \(characteristic.uuid): \(error.localizedDescription)")
            publish {
                self.statusDetail = "Notify enable failed on \(characteristic.uuid): \(error.localizedDescription)"
            }
        } else {
            BleLog.info("Notify ON \(characteristic.uuid.uuidString) isNotifying=\(characteristic.isNotifying)")
            publish {
                self.statusDetail = "Notify ON: \(characteristic.uuid.uuidString)"
            }
        }
        subscribeNext()
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error {
            BleLog.error("Notify value error: \(error.localizedDescription)")
            publish { self.lastEventLog = "Notify error: \(error.localizedDescription)" }
            return
        }
        handleNotify(characteristic: characteristic)
    }

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        guard error == nil else { return }
        publish { self.rssi = RSSI.intValue }
    }
}
