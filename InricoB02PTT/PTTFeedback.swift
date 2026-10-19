import AVFoundation
import AudioToolbox
import UIKit

/// Demo-only visual/audio feedback (not part of InricoB02PTTKit).
final class PTTFeedback {
    static let shared = PTTFeedback()

    var soundEnabled: Bool = true
    private var audioSessionConfigured = false

    private init() {}

    func configureAudioSessionIfNeeded() {
        guard !audioSessionConfigured else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true, options: [])
            audioSessionConfigured = true
        } catch {
            print("[PTTFeedback] AVAudioSession: \(error.localizedDescription)")
        }
    }

    func pttPressed() {
        configureAudioSessionIfNeeded()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if soundEnabled {
            AudioServicesPlaySystemSound(1104)
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
