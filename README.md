# MonitorBar

A compact macOS menu bar control for external-display hardware brightness. This is a local, personal build. It uses DDC/CI commands, not a dark overlay or gamma adjustment.

## Build and run

Requires macOS 26+ and Xcode 26+ on Apple Silicon. On the current Mac, Xcode 27.0 builds it.

```bash
./scripts/build-app.sh
open dist/MonitorBar.app
```

The display icon appears only while an external monitor is connected. Click it to open the near-black glass Quick Panel. The first slider controls the selected external monitor through DDC/CI. The second controls the Mac's built-in display through DisplayServices. “İki ekranı birlikte ayarla” applies subsequent slider changes to both. It also polls the built-in brightness once per second and mirrors changes of at least 2 percentage points to the external display. This was verified with the native brightness slider in macOS Displays settings; a direct Control Center drag and automatic ambient-light changes have not been tested separately. The keyboard slider controls the MacBook keyboard backlight when supported. “Diğer kontroller” has separate saved color pickers for the external, built-in, keyboard, and contrast slider bars. It also shows contrast when supported and reads the input without switching it. The upper-right button shows diagnostics, Refresh, and Quit. If no external monitor is connected, the hidden menu bar app stays alive for reconnection; use Activity Monitor to quit it.

“Saatle parlaklık” is off by default. In “Diğer kontroller,” set the night/day start times and brightness values, then enable it. It applies the selected external monitor and built-in display at the start of each period, when enabled or restarted, and after display reconnection. Manual changes remain until the next period change or reconnection. MonitorBar must remain running. “Night Shift ayarları…” opens macOS Displays settings, where macOS provides its own warm-color schedule.

Read-only hardware diagnostic:

```bash
.build/release/MonitorBar --probe
```

`swift test` checks display-to-DDC matching, value conversion, DDC packets, reply validation, pending-write cancellation, and overnight schedule boundaries. On the Fazeon X27F166QB, MonitorBar's own slider changed VCP `0x10` from `58/100` to `52/100`; an independent read returned `52/100`. The slider restored `58/100`, also confirmed by an independent read. The built-in display was read at 65%, changed to 62%, independently read at 62%, and restored to 65%. Linked control and the schedule set both displays to 60% and 70% respectively; independent reads confirmed both, then their prior levels were restored. Protocol readback does not prove perceived light output.

On the current MacBook, the keyboard backlight was read at 49%, set to 40% with the app slider, and independently read at 40%. It was set back to 49%; macOS automatic adjustment subsequently changed it to 52%. This verifies system readback, not perceived light output. The automatic keyboard backlight setting remains under macOS control and may change the level after a manual adjustment.

## Limits

- DDC/CI support depends on the monitor, cable/adapter, and macOS. The app disables hardware controls when a valid response is unavailable.
- DDC uses the private `IOAVService` interface. A macOS update may change it. This personal build is not intended for Mac App Store distribution.
- Input switching, software dimming, auto-start, and interception of keyboard brightness keys are outside this version.
- macOS Control Center accepts third-party WidgetKit buttons and toggles, but its public ControlWidget templates do not provide a custom brightness slider or a way to extend Apple's Displays slider. MonitorBar uses a menu bar panel for continuous control.
- Built-in brightness, keyboard backlight, and external DDC use Apple private interfaces. A macOS update may change them. Built-in keyboard lighting has one brightness level; MonitorBar color pickers change only the on-screen slider colors.
- Cable disconnect/reconnect and menu bar item visibility were not physically tested during this build. The app listens for macOS display-change and wake events and updates status item visibility from the external display list.

## Source research

The DDC approach was informed by [traderGK/OpenDisplay](https://github.com/traderGK/OpenDisplay) (MIT), [AppleSiliconDDC](https://github.com/waydabber/AppleSiliconDDC) (MIT), [ScreenControl](https://github.com/pushbrands/ScreenControl) (MIT), and [aquitaine/OpenDisplay](https://github.com/aquitaine/OpenDisplay) (GPL-3.0-or-later). MonitorBar is a separate source tree and contains no GPL source or assets.
