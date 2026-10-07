import CoreGraphics
import Foundation

func adjustedContrastTable(_ values: [CGGammaValue], percent: Double) -> [CGGammaValue] {
    let factor = Float(0.5 + min(100, max(0, percent)) / 100)
    return values.map { min(1, max(0, ($0 - 0.5) * factor + 0.5)) }
}

final class BuiltInContrastController {
    private static let modifiedKey = "builtInGammaModified"

    // A crash skips restore(), leaving the contrast curve on the built-in display until the next launch.
    static func recoverAfterCrash() {
        guard UserDefaults.standard.bool(forKey: modifiedKey) else { return }
        CGDisplayRestoreColorSyncSettings()
        UserDefaults.standard.set(false, forKey: modifiedKey)
    }

    private var displayID: CGDirectDisplayID?
    private var original: ([CGGammaValue], [CGGammaValue], [CGGammaValue])?

    func apply(_ percent: Double, to display: CGDirectDisplayID) -> Bool {
        if displayID != display { restore() }
        if original == nil {
            let capacity = CGDisplayGammaTableCapacity(display)
            guard capacity > 0 else { return false }
            var red = [CGGammaValue](repeating: 0, count: Int(capacity))
            var green = red
            var blue = red
            var count: UInt32 = 0
            guard CGGetDisplayTransferByTable(display, capacity, &red, &green, &blue, &count) == .success,
                  count > 0 else { return false }
            original = (Array(red.prefix(Int(count))), Array(green.prefix(Int(count))),
                        Array(blue.prefix(Int(count))))
            displayID = display
        }
        guard let original else { return false }
        let red = adjustedContrastTable(original.0, percent: percent)
        let green = adjustedContrastTable(original.1, percent: percent)
        let blue = adjustedContrastTable(original.2, percent: percent)
        guard CGSetDisplayTransferByTable(display, UInt32(red.count), red, green, blue) == .success else { return false }
        UserDefaults.standard.set(true, forKey: Self.modifiedKey)
        return true
    }

    func restore() {
        if let displayID, let original {
            _ = CGSetDisplayTransferByTable(displayID, UInt32(original.0.count),
                                            original.0, original.1, original.2)
        }
        displayID = nil
        original = nil
        UserDefaults.standard.set(false, forKey: Self.modifiedKey)
    }
}
