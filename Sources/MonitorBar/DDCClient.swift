import DDCBridge
import Foundation

struct HardwareLevels: Equatable, Sendable {
    let current: UInt16
    let maximum: UInt16
    var percent: Double { Double(current) / Double(maximum) * 100 }
}

struct DDCProbe: Sendable {
    let display: DisplayIdentity
    let brightness: HardwareLevels?
    let contrast: HardwareLevels?
    let input: UInt16?
    let issue: String?
}

final class DDCClient: @unchecked Sendable {
    static let shared = DDCClient()
    private let queue = DispatchQueue(label: "com.berkinavci.MonitorBar.ddc", qos: .userInitiated)

    func probe(displays: [DisplayIdentity], completion: @escaping @Sendable ([DDCProbe]) -> Void) {
        queue.async {
            MBRescan()
            let services = Self.services()
            let matched = matchDisplays(displays, to: services)
            let result = displays.map { display -> DDCProbe in
                guard let index = matched[display.id] else {
                    return DDCProbe(display: display, brightness: nil, contrast: nil, input: nil,
                                    issue: "No DDC/CI connection found")
                }
                let brightness = Self.read(0x10, index: index)
                let contrast = Self.read(0x12, index: index)
                let input = Self.read(0x60, index: index)?.current
                return DDCProbe(display: display, brightness: brightness, contrast: contrast,
                                input: input,
                                issue: brightness == nil ? "The monitor did not answer DDC/CI brightness" : nil)
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    func write(display: DisplayIdentity, vcp: UInt8, raw: UInt16,
               completion: @escaping @Sendable (HardwareLevels?) -> Void) {
        queue.async {
            MBRescan()
            let index = matchDisplays([display], to: Self.services())[display.id]
            var result: HardwareLevels?
            if let index, let before = Self.read(vcp, index: index), raw <= before.maximum,
               MBWriteVCP(index, vcp, raw) {
                result = Self.read(vcp, index: index)
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    private static func services() -> [DDCIdentity] {
        let count = MBServiceCount()
        guard count > 0 else { return [] }
        return (0..<count).map { index in
            var vendor: UInt32 = 0
            var product: UInt32 = 0
            var serial: UInt32 = 0
            _ = MBServiceIdentity(index, &vendor, &product, &serial)
            return DDCIdentity(index: index, vendor: vendor, product: product, serial: serial)
        }
    }

    private static func read(_ code: UInt8, index: Int32) -> HardwareLevels? {
        var current: UInt16 = 0
        var maximum: UInt16 = 0
        guard MBReadVCP(index, code, &current, &maximum),
              percent(current: current, maximum: maximum) != nil else { return nil }
        return HardwareLevels(current: current, maximum: maximum)
    }
}
