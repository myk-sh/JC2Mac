import Testing
import Foundation
@testable import JC2Core

struct ProtocolTests {
    private func packet(buttons: UInt32 = 0, left: (Int, Int) = (2048, 2048), right: (Int, Int) = (2048, 2048)) -> Data {
        var b = [UInt8](repeating: 0, count: 63)
        b[0] = 0x78; b[1] = 0x56; b[2] = 0x34; b[3] = 0x12
        for i in 0..<4 { b[4+i] = UInt8(truncatingIfNeeded: buttons >> (8*i)) }
        for (offset, xy) in [(10, left), (13, right)] {
            b[offset] = UInt8(truncatingIfNeeded: xy.0)
            b[offset+1] = UInt8((xy.0 >> 8) | ((xy.1 & 0xf) << 4))
            b[offset+2] = UInt8(xy.1 >> 4)
        }
        b[0x30] = 0x00; b[0x31] = 0xf0 // -4096
        b[0x36] = 0xff; b[0x37] = 0x7f // +32767
        b[0x38] = 0x00; b[0x39] = 0x80 // -32768
        return Data(b)
    }
    @Test func testRejectsMalformedLengthsAndAcceptsDataSlices() throws {
        for length in [0, 1, 16, 60, 62, 65, 100] {
            #expect(InputReport(data: Data(repeating: 0, count: length), side: .left) == nil)
        }
        var withPrefix = Data([0xff]); withPrefix.append(packet())
        #expect(InputReport(data: withPrefix.dropFirst(), side: .left) != nil)
    }
    @Test func testLittleEndianSequencePackedStickAndSignedMotion() throws {
        let report = try #require(InputReport(data: packet(left: (0xabc, 0x123)), side: .left))
        #expect(report.sequence == 0x12345678)
        #expect(report.rawX == 0xabc)
        #expect(report.rawY == 0x123)
        #expect(report.accel == [-4096, 0, 0])
        #expect(report.gyro == [32767, -32768, 0])
    }
    @Test func testSideFiltersInactiveButtonsAndStick() throws {
        let data = packet(buttons: 0x00820088, left: (0, 2048), right: (4095, 2048))
        let left = try #require(InputReport(data: data, side: .left))
        let right = try #require(InputReport(data: data, side: .right))
        #expect(left.buttons == [.up, .zl])
        #expect(right.buttons == [.a, .zr])
        #expect(abs(left.stick.x - -1) < 0.0001)
        #expect(abs(right.stick.x - 1) < 0.0001)
    }
    @Test func testButtonMasksIndividually() throws {
        let masks: [(JoyConSide, Button, UInt32)] = [
            (.right,.y,1), (.right,.x,2), (.right,.b,4), (.right,.a,8),
            (.right,.sr,0x10), (.right,.sl,0x20), (.right,.r,0x40), (.right,.zr,0x80),
            (.right,.plus,0x200), (.right,.rightStick,0x400), (.right,.home,0x1000), (.right,.chat,0x4000),
            (.left,.minus,0x100), (.left,.leftStick,0x800), (.left,.capture,0x2000),
            (.left,.down,0x10000), (.left,.up,0x20000), (.left,.right,0x40000), (.left,.left,0x80000),
            (.left,.sr,0x100000), (.left,.sl,0x200000), (.left,.l,0x400000), (.left,.zl,0x800000)
        ]
        for (side, button, bits) in masks {
            #expect(InputReport(data: packet(buttons: bits), side: side)?.buttons == [button])
        }
    }
    @Test func testCalibrationNeutralExtremesAndRadialDeadzone() {
        let cal = StickCalibration(centerX: 2100, centerY: 1900, deadzone: 0.12)
        #expect(cal.normalize(x: 2100, y: 1900) == Stick())
        #expect(cal.normalize(x: 2200, y: 1950) == Stick())
        #expect(abs(cal.normalize(x: 4095, y: 1900).x - 1) < 0.0001)
        #expect(abs(cal.normalize(x: 0, y: 1900).x - -1) < 0.0001)
        let diagonal = cal.normalize(x: 4095, y: 4095)
        #expect(abs(hypot(diagonal.x, diagonal.y) - 1) < 0.0001)
        #expect(StickCalibration(centerX: 0, centerY: 4095).centerX == 1)
    }
    @Test func testAdvertisementRequiresNintendoAndCorrectProduct() {
        #expect(BLEProtocol.side(manufacturerData: Data([0x53,0x05,1,0,3,0x7e,5,0x67,0x20])) == .left)
        #expect(BLEProtocol.side(manufacturerData: Data([0x53,0x05,1,0,3,0x7e,5,0x66,0x20])) == .right)
        #expect(BLEProtocol.side(manufacturerData: Data([0x53,0x05,1,0,3,0x7e,5,0x69,0x20])) == nil)
        #expect(BLEProtocol.side(manufacturerData: Data([0,0,1,0,3,0x7e,5,0x67,0x20])) == nil)
        #expect(BLEProtocol.side(manufacturerData: Data()) == nil)
    }
    @Test func testInitializationFramingAndDeclaredLengths() {
        #expect(BLEProtocol.initializationPackets.count == 16)
        for packet in BLEProtocol.initializationPackets {
            let bytes = Array(packet)
            #expect(Array(bytes.prefix(17)) == [UInt8](repeating: 0, count: 17))
            #expect(bytes[18] == 0x91)
            #expect(bytes[19] == 0x01)
            #expect(bytes.count == 17 + 8 + Int(bytes[22]))
        }
        #expect(Array(BLEProtocol.initializationPackets.last!.suffix(4)) == [0x37,0,0,0])
    }
    @Test func testStaleInputNeutralizesOnlyAffectedHalf() throws {
        let left = try #require(InputReport(data: packet(buttons: 0x00800000), side: .left))
        let right = try #require(InputReport(data: packet(buttons: 8), side: .right))
        let old = TimedReport(report: left, receivedAt: 10)
        let fresh = TimedReport(report: right, receivedAt: 10.4)
        let combined = GamepadState(left: InputSafety.fresh(old, now: 10.5), right: InputSafety.fresh(fresh, now: 10.5))
        #expect(combined.buttons == [.a])
        #expect(InputSafety.fresh(old, now: 9) == nil)
        #expect(InputSafety.fresh(nil, now: 10) == nil)
    }
    @Test func testKeyboardMappingAndNeutralRelease() {
        var state = GamepadState()
        state.left = Stick(x: -0.8, y: 0.8)
        state.buttons = [.a, .up, .zr]
        #expect(KeyboardMapping.keys(for: state) == [0, 13, 49, 126])
        #expect(KeyboardMapping.keys(for: GamepadState()).isEmpty)
    }
    @Test func testHIDNeutralHatAndSignedAxes() {
        #expect(Array(GamepadHID.report(GamepadState())) == [0,0,0,0,0,0,0,0,0,0,8])
        var state = GamepadState()
        state.buttons = [.b, .a, .zr, .up, .right]
        state.left = Stick(x: 1, y: 1)
        state.right = Stick(x: -1, y: -1)
        #expect(Array(GamepadHID.report(state)) == [0x83,0,0xff,0x7f,1,0x80,1,0x80,0xff,0x7f,1])
        state.buttons = [.up, .down, .left, .right]
        #expect(GamepadHID.report(state).last == 8)
    }
    @Test func testHIDDescriptorInputSizeMatchesReport() {
        // Walk HID short items and compute the declared Input payload bits.
        let bytes = Array(GamepadHID.descriptor)
        var i = 0, size = 0, count = 0, bits = 0
        while i < bytes.count {
            let prefix = bytes[i]; i += 1
            let length = [0,1,2,4][Int(prefix & 3)]
            let value = (0..<length).reduce(0) { $0 | Int(bytes[i+$1]) << ($1*8) }
            switch prefix & 0xfc {
            case 0x74: size = value
            case 0x94: count = value
            case 0x80: bits += size * count
            default: break
            }
            i += length
        }
        #expect(bits == 88)
        #expect(bits / 8 == GamepadHID.report(GamepadState()).count)
    }
}
