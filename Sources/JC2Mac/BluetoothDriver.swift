import Foundation
import CoreBluetooth
import Combine
import JC2Core

struct ControllerDevice: Identifiable {
    var id: UUID
    var name: String
    var side: JoyConSide
    var rssi: Int
    var status = "Available"
    var connected = false
    var report: InputReport?
    var packets = 0
}

/// All delegate callbacks and mutations run on the main queue.
final class BluetoothDriver: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published var devices: [ControllerDevice] = []
    @Published var status = "Bluetooth idle"
    @Published var scanning = false
    @Published var log: [String] = []
    var onInput: ((UUID, JoyConSide, InputReport) -> Void)?
    var onDisconnect: ((UUID) -> Void)?
    var calibration: ((UUID) -> StickCalibration)?
    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var sessions: [UUID: Session] = [:]
    private var scanRequested = false
    private var scanTimeout: DispatchWorkItem?

    private final class Session {
        var input: CBCharacteristic?
        var command: CBCharacteristic?
        var responses: [CBCharacteristic] = []
        var pendingServices = 0
        var packets = BLEProtocol.initializationPackets
        var nextPacket = 0
        var initialized = false
        var pump: DispatchWorkItem?
        var timeout: DispatchWorkItem?
    }

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }
    func record(_ text: String) {
        let time = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        log.append("\(time)  \(text)")
        if log.count > 160 { log.removeFirst(log.count - 160) }
    }
    func scan() {
        scanRequested = true
        guard central.state == .poweredOn else { status = "Waiting for Bluetooth permission / power"; return }
        // Nintendo advertisements may omit service UUIDs, so scan without a service filter.
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        scanning = true
        status = "Scanning — hold each Joy-Con’s SYNC button"
        scanTimeout?.cancel()
        let timeout = DispatchWorkItem { [weak self] in self?.stopScan() }
        scanTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: timeout)
    }
    func stopScan() {
        scanRequested = false
        scanTimeout?.cancel()
        central.stopScan()
        scanning = false
        if central.state == .poweredOn { status = "Scan stopped" }
    }
    func connect(_ id: UUID) {
        guard central.state == .poweredOn, sessions[id] == nil, let p = peripherals[id] else { return }
        let session = Session()
        sessions[id] = session
        update(id) { $0.status = "Connecting…"; $0.report = nil }
        record("Connecting \(p.name ?? id.uuidString)")
        central.connect(p, options: nil)
        let timeout = DispatchWorkItem { [weak self, weak session] in
            guard let self, let session, self.sessions[id] === session else { return }
            self.fail(p, "Connection / initialization timed out. Wake the controller and try again.")
        }
        session.timeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: timeout)
    }
    func disconnect(_ id: UUID) {
        guard let p = peripherals[id] else { return }
        cleanup(id, message: "Disconnected")
        central.cancelPeripheralConnection(p)
    }
    func shutdown() {
        stopScan()
        for id in Array(sessions.keys) { disconnect(id) }
    }
    private func update(_ id: UUID, _ mutation: (inout ControllerDevice) -> Void) {
        guard let index = devices.firstIndex(where: { $0.id == id }) else { return }
        mutation(&devices[index])
    }
    private func cleanup(_ id: UUID, message: String) {
        sessions[id]?.pump?.cancel()
        sessions[id]?.timeout?.cancel()
        sessions.removeValue(forKey: id)
        update(id) { $0.connected = false; $0.status = message; $0.report = nil }
        onDisconnect?(id)
    }
    private func fail(_ p: CBPeripheral, _ message: String) {
        record(message)
        cleanup(p.identifier, message: message)
        central.cancelPeripheralConnection(p)
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: status = "Bluetooth ready"; if scanRequested { scan() }
        case .poweredOff: status = "Turn on Bluetooth in System Settings"
        case .unauthorized: status = "Allow JC2Mac in System Settings → Privacy & Security → Bluetooth"
        case .unsupported: status = "Bluetooth LE is unavailable on this Mac"
        case .resetting: status = "Bluetooth is resetting"
        default: status = "Waiting for Bluetooth"
        }
        if central.state != .poweredOn {
            scanning = false
            scanTimeout?.cancel()
            for id in Array(sessions.keys) { cleanup(id, message: "Bluetooth unavailable") }
        }
    }
    func centralManager(_ central: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? p.name ?? ""
        let mfg = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data ?? Data()
        // Exact Joy-Con 2 names are a fallback if macOS strips manufacturer data.
        let side = BLEProtocol.side(manufacturerData: mfg)
            ?? (localName == "Joy-Con 2 (L)" ? .left : localName == "Joy-Con 2 (R)" ? .right : nil)
        guard let side else { return }
        peripherals[p.identifier] = p
        if devices.contains(where: { $0.id == p.identifier }) {
            update(p.identifier) { $0.rssi = RSSI.intValue }
        } else {
            devices.append(ControllerDevice(id: p.identifier, name: localName.isEmpty ? "Joy-Con 2 (\(side.label))" : localName,
                                            side: side, rssi: RSSI.intValue))
            record("Found \(side.label) Joy-Con 2")
        }
    }
    func centralManager(_ central: CBCentralManager, didConnect p: CBPeripheral) {
        guard sessions[p.identifier] != nil else { central.cancelPeripheralConnection(p); return }
        p.delegate = self
        update(p.identifier) { $0.status = "Discovering services…" }
        p.discoverServices(nil)
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        let message = "Connection failed: \(error?.localizedDescription ?? "unknown error")"
        cleanup(p.identifier, message: message)
        record(message)
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        // A deliberate failure has already stored the actionable error in the row.
        guard sessions[p.identifier] != nil else { return }
        let message = error.map { "Disconnected: \($0.localizedDescription)" } ?? "Disconnected"
        cleanup(p.identifier, message: message)
        record(message)
    }
    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard let s = sessions[p.identifier] else { return }
        guard error == nil, let services = p.services, !services.isEmpty else {
            fail(p, "GATT service discovery failed: \(error?.localizedDescription ?? "no services")"); return
        }
        s.pendingServices = services.count
        for service in services { p.discoverCharacteristics(nil, for: service) }
    }
    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let s = sessions[p.identifier] else { return }
        guard error == nil else { fail(p, "GATT characteristic discovery failed: \(error!.localizedDescription)"); return }
        for c in service.characteristics ?? [] {
            switch c.uuid.uuidString.lowercased() {
            case BLEProtocol.input: s.input = c
            case BLEProtocol.command: s.command = c
            case let uuid where BLEProtocol.responses.contains(uuid): s.responses.append(c)
            default: break
            }
        }
        s.pendingServices -= 1
        guard s.pendingServices == 0 else { return }
        guard let input = s.input, let command = s.command,
              input.properties.contains(.notify), command.properties.contains(.writeWithoutResponse) else {
            fail(p, "Required Joy-Con 2 GATT characteristics missing or incompatible"); return
        }
        // Subscribe to responses before initialization; only input subscription starts the command pump.
        for response in s.responses where response.properties.contains(.notify) { p.setNotifyValue(true, for: response) }
        p.setNotifyValue(true, for: input)
    }
    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor c: CBCharacteristic, error: Error?) {
        guard let s = sessions[p.identifier] else { return }
        guard error == nil else { fail(p, "Notification subscription failed: \(error!.localizedDescription)"); return }
        if c === s.input {
            guard c.isNotifying else { fail(p, "Input notifications stopped"); return }
            update(p.identifier) { $0.status = "Initializing…" }
            pump(p, session: s)
        }
    }
    private func pump(_ p: CBPeripheral, session s: Session) {
        guard sessions[p.identifier] === s, p.state == .connected, let command = s.command else { return }
        guard s.nextPacket < s.packets.count else {
            s.initialized = true
            update(p.identifier) { $0.status = "Waiting for input…" }
            // Streaming is confirmed by an actual report, not by successful writes.
            return
        }
        guard p.canSendWriteWithoutResponse else { return }
        let packet = s.packets[s.nextPacket]
        guard packet.count <= p.maximumWriteValueLength(for: .withoutResponse) else {
            fail(p, "Bluetooth MTU is too small for Joy-Con 2 initialization"); return
        }
        p.writeValue(packet, for: command, type: .withoutResponse)
        s.nextPacket += 1
        let work = DispatchWorkItem { [weak self, weak s, weak p] in
            guard let self, let s, let p else { return }; self.pump(p, session: s)
        }
        s.pump = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }
    func peripheralIsReady(toSendWriteWithoutResponse p: CBPeripheral) {
        guard let s = sessions[p.identifier] else { return }
        // Respect the 80ms spacing even when CoreBluetooth's write queue becomes ready.
        s.pump?.cancel()
        let work = DispatchWorkItem { [weak self, weak s, weak p] in
            guard let self, let s, let p else { return }; self.pump(p, session: s)
        }
        s.pump = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }
    func peripheral(_ p: CBPeripheral, didUpdateValueFor c: CBCharacteristic, error: Error?) {
        guard let s = sessions[p.identifier] else { return }
        guard error == nil else { fail(p, "Read failed: \(error!.localizedDescription)"); return }
        guard c === s.input, s.initialized, let data = c.value,
              let device = devices.first(where: { $0.id == p.identifier }) else { return }
        guard let report = InputReport(data: data, side: device.side, calibration: calibration?(p.identifier) ?? .init()) else {
            record("Ignored unexpected input length: \(data.count) bytes"); return
        }
        if !device.connected {
            s.timeout?.cancel()
            record("\(device.side.label) Joy-Con 2 is streaming")
        }
        update(p.identifier) { $0.connected = true; $0.status = "Streaming"; $0.report = report; $0.packets += 1 }
        onInput?(p.identifier, device.side, report)
    }
}
