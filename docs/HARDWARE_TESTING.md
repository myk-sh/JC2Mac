# Joy-Con 2 hardware validation

Not yet executed against physical controllers. Record macOS version, controller firmware, side, and build identity with each result.

- Launch the packaged app from its final location. Verify Bluetooth permission appears with the JC2Mac name and usage message.
- Scan with no controllers awake; verify the UI stays responsive and scanning ends after 30 seconds.
- Hold SYNC on a left Joy-Con 2, connect it, accept any pairing prompt, and verify reports stream. Repeat for the right controller. Verify an original Joy-Con is ignored.
- Press each physical button individually. Check that only the matching monitor indicator changes, including SL/SR, C, capture, Home, and stick clicks where present.
- Check both sticks at center and each endpoint. Confirm X is positive right and Y positive up; record actual min/center/max raw values if normalization needs adjustment.
- Center untouched sticks, quit/relaunch, reconnect, and verify saved centers. Test reset center and several deadzones.
- Select Monitor and confirm no keys, pointer movement, or clicks are emitted.
- Enable keyboard/mouse with Accessibility absent; verify output stays disabled and the permission prompt is shown. Grant permission, enable output, and check the documented mapping in a harmless test app.
- Hold a mapped key or mouse button, then disconnect, switch output modes, deselect that controller, stop output, quit, disable Bluetooth, and put the Mac to sleep. For each condition verify injected inputs are released.
- Stop input notifications without disconnecting (if reproducible), and verify release after 0.5 seconds. Verify the other controller continues working.
- Resume from sleep and reconnect manually. Verify output stays disabled.
- Connect multiple controllers of the same side; confirm only the selected one supplies output.
- In a default unsigned/ad-hoc build, attempt Virtual Gamepad. Verify refusal is visible and output remains disabled; do not add restricted entitlements without Apple authorization.
- In an approved, provisioned build, verify generic HID enumeration with an HID consumer, all button slots, four axes, diagonals, and neutral hat value. Separately test each intended game/Steam; record compatibility rather than assuming it from enumeration.
- Hold virtual inputs while disconnecting one/both halves, switching mode, and quitting. Confirm neutral reports and device removal.
- Select **Separate · 2 players** and verify the two mapped previews separately before enabling output. Hold both sideways with the sticks on the left and SL/SR on top. Check all four directions, face-button positions, SL/SR shoulders, and −/+ menu buttons. Confirm the right Joy-Con drives its player's left stick.
- In an approved build, verify two HID devices with distinct names, serial/unique IDs, and location IDs appear. Confirm each receives only its own inputs and both right sticks and hats stay neutral.
- With both players holding different inputs, disconnect/stall Player 1, then Player 2. Verify only the affected device goes neutral and the other device's identity and input remain intact. Reconnect manually and verify input resumes in the same player slot.
- While holding inputs, switch Combined ↔ Separate and verify output stops, old devices disappear, and re-enabling creates the correct number of new devices. Stop output and quit with both players holding buttons; verify both devices are removed.
- In Steam and the intended Overcooked edition, test actual two-player joining, movement, interaction, dash, and menus. Verify the game's player order and record bindings/compatibility separately from HID enumeration. Overcooked recognition is not established by the automated tests.
- Exercise failure of the second virtual device in a development build; confirm Player 1 is removed too and output remains disabled. The automated fake-output test covers this cleanup path without entitlements.

Automated tests validate protocol and report math only. BLE pairing, initialization acknowledgments, correct physical button/axis interpretation, CoreHID authorization, and application recognition require these live checks.
