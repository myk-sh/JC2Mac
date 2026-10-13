import SwiftUI
import AppKit
import JC2Core

@main
struct JC2MacApp: App {
    @StateObject private var model = AppModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        WindowGroup("JC2Mac") {
            ContentView(model: model)
                .onAppear { delegate.model = model; NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true) }
        }
        .defaultSize(width: 930, height: 760)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Stop Output") { model.disableOutput() }.keyboardShortcut(".", modifiers: .command)
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model?.shutdown()
        return .terminateNow
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

private let cyan = Color(red: 0.35, green: 0.84, blue: 0.87)
private let coral = Color(red: 0.97, green: 0.43, blue: 0.38)

struct ContentView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("JC2Mac").font(.system(size: 34, weight: .bold, design: .rounded))
                        Text("Joy-Con 2 · Bluetooth driver for macOS").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Label(model.armed ? "OUTPUT ON" : "MONITORING", systemImage: model.armed ? "bolt.fill" : "waveform")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .padding(10).background((model.armed ? coral : cyan).opacity(0.15), in: Capsule())
                }
                HStack(spacing: 12) {
                    Image(systemName: "antenna.radiowaves.left.and.right").foregroundStyle(cyan)
                    Text(model.driver.status).font(.callout)
                    Spacer()
                    Button(model.driver.scanning ? "Stop scan" : "Find Joy-Cons") {
                        if model.driver.scanning { model.driver.stopScan() } else { model.driver.scan() }
                    }.buttonStyle(.borderedProminent).tint(cyan)
                }.padding(16).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))

                HStack(alignment: .top, spacing: 16) {
                    controllerCard(.left, selection: $model.selectedLeft)
                    controllerCard(.right, selection: $model.selectedRight)
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text("Output").font(.title3.bold())
                    HStack {
                        Picker("Output", selection: $model.mode) {
                            ForEach(AppModel.Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }.pickerStyle(.segmented).labelsHidden().disabled(model.busy)
                        Button(model.armed ? "Stop output" : model.busy ? "Please wait…" : "Enable output") { model.toggleOutput() }
                            .buttonStyle(.borderedProminent).tint(model.armed ? coral : cyan)
                            .disabled(model.mode == .monitor || model.busy)
                    }
                    Text(model.outputStatus).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    if model.mode == .keyboard {
                        Text("Left stick → WASD    D-pad → arrows    Right stick → pointer\nA → Space    B → Esc    X → E    Y → R    L → Q    R → F\n+ → Return    − → Tab    L3 → C    R3 → V    ZR / ZL → left / right click")
                            .font(.system(size: 12, design: .monospaced)).lineSpacing(5)
                        HStack {
                            Label(model.accessible ? "Accessibility granted" : "Accessibility permission needed",
                                  systemImage: model.accessible ? "checkmark.circle" : "lock")
                            Spacer()
                            Button("Grant Accessibility") { model.requestAccessibility() }
                        }.font(.callout)
                        HStack {
                            Text("Pointer speed").frame(width: 110, alignment: .leading)
                            Slider(value: $model.pointerSpeed, in: 200...1800)
                            Text("\(Int(model.pointerSpeed)) pt/s").monospacedDigit().frame(width: 80)
                        }.font(.caption)
                    } else if model.mode == .gamepad {
                        Picker("Players", selection: $model.gamepadLayout) {
                            ForEach(GamepadLayout.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }.pickerStyle(.segmented).disabled(model.busy)
                        if model.gamepadLayout == .separate {
                            Text("Player 1 = left Joy-Con · Player 2 = right Joy-Con. Hold each sideways with the stick on the left and SL/SR on top. SL/SR are shoulders; − or + opens the menu. Face buttons follow their sideways positions.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(Array(model.gamepadLayout.slots.enumerated()), id: \.element) { index, slot in
                                playerPreview(index: index, slot: slot)
                            }
                        }
                        Text("Requires an Apple-approved virtual HID entitlement. Steam and game recognition still need testing; keyboard/mouse mode supplies one shared player. Changing the player layout stops output — enable it again to create the new controllers.")
                            .font(.callout).foregroundStyle(.secondary)
                    } else {
                        Text("Pair controllers and inspect inputs here. Select an output mode when you’re ready to use them.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Stick deadzone").frame(width: 110, alignment: .leading)
                        Slider(value: $model.deadzone, in: 0...0.4)
                        Text("\(Int(model.deadzone * 100))%") .monospacedDigit().frame(width: 40)
                    }.font(.caption)
                }.padding(20).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))

                DisclosureGroup("Diagnostics") {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Recent Bluetooth and output events").foregroundStyle(.secondary)
                            Spacer()
                            Button("Copy log") { model.copyDiagnostics() }
                        }
                        Text(model.driver.log.isEmpty ? "No events yet." : model.driver.log.suffix(24).joined(separator: "\n"))
                            .font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.padding(.top, 10)
                }.font(.callout)
                Text("Hold SYNC on each detached Joy-Con until the player LEDs cycle. Connect from this app and accept any macOS pairing request. Output is released after 0.5 seconds without input. ⌘. stops output.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(28)
        }
        .frame(minWidth: 820, minHeight: 680)
        .preferredColorScheme(.dark)
    }

    private func controllerCard(_ side: JoyConSide, selection: Binding<UUID?>) -> some View {
        let devices = model.driver.devices.filter { $0.side == side }
        let device = devices.first { $0.id == selection.wrappedValue }
        let stick = side == .left ? model.state.left : model.state.right
        let color = side == .left ? cyan : coral
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Circle().fill(color).frame(width: 8, height: 8)
                Text("\(side.label) Joy-Con").font(.headline)
                if model.mode == .gamepad && model.gamepadLayout == .separate {
                    Text(side == .left ? "PLAYER 1" : "PLAYER 2")
                        .font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(color)
                }
                Spacer()
                Text(device?.connected == true ? "CONNECTED" : "DISCONNECTED")
                    .font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
            }
            Picker("Controller", selection: selection) {
                Text("Choose a controller").tag(Optional<UUID>.none)
                ForEach(devices) { d in Text("\(d.name) · \(d.id.uuidString.prefix(6))").tag(Optional(d.id)) }
            }.labelsHidden()
            if let device {
                Text(device.status).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                HStack {
                    Text("\(device.rssi) dBm · \(device.packets) reports").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    Spacer()
                    Button(device.connected || ["Connecting…", "Discovering services…", "Initializing…", "Waiting for input…"].contains(device.status) ? "Disconnect" : "Connect") {
                        if device.connected || ["Connecting…", "Discovering services…", "Initializing…", "Waiting for input…"].contains(device.status) {
                            model.driver.disconnect(device.id)
                        } else { model.driver.connect(device.id) }
                    }
                }
            } else {
                Text("Hold SYNC, click Find Joy-Cons, then select a controller.").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 18) {
                StickView(stick: stick, color: color)
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(format: "X %+.2f\nY %+.2f", stick.x, stick.y))
                        .font(.system(size: 13, design: .monospaced)).foregroundStyle(.secondary)
                    Button("Center stick") { if let id = device?.id { model.center(id) } }.disabled(device?.connected != true)
                    Button("Reset center") { if let id = device?.id { model.resetCalibration(id) } }.disabled(device == nil)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            let buttons: [JC2Core.Button] = side == .left ? [.up, .down, .left, .right, .l, .zl, .minus, .leftStick, .sl, .sr, .capture]
                                                    : [.a, .b, .x, .y, .r, .zr, .plus, .rightStick, .sl, .sr, .home, .chat]
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                ForEach(buttons, id: \.self) { button in
                    let pressed = (side == .left ? model.leftButtons : model.rightButtons).contains(button)
                    Text(button.rawValue).font(.system(size: 10, weight: .semibold))
                        .frame(maxWidth: .infinity).frame(height: 28)
                        .background(pressed ? color.opacity(0.7) : Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .topLeading)
            .background(color.opacity(0.045), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(color.opacity(0.2), lineWidth: 1))
    }

    private func playerPreview(index: Int, slot: VirtualControllerSlot) -> some View {
        let state = model.playerStates.indices.contains(index) ? model.playerStates[index] : GamepadState()
        let label = slot == .combined ? "Combined player" : slot == .player1 ? "Player 1 · Left" : "Player 2 · Right"
        let pressed = state.buttons.map(\.rawValue).sorted().joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.subheadline.bold())
            Text(String(format: "Movement X %+.2f  Y %+.2f", state.left.x, state.left.y))
                .font(.system(size: 11, design: .monospaced))
            Text(pressed.isEmpty ? "No buttons pressed" : "Buttons: \(pressed)")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct StickView: View {
    var stick: Stick
    var color: Color
    var body: some View {
        ZStack {
            Circle().fill(.white.opacity(0.04))
            Circle().stroke(.white.opacity(0.13), lineWidth: 1)
            Rectangle().fill(.white.opacity(0.1)).frame(width: 1, height: 100)
            Rectangle().fill(.white.opacity(0.1)).frame(width: 100, height: 1)
            Circle().fill(color).frame(width: 18, height: 18)
                .offset(x: stick.x * 43, y: -stick.y * 43)
        }.frame(width: 112, height: 112)
            .accessibilityLabel("Stick X \(stick.x), Y \(stick.y)")
    }
}
