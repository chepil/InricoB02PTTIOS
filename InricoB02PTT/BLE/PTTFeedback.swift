import AVFoundation
import AudioToolbox
import UIKit

/// Visual + optional audio feedback for PTT press/release.
final class PTTFeedback {
    static let shared = PTTFeedback()

    var soundEnabled: Bool = true

    private var audioSessionConfigured = false

    private init() {}

    func configureAudioSessionIfNeeded() {
        guard !audioSessionConfigured else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            // Ambient + mix so we do not steal HFP/A2DP from other apps; still allows short cues.
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true, options: [])
            audioSessionConfigured = true
        } catch {
            // Non-fatal: visual feedback still works.
            print("[PTTFeedback] AVAudioSession: \(error.localizedDescription)")
        }
    }

    func pttPressed() {
        configureAudioSessionIfNeeded()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if soundEnabled {
            AudioServicesPlaySystemSound(1104) // short "tock"
        }
    }

    func pttReleased() {
        configureAudioSessionIfNeeded()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if soundEnabled {
            AudioServicesPlaySystemSound(1103)
        }
    }
}
