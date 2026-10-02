# MonitorBar Design

> 2026-10-02 · Codex. Berkin approved the Hızlı Panel visual and the technical direction in chat.

## Purpose

A personal macOS menu bar app for direct hardware control of connected external monitors. The first target is Berkin's Fazeon X27F166QB, while display discovery and DDC matching must also support other external monitors. The app must not represent software dimming as physical brightness.

## Verified hardware baseline

- Mac: Apple M5 Pro, macOS 27.0.1. External display: X27F166QB, 2560 × 1440 at 144 Hz, one external DCP AV service; service EDID vendor `0x598b`, product `0x2700`, serial `1`.
- AppleSiliconDDC `getvcp 0x10` failed to read on this connection. A separate MIT-licensed implementation, `traderGK/OpenDisplay` at `cf9672ce92fa33ebb8e440b857725cf47279ef27`, read VCP `0x10` as `58/100`.
- A small, reversible DDC test wrote `52/100`, read back `52/100`, restored `58/100`, then read back `58/100`. These are hardware protocol readbacks. Perceived light-output change awaits user observation.
- The Mac reports a DP-to-HDMI path. The precise cable/adapter path and monitor OSD settings remain unknown.

## Scope

1. **Display presence:** show a status item only while at least one physical external monitor is online. Reconfigure on connect, disconnect, wake, and display change. The app remains running when the item is hidden so it can reappear on reconnect.
2. **Quick panel:** reproduce the approved compact layout: model header, actual brightness slider, three presets (25%, 60%, 100%), a collapsed secondary area, and a quiet DDC status. Use SwiftUI system fonts, SF Symbols, native controls, and Liquid Glass on supported macOS.
3. **Hardware brightness:** read VCP `0x10` from the EDID-matched DDC service. Enable the slider only after a valid read. Debounce writes during dragging; read back after writes. Show errors without silently falling back to gamma or an overlay.
4. **Secondary controls:** show hardware contrast VCP `0x12` only if readable. Show current input VCP `0x60` as information if available. Do not switch input in the first build, because that could remove the active video path.
5. **Diagnostics:** the settings button reveals connection and DDC status plus a Quit action. When a monitor does not answer DDC, give one specific next step: check its on-screen DDC/CI setting or try a direct USB-C/DisplayPort cable.

## Architecture

- `MonitorBarApp` owns one `NSStatusItem` and one `NSPopover` hosting `QuickPanel`. `LSUIElement` prevents a Dock icon. The item visibility follows the current external-display list.
- `DisplayDiscovery` uses `CGGetOnlineDisplayList` and `CGDisplayRegisterReconfigurationCallback`; it publishes physical external IDs and their identity. It ignores the callback's begin-configuration phase and refreshes after completion on the main actor.
- `DDCBridge` is a small C/Objective-C target that resolves the private `IOAVService` functions at runtime, enumerates external `DCPAVServiceProxy` nodes, obtains EDID, and performs MCCS Get/Set VCP packets on a serialized queue. Its public functions report actual success/failure and values.
- `MonitorModel` matches each CoreGraphics display to its DDC service by vendor/product/serial. With one external display and one service it may use that pairing when EDID is unavailable; with multiple ambiguous displays it disables control instead of risking the wrong screen. It owns read/write state and keeps UI responsive.
- The Swift package builds the executable. `scripts/build-app.sh` wraps it in a local `.app` bundle with `LSUIElement`; no installer, launch-at-login helper, or external package dependency in this version.

## Failure behavior

- Disconnect during a pending write cancels that write and closes the panel.
- A missing private symbol, unmatched EDID, invalid VCP response, zero maximum, failed write, or failed readback disables the affected control and shows a short reason. No optimistic success label.
- A write never targets built-in or virtual displays. Values are clamped to `0...maximum`.
- Quit from the panel stops the monitor listener and releases the DDC service references.

## Verification

- Unit checks for display-to-service matching, ambiguous-display rejection, value conversion, and stale-write cancellation.
- `swift test` and `swift build -c release` must pass.
- Launch the local app, inspect dark/light layout and panel interactions, verify status item presence with the Fazeon connected. Disconnect/reconnect behavior requires a physical test if the cable can be safely handled during acceptance.
- Repeat a reversible 58→52→58 DDC write/readback through the app. Distinguish protocol success from a visibly observed brightness change.

## Sources and boundaries

- Apple documentation: [display callbacks](https://developer.apple.com/documentation/coregraphics/cgdisplayreconfigurationcallback), [status item visibility](https://developer.apple.com/documentation/appkit/nsstatusitem/isvisible), [Liquid Glass](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views).
- Reference code inspected: [traderGK/OpenDisplay](https://github.com/traderGK/OpenDisplay) (MIT), [AppleSiliconDDC](https://github.com/waydabber/AppleSiliconDDC) (MIT), [ScreenControl](https://github.com/pushbrands/ScreenControl) (MIT), [aquitaine/OpenDisplay](https://github.com/aquitaine/OpenDisplay) (GPL-3.0-or-later). No GPL source or assets are copied into MonitorBar. The private DDC API can change across macOS releases; this personal app is not designed for Mac App Store distribution.
