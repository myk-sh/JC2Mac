import Foundation
import Testing
@testable import JC2Core

private func input(side: JoyConSide, buttons: Set<Button> = [], stick: Stick = .init()) -> InputReport {
    // Start with a valid payload; override normalized fields to test routing independently of decoding.
    var report = InputReport(data: Data(repeating: 0, count: 63), side: side)!
    report.buttons = buttons
    report.stick = stick
    return report
}

struct SeparatePlayersTests {
    @Test func sidewaysCardinalDirectionsForBothHands() {
        let vectors: [(Stick, Stick, Stick)] = [
            (Stick(x: 1, y: 0), Stick(x: 0, y: 1), Stick(x: 0, y: -1)),
            (Stick(x: -1, y: 0), Stick(x: 0, y: -1), Stick(x: 0, y: 1)),
            (Stick(x: 0, y: 1), Stick(x: -1, y: 0), Stick(x: 1, y: 0)),
            (Stick(x: 0, y: -1), Stick(x: 1, y: 0), Stick(x: -1, y: 0))
        ]
        for (physical, expectedLeft, expectedRight) in vectors {
            #expect(GamepadRouting.sideways(input(side: .left, stick: physical), side: .left).left == expectedLeft)
            #expect(GamepadRouting.sideways(input(side: .right, stick: physical), side: .right).left == expectedRight)
        }
    }

    @Test func faceButtonsFollowSidewaysPositions() {
        let mapping: [(JoyConSide, Button, Button)] = [
            (.left, .left, .b), (.left, .down, .a), (.left, .up, .y), (.left, .right, .x),
            (.right, .a, .b), (.right, .x, .a), (.right, .b, .y), (.right, .y, .x)
        ]
        for (side, physical, expected) in mapping {
            let state = GamepadRouting.sideways(input(side: side, buttons: [physical]), side: side)
            #expect(state.buttons == [expected])
            #expect(GamepadHID.report(state).last == 8) // Left face buttons no longer drive the hat.
        }
    }

    @Test func shouldersMenuAndStickClickAvailableToEachPlayer() {
        let left = GamepadRouting.sideways(input(side: .left, buttons: [.sl, .sr, .l, .zl, .minus, .leftStick]), side: .left)
        let right = GamepadRouting.sideways(input(side: .right, buttons: [.sl, .sr, .r, .zr, .plus, .rightStick]), side: .right)
        #expect(left.buttons == [.l, .r, .zl, .zr, .plus, .leftStick])
        #expect(right.buttons == left.buttons)
        #expect(!right.buttons.contains(.rightStick))
    }

    @Test func separatePlayersHaveIndependentButtonsAndMovement() {
        let left = input(side: .left, buttons: [.left, .sl], stick: Stick(x: 0.4, y: -0.7))
        let right = input(side: .right, buttons: [.x, .sr], stick: Stick(x: -0.8, y: 0.2))
        let states = GamepadRouting.states(layout: .separate, left: left, right: right)
        #expect(states.count == 2)
        #expect(states[0].buttons == [.b, .l])
        #expect(states[1].buttons == [.a, .r])
        #expect(states[0].left == Stick(x: 0.7, y: 0.4))
        #expect(states[1].left == Stick(x: 0.2, y: 0.8))
        #expect(states.allSatisfy { $0.right == Stick() })
        let bytes1 = Array(GamepadHID.report(states[0]))
        let bytes2 = Array(GamepadHID.report(states[1]))
        #expect(bytes1[0] == 0x11) // B + left shoulder only
        #expect(bytes2[0] == 0x22) // A + right shoulder only
        #expect(Array(bytes1[6...9]) == [0, 0, 0, 0])
        #expect(Array(bytes2[6...9]) == [0, 0, 0, 0])
    }

    @Test func disconnectOrTimeoutNeutralizesOnlyThatPlayerWithoutRenumbering() {
        let left = TimedReport(report: input(side: .left, buttons: [.left]), receivedAt: 10)
        let right = TimedReport(report: input(side: .right, buttons: [.x]), receivedAt: 10.4)
        let states = GamepadRouting.states(layout: .separate,
            left: InputSafety.fresh(left, now: 10.5), right: InputSafety.fresh(right, now: 10.5))
        #expect(states[0] == GamepadState())
        #expect(states[1].buttons == [.a])
        let missingRight = GamepadRouting.states(layout: .separate, left: left.report, right: nil)
        #expect(missingRight[0].buttons == [.b])
        #expect(missingRight[1] == GamepadState())
        #expect(GamepadRouting.states(layout: .separate, left: nil, right: nil) == [GamepadState(), GamepadState()])
    }

    @Test func combinedModeRetainsOriginalUprightMapping() {
        let left = input(side: .left, buttons: [.up, .minus], stick: Stick(x: 0.3, y: 0.8))
        let right = input(side: .right, buttons: [.a, .zr], stick: Stick(x: -0.4, y: 0.5))
        #expect(GamepadRouting.states(layout: .combined, left: left, right: right) == [GamepadState(left: left, right: right)])
    }

    @Test func eachVirtualControllerHasADistinctIdentity() {
        #expect(GamepadLayout.combined.slots == [.combined])
        #expect(GamepadLayout.separate.slots == [.player1, .player2])
        #expect(Set(VirtualControllerSlot.allCases.map(\.uniqueID)).count == 3)
        #expect(Set(VirtualControllerSlot.allCases.map(\.locationID)).count == 3)
        #expect(Set(VirtualControllerSlot.allCases.map(\.productName)).count == 3)
    }
}

@MainActor
private final class FakeOutput: VirtualControllerOutput {
    var slot: VirtualControllerSlot?
    var updates: [GamepadState] = []
    var stopCount = 0
    var failOnStart = false
    func start(slot: VirtualControllerSlot, onError: @escaping @MainActor (String) -> Void) async throws {
        self.slot = slot
        if failOnStart { throw NSError(domain: "TestHID", code: 1) }
    }
    func update(_ state: GamepadState) { updates.append(state) }
    func stop() async { stopCount += 1 }
}

@MainActor
struct VirtualGamepadGroupTests {
    @Test func startsTwoDevicesAndRoutesEachHalfToItsOwnOutput() async throws {
        var outputs: [FakeOutput] = []
        let group = VirtualGamepadGroup { let output = FakeOutput(); outputs.append(output); return output }
        try await group.start(layout: .separate) { _ in }
        #expect(outputs.map(\.slot) == [.player1, .player2])
        group.update(left: input(side: .left, buttons: [.up]), right: input(side: .right, buttons: [.x]))
        #expect(outputs[0].updates.last?.buttons == [.y])
        #expect(outputs[1].updates.last?.buttons == [.a])
        group.update(left: nil, right: input(side: .right, buttons: [.zr]))
        #expect(outputs[0].updates.last == GamepadState())
        #expect(outputs[1].updates.last?.buttons == [.zr])
        await group.stop()
        #expect(outputs.allSatisfy { $0.updates.last == GamepadState() && $0.stopCount == 1 })
        let counts = outputs.map { $0.updates.count }
        group.update(left: input(side: .left, buttons: [.up]), right: nil)
        #expect(outputs.map { $0.updates.count } == counts)
    }

    @Test func secondDeviceFailureRollsBackBothDevices() async {
        var outputs: [FakeOutput] = []
        let group = VirtualGamepadGroup {
            let output = FakeOutput()
            output.failOnStart = outputs.count == 1
            outputs.append(output)
            return output
        }
        do {
            try await group.start(layout: .separate) { _ in }
            Issue.record("Expected the second device to fail")
        } catch {
            #expect((error as NSError).domain == "TestHID")
        }
        #expect(outputs.count == 2)
        #expect(outputs.allSatisfy { $0.stopCount == 1 && $0.updates.last == GamepadState() })
        group.update(left: input(side: .left, buttons: [.left]), right: nil)
        #expect(outputs.allSatisfy { $0.updates.count == 1 })
        await group.stop()
        #expect(outputs.allSatisfy { $0.stopCount == 1 })
    }

    @Test func firstDeviceFailureDoesNotStartSecondPlayer() async {
        var outputs: [FakeOutput] = []
        let group = VirtualGamepadGroup {
            let output = FakeOutput(); output.failOnStart = true; outputs.append(output); return output
        }
        do {
            try await group.start(layout: .separate) { _ in }
            Issue.record("Expected startup to fail")
        } catch {}
        #expect(outputs.count == 1)
        #expect(outputs[0].stopCount == 1)
        #expect(outputs[0].updates.last == GamepadState())
    }

    @Test func changingLayoutRemovesOldPlayersBeforeStartingCombinedOutput() async throws {
        var outputs: [FakeOutput] = []
        let group = VirtualGamepadGroup {
            #expect(outputs.allSatisfy { $0.stopCount == 1 } || outputs.count < 2)
            let output = FakeOutput(); outputs.append(output); return output
        }
        try await group.start(layout: .separate) { _ in }
        group.update(left: input(side: .left, buttons: [.up]), right: input(side: .right, buttons: [.x]))
        try await group.start(layout: .combined) { _ in }
        #expect(outputs.map(\.slot) == [.player1, .player2, .combined])
        #expect(outputs[0].stopCount == 1 && outputs[1].stopCount == 1)
        #expect(outputs[0].updates.last == GamepadState() && outputs[1].updates.last == GamepadState())
        group.update(left: input(side: .left, buttons: [.up]), right: input(side: .right, buttons: [.a]))
        #expect(outputs[2].updates.last?.buttons == [.up, .a])
        await group.stop()
        #expect(outputs[2].stopCount == 1)
    }

    @Test func selectionChangeCanReleaseBothPlayersImmediately() async throws {
        var outputs: [FakeOutput] = []
        let group = VirtualGamepadGroup { let output = FakeOutput(); outputs.append(output); return output }
        try await group.start(layout: .separate) { _ in }
        group.update(left: input(side: .left, buttons: [.sl]), right: input(side: .right, buttons: [.sr]))
        group.neutralize()
        #expect(outputs.allSatisfy { $0.updates.last == GamepadState() })
        await group.stop()
    }
}
