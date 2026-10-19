import Foundation
import CoreBluetooth

/// Known BLE layout for Inrico B02PTT-FF01 (confirmed in device logs).
///
/// Preferred (Coda / Zello-compatible):
/// - Service `89A8591D-BB19-485B-9F59-58492BC33E24`
/// - Characteristic `894C8042-E841-461C-A5C9-5A73D25DB08E` → `0x01` / `0x00`
///
/// Fallback: HM-10 `FFE0`/`FFE1`, ASCII `+PTT=P` / `+PTT=R`.
enum B02PTTProtocol {
    static let deviceNamePrefixes = ["B02PTT", "BT02PTT", "B02PTT_BLE"]

    static let preferredService = CBUUID(string: "89A8591D-BB19-485B-9F59-58492BC33E24")
    static let preferredNotifyCharacteristic = CBUUID(string: "894C8042-E841-461C-A5C9-5A73D25DB08E")
    static let fallbackService = CBUUID(string: "FFE0")
    static let fallbackNotifyCharacteristic = CBUUID(string: "FFE1")

    /// CoreBluetooth restore id — keep stable across app versions so iOS can wake the app.
    static let centralRestoreIdentifier = "ru.chepil.InricoB02PTT.central"

    static func matchesDeviceName(_ name: String?) -> Bool {
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return false
        }
        let upper = name.uppercased()
        return deviceNamePrefixes.contains { upper.hasPrefix($0.uppercased()) }
            || upper.contains("B02PTT")
    }

    /// Interprets a notify/indicate payload as PTT press (`true`), release (`false`), or unknown (`nil`).
    static func parsePttState(from data: Data) -> Bool? {
        if data.isEmpty { return nil }

        // Single-byte / first-byte: 1 = down, 0 = up (FFE1 convention).
        if data.count == 1 {
            let b = data[0]
            if b == 0x01 || b == 0x31 { return true }   // 0x31 = ASCII '1'
            if b == 0x00 || b == 0x30 { return false }  // 0x30 = ASCII '0'
        }

        // Some modules send multi-byte with state in first byte.
        if data.count >= 1 {
            let b = data[0]
            if b == 0x01 { return true }
            if b == 0x00 { return false }
        }

        // ASCII stream: +PTT=P / +PTT=R (same as classic SPP on this headset).
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

    static func hexString(from data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
