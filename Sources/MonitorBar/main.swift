import AppKit
import DDCBridge
import Foundation
import SwiftUI

if CommandLine.arguments.contains("--probe") {
    var nightActive = false, nightEnabled = false
    var nightMode: Int32 = 0
    let nightValue = MBReadNightShift(&nightActive, &nightEnabled, &nightMode)
        ? "\(nightActive && nightEnabled ? "warm" : "off") (mode \(nightMode), enabled \(nightEnabled))" : "unavailable"
    print("Night Shift: \(nightValue)")
    var keyboardLevel: Float = 0
    let keyboardValue = MBReadKeyboardBrightness(&keyboardLevel) ? "\(Int((keyboardLevel * 100).rounded()))%" : "unavailable"
    print("Keyboard backlight: \(keyboardValue)")
    var keyboardAuto = false
    let keyboardAutoValue = MBReadKeyboardAutoBrightness(&keyboardAuto) ? (keyboardAuto ? "on" : "off") : "unavailable"
    print("Keyboard auto brightness: \(keyboardAutoValue)")
    if let builtIn = DisplayDiscovery.builtInDisplay() {
        var level: Float = 0
        let value = MBReadBuiltInBrightness(builtIn.id, &level) ? "\(Int((level * 100).rounded()))%" : "unavailable"
        print("Built-in display: \(builtIn.name) [\(builtIn.id)]: brightness \(value)")
    }
    let displays = DisplayDiscovery.externalDisplays()
    print("External displays: \(displays.count)")
    DDCClient.shared.probe(displays: displays) { results in
        for probe in results {
            let level = probe.brightness.map { "\($0.current)/\($0.maximum)" } ?? "unavailable"
            print("\(probe.display.name) [\(probe.display.id)]: brightness \(level)")
            if let issue = probe.issue { print("  \(issue)") }
        }
        exit(0)
    }
    RunLoop.main.run()
} else if CommandLine.arguments.contains("--preview") {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    if CommandLine.arguments.contains("--preview-light") {
        app.appearance = NSAppearance(named: .aqua)
    }
    let model = MonitorModel()
    model.start()
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 386, height: 430),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.title = "MonitorBar Preview"
    window.isOpaque = false
    window.backgroundColor = .clear
    window.contentViewController = NSHostingController(rootView: QuickPanel(model: model))
    window.center()
    window.makeKeyAndOrderFront(nil)
    app.run()
} else {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = MonitorBarAppDelegate()
    app.delegate = delegate
    app.run()
}
