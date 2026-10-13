import Foundation

public enum GamepadLayout: String, CaseIterable, Sendable {
    case combined = "Combined · 1 player"
    case separate = "Separate · 2 players"

    public var slots: [VirtualControllerSlot] {
        self == .combined ? [.combined] : [.player1, .player2]
    }
}

public enum VirtualControllerSlot: String, CaseIterable, Sendable {
    case combined, player1, player2

    public var productName: String {
        switch self {
        case .combined: return "JC2Mac Combined Joy-Con 2"
        case .player1: return "JC2Mac Player 1 (Left Joy-Con 2)"
        case .player2: return "JC2Mac Player 2 (Right Joy-Con 2)"
        }
    }
    public var uniqueID: String { "org.jc2mac.gamepad.\(rawValue)" }
    public var locationID: UInt64 {
        switch self { case .combined: return 1; case .player1: return 2; case .player2: return 3 }
    }
}

public enum GamepadRouting {
    /// Hold each controller horizontally, with the stick on the left and SL/SR on top.
    /// Face buttons are mapped by position: south/east/west/north = B/A/Y/X.
    public static func sideways(_ report: InputReport?, side: JoyConSide) -> GamepadState {
        guard let report else { return GamepadState() }
        var state = GamepadState()
        let stick = report.stick
        state.left = side == .left ? Stick(x: -stick.y, y: stick.x) : Stick(x: stick.y, y: -stick.x)
        let mappings: [(Button, Button)] = side == .left ? [
            (.left, .b), (.down, .a), (.up, .y), (.right, .x),
            (.sl, .l), (.sr, .r), (.l, .zl), (.zl, .zr),
            (.minus, .plus), (.leftStick, .leftStick), (.capture, .capture)
        ] : [
            (.a, .b), (.x, .a), (.b, .y), (.y, .x),
            (.sl, .l), (.sr, .r), (.r, .zl), (.zr, .zr),
            (.plus, .plus), (.rightStick, .leftStick), (.home, .home), (.chat, .chat)
        ]
        state.buttons = Set(mappings.filter { report.buttons.contains($0.0) }.map(\.1))
        // One stick per controller drives the virtual LEFT stick; the right stick and hat stay neutral.
        return state
    }

    public static func states(layout: GamepadLayout, left: InputReport?, right: InputReport?) -> [GamepadState] {
        switch layout {
        case .combined: return [GamepadState(left: left, right: right)]
        case .separate: return [sideways(left, side: .left), sideways(right, side: .right)]
        }
    }
}
