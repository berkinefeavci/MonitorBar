import Foundation

struct DisplayIdentity: Equatable, Sendable {
    let id: UInt32
    let name: String
    let vendor: UInt32
    let product: UInt32
    let serial: UInt32
    var isVirtual = false
}

struct DDCIdentity: Equatable, Sendable {
    let index: Int32
    let vendor: UInt32
    let product: UInt32
    let serial: UInt32
}

func matchDisplays(_ displays: [DisplayIdentity], to services: [DDCIdentity]) -> [UInt32: Int32] {
    var result: [UInt32: Int32] = [:]
    var used = Set<Int32>()

    for display in displays where display.serial != 0 {
        let sameDisplayCount = displays.filter {
            $0.vendor == display.vendor && $0.product == display.product && $0.serial == display.serial
        }.count
        let matches = services.filter {
            $0.vendor == display.vendor && $0.product == display.product && $0.serial == display.serial
        }
        if sameDisplayCount == 1 && matches.count == 1 {
            result[display.id] = matches[0].index
            used.insert(matches[0].index)
        }
    }

    for display in displays where result[display.id] == nil {
        let matchingDisplays = displays.filter {
            result[$0.id] == nil && $0.vendor == display.vendor && $0.product == display.product
        }
        let matchingServices = services.filter {
            !used.contains($0.index) && $0.vendor == display.vendor && $0.product == display.product &&
            ($0.serial == 0 || display.serial == 0 || $0.serial == display.serial)
        }
        if matchingDisplays.count == 1 && matchingServices.count == 1 && display.vendor != 0 && display.product != 0 {
            result[display.id] = matchingServices[0].index
            used.insert(matchingServices[0].index)
        }
    }

    if result.isEmpty && displays.count == 1 && services.count == 1 &&
        services[0].vendor == 0 && services[0].product == 0 {
        result[displays[0].id] = services[0].index
    }
    return result
}

func rawLevel(percent value: Double, maximum: UInt16) -> UInt16? {
    guard maximum > 0 && value.isFinite else { return nil }
    return UInt16((min(100, max(0, value)) / 100 * Double(maximum)).rounded())
}

func percent(current: UInt16, maximum: UInt16) -> Double? {
    guard maximum > 0 && current <= maximum else { return nil }
    return Double(current) / Double(maximum) * 100
}
