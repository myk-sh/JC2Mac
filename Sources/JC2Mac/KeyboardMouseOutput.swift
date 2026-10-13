import AppKit
import ApplicationServices
import JC2Core

final class KeyboardMouseOutput {
    private var heldKeys: Set<UInt16> = []
    private var leftDown = false
    private var rightDown = false
    private let source = CGEventSource(stateID: .privateState)
    var speed: Double = 900 // points per second at full stick deflection

    var permitted: Bool { AXIsProcessTrusted() }
    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
    func update(_ state: GamepadState, delta: Double) {
        guard permitted else { releaseAll(); return }
        let wanted = KeyboardMapping.keys(for: state)
        for key in heldKeys.subtracting(wanted) { postKey(key, down: false) }
        for key in wanted.subtracting(heldKeys) { postKey(key, down: true) }
        heldKeys = wanted
        let dx = state.right.x * speed * delta
        let dy = -state.right.y * speed * delta
        if abs(dx) + abs(dy) > 0.01, let position = CGEvent(source: nil)?.location {
            // CGEvent uses top-left display coordinates. Clamp to the active display union.
            let bounds = NSScreen.screens.reduce(CGRect.null) { $0.union($1.frame) }
            let mainHeight = CGDisplayBounds(CGMainDisplayID()).height
            let cgBounds = CGRect(x: bounds.minX, y: mainHeight - bounds.maxY, width: bounds.width, height: bounds.height)
            let point = CGPoint(x: min(cgBounds.maxX - 1, max(cgBounds.minX, position.x + dx)),
                                y: min(cgBounds.maxY - 1, max(cgBounds.minY, position.y + dy)))
            let type: CGEventType = leftDown ? .leftMouseDragged : rightDown ? .rightMouseDragged : .mouseMoved
            let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point,
                               mouseButton: rightDown ? .right : .left)
            event?.setDoubleValueField(.mouseEventDeltaX, value: dx)
            event?.setDoubleValueField(.mouseEventDeltaY, value: dy)
            event?.post(tap: .cghidEventTap)
        }
        setMouse(left: state.buttons.contains(.zr), right: state.buttons.contains(.zl))
    }
    func releaseAll() {
        for key in heldKeys { postKey(key, down: false) }
        heldKeys.removeAll()
        setMouse(left: false, right: false)
    }
    private func postKey(_ key: UInt16, down: Bool) {
        CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(key), keyDown: down)?.post(tap: .cghidEventTap)
    }
    private func setMouse(left: Bool, right: Bool) {
        let point = CGEvent(source: nil)?.location ?? .zero
        if left != leftDown {
            CGEvent(mouseEventSource: source, mouseType: left ? .leftMouseDown : .leftMouseUp,
                    mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
            leftDown = left
        }
        if right != rightDown {
            CGEvent(mouseEventSource: source, mouseType: right ? .rightMouseDown : .rightMouseUp,
                    mouseCursorPosition: point, mouseButton: .right)?.post(tap: .cghidEventTap)
            rightDown = right
        }
    }
}
