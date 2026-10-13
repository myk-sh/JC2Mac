import Foundation
import CoreHID
import JC2Core

private actor GamepadDelegate: HIDVirtualDeviceDelegate {
    var lastReport = GamepadHID.report(GamepadState())
    func remember(_ data: Data) { lastReport = data }
    func hidVirtualDevice(_ device: HIDVirtualDevice, receivedSetReportRequestOfType type: HIDReportType,
                          id: HIDReportID?, data: Data) async throws {
        throw NSError(domain: "JC2Mac.HID", code: 1, userInfo: [NSLocalizedDescriptionKey: "Output/feature reports are unsupported"])
    }
    func hidVirtualDevice(_ device: HIDVirtualDevice, receivedGetReportRequestOfType type: HIDReportType,
                          id: HIDReportID?, maxSize: Int) async throws -> Data {
        guard type == .input, (id == nil || id?.rawValue == 0), maxSize >= lastReport.count else {
            throw NSError(domain: "JC2Mac.HID", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unsupported report request"])
        }
        return lastReport
    }
}

@MainActor
final class VirtualGamepad: VirtualControllerOutput {
    private var continuation: AsyncStream<Data>.Continuation?
    private var worker: Task<Void, Never>?

    func start(slot: VirtualControllerSlot, onError: @escaping @MainActor (String) -> Void) async throws {
        await stop()
        let properties = HIDVirtualDevice.Properties(
            descriptor: GamepadHID.descriptor, vendorID: 0, productID: 2,
            product: slot.productName, manufacturer: "JC2Mac", serialNumber: slot.uniqueID,
            uniqueID: slot.uniqueID, locationID: slot.locationID)
        guard let device = HIDVirtualDevice(properties: properties) else {
            throw NSError(domain: "JC2Mac.HID", code: 3, userInfo: [NSLocalizedDescriptionKey:
                "macOS refused \(slot.productName) creation. This build needs an Apple-approved com.apple.developer.hid.virtual.device entitlement and provisioning profile. Keyboard & Mouse is available for one shared player."])
        }
        let delegate = GamepadDelegate()
        await device.activate(delegate: delegate)
        // Fail at activation/first report instead of claiming success before the device works.
        try await device.dispatchInputReport(data: GamepadHID.report(GamepadState()), timestamp: SuspendingClock().now)
        let stream = AsyncStream<Data>(bufferingPolicy: .bufferingNewest(1)) { continuation = $0 }
        worker = Task {
            do {
                for await data in stream {
                    await delegate.remember(data)
                    try await device.dispatchInputReport(data: data, timestamp: SuspendingClock().now)
                }
                let neutral = GamepadHID.report(GamepadState())
                await delegate.remember(neutral)
                try await device.dispatchInputReport(data: neutral, timestamp: SuspendingClock().now)
            } catch { onError("\(slot.productName) report failed: \(error.localizedDescription)") }
            // Releasing the last reference disconnects the virtual HID device.
        }
    }
    func update(_ state: GamepadState) { continuation?.yield(GamepadHID.report(state)) }
    func stop() async {
        continuation?.finish()
        continuation = nil
        let oldWorker = worker
        worker = nil
        await oldWorker?.value
    }
}
