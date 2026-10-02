import AppKit
import Combine

@MainActor final class MonitorModel: ObservableObject {
    @Published private(set) var displays: [DisplayIdentity] = []
    @Published private(set) var probes: [DDCProbe] = []
    @Published private(set) var selectedID: UInt32?
    @Published private(set) var brightnessValue = 0.0
    @Published private(set) var contrastValue = 0.0
    @Published private(set) var isLoading = false
    @Published private(set) var isWriting = false
    @Published private(set) var errorMessage: String?

    var onPresenceChange: ((Bool) -> Void)?
    private let discovery = DisplayDiscovery()
    private let brightnessScheduler = WriteScheduler()
    private let contrastScheduler = WriteScheduler()
    private var generation = 0
    private var brightnessRequest = 0
    private var contrastRequest = 0

    var selectedProbe: DDCProbe? { probes.first { $0.display.id == selectedID } }
    var canChangeBrightness: Bool { selectedProbe?.brightness != nil && !isLoading }
    var canChangeContrast: Bool { selectedProbe?.contrast != nil && !isLoading }

    func start() {
        discovery.onChange = { [weak self] displays in
            MainActor.assumeIsolated { self?.updateDisplays(displays) }
        }
        discovery.start()
    }

    func stop() {
        brightnessScheduler.cancel()
        contrastScheduler.cancel()
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

    func setBrightness(_ value: Double) {
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
        brightnessScheduler.cancel()
        contrastScheduler.cancel()
        displays = newDisplays
        onPresenceChange?(!newDisplays.isEmpty)
        if newDisplays.isEmpty {
            selectedID = nil
            probes = []
            isLoading = false
            isWriting = false
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
}
