import Foundation

public enum JoyConSide: String, Codable, CaseIterable, Sendable {
    case left, right
    public var label: String { self == .left ? "Left" : "Right" }
}

public enum Button: String, CaseIterable, Sendable {
    case a = "A", b = "B", x = "X", y = "Y"
    case up = "↑", down = "↓", left = "←", right = "→"
    case l = "L", r = "R", zl = "ZL", zr = "ZR", sl = "SL", sr = "SR"
    case plus = "+", minus = "−", leftStick = "L3", rightStick = "R3"
    case home = "Home", capture = "Capture", chat = "C"
}

public struct Stick: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double = 0, y: Double = 0) { self.x = x; self.y = y }
}

public struct StickCalibration: Codable, Equatable, Sendable {
    public var centerX: Int
    public var centerY: Int
    public var deadzone: Double
    public init(centerX: Int = 2048, centerY: Int = 2048, deadzone: Double = 0.12) {
        self.centerX = min(4094, max(1, centerX))
        self.centerY = min(4094, max(1, centerY))
        self.deadzone = min(0.5, max(0, deadzone))
    }
    public func normalize(x: Int, y: Int) -> Stick {
        func axis(_ raw: Int, _ center: Int) -> Double {
            let center = min(4094, max(1, center))
            return min(1, max(-1, Double(raw - center) / Double(raw >= center ? 4095 - center : center)))
        }
        let sx = axis(x, centerX), sy = axis(y, centerY)
        let magnitude = hypot(sx, sy), dz = min(0.5, max(0, deadzone))
        guard magnitude > dz else { return Stick() }
        let scale = min(1, (magnitude - dz) / (1 - dz)) / magnitude
        return Stick(x: sx * scale, y: sy * scale)
    }
}

public struct InputReport: Sendable {
    public var sequence: UInt32
    public var buttons: Set<Button>
    public var rawX: Int
    public var rawY: Int
    public var stick: Stick
    public var accel: [Int16]
    public var gyro: [Int16]

    /// BLE characteristic payload, without an HID report ID. Joy-Con 2 uses 63 bytes.
    public init?(data: Data, side: JoyConSide, calibration: StickCalibration = .init()) {
        guard data.count == 63 || data.count == 64 else { return nil }
        let b = Array(data)
        func u32(_ o: Int) -> UInt32 {
            (0..<4).reduce(0) { $0 | UInt32(b[o + $1]) << ($1 * 8) }
        }
        func s16(_ o: Int) -> Int16 { Int16(bitPattern: UInt16(b[o]) | UInt16(b[o + 1]) << 8) }
        sequence = u32(0)
        let bits = u32(4)
        // The inactive half's bits and stick data may contain garbage; filter by side.
        let masks: [(Button, UInt32)] = side == .left ? [
            (.down, 0x00010000), (.up, 0x00020000), (.right, 0x00040000), (.left, 0x00080000),
            (.sr, 0x00100000), (.sl, 0x00200000), (.l, 0x00400000), (.zl, 0x00800000),
            (.minus, 0x00000100), (.leftStick, 0x00000800), (.capture, 0x00002000)
        ] : [
            (.y, 0x00000001), (.x, 0x00000002), (.b, 0x00000004), (.a, 0x00000008),
            (.sr, 0x00000010), (.sl, 0x00000020), (.r, 0x00000040), (.zr, 0x00000080),
            (.plus, 0x00000200), (.rightStick, 0x00000400), (.home, 0x00001000), (.chat, 0x00004000)
        ]
        buttons = Set(masks.filter { bits & $0.1 != 0 }.map(\.0))
        let o = side == .left ? 10 : 13
        rawX = Int(b[o]) | Int(b[o + 1] & 0x0f) << 8
        rawY = Int(b[o + 1] >> 4) | Int(b[o + 2]) << 4
        stick = calibration.normalize(x: rawX, y: rawY)
        accel = [s16(0x30), s16(0x32), s16(0x34)]
        gyro = [s16(0x36), s16(0x38), s16(0x3a)]
    }
}

public struct GamepadState: Equatable, Sendable {
    public var buttons: Set<Button> = []
    public var left = Stick()
    public var right = Stick()
    public init() {}
    public init(left: InputReport?, right: InputReport?) {
        buttons = (left?.buttons ?? []).union(right?.buttons ?? [])
        self.left = left?.stick ?? Stick()
        self.right = right?.stick ?? Stick()
    }
}

public struct TimedReport: Sendable {
    public var report: InputReport
    public var receivedAt: TimeInterval
    public init(report: InputReport, receivedAt: TimeInterval) { self.report = report; self.receivedAt = receivedAt }
}

public enum InputSafety {
    /// Use a monotonic clock. Do not keep a held input alive after notifications stop.
    public static func fresh(_ value: TimedReport?, now: TimeInterval, timeout: TimeInterval = 0.5) -> InputReport? {
        guard let value, now >= value.receivedAt, now - value.receivedAt < timeout else { return nil }
        return value.report
    }
}
