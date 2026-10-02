# MonitorBar Implementation Plan

> **For agentic workers:** Implement natively, task by task. No subagents are requested. Use test-first checks for logic; verify the UI in a live macOS window.

**Goal:** Build the approved Hızlı Panel as a macOS menu bar app that controls external monitors through real DDC/CI hardware commands.

**Architecture:** A small SwiftUI panel lives in an AppKit status item. CoreGraphics reports external display changes. A serial DDC client uses a C bridge to the runtime-resolved IOAVService API; the UI enables controls only after a valid VCP read and verifies writes by readback.

**Tech Stack:** Swift Package Manager, SwiftUI, AppKit, CoreGraphics, IOKit, Objective-C C bridge. No package dependencies.

**Spec:** `docs/superpowers/specs/2026-10-02-monitorbar-design.md`

## Global Constraints

- macOS 26+; current acceptance device is macOS 27.0.1 on Apple M5 Pro.
- No GPL source, software gamma dimming, overlay, automatic input switching, helper process, or launch-at-login feature.
- Never claim physical brightness from a UI slider alone. A valid VCP read and post-write readback are required.
- The menu bar item must disappear when the external display list is empty and reappear on reconnect.
- Preserve the approved compact Hızlı Panel look with native SF Symbols, controls, and Liquid Glass.

## Review Focus

1. Two identical monitors: serial-number matching must select the right service or refuse ambiguous control. Test in matching task.
2. Invalid VCP data: zero maximum or current above maximum must disable control. Test in value task.
3. Fast slider drag: only the final pending value must write. Test in model task.
4. Disconnect before a scheduled write: the stale write must not reach a different monitor. Test in model task.
5. A failed readback: UI must report failure and refresh the actual value. Test in model task.

---

### Task 1: Package and pure display logic

**Files:** `Package.swift`, `Sources/MonitorBar/DisplayIdentity.swift`, `Tests/MonitorBarTests/DisplayIdentityTests.swift`, `.gitignore`.

**Interfaces:**
- `DisplayIdentity(id: UInt32, name: String, vendor: UInt32, product: UInt32, serial: UInt32)`.
- `DDCIdentity(index: Int32, vendor: UInt32, product: UInt32, serial: UInt32)`.
- `matchDisplays(_ displays: [DisplayIdentity], to services: [DDCIdentity]) -> [UInt32: Int32]`.
- `rawLevel(percent: Double, maximum: UInt16) -> UInt16?` and `percent(current: UInt16, maximum: UInt16) -> Double?`.

- [ ] Write tests for exact vendor/product/serial match, one-to-one fallback, ambiguous rejection, zero maximum, out-of-range current, and clamped conversion.
- [ ] Run `swift test`; confirm failures from missing symbols, then implement only the stated pure functions.
- [ ] Run `swift test` again; commit `feat: add display identity matching`.

### Task 2: Hardware bridge and discovery

**Files:** `Sources/DDCBridge/include/DDCBridge.h`, `Sources/DDCBridge/DDCBridge.m`, `Sources/MonitorBar/DisplayDiscovery.swift`, `Sources/MonitorBar/DDCClient.swift`.

**Interfaces:**
- C functions `MBRescan`, `MBServiceCount`, `MBServiceIdentity`, `MBReadVCP`, `MBWriteVCP` return explicit success/failure. `MBReadVCP` fills current and maximum `uint16_t` outputs.
- `DisplayDiscovery.onChange: ([DisplayIdentity]) -> Void`, `start()`, `stop()`.
- `DDCClient.probe(displays:completion:)` and `write(display:vcp:raw:completion:)` run on one serial queue and re-resolve identity before each write.

- [ ] Add a small bridge self-check that validates DDC packet checksums and read-response parsing without touching hardware; run it red, then implement the packet helpers and run green.
- [ ] Implement runtime symbol lookup, external service enumeration, EDID parsing, Get/Set VCP with bounded retries and checksum validation.
- [ ] Implement CoreGraphics online-display snapshot and reconfiguration callback. Ignore begin flags; dispatch completed changes to main.
- [ ] Build release. Run a read-only CLI diagnostic against X27F166QB; require a valid `0x10` read before any app write. Commit `feat: connect external displays to DDC`.

### Task 3: State and native quick panel

**Files:** `Sources/MonitorBar/MonitorModel.swift`, `Sources/MonitorBar/QuickPanel.swift`, `Sources/MonitorBar/MonitorBarApp.swift`, `Tests/MonitorBarTests/MonitorModelTests.swift`.

**Interfaces:**
- `MonitorModel` publishes external displays, selected display, brightness/contrast capabilities, busy/error state, and diagnostic text.
- `setBrightness(percent:)` debounces 150 ms and verifies readback. Presets call the same path. Contrast uses `0x12` only when readable.
- `MonitorBarApp` owns the status item and popover; `.isVisible` follows external-display presence.

- [ ] Write model tests for final-value coalescing, disconnect cancellation, and failed-readback state; run red.
- [ ] Implement model on main actor, with serial DDC operations off the main thread; run tests green.
- [ ] Implement the compact SwiftUI panel with system SF Symbols, native sliders, preset pills, a collapsed contrast/input area, a diagnostics view, and Quit. Use `.glassEffect` and standard glass button styles where appropriate.
- [ ] Run `swift test` and `swift build -c release`. Commit `feat: add native menu bar panel`.

### Task 4: Bundle and live acceptance

**Files:** `scripts/build-app.sh`, `Resources/Info.plist`, `README.md`.

- [ ] Package `dist/MonitorBar.app` with `LSUIElement=YES`; document install, DDC limitations, and how to quit when no monitor is connected.
- [ ] Run `swift test`, `swift build -c release`, and bundle creation; launch the app.
- [ ] Inspect actual dark/light popover, slider, presets, details, diagnostics, and layout at native screen scale. Repair visual defects.
- [ ] Perform one small reversible app-side brightness write/readback and restore original value. Report protocol readback separately from user-observed light-output change.
- [ ] Check the status item with display attached. Exercise unplug/replug only if safely available; otherwise report this acceptance item unverified.
- [ ] Commit `feat: package and verify MonitorBar` and leave the local app available for user review.

## Self-review

The tasks cover every section of the spec. The first build is deliberately limited to hardware brightness, supported contrast, input readout, display presence, and diagnostics. The physical disconnect/reconnect check may need user participation; build and code verification do not substitute for it.
