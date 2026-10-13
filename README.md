# JC2Mac

An experimental native macOS **Joy-Con 2 Bluetooth LE driver / input bridge**, built in Swift. Connect either controller or a left/right pair, inspect buttons and sticks, and use them as a keyboard/mouse, one combined virtual gamepad, or two independent sideways virtual gamepads.

**Status:** source builds and automated protocol tests are included. Physical Joy-Con 2 pairing, firmware compatibility, stick direction/range, and live game compatibility still require hardware validation. This is a userspace app, not a kernel extension or a finished notarized driver release.

## Requirements

- macOS 15 or later, Bluetooth LE, and genuine Nintendo Joy-Con 2 controllers.
- Xcode 16 or newer, or compatible Swift 6 Command Line Tools (`xcode-select --install`).
- Bluetooth permission for connecting; Accessibility permission only for keyboard/mouse output.
- No dependencies, administrator access, or kernel extension for the default build.

## Build and launch

```sh
./scripts/build-app.sh
open dist/JC2Mac.app
```

The build produces an ad-hoc signed app for your current Mac architecture. Run the app bundle rather than `swift run`, so macOS has a stable bundle identity and Bluetooth usage description. You can move it to Applications yourself; grant permissions to the final copy. Rebuilds or moving the app may require removing and re-adding it in Accessibility settings.

The build helper keeps Swift caches inside `.build` and uses SwiftPM's native build system to accommodate standalone Command Line Tools. Open `Package.swift` in Xcode to work on the package there. On Swift versions that deprecate `--build-system native`, a deprecation warning is expected.

If a newly installed Xcode requests license/first-launch setup, complete that in Xcode yourself. To build with already configured standalone Command Line Tools instead, use `DEVELOPER_DIR=/Library/Developer/CommandLineTools ./scripts/build-app.sh` (the same prefix works with `./scripts/test.sh`). This selects tools for that command without changing your system configuration.

## Pair and use

1. Detach the Joy-Con 2 controllers. Hold the small **SYNC** button until the player LEDs cycle.
2. Launch JC2Mac, grant Bluetooth access, and click **Find Joy-Cons**. Scanning stops after 30 seconds.
3. Select a controller in each side's picker and click **Connect**. Accept a macOS pairing dialog if shown. The app discovers GATT characteristics and sends the Joy-Con 2 initialization sequence.
4. Confirm that the report count increases and the sticks/buttons respond in **Monitor** mode.
5. With each stick untouched, click **Center stick** if its neutral position needs correction. Adjust the deadzone as needed. Center offsets are saved per macOS peripheral UUID; endpoint range uses the nominal 12-bit range and is not factory-calibrated.
6. Select **Keyboard & Mouse**, grant Accessibility, and click **Enable output**. Switch to your game or app. Output starts disabled every launch.

**Stop output**, **⌘.** in JC2Mac, closing the app, or changing output mode releases injected keys and mouse buttons. Each controller's inputs become neutral after 0.5 seconds without a valid report. Disconnecting one half releases that half while the other continues. The app disconnects controllers and stops output before system sleep. Reconnect manually after waking.

### Default keyboard/mouse layout

| Joy-Con input | macOS output |
| --- | --- |
| Left stick | W / A / S / D |
| D-pad | Arrow keys |
| Right stick | Pointer movement |
| A / B / X / Y | Space / Escape / E / R |
| L / R | Q / F |
| ZR / ZL | Left / right mouse button |
| + / − | Return / Tab |
| Left / right stick press | C / V |

Uses physical macOS key codes; keyboard layout can change the resulting characters. Capture, Home, C, and rail buttons are monitored but do not emit keyboard actions. A single left or right controller works with its half of this upright layout. Keyboard/mouse mode supplies one shared player; the separate-player layout applies to Virtual Gamepad mode.

## Two players with separate Joy-Cons

In **Virtual Gamepad**, choose **Separate · 2 players**, then **Enable output**. This requires the approved signing described below; the default ad-hoc build cannot create virtual gamepads. The selected left controller supplies **Player 1**, and the selected right supplies **Player 2**. This version supports one controller of each side, rather than two controllers of the same side.

Hold each controller sideways, with the **stick on the left and SL/SR on top**. Each controller is published as a separate device with a distinct name, serial/unique ID, and location ID. The player input previews show the rotated movement and mapped buttons even before HID output is enabled, so you can check the layout in an ordinary build.

| Physical input | Left Joy-Con → Player 1 | Right Joy-Con → Player 2 |
| --- | --- | --- |
| Stick | Movement (virtual left stick), rotated sideways | Movement (virtual left stick), rotated sideways |
| Bottom face button when held sideways | Physical ← → virtual B / slot 1 | Physical A → virtual B / slot 1 |
| Right face button when held sideways | Physical ↓ → virtual A / slot 2 | Physical X → virtual A / slot 2 |
| Left face button when held sideways | Physical ↑ → virtual Y / slot 3 | Physical B → virtual Y / slot 3 |
| Top face button when held sideways | Physical → → virtual X / slot 4 | Physical Y → virtual X / slot 4 |
| SL / SR | L / R shoulders | L / R shoulders |
| Outer shoulder / trigger | L → ZL, ZL → ZR | R → ZL, ZR → ZR |
| − or + | − → Start (+) | + → Start (+) |
| Stick press | Left stick click | Left stick click |

The right stick and D-pad hat stay neutral on each separate virtual controller. Face-button positions follow a conventional gamepad layout; physical Nintendo letters on the right Joy-Con are rotated by the mapping. Capture, Home, and C retain their auxiliary button slots where present. The controller panels continue showing physical buttons/upright sticks; the player previews show the actual virtual output.

Connect both controllers and enable the two virtual gamepads before launching the game. A game such as Overcooked must recognize two generic HID controllers and allow each player to join. **Steam/Overcooked compatibility is not yet verified**, and a game may assign its own player order. If it does recognize them, use its controller bindings to adjust actions as needed.

Disconnecting or losing reports from one Joy-Con neutralizes only that player's output, leaving the other playing. Both virtual device identities remain in place until output is stopped, so losing Player 1 does not promote Player 2. Selecting another physical controller releases the previous inputs. Changing between combined and separate layouts stops output; enable it again to create the new devices. If either device fails during startup, both are cleaned up and output stays disabled.

## Virtual gamepad signing

The **Virtual Gamepad** backend uses Apple's public `CoreHID.HIDVirtualDevice` API. **Combined · 1 player** publishes one generic HID gamepad; **Separate · 2 players** publishes two. Each has 16 button slots, four signed stick axes, and a D-pad hat. Nintendo B/A/Y/X map to slots 1/2/3/4; L/R/ZL/ZR to 5/6/7/8. The remaining slots are −, +, L3, R3, Home, Capture, C, SL. SR shares R in combined mode; separate mode maps SL/SR to L/R. ZL/ZR are digital buttons. Rail buttons from both halves are merged only in combined mode.

Live creation requires the restricted **`com.apple.developer.hid.virtual.device`** entitlement approved by Apple, a matching App ID/provisioning profile, and a valid signing identity. Adding an entitlement to an ad-hoc signature does not grant authorization; the default build deliberately omits it. If creation fails, the app reports the failure and leaves output off.

With your own approved profile:

```sh
SIGNING_IDENTITY='Apple Development: Your Name (TEAMID)' \
VIRTUAL_HID_PROFILE='/absolute/path/to/approved.provisionprofile' \
./scripts/build-app.sh
```

The example bundle identifier is `org.jc2mac.driver`; update `Resources/Info.plist` to match your approved App ID. The supplied entitlement plist is a starting point; use the exact entitlements required by your profile for distribution. Notarization/distribution packaging is not included.

Generic HID enumeration does **not** guarantee recognition in System Settings → Game Controllers, Steam, every game, or Apple's Game Controller framework. Apple explicitly does not guarantee virtual-controller compatibility. The app does not impersonate an Xbox/PlayStation/Nintendo device. Keyboard/mouse mode works independently of virtual HID authorization.

References: [HIDVirtualDevice](https://developer.apple.com/documentation/corehid/hidvirtualdevice), [virtual HID entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.hid.virtual.device), [Apple framework engineer's compatibility guidance](https://developer.apple.com/forums/thread/812774).

## Tests

```sh
./scripts/test.sh
```

The 23 tests cover report decoding, advertisement/initialization framing, calibration, stale-input handling, keyboard/HID encoding, sideways button/stick rotations, independent player routing, stable device identities, and multi-device startup/rollback/shutdown. Protocol tests use synthetic packets; lifecycle tests use fake output devices without entitlements. They cannot establish hardware or game compatibility. See [the hardware validation checklist](docs/HARDWARE_TESTING.md) for end-to-end checks.

## Troubleshooting

- **No controllers found:** wake the detached controllers with SYNC, verify Bluetooth permission, and scan again. Exact `Joy-Con 2 (L)` / `Joy-Con 2 (R)` names are accepted as a fallback to Nintendo manufacturer data. Original Joy-Cons and Pro controllers are intentionally excluded.
- **Connection stalls:** inspect **Diagnostics**, disconnect, wake the controller, and reconnect. If macOS has an old pairing, forgetting it in Bluetooth settings may help. Avoid repeated rapid pairing attempts; upstream reports a controller cooldown after repeated failures.
- **Unexpected report length / missing characteristics:** firmware may differ from the reference protocol. Copy diagnostics and record controller firmware, macOS version, and the failing stage. No raw Bluetooth addresses are needed.
- **No keyboard/mouse response:** allow the final app location in System Settings → Privacy & Security → Accessibility, then enable output again. Some games reject synthetic events.
- **Stick range too small or reversed:** this initial version uses nominal 0…4095 endpoints and upright axes. Capture hardware observations before changing normalization; factory calibration reads and direction validation remain future work.

## Scope and protocol sources

Bluetooth only. USB transport, optical mouse sensor output, rumble, factory calibration reads, motion-control output, automatic reconnection, two controllers of the same side, and more than two players are not implemented. Accelerometer/gyro samples are decoded as raw signed values for future use, without claiming calibrated motion output.

Protocol details were checked against [TheFrano/joycon2cpp](https://github.com/TheFrano/joycon2cpp) and [minichip3/joycon2linux](https://github.com/minichip3/joycon2linux). The complete 16-command Joy-Con 2 initialization sequence is adapted from the former under MIT; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). The code uses the implementation's 10/13 stick offsets, rather than an older inconsistent README offset table.
