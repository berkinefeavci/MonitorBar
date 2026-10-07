import AppKit

// Sidecar and AirPlay screens have no DDC/CI, so their brightness is lowered with a click-through black overlay.
@MainActor final class SoftwareDimmer {
    private let maximumDim = 0.9
    private var levels: [UInt32: Double] = [:]
    private var windows: [UInt32: NSWindow] = [:]
    private var screenObserver: NSObjectProtocol?

    init() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reapply() }
        }
    }

    func level(for id: UInt32) -> Double { levels[id] ?? 100 }

    func set(_ percent: Double, for id: UInt32) {
        levels[id] = min(100, max(0, percent))
        apply(id)
    }

    func keep(only ids: Set<UInt32>) {
        for id in Set(levels.keys).subtracting(ids) { levels[id] = nil }
        for id in Set(windows.keys).subtracting(ids) { windows.removeValue(forKey: id)?.orderOut(nil) }
        reapply()
    }

    func removeAll() { keep(only: []) }

    private func reapply() { for id in levels.keys { apply(id) } }

    private func apply(_ id: UInt32) {
        let value = level(for: id)
        guard value < 100, let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
        }) else {
            windows.removeValue(forKey: id)?.orderOut(nil)
            return
        }
        let window = windows[id] ?? makeWindow()
        windows[id] = window
        window.setFrame(screen.frame, display: false)
        window.alphaValue = (100 - value) / 100 * maximumDim
        window.orderFrontRegardless()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .black
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.animationBehavior = .none
        // Above the menu bar and Dock; the PanelLight panel sits higher so it stays readable.
        window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        return window
    }
}
