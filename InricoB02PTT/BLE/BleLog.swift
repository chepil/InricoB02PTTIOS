import Foundation
import OSLog

/// Console logging for Xcode Debug area and Console.app.
/// Filter: subsystem `ru.chepil.InricoB02PTT` or text `B02PTT`.
enum BleLog {
    static let subsystem = "ru.chepil.InricoB02PTT"
    private static let logger = Logger(subsystem: subsystem, category: "BLE")

    static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
        // Also print so it always shows in Xcode Debug area without Console filters.
        print("📡 [B02PTT] \(message)")
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        print("❌ [B02PTT] \(message)")
    }

    static func ptt(_ message: String) {
        logger.notice("\(message, privacy: .public)")
        print("🎙 [B02PTT] \(message)")
    }
}
