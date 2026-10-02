import AppKit
import Combine
import DDCBridge

@MainActor final class MonitorModel: ObservableObject {
    @Published private(set) var displays: [DisplayIdentity] = []
    @Published private(set) var probes: [DDCProbe] = []
    @Published private(set) var selectedID: UInt32?
    @Published private(set) var brightnessValue = 0.0
    @Published private(set) var builtInDisplay: DisplayIdentity?
    @Published private(set) var builtInBrightnessValue: Double?
    @Published private(set) var keyboardBrightnessValue: Double?
    @Published private(set) var nightShiftWarm: Bool?
    @Published private(set) var linkBrightness = UserDefaults.standard.bool(forKey: "linkBrightness")
    @Published private(set) var scheduleEnabled = UserDefaults.standard.bool(forKey: "scheduleEnabled")
    @Published private(set) var nightStart = UserDefaults.standard.object(forKey: "nightStart") as? Int ?? 22 * 60
    @Published private(set) var nightEnd = UserDefaults.standard.object(forKey: "nightEnd") as? Int ?? 7 * 60
    @Published private(set) var nightBrightness = UserDefaults.standard.object(forKey: "nightBrightness") as? Double ?? 35
    @Published private(set) var dayBrightness = UserDefaults.standard.object(forKey: "dayBrightness") as? Double ?? 70
    @Published private(set) var contrastValue = 0.0
    @Published private(set) var isLoading = false
    @Published private(set) var isWriting = false
    @Published private(set) var errorMessage: String?

    var onPresenceChange: ((Bool) -> Void)?
    private let discovery = DisplayDiscovery()
    private let brightnessScheduler = WriteScheduler()
    private let contrastScheduler = WriteScheduler()
    private let builtInScheduler = WriteScheduler()
    private let keyboardScheduler = WriteScheduler()
    private var generation = 0
    private var brightnessRequest = 0
    private var contrastRequest = 0
    private var builtInRequest = 0
    private var keyboardRequest = 0
    private var keyboardWritePending = false
    private var scheduleTimer: Timer?
    private var builtInPollTimer: Timer?
    private var lastMirroredBuiltIn: Double?
    private var lastAppliedNight: Bool?

    var selectedProbe: DDCProbe? { probes.first { $0.display.id == selectedID } }
    var canChangeBrightness: Bool { selectedProbe?.brightness != nil && !isLoading }
    var canChangeContrast: Bool { selectedProbe?.contrast != nil && !isLoading }
    var canChangeBuiltInBrightness: Bool { builtInDisplay != nil && builtInBrightnessValue != nil }
    var canChangeKeyboardBrightness: Bool { keyboardBrightnessValue != nil }

    func start() {
        discovery.onChange = { [weak self] displays in
            MainActor.assumeIsolated { self?.updateDisplays(displays) }
        }
        discovery.start()
        pollKeyboardBrightness()
        pollNightShift()
        scheduleTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyScheduleIfNeeded() }
        }
        builtInPollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollBuiltInBrightness() }
        }
    }

    func stop() {
        brightnessScheduler.cancel()
        contrastScheduler.cancel()
        builtInScheduler.cancel()
        keyboardScheduler.cancel()
        scheduleTimer?.invalidate()
        scheduleTimer = nil
        builtInPollTimer?.invalidate()
        builtInPollTimer = nil
        discovery.stop()
    }

    func selectDisplay(_ id: UInt32) {
        guard displays.contains(where: { $0.id == id }) else { return }
        brightnessScheduler.cancel()
        contrastScheduler.cancel()
        selectedID = id
        syncValues()
    }

    func refresh() { updateDisplays(DisplayDiscovery.externalDisplays()) }

    func setLinkBrightness(_ enabled: Bool) {
        linkBrightness = enabled
        UserDefaults.standard.set(enabled, forKey: "linkBrightness")
        lastMirroredBuiltIn = builtInBrightnessValue
    }

    func setScheduleEnabled(_ enabled: Bool) {
        scheduleEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "scheduleEnabled")
        lastAppliedNight = nil
        applyScheduleIfNeeded()
    }

    func setScheduleTime(_ minutes: Int, night: Bool) {
        let value = min(1439, max(0, minutes))
        if night {
            nightStart = value
            UserDefaults.standard.set(value, forKey: "nightStart")
        } else {
            nightEnd = value
            UserDefaults.standard.set(value, forKey: "nightEnd")
        }
        lastAppliedNight = nil
        applyScheduleIfNeeded()
    }

    func setScheduleBrightness(_ value: Double, night: Bool) {
        let level = min(100, max(0, value))
        if night {
            nightBrightness = level
            UserDefaults.standard.set(level, forKey: "nightBrightness")
        } else {
            dayBrightness = level
            UserDefaults.standard.set(level, forKey: "dayBrightness")
        }
        lastAppliedNight = nil
        applyScheduleIfNeeded()
    }

    func setBrightness(_ value: Double) {
        setExternalBrightness(value)
        if linkBrightness { setBuiltInBrightnessOnly(value) }
    }

    func setBuiltInBrightness(_ value: Double) {
        setBuiltInBrightnessOnly(value)
        if linkBrightness { setExternalBrightness(value) }
    }

    func setKeyboardBrightness(_ value: Double) {
        guard keyboardBrightnessValue != nil else { return }
        let requested = min(100, max(0, value))
        keyboardBrightnessValue = requested
        errorMessage = nil
        keyboardRequest += 1
        let request = keyboardRequest
        keyboardWritePending = true
        keyboardScheduler.schedule(after: 0.15) { [weak self] in
            guard let self, self.keyboardRequest == request else { return }
            var readback: Float = 0
            let target = Float(requested / 100)
            if MBWriteKeyboardBrightness(target), MBReadKeyboardBrightness(&readback) {
                self.keyboardBrightnessValue = Double(readback) * 100
                if abs(Double(readback) - Double(target)) > 0.02 {
                    self.errorMessage = "Klavye ışığı değişikliği doğrulanmadı"
                }
            } else {
                self.keyboardBrightnessValue = nil
                self.errorMessage = "Klavye ışığı kullanılamıyor"
            }
            self.keyboardWritePending = false
        }
    }

    func setNightShiftWarm(_ warm: Bool) {
        guard nightShiftWarm != nil else { return }
        if !MBSetNightShiftWarm(warm) {
            errorMessage = "Night Shift değişikliği doğrulanmadı"
        } else {
            errorMessage = nil
        }
        pollNightShift()
    }

    private func setExternalBrightness(_ value: Double) {
        guard let probe = selectedProbe, let levels = probe.brightness,
              let raw = rawLevel(percent: value, maximum: levels.maximum) else { return }
        brightnessValue = value
        errorMessage = nil
        isWriting = true
        brightnessRequest += 1
        let token = generation
        let request = brightnessRequest
        brightnessScheduler.schedule(after: 0.15) { [weak self] in
            self?.send(display: probe.display, vcp: 0x10, raw: raw, token: token, request: request)
        }
    }

    private func setBuiltInBrightnessOnly(_ value: Double) {
        guard let display = builtInDisplay, builtInBrightnessValue != nil else { return }
        let requested = min(100, max(0, value))
        builtInBrightnessValue = requested
        builtInRequest += 1
        let request = builtInRequest
        builtInScheduler.schedule(after: 0.15) { [weak self] in
            guard let self, self.builtInDisplay?.id == display.id, self.builtInRequest == request else { return }
            let target = Float(requested / 100)
            var readback: Float = 0
            if MBWriteBuiltInBrightness(display.id, target), MBReadBuiltInBrightness(display.id, &readback) {
                self.builtInBrightnessValue = Double(readback) * 100
                self.lastMirroredBuiltIn = Double(readback) * 100
                if abs(Double(readback) - Double(target)) > 0.02 {
                    self.errorMessage = "Yerleşik ekran değişikliği doğrulanmadı"
                }
            } else {
                self.builtInBrightnessValue = nil
                self.errorMessage = "Yerleşik ekran parlaklığı kullanılamıyor"
            }
        }
    }

    func setContrast(_ value: Double) {
        guard let probe = selectedProbe, let levels = probe.contrast,
              let raw = rawLevel(percent: value, maximum: levels.maximum) else { return }
        contrastValue = value
        errorMessage = nil
        isWriting = true
        contrastRequest += 1
        let token = generation
        let request = contrastRequest
        contrastScheduler.schedule(after: 0.15) { [weak self] in
            self?.send(display: probe.display, vcp: 0x12, raw: raw, token: token, request: request)
        }
    }

    private func updateDisplays(_ newDisplays: [DisplayIdentity]) {
        generation += 1
        if newDisplays != displays { lastAppliedNight = nil }
        brightnessScheduler.cancel()
        contrastScheduler.cancel()
        builtInScheduler.cancel()
        builtInDisplay = DisplayDiscovery.builtInDisplay()
        if let builtInDisplay {
            var level: Float = 0
            builtInBrightnessValue = MBReadBuiltInBrightness(builtInDisplay.id, &level) ? Double(level) * 100 : nil
            lastMirroredBuiltIn = builtInBrightnessValue
        } else {
            builtInBrightnessValue = nil
            lastMirroredBuiltIn = nil
        }
        displays = newDisplays
        onPresenceChange?(!newDisplays.isEmpty)
        if newDisplays.isEmpty {
            selectedID = nil
            probes = []
            isLoading = false
            isWriting = false
            applyScheduleIfNeeded()
            return
        }
        if selectedID == nil || !newDisplays.contains(where: { $0.id == selectedID }) {
            selectedID = newDisplays[0].id
        }
        probe(newDisplays, token: generation)
    }

    private func probe(_ displays: [DisplayIdentity], token: Int) {
        isLoading = true
        DDCClient.shared.probe(displays: displays) { [weak self] results in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.probes = results
                self.isLoading = false
                self.isWriting = false
                self.syncValues()
                self.applyScheduleIfNeeded()
            }
        }
    }

    private func send(display: DisplayIdentity, vcp: UInt8, raw: UInt16, token: Int, request: Int) {
        guard generation == token, selectedID == display.id else { return }
        DDCClient.shared.write(display: display, vcp: vcp, raw: raw) { [weak self] readback in
            Task { @MainActor in
                guard let self, self.generation == token, self.selectedID == display.id,
                      request == (vcp == 0x10 ? self.brightnessRequest : self.contrastRequest) else { return }
                self.isWriting = false
                switch writeOutcome(requested: raw, readback: readback) {
                case .verified:
                    self.replaceLevels(readback, vcp: vcp, displayID: display.id)
                    self.errorMessage = nil
                case .mismatch:
                    self.replaceLevels(readback, vcp: vcp, displayID: display.id)
                    self.errorMessage = "Monitör farklı bir değer bildirdi"
                case .unreadable:
                    self.syncValues()
                    self.errorMessage = "Monitör değişikliği doğrulamadı"
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
        syncValues()
    }

    private func syncValues() {
        brightnessValue = selectedProbe?.brightness?.percent ?? 0
        contrastValue = selectedProbe?.contrast?.percent ?? 0
    }

    private func applyScheduleIfNeeded() {
        guard scheduleEnabled, !isLoading else { return }
        let isNight = BrightnessSchedule(nightStart: nightStart, nightEnd: nightEnd).isNight(at: Date())
        guard lastAppliedNight != isNight else { return }
        lastAppliedNight = isNight
        let level = isNight ? nightBrightness : dayBrightness
        setExternalBrightness(level)
        setBuiltInBrightnessOnly(level)
    }

    private func pollBuiltInBrightness() {
        pollKeyboardBrightness()
        pollNightShift()
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
            setExternalBrightness(value)
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
