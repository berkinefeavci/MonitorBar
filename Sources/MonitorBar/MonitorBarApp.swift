import AppKit
import SwiftUI

@MainActor final class MonitorBarAppDelegate: NSObject, NSApplicationDelegate {
    private let model = MonitorModel()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.isVisible = false
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "display", accessibilityDescription: "MonitorBar")
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(togglePopover)
        }
        popover.behavior = .transient
        let hosting = NSHostingController(rootView: QuickPanel(model: model))
        hosting.sizingOptions = [.preferredContentSize, .intrinsicContentSize]
        popover.contentViewController = hosting
        model.onPresenceChange = { [weak self] present in
            self?.statusItem.isVisible = present
            if !present { self?.popover.close() }
        }
        model.start()
    }

    func applicationWillTerminate(_ notification: Notification) { model.stop() }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown { popover.close() }
        else {
            model.refresh()
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}
