import AppKit
import Combine
import JC2Core

@MainActor
final class AppModel: ObservableObject {
    enum Mode: String, CaseIterable { case monitor = "Monitor", keyboard = "Keyboard & Mouse", gamepad = "Virtual Gamepad" }
    let driver = BluetoothDriver()
    @Published var mode: Mode = .monitor {
        didSet { if oldValue != mode { disableOutput() } }
    }
    @Published var gamepadLayout: GamepadLayout = .combined {
        didSet { if oldValue != gamepadLayout { disableOutput(); tick() } }
    }
    @Published var armed = false
    @Published var busy = false
    @Published var outputStatus = "Monitor only — no input sent"
    @Published var state = GamepadState()
    @Published var playerStates = [GamepadState()]
    @Published var leftButtons: Set<JC2Core.Button> = []
    @Published var rightButtons: Set<JC2Core.Button> = []
    @Published var selectedLeft: UUID? { didSet { selectionChanged() } }
    @Published var selectedRight: UUID? { didSet { selectionChanged() } }
    @Published var deadzone = 0.12 { didSet { saveDeadzones() } }
    @Published var pointerSpeed = 900.0 { didSet { keyboard.speed = pointerSpeed } }
    @Published var accessible = AXIsProcessTrusted()
    private var reports: [UUID: TimedReport] = [:]
    private var calibrations: [UUID: StickCalibration] = [:]
    private let keyboard = KeyboardMouseOutput()
    private let virtual = VirtualGamepadGroup { VirtualGamepad() }
    private var timer: Timer?
    private var lastTick = ProcessInfo.processInfo.systemUptime
    private var lastPermissionCheck = 0.0
    private var generation = 0
    private var outputTransition: Task<Void, Never>?
    private var cancellation: AnyCancellable?

    init() {
        if let data = UserDefaults.standard.data(forKey: "calibrations"),
           let stored = try? JSONDecoder().decode([UUID: StickCalibration].self, from: data) { calibrations = stored }
        driver.calibration = { [weak self] id in
            var cal = self?.calibrations[id] ?? .init()
            cal.deadzone = self?.deadzone ?? 0.12
            return cal
        }
        driver.onInput = { [weak self] id, side, report in
            guard let self else { return }
            self.reports[id] = TimedReport(report: report, receivedAt: ProcessInfo.processInfo.systemUptime)
            if side == .left && self.selectedLeft == nil { self.selectedLeft = id }
            if side == .right && self.selectedRight == nil { self.selectedRight = id }
        }
        driver.onDisconnect = { [weak self] id in
            guard let self else { return }
            self.reports.removeValue(forKey: id)
            self.tick()
        }
        cancellation = driver.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification,
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.disableOutput(); self?.driver.shutdown() }
            }
    }
    private func selectionChanged() {
        keyboard.releaseAll()
        virtual.neutralize()
        tick()
    }
    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let delta = min(1.0 / 30, max(0, now - lastTick))
        lastTick = now
        let left = selectedLeft.flatMap { InputSafety.fresh(reports[$0], now: now) }
        let right = selectedRight.flatMap { InputSafety.fresh(reports[$0], now: now) }
        let next = GamepadState(left: left, right: right)
        let players = GamepadRouting.states(layout: gamepadLayout, left: left, right: right)
        if players != playerStates { playerStates = players }
        if leftButtons != (left?.buttons ?? []) { leftButtons = left?.buttons ?? [] }
        if rightButtons != (right?.buttons ?? []) { rightButtons = right?.buttons ?? [] }
        if next != state { state = next }
        if now - lastPermissionCheck > 1 {
            lastPermissionCheck = now
            accessible = keyboard.permitted
            if armed && mode == .keyboard && !accessible { disableOutput(); outputStatus = "Accessibility permission was removed" }
        }
        guard armed else { return }
        if mode == .keyboard { keyboard.update(next, delta: delta) }
        if mode == .gamepad { virtual.update(left: left, right: right) }
    }
    func toggleOutput() {
        if armed { disableOutput(); return }
        guard !busy, mode != .monitor else { return }
        if mode == .keyboard {
            guard keyboard.permitted else { requestAccessibility(); outputStatus = "Grant Accessibility, then enable output again"; return }
            armed = true
            outputStatus = "Keyboard & mouse output enabled"
        } else {
            busy = true
            generation += 1
            let token = generation
            let layout = gamepadLayout
            let previous = outputTransition
            outputTransition = Task { [self] in
                await previous?.value
                guard token == generation else { return }
                do {
                    try await virtual.start(layout: layout) { [weak self] message in
                        guard let self, self.generation == token else { return }
                        self.disableOutput(); self.outputStatus = message; self.driver.record(message)
                    }
                    guard token == generation else { return }
                    armed = true
                    outputStatus = layout == .combined
                        ? "Combined gamepad enabled — game compatibility varies"
                        : "Two independent gamepads enabled: Player 1 = left, Player 2 = right — game compatibility varies"
                } catch {
                    guard token == generation else { return }
                    outputStatus = error.localizedDescription
                    driver.record(outputStatus)
                }
                busy = false
            }
        }
    }
    func disableOutput() {
        generation += 1
        armed = false
        keyboard.releaseAll()
        outputStatus = "Output stopped"
        // Prevent a second start while the previous virtual worker is draining.
        busy = true
        let token = generation
        let previous = outputTransition
        outputTransition = Task {
            await previous?.value
            await virtual.stop()
            if token == generation { busy = false }
        }
    }
    func requestAccessibility() { keyboard.requestPermission() }
    func center(_ id: UUID) {
        guard let report = InputSafety.fresh(reports[id], now: ProcessInfo.processInfo.systemUptime) else { return }
        calibrations[id] = StickCalibration(centerX: report.rawX, centerY: report.rawY, deadzone: deadzone)
        saveDeadzones()
        driver.record("Stick center saved. Leave the stick untouched when centering.")
    }
    func resetCalibration(_ id: UUID) { calibrations.removeValue(forKey: id); saveDeadzones() }
    private func saveDeadzones() {
        if let data = try? JSONEncoder().encode(calibrations) { UserDefaults.standard.set(data, forKey: "calibrations") }
    }
    func shutdown() {
        timer?.invalidate()
        disableOutput()
        driver.shutdown()
    }
    func copyDiagnostics() {
        let text = "JC2Mac diagnostics\nmacOS \(ProcessInfo.processInfo.operatingSystemVersionString)\nMode: \(mode.rawValue)\nGamepad layout: \(gamepadLayout.rawValue)\n\(outputStatus)\n\n" + driver.log.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
