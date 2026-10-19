# Inrico B02PTT-FF01 — iOS BLE PTT reference

Single-screen demo app for integrating the **Inrico BT02 / B02PTT-FF01** PTT button into any iOS PTT application.

**For third-party app developers**, use the UI-free package:  
→ [`lib/`](lib/) (`InricoB02PTTKit` + integration guide).

Verified in practice: Zello on iPhone lists the device as a **Bluetooth Low Energy button** and accepts press/hold. This project does the same via **CoreBluetooth**.

## Features

1. Foreground operation
2. Background operation (`UIBackgroundModes` → `bluetooth-central` + state restoration)
3. BLE button discovery and connection by name `B02PTT*` / `BT02PTT*`
4. Visual PTT DOWN / UP indication + optional sound and haptic feedback

Headset audio (speaker / microphone) uses system **Classic Bluetooth (HFP/A2DP)** after pairing in Settings. This app handles **BLE PTT button events only**.

## Architecture (for embedding)

| File | Role |
|------|------|
| `BLE/B02PTTBleController.swift` | Central: scan, connect, restore, reconnect, notify |
| `BLE/B02PTTProtocol.swift` | Device name, Coda / FFE UUIDs, payload parser |
| `BLE/PTTFeedback.swift` | Sound / haptic (optional) |
| `ContentView.swift` | Demo UI |

Minimal integration into another app (prefer the `lib` package instead):

```swift
let ble = B02PTTBleController()
ble.onPttChanged = { isPressed in
    if isPressed { startTransmit() } else { stopTransmit() }
}
ble.start()
```

Copy the `BLE/` folder and the keys from `Info.plist` (`NSBluetoothAlwaysUsageDescription`, `UIBackgroundModes`).

## BLE protocol (verified on device)

```
PTT DOWN — 894C8042-E841-461C-A5C9-5A73D25DB08E [01]
PTT UP   — 894C8042-E841-461C-A5C9-5A73D25DB08E [00]
```

| | UUID |
|--|------|
| Service (Coda) | `89A8591D-BB19-485B-9F59-58492BC33E24` |
| Characteristic (Notify) | `894C8042-E841-461C-A5C9-5A73D25DB08E` |
| Press | `0x01` |
| Release | `0x00` |

Fallback: HM-10 style `FFE0` / `FFE1`, and ASCII `+PTT=P` / `+PTT=R` if a UART notify path is used.

The controller:

1. Scans by **name** (`B02PTT…`)
2. Prefers the Coda notify characteristic, then other Notify characteristics
3. Also parses ASCII `+PTT=P` / `+PTT=R` and `TALK,1` / `TALK,0` when present

The screen shows the characteristic UUID and hex payload — useful to compare with nRF Connect.

> On Android, HyTalkPTT also supports Classic **SPP** (`+PTT=P` / `+PTT=R`) for this model. On iOS, SPP is not available to third-party apps; use **BLE** for the button, as Zello does.

## Running

1. Open `InricoB02PTT.xcodeproj` in Xcode
2. Select your Development Team (Signing)
3. Install on a **physical iPhone** (BLE simulator is useless)
4. Pair the Inrico in **Settings → Bluetooth** (for audio)
5. Run the app → allow Bluetooth → **Scan / Connect**
6. Hold PTT on the headset — the indicator turns red (**PTT DOWN**)

Background: leave the app and press PTT again — iOS may wake the central; for continuous background use, keep the BLE session active (as in the demo).

Regenerate the Xcode project from `project.yml` (after changing the file tree):

```bash
xcodegen generate
```

## Requirements

- iOS 15+
- Xcode 15+
- Physical device
- Inrico B02 / BLE name: `B02PTT-FF01` (variants `B02PTT*` may appear)

## Handing off to a developer

Prefer shipping only [`lib/`](lib/). If you ship the whole repo, the key contract is:

- `isPttPressed` / `onPttChanged(Bool)` — the only API a walkie-talkie host needs
- HFP audio session is configured by the host (`AVAudioSession` playAndRecord + Bluetooth HFP)

If a firmware uses a different payload, adjust `B02PTTProtocol.parsePttState` using the on-screen log or nRF Connect.
