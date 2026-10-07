import AppKit
import SwiftUI

private final class MonitorPanel: NSPanel {
    var onCancel: () -> Void = {}
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel() }   // Esc
}

@MainActor final class MonitorBarAppDelegate: NSObject, NSApplicationDelegate {
    private let model = MonitorModel()
    private var statusItem: NSStatusItem!
    private var panel: NSPanel!
    private var outsideClickMonitor: Any?
    // Bumped on every open/close so a finished fade-out never hides a panel that was reopened meanwhile.
    private var transition = 0
    private var isOpen = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "display", accessibilityDescription: "PanelLight")
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(togglePopover)
        }
        panel = MonitorPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 500),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.transient, .moveToActiveSpace]
        panel.animationBehavior = .none
        (panel as? MonitorPanel)?.onCancel = { [weak self] in self?.closePanel() }
        let hosting = NSHostingController(rootView: QuickPanel(model: model) { [weak self] size in
            self?.updatePanelSize(size)
        })
        if #available(macOS 13, *) {
            hosting.sizingOptions = [.preferredContentSize, .intrinsicContentSize]
        }
        panel.contentViewController = hosting
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePanelIfOutside(at: NSEvent.mouseLocation)
        }
        model.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
    }

    @objc private func togglePopover() {
        if isOpen { closePanel() } else { openPanel() }
    }

    // Opens like a system popover: fades in while settling a few points down under the menu bar icon.
    private func openPanel() {
        guard let button = statusItem.button else { return }
        isOpen = true
        transition += 1
        model.refresh()
        panel.contentViewController?.view.layoutSubtreeIfNeeded()
        updatePanelSize(panel.contentViewController?.view.fittingSize ?? NSSize(width: 300, height: 500))
        positionPanel(below: button)
        let target = panel.frame
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.setFrameOrigin(NSPoint(x: target.minX, y: target.minY + 8))
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(target, display: true)
        }
    }

    // A click on the menu bar icon also reaches the outside-click monitor. Closing here would make the
    // icon's own action reopen the panel right away, so the icon (and the panel itself) do not count as outside.
    private func closePanelIfOutside(at point: NSPoint) {
        guard isOpen, !panel.frame.contains(point) else { return }
        if let button = statusItem.button, let window = button.window,
           window.convertToScreen(button.convert(button.bounds, to: nil)).insetBy(dx: -4, dy: -4).contains(point) { return }
        closePanel()
    }

    private func closePanel() {
        guard isOpen else { return }
        isOpen = false
        transition += 1
        let current = transition
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.transition == current else { return }
                self.panel.orderOut(nil)
            }
        })
    }

    private func updatePanelSize(_ size: CGSize) {
        guard size.width > 0, size.height > 0, let panel else { return }
        let target = NSSize(width: 300, height: size.height)
        guard panel.contentRect(forFrameRect: panel.frame).size != target else { return }
        panel.setContentSize(target)
        if isOpen, let button = statusItem.button { positionPanel(below: button) }
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
