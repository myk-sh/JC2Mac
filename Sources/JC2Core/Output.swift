import Foundation

public enum KeyboardMapping {
    // macOS virtual key codes (physical ANSI positions).
    public static func keys(for state: GamepadState) -> Set<UInt16> {
        let mapping: [Button: UInt16] = [
            .a: 49, .b: 53, .x: 14, .y: 15, .l: 12, .r: 3,
            .plus: 36, .minus: 48, .leftStick: 8, .rightStick: 9,
            .up: 126, .down: 125, .left: 123, .right: 124
        ]
        var keys = Set(state.buttons.compactMap { mapping[$0] })
        if state.left.x < -0.35 { keys.insert(0) }   // A
        if state.left.x > 0.35 { keys.insert(2) }    // D
        if state.left.y > 0.35 { keys.insert(13) }   // W
        if state.left.y < -0.35 { keys.insert(1) }   // S
        return keys
    }
}

public enum GamepadHID {
    // Generic gamepad: 16 buttons, four signed 16-bit axes, a 4-bit hat + padding.
    // No vendor impersonation. Consumers must support generic HID gamepads.
    public static let descriptor = Data([
        0x05,0x01, 0x09,0x05, 0xa1,0x01,
        0x05,0x09, 0x19,0x01, 0x29,0x10, 0x15,0x00, 0x25,0x01,
        0x75,0x01, 0x95,0x10, 0x81,0x02,
        0x05,0x01, 0x09,0x30, 0x09,0x31, 0x09,0x33, 0x09,0x34,
        0x16,0x01,0x80, 0x26,0xff,0x7f, 0x75,0x10, 0x95,0x04, 0x81,0x02,
        0x09,0x39, 0x15,0x00, 0x25,0x07, 0x35,0x00, 0x46,0x3b,0x01,
        0x65,0x14, 0x75,0x04, 0x95,0x01, 0x81,0x42,
        0x65,0x00, 0x75,0x04, 0x95,0x01, 0x81,0x03, 0xc0
    ])
    public static func report(_ state: GamepadState) -> Data {
        let order: [Button] = [.b, .a, .y, .x, .l, .r, .zl, .zr, .minus, .plus,
                               .leftStick, .rightStick, .home, .capture, .chat, .sl]
        var bits: UInt16 = 0
        for (i, button) in order.enumerated() where state.buttons.contains(button) { bits |= 1 << i }
        // Rail shoulder SR shares the normal R button in a combined layout.
        if state.buttons.contains(.sr) { bits |= 1 << 5 }
        var bytes: [UInt8] = [UInt8(truncatingIfNeeded: bits), UInt8(bits >> 8)]
        for value in [state.left.x, -state.left.y, state.right.x, -state.right.y] {
            let finite = value.isFinite ? value : 0
            let axis = UInt16(bitPattern: Int16((min(1, max(-1, finite)) * 32767).rounded()))
            bytes += [UInt8(truncatingIfNeeded: axis), UInt8(axis >> 8)]
        }
        let dx = (state.buttons.contains(.right) ? 1 : 0) - (state.buttons.contains(.left) ? 1 : 0)
        let dy = (state.buttons.contains(.down) ? 1 : 0) - (state.buttons.contains(.up) ? 1 : 0)
        let hats = ["0,-1": 0, "1,-1": 1, "1,0": 2, "1,1": 3,
                    "0,1": 4, "-1,1": 5, "-1,0": 6, "-1,-1": 7]
        bytes.append(UInt8(hats["\(dx),\(dy)"] ?? 8))
        return Data(bytes)
    }
}
