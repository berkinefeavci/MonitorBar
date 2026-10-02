# MonitorBar

A compact macOS menu bar control for external-display hardware brightness. This is a local, personal build. It uses DDC/CI commands, not a dark overlay or gamma adjustment.

## Build and run

Requires macOS 26+ and Xcode 26+ on Apple Silicon. On the current Mac, Xcode 27.0 builds it.

```bash
./scripts/build-app.sh
open dist/MonitorBar.app
```

The display icon appears only while an external monitor is connected. Click it to open the Quick Panel. Drag the brightness slider or choose Gece 25%, Çalışma 60%, or Tam 100%. The secondary area shows contrast when the monitor supports it and reads the input without switching it. The upper-right button shows DDC diagnostics, Refresh, and Quit. If no external monitor is connected, the hidden menu bar app stays alive for reconnection; use Activity Monitor to quit it.

Read-only hardware diagnostic:

```bash
.build/release/MonitorBar --probe
```

`swift test` checks display-to-DDC matching, value conversion, DDC packets, reply validation, and pending-write cancellation. On the Fazeon X27F166QB, MonitorBar's own slider changed VCP `0x10` from `58/100` to `52/100`; an independent read returned `52/100`. The slider restored `58/100`, also confirmed by an independent read. This verifies the monitor's hardware protocol state. Perceived light-output change still needs direct observation.

## Limits

- DDC/CI support depends on the monitor, cable/adapter, and macOS. The app disables hardware controls when a valid response is unavailable.
- DDC uses the private `IOAVService` interface. A macOS update may change it. This personal build is not intended for Mac App Store distribution.
- Input switching, software dimming, auto-start, and keyboard brightness keys are outside this first version.
- Cable disconnect/reconnect and menu bar item visibility were not physically tested during this build. The app listens for macOS display-change and wake events and updates status item visibility from the external display list.

## Source research

The DDC approach was informed by [traderGK/OpenDisplay](https://github.com/traderGK/OpenDisplay) (MIT), [AppleSiliconDDC](https://github.com/waydabber/AppleSiliconDDC) (MIT), [ScreenControl](https://github.com/pushbrands/ScreenControl) (MIT), and [aquitaine/OpenDisplay](https://github.com/aquitaine/OpenDisplay) (GPL-3.0-or-later). MonitorBar is a separate source tree and contains no GPL source or assets.
