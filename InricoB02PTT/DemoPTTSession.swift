import Combine
import Foundation
import InricoB02PTTKit

/// Demo-only SwiftUI bridge around `InricoB02PTTClient` from `lib/`.
/// Host apps should use `InricoB02PTTClient` directly — see `lib/README.md`.
@MainActor
final class DemoPTTSession: ObservableObject {
    @Published private(set) var connectionState: InricoB02PTTConnectionState = .idle
    @Published private(set) var statusDetail: String = "Starting…"
    @Published private(set) var deviceName: String = "—"
    @Published private(set) var deviceIdentifier: String = "—"
    @Published private(set) var isPttPressed: Bool = false
    @Published private(set) var lastEventLog: String = "No PTT events yet"
    @Published var soundEnabled: Bool = true {
        didSet { PTTFeedback.shared.soundEnabled = soundEnabled }
    }

    private let client: InricoB02PTTClient
    private let bridge = DelegateBridge()

    init() {
        client = InricoB02PTTClient(
            configuration: .init(
                centralRestoreIdentifier: "ru.chepil.InricoB02PTT.demo.central"
            )
        )
        bridge.owner = self
        client.delegate = bridge
        PTTFeedback.shared.soundEnabled = soundEnabled
    }

    func start() {
        print("📡 [Demo] InricoB02PTTClient.start() — using package InricoB02PTTKit")
        client.start()
    }

    func connect() {
        client.connect()
    }

    func disconnect() {
        client.disconnect(forgetDevice: true)
    }

    fileprivate func apply(state: InricoB02PTTConnectionState, detail: String) {
        connectionState = state
        statusDetail = detail
        deviceName = client.connectedDeviceName ?? "—"
        if let id = client.connectedDeviceIdentifier {
            deviceIdentifier = id.uuidString
        } else if state == .idle {
            deviceIdentifier = "—"
        }
    }

    fileprivate func applyPtt(pressed: Bool) {
        isPttPressed = pressed
        let stamp = Self.timeStamp()
        lastEventLog = (pressed ? "PTT DOWN" : "PTT UP") + " @ \(stamp)"
        statusDetail = pressed ? "PTT pressed" : "PTT released"
        deviceName = client.connectedDeviceName ?? deviceName
        if let id = client.connectedDeviceIdentifier {
            deviceIdentifier = id.uuidString
        }
        print("🎙 [Demo] \(lastEventLog)")
        if pressed {
            PTTFeedback.shared.pttPressed()
        } else {
            PTTFeedback.shared.pttReleased()
        }
    }

    private static func timeStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: Date())
    }
}

/// Non-actor delegate trampoline (CoreBluetooth / kit callbacks → MainActor session).
private final class DelegateBridge: NSObject, InricoB02PTTClientDelegate {
    weak var owner: DemoPTTSession?

    func inricoB02PTTClient(_ client: InricoB02PTTClient, pttPressed: Bool) {
        Task { @MainActor in
            owner?.applyPtt(pressed: pttPressed)
        }
    }

    func inricoB02PTTClient(
        _ client: InricoB02PTTClient,
        didChange state: InricoB02PTTConnectionState,
        detail: String
    ) {
        print("📡 [Demo] \(state.rawValue) — \(detail)")
        Task { @MainActor in
            owner?.apply(state: state, detail: detail)
        }
    }
}
