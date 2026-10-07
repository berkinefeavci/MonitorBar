import AppKit
import Combine
import DDCBridge
import ServiceManagement

@MainActor final class MonitorModel: ObservableObject {
    @Published private(set) var displays: [DisplayIdentity] = []
    @Published private(set) var probes: [DDCProbe] = []
    // External screens without DDC/CI brightness (Sidecar, AirPlay, unresponsive monitors) dimmed by overlay.
    @Published private(set) var softwareDimmed: Set<UInt32> = []
    @Published private(set) var builtInDisplay: DisplayIdentity?
    @Published private(set) var builtInBrightnessValue: Double?
    @Published private(set) var keyboardBrightnessValue: Double?
    @Published private(set) var nightShiftWarm: Bool?
    @Published private(set) var linkBrightness = UserDefaults.standard.bool(forKey: "linkBrightness")
    @Published private(set) var contrastValue = 0.0
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var launchAtLogin = false

    private let discovery = DisplayDiscovery()
    private var brightnessQueues: [UInt32: LatestWriteQueue] = [:]
    private let contrastScheduler = WriteScheduler()
    private let builtInScheduler = WriteScheduler()
    private let keyboardScheduler = WriteScheduler()
    private let builtInContrast = BuiltInContrastController()
    private let dimmer = SoftwareDimmer()
    private var generation = 0
    private var brightnessRequests: [UInt32: Int] = [:]
    private var contrastRequest = 0
    private var builtInRequest = 0
    private var keyboardRequest = 0
    private var keyboardWritePending = false
    private var builtInWritePending = false
    private var builtInContrastFailed = false
    private var nightShiftEnabledBeforeOverride: Bool?
    private var builtInPollTimer: Timer?
    private var lastMirroredBuiltIn: Double?

    // Rows stay usable while a refresh re-reads the monitors; only the first probe has nothing to show.
    var canChangeContrast: Bool { probes.contains { $0.contrast != nil } }
    var canChangeBuiltInBrightness: Bool { builtInDisplay != nil && builtInBrightnessValue != nil }
    var canChangeKeyboardBrightness: Bool { keyboardBrightnessValue != nil }
    var canLinkBrightness: Bool {
        (canChangeBuiltInBrightness ? 1 : 0) + probes.filter { $0.brightness != nil }.count >= 2
    }

    // Shown on the single bar while all screens are linked: the Mac's level, or the first screen's.
    var linkedBrightnessValue: Double? {
        builtInBrightnessValue ?? probes.first { $0.brightness != nil }?.brightness?.percent
    }

    func brightness(of id: UInt32) -> Double? {
        probes.first { $0.display.id == id }?.brightness?.percent
    }

    func canChangeBrightness(of id: UInt32) -> Bool { brightness(of: id) != nil }

    func start() {
        BuiltInContrastController.recoverAfterCrash()
        if #available(macOS 13, *) { launchAtLogin = SMAppService.mainApp.status == .enabled }
        discovery.onChange = { [weak self] displays, force in
            MainActor.assumeIsolated { self?.updateDisplays(displays, force: force) }
        }
        discovery.start()
        pollKeyboardBrightness()
        pollNightShift()
        builtInPollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollBuiltInBrightness() }
        }
    }

    func stop() {
        cancelBrightnessWrites()
        contrastScheduler.cancel()
        builtInScheduler.cancel()
        keyboardScheduler.cancel()
        builtInWritePending = false
        keyboardWritePending = false
        builtInPollTimer?.invalidate()
        builtInPollTimer = nil
        builtInContrast.restore()
        dimmer.removeAll()
        discovery.stop()
    }

    @available(macOS 13, *)
    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            errorMessage = nil
        } catch {
            errorMessage = String(localized: "Open at login could not be changed")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func refresh() { updateDisplays(DisplayDiscovery.externalDisplays(), force: true) }

    func setLinkBrightness(_ enabled: Bool) {
        linkBrightness = enabled
        UserDefaults.standard.set(enabled, forKey: "linkBrightness")
        lastMirroredBuiltIn = builtInBrightnessValue
        syncExternalToBuiltIn()
    }

    func setBrightness(_ value: Double, of id: UInt32) {
        if linkBrightness {
            setAllBrightness(value)
        } else {
            setExternalBrightness(value, of: id)
        }
    }

    func setBuiltInBrightness(_ value: Double) {
        if linkBrightness {
            setAllBrightness(value)
        } else {
            setBuiltInBrightnessOnly(value)
            lastMirroredBuiltIn = min(100, max(0, value))
        }
    }

    func setAllBrightness(_ value: Double) {
        if canChangeBuiltInBrightness {
            setBuiltInBrightnessOnly(value)
            lastMirroredBuiltIn = min(100, max(0, value))
        }
        for probe in probes where probe.brightness != nil {
            setExternalBrightness(value, of: probe.display.id)
        }
    }

    func setKeyboardBrightness(_ value: Double) {
        guard keyboardBrightnessValue != nil else { return }
        let requested = min(100, max(0, value))
        keyboardBrightnessValue = requested
        errorMessage = nil
        keyboardRequest += 1
        let request = keyboardRequest
        keyboardWritePending = true
        keyboardScheduler.schedule(after: 0) { [weak self] in
            guard let self, self.keyboardRequest == request else { return }
            var readback: Float = 0
            let target = Float(requested / 100)
            if MBWriteKeyboardBrightness(target), MBReadKeyboardBrightness(&readback) {
                self.keyboardBrightnessValue = Double(readback) * 100
                if abs(Double(readback) - Double(target)) > 0.02 {
                    self.errorMessage = String(localized: "Keyboard backlight change was not confirmed")
                }
            } else {
                self.keyboardBrightnessValue = nil
                self.errorMessage = String(localized: "Keyboard backlight is unavailable")
            }
            self.keyboardWritePending = false
        }
    }

    func setNightShiftWarm(_ warm: Bool) {
        guard nightShiftWarm != nil else { return }
        var active = false, enabled = false
        var mode: Int32 = 0
        guard MBReadNightShift(&active, &enabled, &mode) else { return }
        if warm { nightShiftEnabledBeforeOverride = enabled }
        let enabledWhenOff = nightShiftEnabledBeforeOverride ?? (mode != 0 && enabled)
        if !MBSetNightShiftWarm(warm, enabledWhenOff) {
            errorMessage = String(localized: "Night Shift change was not confirmed")
        } else {
            errorMessage = nil
            if !warm { nightShiftEnabledBeforeOverride = nil }
        }
        pollNightShift()
    }

    private func setExternalBrightness(_ value: Double, of id: UInt32) {
        guard let probe = probes.first(where: { $0.display.id == id }) else { return }
        if softwareDimmed.contains(id) {
            dimmer.set(value, for: id)
            replaceLevels(softwareLevels(id), vcp: 0x10, displayID: id)
            return
        }
        guard let levels = probe.brightness,
              let raw = rawLevel(percent: value, maximum: levels.maximum) else { return }
        // Show the requested level right away; the monitor's readback replaces it once the write lands.
        replaceLevels(HardwareLevels(current: raw, maximum: levels.maximum), vcp: 0x10, displayID: id)
        errorMessage = nil
        let request = (brightnessRequests[id] ?? 0) + 1
        brightnessRequests[id] = request
        let token = generation
        let queue = brightnessQueues[id] ?? LatestWriteQueue()
        brightnessQueues[id] = queue
        queue.submit { [weak self] finish in
            guard let self else { finish(); return }
            self.send(display: probe.display, vcp: 0x10, raw: raw, token: token,
                      request: request, finished: finish)
        }
    }

    private func setBuiltInBrightnessOnly(_ value: Double) {
        guard let display = builtInDisplay, builtInBrightnessValue != nil else { return }
        let requested = min(100, max(0, value))
        builtInBrightnessValue = requested
        builtInWritePending = true
        builtInRequest += 1
        let request = builtInRequest
        builtInScheduler.schedule(after: 0) { [weak self] in
            guard let self, self.builtInDisplay?.id == display.id, self.builtInRequest == request else { return }
            let target = Float(requested / 100)
            var readback: Float = 0
            if MBWriteBuiltInBrightness(display.id, target), MBReadBuiltInBrightness(display.id, &readback) {
                self.builtInBrightnessValue = Double(readback) * 100
                self.lastMirroredBuiltIn = Double(readback) * 100
                if abs(Double(readback) - Double(target)) > 0.02 {
                    self.errorMessage = String(localized: "Built-in display change was not confirmed")
                }
            } else {
                self.builtInBrightnessValue = nil
                self.errorMessage = String(localized: "Built-in display brightness is unavailable")
            }
            self.builtInWritePending = false
        }
    }

    // One contrast control for every screen that supports it: monitors over DDC/CI, the Mac via gamma.
    func setContrast(_ value: Double) {
        let targets = probes.compactMap { probe -> (DisplayIdentity, UInt16)? in
            guard let levels = probe.contrast,
                  let raw = rawLevel(percent: value, maximum: levels.maximum) else { return nil }
            return (probe.display, raw)
        }
        guard !targets.isEmpty else { return }
        contrastValue = value
        errorMessage = nil
        contrastRequest += 1
        let token = generation
        let request = contrastRequest
        contrastScheduler.schedule(after: 0.15) { [weak self] in
            guard let self, self.generation == token else { return }
            self.builtInContrastFailed = self.builtInDisplay.map {
                !self.builtInContrast.apply(value, to: $0.id)
            } ?? false
            for (display, raw) in targets {
                self.send(display: display, vcp: 0x12, raw: raw, token: token, request: request)
            }
        }
    }

    private func updateDisplays(_ newDisplays: [DisplayIdentity], force: Bool) {
        dimmer.keep(only: softwareDimmed.intersection(newDisplays.map(\.id)))
        let nextBuiltInDisplay = DisplayDiscovery.builtInDisplay()
        if !force && newDisplays == displays && nextBuiltInDisplay?.id == builtInDisplay?.id && !probes.isEmpty {
            return
        }
        generation += 1
        cancelBrightnessWrites()
        contrastScheduler.cancel()
        builtInScheduler.cancel()
        builtInWritePending = false
        if nextBuiltInDisplay?.id != builtInDisplay?.id { builtInContrast.restore() }
        builtInDisplay = nextBuiltInDisplay
        if let builtInDisplay {
            var level: Float = 0
            builtInBrightnessValue = MBReadBuiltInBrightness(builtInDisplay.id, &level) ? Double(level) * 100 : nil
            lastMirroredBuiltIn = builtInBrightnessValue
        } else {
            builtInBrightnessValue = nil
            lastMirroredBuiltIn = nil
        }
        displays = newDisplays
        if newDisplays.isEmpty {
            probes = []
            softwareDimmed = []
            isLoading = false
            return
        }
        probe(newDisplays, token: generation)
    }

    private func probe(_ displays: [DisplayIdentity], token: Int) {
        isLoading = true
        let requestsAtStart = brightnessRequests
        let contrastRequestAtStart = contrastRequest
        DDCClient.shared.probe(displays: displays.filter { !$0.isVirtual }) { [weak self] results in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                var dimmed = Set<UInt32>()
                self.probes = displays.map { display in
                    if let result = results.first(where: { $0.display.id == display.id }),
                       result.brightness != nil {
                        // A slider moved during the probe: keep its newer value instead of the reading taken before it.
                        let current = self.probes.first { $0.display.id == display.id }
                        let brightnessMoved = self.brightnessRequests[display.id] != requestsAtStart[display.id]
                        let contrastMoved = self.contrastRequest != contrastRequestAtStart
                        return DDCProbe(display: display,
                                        brightness: brightnessMoved ? current?.brightness ?? result.brightness : result.brightness,
                                        contrast: contrastMoved ? current?.contrast ?? result.contrast : result.contrast,
                                        input: result.input, issue: result.issue)
                    }
                    dimmed.insert(display.id)
                    let result = results.first { $0.display.id == display.id }
                    return DDCProbe(display: display, brightness: self.softwareLevels(display.id),
                                    contrast: nil, input: result?.input, issue: nil)
                }
                self.softwareDimmed = dimmed
                self.dimmer.keep(only: dimmed)
                self.isLoading = false
                self.syncContrast()
                self.syncExternalToBuiltIn()
            }
        }
    }

    private func softwareLevels(_ id: UInt32) -> HardwareLevels {
        HardwareLevels(current: UInt16((dimmer.level(for: id) * 10).rounded()), maximum: 1000)
    }

    private func cancelBrightnessWrites() {
        brightnessQueues.values.forEach { $0.cancel() }
    }

    private func send(display: DisplayIdentity, vcp: UInt8, raw: UInt16, token: Int,
                      request: Int, finished: (@MainActor () -> Void)? = nil) {
        guard generation == token else { finished?(); return }
        DDCClient.shared.write(display: display, vcp: vcp, raw: raw) { [weak self] readback in
            Task { @MainActor in
                defer { finished?() }
                guard let self, self.generation == token,
                      request == (vcp == 0x10 ? self.brightnessRequests[display.id] : self.contrastRequest)
                else { return }
                switch writeOutcome(requested: raw, readback: readback) {
                case .verified:
                    self.replaceLevels(readback, vcp: vcp, displayID: display.id)
                    self.errorMessage = vcp == 0x12 && self.builtInContrastFailed ?
                        String(localized: "Built-in display contrast could not be applied") : nil
                case .mismatch:
                    self.replaceLevels(readback, vcp: vcp, displayID: display.id)
                    self.errorMessage = String(localized: "\(display.name) reported a different value")
                case .unreadable:
                    self.errorMessage = String(localized: "\(display.name) did not confirm the change")
                    self.probe(self.displays, token: token)
                }
            }
        }
    }

    private func replaceLevels(_ levels: HardwareLevels?, vcp: UInt8, displayID: UInt32) {
        guard let levels, let index = probes.firstIndex(where: { $0.display.id == displayID }) else { return }
        let old = probes[index]
        probes[index] = DDCProbe(display: old.display,
                                 brightness: vcp == 0x10 ? levels : old.brightness,
                                 contrast: vcp == 0x12 ? levels : old.contrast,
                                 input: old.input, issue: old.issue)
        if vcp == 0x12 { syncContrast() }
    }

    private func syncContrast() {
        contrastValue = probes.first { $0.contrast != nil }?.contrast?.percent ?? 0
    }

    private func syncExternalToBuiltIn() {
        guard linkBrightness, let value = builtInBrightnessValue else { return }
        for probe in probes where probe.brightness != nil {
            setExternalBrightness(value, of: probe.display.id)
        }
    }

    private func pollBuiltInBrightness() {
        pollKeyboardBrightness()
        pollNightShift()
        guard !builtInWritePending else { return }
        guard let display = builtInDisplay else { return }
        var raw: Float = 0
        guard MBReadBuiltInBrightness(display.id, &raw) else { return }
        let value = Double(raw) * 100
        builtInBrightnessValue = value
        guard let previous = lastMirroredBuiltIn else {
            lastMirroredBuiltIn = value
            return
        }
        if !linkBrightness {
            lastMirroredBuiltIn = value
        } else if abs(value - previous) >= 2 {
            lastMirroredBuiltIn = value
            syncExternalToBuiltIn()
        }
    }

    private func pollKeyboardBrightness() {
        guard !keyboardWritePending else { return }
        var raw: Float = 0
        keyboardBrightnessValue = MBReadKeyboardBrightness(&raw) ? Double(raw) * 100 : nil
    }

    private func pollNightShift() {
        var active = false, enabled = false
        var mode: Int32 = 0
        nightShiftWarm = MBReadNightShift(&active, &enabled, &mode) ? active && enabled : nil
    }
}
