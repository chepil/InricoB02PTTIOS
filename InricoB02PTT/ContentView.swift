import InricoB02PTTKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var session: DemoPTTSession

    var body: some View {
        ZStack {
            background
            VStack(spacing: 20) {
                header
                pttIndicator
                statusCard
                controls
                Spacer(minLength: 8)
                footerHint
            }
            .padding(20)
        }
    }

    private var background: some View {
        LinearGradient(
            colors: session.isPttPressed
                ? [Color(red: 0.55, green: 0.08, blue: 0.08), Color(red: 0.15, green: 0.02, blue: 0.02)]
                : [Color(red: 0.07, green: 0.10, blue: 0.16), Color(red: 0.03, green: 0.04, blue: 0.07)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.15), value: session.isPttPressed)
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("Inrico B02 PTT")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text("Demo app using InricoB02PTTKit (lib/)")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.top, 8)
    }

    private var pttIndicator: some View {
        ZStack {
            Circle()
                .fill(session.isPttPressed ? Color.red.opacity(0.35) : Color.white.opacity(0.08))
                .frame(width: 220, height: 220)
                .scaleEffect(session.isPttPressed ? 1.06 : 1.0)
                .animation(.easeInOut(duration: 0.12), value: session.isPttPressed)

            Circle()
                .stroke(session.isPttPressed ? Color.red : Color.white.opacity(0.25), lineWidth: 6)
                .frame(width: 180, height: 180)

            VStack(spacing: 8) {
                Image(systemName: session.isPttPressed ? "mic.fill" : "mic")
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundColor(session.isPttPressed ? .white : .white.opacity(0.85))
                Text(session.isPttPressed ? "PTT DOWN" : "PTT UP")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(session.isPttPressed ? "PTT pressed" : "PTT released")
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            row("State", session.connectionState.rawValue)
            row("Detail", session.statusDetail)
            row("Device", session.deviceName)
            row("UUID", shortUUID(session.deviceIdentifier))
            row("Package", "InricoB02PTTKit")
            Divider().background(Color.white.opacity(0.2))
            Text(session.lastEventLog)
                .font(.system(.footnote, design: .monospaced))
                .foregroundColor(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var controls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button(action: { session.connect() }) {
                    label("Scan / Connect", systemImage: "antenna.radiowaves.left.and.right")
                }
                .buttonStyle(PrimaryButtonStyle())

                Button(action: { session.disconnect() }) {
                    label("Disconnect", systemImage: "xmark.circle")
                }
                .buttonStyle(SecondaryButtonStyle())
            }

            Toggle(isOn: $session.soundEnabled) {
                Text("Sound on PTT")
                    .foregroundColor(.white)
            }
            .tint(.orange)
        }
    }

    private var footerHint: some View {
        Text("This UI is a sample host. BLE PTT logic lives in lib/ (InricoB02PTTKit). Pair the headset in Settings for HFP/A2DP audio; background mode is bluetooth-central.")
            .font(.caption)
            .foregroundColor(.white.opacity(0.55))
            .multilineTextAlignment(.center)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.white.opacity(0.5))
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundColor(.white.opacity(0.95))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func label(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
    }

    private func shortUUID(_ uuid: String) -> String {
        guard uuid.count > 12 else { return uuid }
        return String(uuid.prefix(8)) + "…" + String(uuid.suffix(4))
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.white)
            .background(Color.orange.opacity(configuration.isPressed ? 0.7 : 1.0))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.white)
            .background(Color.white.opacity(configuration.isPressed ? 0.12 : 0.18))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(DemoPTTSession())
    }
}
#endif
