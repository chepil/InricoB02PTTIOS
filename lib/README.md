# InricoB02PTTKit

Swift package for the **Inrico B02PTT-FF01** (Inrico BT02) PTT button on iOS.

Library only: no UI, no test screen, no sound feedback.  
Intended to be handed to a third-party PTT app developer.

## Hardware

**Inrico B02** Bluetooth remote speaker microphone (RSM). On iOS / BLE it typically appears as **`B02PTT-FF01`**.

| | |
|--|--|
| Official product page | [B01 & B02 — inricosolutions.com](https://www.inricosolutions.com/products/B01-B02.html) |
| Manufacturer brochure (PDF) | [B01/B02 brochure](https://www.inricosolutions.com/file/upload/2026-07/16/202607160952056521.pdf) |

Notes:

- **B02** supports **iOS and Android**; **B01** is primarily Android.
- Profiles include HFP, A2DP, SPP, and BLE (this package uses the BLE PTT path).
- Marketplace listings (Amazon, AliExpress, etc.) often mix B01/B02 names — prefer the official page and the BLE name `B02PTT-FF01` for identification.

## License

[MIT](../LICENSE) — free to use in closed-source host apps; keep the copyright notice.

## What the package does

| | |
|--|--|
| **Yes** | BLE scan for `B02PTT*`, connect, notify subscription, press/release, reconnect, background restore |
| **No** | UI, in-app scanner screen, test sounds, microphone/speaker handling |

Audio (speaker / mic) uses system **HFP/A2DP** after the headset is paired in **Settings → Bluetooth**. The host app configures `AVAudioSession` itself.

## Protocol (verified on device)

From the reference app logs:

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

Device name: `B02PTT-FF01` (prefix `B02PTT`).

---

## Integrating into your project

### 1. Add the package

**Option A — local Swift Package (recommended)**

1. In Xcode: **File → Add Package Dependencies…**
2. **Add Local…** → select the folder  
   `…/InricoB02PTT-FF01/lib`
3. Product: **InricoB02PTTKit** → Add to your app target

**Option B — copy sources**

Copy the contents of  
`lib/InricoB02PTTKit/Sources/InricoB02PTTKit/`  
into your target and add the files to Compile Sources.

### 2. Info.plist (required)

In the **host** app (not in the package):

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Bluetooth is required to connect to the Inrico B02 PTT button.</string>

<key>UIBackgroundModes</key>
<array>
    <string>bluetooth-central</string>
</array>
```

`bluetooth-central` is required so PTT keeps working in the background / after session restore.

### 3. Code

```swift
import InricoB02PTTKit

final class PTTBridge: InricoB02PTTClientDelegate {
    private let inrico = InricoB02PTTClient(
        configuration: .init(
            // Unique id for your app (CoreBluetooth state restoration)
            centralRestoreIdentifier: "com.yourapp.inrico.b02.central"
        )
    )

    func startInrico() {
        inrico.delegate = self
        // or: inrico.onPttChanged = { pressed in … }
        inrico.start()
    }

    func inricoB02PTTClient(_ client: InricoB02PTTClient, pttPressed: Bool) {
        if pressed {
            // startTransmit()
        } else {
            // stopTransmit()
        }
    }

    func inricoB02PTTClient(
        _ client: InricoB02PTTClient,
        didChange state: InricoB02PTTConnectionState,
        detail: String
    ) {
        // optional: update host UI status
        print("Inrico:", state, detail)
    }
}
```

### 4. When to call `start()` / `connect()`

| Situation | Call |
|-----------|------|
| User enables Inrico support | `start()` |
| Re-discover the button | `connect()` |
| Disable support | `stop()` or `disconnect(forgetDevice: true)` |

On powered-on, `start()` runs: restore → saved UUID → scan.

### 5. Audio (outside this library)

```swift
let session = AVAudioSession.sharedInstance()
try session.setCategory(
    .playAndRecord,
    mode: .voiceChat,
    options: [.allowBluetooth, .allowBluetoothA2DP]
)
try session.setActive(true)
```

The headset must be paired in the system. This library does **not** change the audio route.

---

## Public API

| API | Purpose |
|-----|---------|
| `start()` | Create central, keep-alive, auto connect |
| `connect()` | Force a new scan |
| `stop()` | Stop keep-alive |
| `disconnect(forgetDevice:)` | Drop the link |
| `onPttChanged` / `delegate` | PTT events |
| `isPttPressed` | Current PTT state |
| `connectionState` | idle / scanning / ready / … |

---

## Requirements

- iOS 15+
- Physical device (BLE simulator is not suitable)
- Inrico B02 paired for audio; the BLE button is handled by this package

## Contents of `lib`

```
lib/
  Package.swift
  README.md                          ← this guide
  InricoB02PTTKit/Sources/InricoB02PTTKit/
    InricoB02PTTClient.swift         ← client
    B02PTTProtocol.swift             ← UUIDs / parser
```

A reference **demo host** that depends on this local package lives at the repository root  
(`InricoB02PTT` app + `DemoPTTSession.swift`). Open `InricoB02PTT.xcodeproj` to see a working consumer.

For production integration, use **only** this package — not the demo UI.
