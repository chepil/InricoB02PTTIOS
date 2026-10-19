import CoreBluetooth
import Foundation

/// Connection state for host-app UI (optional).
public enum InricoB02PTTConnectionState: String, Sendable {
    case bluetoothUnavailable
    case idle
    case scanning
    case connecting
    case ready
    case reconnecting
}

/// Delegate for PTT press/release and connection lifecycle.
public protocol InricoB02PTTClientDelegate: AnyObject {
    /// Called on the main queue when the physical PTT button changes.
    func inricoB02PTTClient(_ client: InricoB02PTTClient, pttPressed: Bool)

    /// Optional: connection / scan status. Default empty.
    func inricoB02PTTClient(_ client: InricoB02PTTClient, didChange state: InricoB02PTTConnectionState, detail: String)
}

public extension InricoB02PTTClientDelegate {
    func inricoB02PTTClient(_ client: InricoB02PTTClient, didChange state: InricoB02PTTConnectionState, detail: String) {}
}

/// BLE client for Inrico B02PTT-FF01 PTT button (iOS).
///
/// Audio (speaker/mic) is handled by the system HFP/A2DP stack after the user pairs
/// the headset in Settings. This client only owns the **BLE PTT** path.
///
/// Minimal host integration:
/// ```swift
/// let client = InricoB02PTTClient()
/// client.delegate = self
/// client.start() // scan + connect + auto-reconnect + background restore
/// // → inricoB02PTTClient(_:pttPressed:)
/// ```
public final class InricoB02PTTClient: NSObject {
    public struct Configuration: Sendable {
        /// `CBCentralManager` restore identifier — must be unique per app.
        public var centralRestoreIdentifier: String
        /// Persist last peripheral UUID in `UserDefaults` for faster reconnect.
        public var rememberPeripheral: Bool
        /// `UserDefaults` key when `rememberPeripheral` is true.
        public var peripheralDefaultsKey: String
        /// Reconnect delay after drop (seconds).
        public var reconnectDelay: TimeInterval

        public init(
            centralRestoreIdentifier: String = B02PTTProtocol.defaultCentralRestoreIdentifier,
            rememberPeripheral: Bool = true,
            peripheralDefaultsKey: String = "InricoB02PTTKit.peripheral.uuid",
            reconnectDelay: TimeInterval = 2.0
        ) {
            self.centralRestoreIdentifier = centralRestoreIdentifier
            self.rememberPeripheral = rememberPeripheral
            self.peripheralDefaultsKey = peripheralDefaultsKey
            self.reconnectDelay = reconnectDelay
        }
    }

    public weak var delegate: InricoB02PTTClientDelegate?

    /// Closure alternative to `delegate` for PTT edges (main queue).
    public var onPttChanged: ((Bool) -> Void)?

    public private(set) var connectionState: InricoB02PTTConnectionState = .idle
    public private(set) var isPttPressed: Bool = false
    public private(set) var connectedDeviceName: String?
    public private(set) var connectedDeviceIdentifier: UUID?

    private let configuration: Configuration
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var pendingNotifyQueue: [CBCharacteristic] = []
    private var preferredNotify: CBCharacteristic?
    private var isScanning = false
    private var shouldKeepAlive = false
    private var reconnectWorkItem: DispatchWorkItem?
    private var pendingRestorePeripheral: CBPeripheral?
    private let queue = DispatchQueue(label: "InricoB02PTTKit.ble", qos: .userInitiated)

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        super.init()
    }

    // MARK: - Public API

    /// Start BLE central: restore / reconnect / scan for `B02PTT*`.
    /// Safe to call from `application(_:didFinishLaunchingWithOptions:)` or when the PTT feature is enabled.
    public func start() {
        shouldKeepAlive = true
        if central == nil {
            central = CBCentralManager(
                delegate: self,
                queue: queue,
                options: [
                    CBCentralManagerOptionRestoreIdentifierKey: configuration.centralRestoreIdentifier,
                    CBCentralManagerOptionShowPowerAlertKey: true
                ]
            )
        } else {
            handlePoweredOnIfNeeded()
        }
    }

    /// Stop scanning, cancel connection, clear keep-alive (does not erase saved peripheral).
    public func stop() {
        shouldKeepAlive = false
        reconnectWorkItem?.cancel()
        stopScan()
        if let peripheral {
            central?.cancelPeripheralConnection(peripheral)
        }
        setPtt(false, force: true, source: "stop")
        setState(.idle, detail: "Stopped")
    }

    /// Force a new scan (e.g. user tapped “Connect PTT mic”).
    public func connect() {
        shouldKeepAlive = true
        guard let central, central.state == .poweredOn else {
            setState(.bluetoothUnavailable, detail: "Bluetooth not ready")
            return
        }
        if let peripheral, peripheral.state == .connected {
            setState(.ready, detail: "Already connected")
            return
        }
        startScan()
    }

    /// Disconnect and forget saved peripheral UUID.
    public func disconnect(forgetDevice: Bool = true) {
        reconnectWorkItem?.cancel()
        stopScan()
        if let peripheral {
            central?.cancelPeripheralConnection(peripheral)
        }
        if forgetDevice { clearSavedPeripheral() }
        self.peripheral = nil
        preferredNotify = nil
        pendingNotifyQueue.removeAll()
        connectedDeviceName = nil
        connectedDeviceIdentifier = nil
        setPtt(false, force: true, source: "disconnect")
        setState(.idle, detail: "Disconnected")
    }

    // MARK: - Internals

    private func handlePoweredOnIfNeeded() {
        guard shouldKeepAlive, let central, central.state == .poweredOn else { return }

        if let restored = pendingRestorePeripheral {
            pendingRestorePeripheral = nil
            connect(to: restored, reason: "Restored session")
            return
        }

        if let peripheral, peripheral.state == .connected {
            setState(.ready, detail: "Connected")
            if peripheral.services == nil {
                peripheral.discoverServices(nil)
            }
            return
        }

        if peripheral?.state == .connecting {
            setState(.connecting, detail: "Connecting…")
            return
        }

        if configuration.rememberPeripheral,
           let uuidString = UserDefaults.standard.string(forKey: configuration.peripheralDefaultsKey),
           let uuid = UUID(uuidString: uuidString) {
            if let saved = central.retrievePeripherals(withIdentifiers: [uuid]).first {
                connect(to: saved, reason: "Saved peripheral")
                return
            }
        }

        startScan()
    }

    private func startScan() {
        guard let central, central.state == .poweredOn else { return }
        stopScan()
        isScanning = true
        setState(.scanning, detail: "Scanning for B02PTT*")
        // Open scan: B02 often advertises by name only (service UUID may be absent in ADV).
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    private func stopScan() {
        guard isScanning else { return }
        isScanning = false
        central?.stopScan()
    }

    private func connect(to peripheral: CBPeripheral, reason: String) {
        guard let central, central.state == .poweredOn else {
            pendingRestorePeripheral = peripheral
            return
        }
        stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        savePeripheral(peripheral)
        connectedDeviceName = peripheral.name
        connectedDeviceIdentifier = peripheral.identifier
        setState(.connecting, detail: reason)
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
            self.setState(.reconnecting, detail: "Reconnecting…")
            if let peripheral = self.peripheral {
                self.central?.connect(peripheral, options: nil)
            } else {
                self.startScan()
            }
        }
        reconnectWorkItem = work
        queue.asyncAfter(deadline: .now() + configuration.reconnectDelay, execute: work)
    }

    private func savePeripheral(_ peripheral: CBPeripheral) {
        guard configuration.rememberPeripheral else { return }
        UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: configuration.peripheralDefaultsKey)
    }

    private func clearSavedPeripheral() {
        UserDefaults.standard.removeObject(forKey: configuration.peripheralDefaultsKey)
    }

    private func preferAndSubscribe(from services: [CBService]) {
        pendingNotifyQueue.removeAll()
        preferredNotify = nil

        for service in services {
            guard let characteristics = service.characteristics else { continue }
            for ch in characteristics {
                let canNotify = ch.properties.contains(.notify) || ch.properties.contains(.indicate)
                guard canNotify else { continue }

                if ch.uuid == B02PTTProtocol.codaNotifyCharacteristic
                    || service.uuid == B02PTTProtocol.codaService
                    || ch.uuid == B02PTTProtocol.ffe1Characteristic
                    || service.uuid == B02PTTProtocol.ffe0Service {
                    if preferredNotify == nil
                        || ch.uuid == B02PTTProtocol.codaNotifyCharacteristic {
                        preferredNotify = ch
                    }
                }
                pendingNotifyQueue.append(ch)
            }
        }

        if let preferred = preferredNotify {
            pendingNotifyQueue.removeAll { $0.uuid == preferred.uuid }
            pendingNotifyQueue.insert(preferred, at: 0)
        }

        // Prefer only known PTT chars when present — avoid noise from other notifies.
        if let preferred = preferredNotify,
           preferred.uuid == B02PTTProtocol.codaNotifyCharacteristic
            || preferred.uuid == B02PTTProtocol.ffe1Characteristic {
            pendingNotifyQueue = [preferred]
        }

        if pendingNotifyQueue.isEmpty {
            setState(.ready, detail: "Connected — no notify characteristic")
            return
        }
        subscribeNext()
    }

    private func subscribeNext() {
        guard let peripheral, let next = pendingNotifyQueue.first else {
            setState(.ready, detail: "Subscribed — waiting for PTT")
            return
        }
        pendingNotifyQueue.removeFirst()
        peripheral.setNotifyValue(true, for: next)
    }

    private func handleNotify(_ characteristic: CBCharacteristic) {
        guard let data = characteristic.value else { return }
        if let pressed = B02PTTProtocol.parsePttState(from: data) {
            setPtt(pressed, force: false, source: characteristic.uuid.uuidString)
        }
    }

    private func setPtt(_ pressed: Bool, force: Bool, source: String) {
        if !force && pressed == isPttPressed { return }
        isPttPressed = pressed
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.inricoB02PTTClient(self, pttPressed: pressed)
            self.onPttChanged?(pressed)
        }
    }

    private func setState(_ state: InricoB02PTTConnectionState, detail: String) {
        connectionState = state
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.inricoB02PTTClient(self, didChange: state, detail: detail)
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension InricoB02PTTClient: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            handlePoweredOnIfNeeded()
        case .unauthorized, .poweredOff, .unsupported, .resetting, .unknown:
            setState(.bluetoothUnavailable, detail: "Bluetooth unavailable")
            setPtt(false, force: true, source: "bt-off")
        @unknown default:
            break
        }
    }

    public func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        guard let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral],
              let first = peripherals.first else { return }
        first.delegate = self
        peripheral = first
        connectedDeviceName = first.name
        connectedDeviceIdentifier = first.identifier
        // Do NOT discover/connect until poweredOn — avoids "API MISUSE".
        pendingRestorePeripheral = first
        setState(.reconnecting, detail: "Restoring BLE session")
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name
        let services = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]
        let hasCoda = services?.contains(B02PTTProtocol.codaService) == true
        guard B02PTTProtocol.matchesDeviceName(name) || hasCoda else { return }
        connect(to: peripheral, reason: "Found \(name ?? "B02PTT")")
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedDeviceName = peripheral.name
        setState(.connecting, detail: "Discovering GATT")
        peripheral.discoverServices(nil)
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        setState(.reconnecting, detail: error?.localizedDescription ?? "Connect failed")
        scheduleReconnect()
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        setPtt(false, force: true, source: "disconnect")
        setState(.reconnecting, detail: "Disconnected")
        if shouldKeepAlive { scheduleReconnect() }
    }
}

// MARK: - CBPeripheralDelegate

extension InricoB02PTTClient: CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let services = peripheral.services, !services.isEmpty else {
            setState(.ready, detail: "No GATT services")
            return
        }
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else { return }
        let pending = peripheral.services?.contains { $0.characteristics == nil } ?? true
        if pending { return }
        preferAndSubscribe(from: peripheral.services ?? [])
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        subscribeNext()
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard error == nil else { return }
        handleNotify(characteristic)
    }
}
