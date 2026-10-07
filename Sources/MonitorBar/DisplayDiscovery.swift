import AppKit
import CoreGraphics

final class DisplayDiscovery: @unchecked Sendable {
    var onChange: (([DisplayIdentity], Bool) -> Void)?
    private var wakeObserver: NSObjectProtocol?

    func start() {
        CGDisplayRegisterReconfigurationCallback(Self.displayChanged, Unmanaged.passUnretained(self).toOpaque())
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.publish(force: true) }
        publish()
    }

    func stop() {
        CGDisplayRemoveReconfigurationCallback(Self.displayChanged, Unmanaged.passUnretained(self).toOpaque())
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
    }

    private static let displayChanged: CGDisplayReconfigurationCallBack = { _, flags, context in
        guard !flags.contains(.beginConfigurationFlag), let context else { return }
        let instance = Unmanaged<DisplayDiscovery>.fromOpaque(context).takeUnretainedValue()
        DispatchQueue.main.async { instance.publish() }
    }

    private func publish(force: Bool = false) { onChange?(Self.externalDisplays(), force) }

    private static func isVirtualDisplay(vendor: UInt32, name: String) -> Bool {
        vendor > 0xFFFF || name.localizedCaseInsensitiveContains("AirPlay") ||
            name.localizedCaseInsensitiveContains("Sidecar")
    }

    static func builtInDisplay() -> DisplayIdentity? {
        var ids = [CGDirectDisplayID](repeating: 0, count: 32)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count) == .success,
              let id = ids.prefix(Int(count)).first(where: { CGDisplayIsBuiltin($0) != 0 }) else { return nil }
        let name = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
        }?.localizedName ?? String(localized: "Built-in Display")
        return DisplayIdentity(id: id, name: name,
                               vendor: CGDisplayVendorNumber(id),
                               product: CGDisplayModelNumber(id),
                               serial: CGDisplaySerialNumber(id))
    }

    static func externalDisplays() -> [DisplayIdentity] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 32)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).filter { CGDisplayIsBuiltin($0) == 0 }.map { id in
            let name = NSScreen.screens.first {
                ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
            }?.localizedName ?? String(localized: "External Display")
            let vendor = CGDisplayVendorNumber(id)
            return DisplayIdentity(id: id, name: name,
                                   vendor: vendor,
                                   product: CGDisplayModelNumber(id),
                                   serial: CGDisplaySerialNumber(id),
                                   isVirtual: isVirtualDisplay(vendor: vendor, name: name))
        }
    }
}
