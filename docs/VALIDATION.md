# Local validation — 2026-10-12

Environment: Apple Silicon (arm64), macOS 27.0, Swift 6.4 Command Line Tools. The package deployment target is macOS 15; older supported macOS versions and Intel builds have not been exercised locally.

- Debug and release builds completed.
- All 11 Swift Testing protocol tests passed.
- Packaged `dist/JC2Mac.app`; code-signature verification and Info.plist lint passed. The default app has no virtual HID entitlement.
- Launched the packaged app and visually checked the two controller panels, stick monitors, output selector, mapping instructions, and diagnostics.
- Bluetooth reached the powered-on state; Find Joy-Cons started scanning and Stop scan stopped it.
- Selected Virtual Gamepad and enabled output in the default build. macOS refused virtual HID creation; the error was displayed in the output pane and diagnostics, and output remained off.
- Keyboard/mouse mode displayed the mapping and Accessibility requirement. Accessibility was not granted during this smoke test, and live keyboard/mouse injection was not exercised.
- Shell syntax, property lists, and whitespace checks passed.

Physical controllers were not paired during validation. The test fixtures are synthetic. Bluetooth initialization, button/stick direction and range, safe releases with live injected input, approved virtual HID creation, and game compatibility remain pending the hardware checklist in HARDWARE_TESTING.md.

The active developer-tool selection changed during the session to an Xcode installation requesting license/first-launch setup. Final builds/tests used `DEVELOPER_DIR=/Library/Developer/CommandLineTools` with the already configured Command Line Tools. No system tool selection or license acceptance was changed.

# Separate-player validation — 2026-10-13 (0.2.0)

- Debug/release builds completed with the configured Command Line Tools.
- All 23 Swift Testing tests passed: 11 original protocol tests, 7 separate-player mapping/routing tests, and 5 multi-device lifecycle tests using fake outputs.
- New coverage checks both sideways stick rotations, all face-button positions, SL/SR shoulders and menu/stick clicks, isolated input reports, timeout/disconnect behavior without player renumbering, distinct HID identities, first/second-device failure cleanup, switching layouts, and neutralization of both outputs.
- Launched the packaged app; verified Combined/Separate selector, left/right player labels, independent neutral player previews, and sideways instructions visually.
- Attempted Separate output in the default ad-hoc build. macOS refused Player 1 virtual HID creation; the app displayed the named error, left output disabled, and remained responsive. Two-device creation with an approved entitlement could not be exercised on this build.
- Physical Joy-Con 2 pairing, sideways physical button/stick interpretation, approved live dual-HID output, and Steam/Overcooked recognition remain unverified. The hardware checklist now includes separate-player joining and disconnect checks.
