import AppKit
import SwiftUI

private final class MonitorPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor final class MonitorBarAppDelegate: NSObject, NSApplicationDelegate {
    private let model = MonitorModel()
    private var statusItem: NSStatusItem!
    private var panel: NSPanel!
    private var outsideClickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.isVisible = false
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "display", accessibilityDescription: "MonitorBar")
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(togglePopover)
        }
        panel = MonitorPanel(contentRect: NSRect(x: 0, y: 0, width: 350, height: 500),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.transient, .moveToActiveSpace]
        let hosting = NSHostingController(rootView: QuickPanel(model: model) { [weak self] size in
            self?.updatePanelSize(size)
        })
        if #available(macOS 13, *) {
            hosting.sizingOptions = [.preferredContentSize, .intrinsicContentSize]
        }
        panel.contentViewController = hosting
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.panel.orderOut(nil)
        }
        model.onPresenceChange = { [weak self] present in
            guard let self else { return }
            self.statusItem.isVisible = present
            if !present { self.panel.orderOut(nil) }
        }
        model.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if panel.isVisible { panel.orderOut(nil) }
        else {
            model.refresh()
            panel.contentViewController?.view.layoutSubtreeIfNeeded()
            updatePanelSize(panel.contentViewController?.view.fittingSize ?? NSSize(width: 350, height: 500))
            positionPanel(below: button)
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        }
    }

    private func updatePanelSize(_ size: CGSize) {
        guard size.width > 0, size.height > 0, let panel else { return }
        let target = NSSize(width: 350, height: size.height)
        guard panel.contentRect(forFrameRect: panel.frame).size != target else { return }
        panel.setContentSize(target)
        if panel.isVisible, let button = statusItem.button { positionPanel(below: button) }
    }

    private func positionPanel(below button: NSStatusBarButton) {
        guard let window = button.window else { return }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let x = min(max(anchor.midX - panel.frame.width / 2, visible.minX + 8),
                    visible.maxX - panel.frame.width - 8)
        let y = anchor.minY - panel.frame.height - 6
        panel.setFrameOrigin(NSPoint(x: x, y: max(visible.minY + 8, y)))
    }
}
