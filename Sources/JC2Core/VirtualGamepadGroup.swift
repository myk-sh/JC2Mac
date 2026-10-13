import Foundation

/// A platform output interface so multi-device routing and lifecycle can be tested without HID entitlements.
@MainActor
public protocol VirtualControllerOutput: AnyObject {
    func start(slot: VirtualControllerSlot, onError: @escaping @MainActor (String) -> Void) async throws
    func update(_ state: GamepadState)
    func stop() async
}

/// The caller serializes start/stop transitions. Either all requested players start, or none remain.
@MainActor
public final class VirtualGamepadGroup {
    private let makeOutput: () -> any VirtualControllerOutput
    private var outputs: [any VirtualControllerOutput] = []
    private var layout: GamepadLayout?

    public init(makeOutput: @escaping () -> any VirtualControllerOutput) { self.makeOutput = makeOutput }

    public func start(layout: GamepadLayout, onError: @escaping @MainActor (String) -> Void) async throws {
        await stop()
        do {
            for slot in layout.slots {
                let output = makeOutput()
                // Include the currently starting output in cleanup if it partially initializes then throws.
                outputs.append(output)
                try await output.start(slot: slot, onError: onError)
            }
            self.layout = layout
        } catch {
            await stop()
            throw error
        }
    }

    public func update(left: InputReport?, right: InputReport?) {
        guard let layout else { return }
        let states = GamepadRouting.states(layout: layout, left: left, right: right)
        for (output, state) in zip(outputs, states) { output.update(state) }
    }

    public func neutralize() {
        for output in outputs { output.update(GamepadState()) }
    }

    public func stop() async {
        layout = nil
        let previous = outputs
        outputs.removeAll()
        // Release every player's input before awaiting removal of individual devices.
        for output in previous { output.update(GamepadState()) }
        for output in previous { await output.stop() }
    }
}
