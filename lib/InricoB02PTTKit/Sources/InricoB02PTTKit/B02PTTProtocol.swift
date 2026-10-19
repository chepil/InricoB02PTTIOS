import CoreBluetooth
import Foundation

/// BLE layout for Inrico B02PTT-FF01 (confirmed on device with Zello-compatible Coda profile).
///
/// Notify characteristic (captured in production logs):
/// `894C8042-E841-461C-A5C9-5A73D25DB08E` → `0x01` press, `0x00` release.
public enum B02PTTProtocol {
    /// Advertising / GAP name prefixes.
    public static let deviceNamePrefixes = ["B02PTT", "BT02PTT", "B02PTT_BLE"]

    /// Coda-compatible PTT service (ProPTT2 / Inrico B02 BLE).
    public static let codaService = CBUUID(string: "89A8591D-BB19-485B-9F59-58492BC33E24")

    /// Coda-compatible PTT notify characteristic.
    public static let codaNotifyCharacteristic = CBUUID(string: "894C8042-E841-461C-A5C9-5A73D25DB08E")

    /// Fallback HM-10 style (some firmwares / ProPTT2 “common UUID”).
    public static let ffe0Service = CBUUID(string: "FFE0")
    public static let ffe1Characteristic = CBUUID(string: "FFE1")

    /// Stable restore identifier for `CBCentralManager`. Override via `InricoB02PTTClient.Configuration`.
    public static let defaultCentralRestoreIdentifier = "ru.chepil.InricoB02PTTKit.central"

    public static func matchesDeviceName(_ name: String?) -> Bool {
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return false
        }
        let upper = name.uppercased()
        return deviceNamePrefixes.contains { upper.hasPrefix($0.uppercased()) }
            || upper.contains("B02PTT")
    }

    /// `true` = pressed, `false` = released, `nil` = unknown payload.
    public static func parsePttState(from data: Data) -> Bool? {
        if data.isEmpty { return nil }

        if data.count >= 1 {
            let b = data[0]
            if b == 0x01 || b == 0x31 { return true }
            if b == 0x00 || b == 0x30 { return false }
        }

        if let text = String(data: data, encoding: .utf8)?.uppercased() {
            if text.contains("+PTT=P") || text.contains("TALK,1") || text.contains("PTT=P") {
                return true
            }
            if text.contains("+PTT=R") || text.contains("TALK,0") || text.contains("PTT=R") {
                return false
            }
        }
        return nil
    }

    public static func hexString(from data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
