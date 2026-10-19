# Inrico B02PTT-FF01 — iOS BLE PTT reference

Single-screen **demo app** that integrates the **Inrico B02 / B02PTT-FF01** PTT button by depending on the local Swift package in [`lib/`](lib/) (`InricoB02PTTKit`).

**For third-party app developers**, copy or add that package — not the demo UI:  
→ [`lib/README.md`](lib/README.md)

Verified in practice: Zello on iPhone lists the device as a **Bluetooth Low Energy button** and accepts press/hold. The kit does the same via **CoreBluetooth**.

## Hardware

**Inrico B02** Bluetooth remote speaker microphone (RSM). On iOS / BLE it typically appears as **`B02PTT-FF01`**.

| | |
|--|--|
| Official product page | [B01 & B02 — inricosolutions.com](https://www.inricosolutions.com/products/B01-B02.html) |
| Manufacturer brochure (PDF) | [B01/B02 brochure](https://www.inricosolutions.com/file/upload/2026-07/16/202607160952056521.pdf) |

Notes:

- **B02** supports **iOS and Android**; **B01** is primarily Android.
- Profiles include HFP, A2DP, SPP, and BLE (PTT button path used by the kit).
- Marketplace listings (Amazon, AliExpress, etc.) often mix B01/B02 names — prefer the official page and the BLE name `B02PTT-FF01` for identification.

## License

[MIT](LICENSE) — free to use in closed-source host apps; keep the copyright notice.

## Layout

```
InricoB02PTT-FF01/
  lib/                    ← InricoB02PTTKit (integrate this)
  InricoB02PTT/           ← demo host UI (example consumer)
  InricoB02PTT.xcodeproj  ← links the local package from lib/
```

The Xcode app target depends on the package via `project.yml` (`packages.path: lib`). BLE scan/connect/PTT lives only in the kit; the app adds SwiftUI, haptic/sound, and logging.

## Demo app features

1. Foreground operation
2. Background operation (`UIBackgroundModes` → `bluetooth-central` + state restoration)
3. Calls `InricoB02PTTClient.start()` / `connect()` / `disconnect()`
4. Visual PTT DOWN / UP + optional sound and haptic

Headset audio uses system **HFP/A2DP** after pairing in Settings. The kit handles **BLE PTT events only**.

## Architecture (this repo as an example)

| File | Role |
|------|------|
| `lib/…/InricoB02PTTClient.swift` | Production BLE client (use in your app) |
| `lib/…/B02PTTProtocol.swift` | Device name, Coda UUIDs, payload parser |
| `InricoB02PTT/DemoPTTSession.swift` | Thin SwiftUI bridge + delegate → kit |
| `InricoB02PTT/ContentView.swift` | Demo UI |
| `InricoB02PTT/PTTFeedback.swift` | Demo-only sound / haptic |

Host integration (same as the demo, without UI):

```swift
import InricoB02PTTKit

let client = InricoB02PTTClient()
client.onPttChanged = { isPressed in
    if isPressed { startTransmit() } else { stopTransmit() }
}
client.start()
```

See [`lib/README.md`](lib/README.md) for Info.plist keys and package setup.

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

> On Android, HyTalkPTT also supports Classic **SPP** (`+PTT=P` / `+PTT=R`) for this model. On iOS, SPP is not available to third-party apps; use **BLE** for the button, as Zello does.

## Running

1. Open `InricoB02PTT.xcodeproj` in Xcode (resolves local package `lib/`)
2. Select your Development Team (Signing)
3. Install on a **physical iPhone** (BLE simulator is useless)
4. Pair the Inrico in **Settings → Bluetooth** (for audio)
5. Run the app → allow Bluetooth → **Scan / Connect**
6. Hold PTT on the headset — the indicator turns red (**PTT DOWN**)

Regenerate the Xcode project after changing sources / `project.yml`:

```bash
xcodegen generate
```

## Requirements

- iOS 15+
- Xcode 15+
- Physical device
- Inrico B02 / BLE name: `B02PTT-FF01` (variants `B02PTT*` may appear)

## Handing off to a developer

Ship [`lib/`](lib/) (or point them at this repo and the package). Contract:

- `InricoB02PTTClient` → `onPttChanged` / `InricoB02PTTClientDelegate`
- HFP audio session is configured by the host (`AVAudioSession` playAndRecord + Bluetooth HFP)
