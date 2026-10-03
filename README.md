# MonitorBar

MonitorBar is a macOS menu bar app for external monitor brightness through DDC/CI. It sends hardware commands when the display responds; it does not dim the screen with an overlay. The menu bar icon appears while an external display is connected and disappears when none is connected.

## Download

Download the latest signed and notarized universal app from [GitHub Releases](https://github.com/berkinefeavci/MonitorBar/releases). Unzip it, move `MonitorBar.app` to Applications, and open it. The menu bar icon appears when an external display is connected. The interface is currently in Turkish.

## Compatibility

- macOS 12 or newer, on Apple Silicon or Intel MacBooks. The build script creates one universal app containing both architectures.
- The panel uses Liquid Glass on macOS 26 or newer. Earlier versions use a standard macOS material. Liquid Glass buttons are available only on macOS 26 or newer; the setting is hidden on older versions.
- External hardware brightness and contrast require a compatible monitor, cable or adapter, and macOS DDC/CI transport. The controls are disabled when the monitor does not return a valid response.
- Built-in display brightness, keyboard backlight, and Night Shift appear only when the Mac exposes working controls. Keyboard backlight color cannot be changed by this app; its color picker changes the slider color.
- Apple Silicon DDC/CI was verified on a Fazeon X27F166QB. Intel DDC/CI compiles and its protocol tests pass under Rosetta, but has not been tested on Intel hardware. Compatibility with every MacBook or monitor is not established.

## Build and run

Install Xcode with the macOS SDK and command-line tools. This repository was built with Xcode 27.0.

```bash
./scripts/build-app.sh
open dist/MonitorBar.app
```

The script builds both architectures for macOS 12 and ad-hoc signs `dist/MonitorBar.app` for local use. The app in GitHub Releases is separately Developer ID signed and Apple notarized.

The first slider controls the selected external monitor. The built-in slider controls the Mac display when available. “İki ekranı birlikte ayarla” changes both displays together and follows built-in brightness changes of at least 2 percentage points. The keyboard slider appears only on supported MacBooks. Expand “Diğer kontroller” for contrast and current input information. The input is read only.

Open the upper-right **Ayarlar** button to apply one color to all slider bars or choose each color separately, enable or disable glass buttons on macOS 26+, configure timed brightness, open Night Shift settings, refresh the connection, or quit. These choices stay in the settings screen so the main panel stays compact. On macOS 12, the Night Shift settings link opens the legacy Displays preferences pane.

“Saatle parlaklık” is off by default. Once enabled, it sets the selected external display and built-in display at each configured period change, when the app starts, and after display reconnection. Manual changes remain until the next period change or reconnection. MonitorBar must remain running. “Sıcak ışık şimdi” controls macOS Night Shift while preserving its system schedule.

If no external display is connected, MonitorBar stays running with its menu bar icon hidden. Reconnect a display to show it again; use Activity Monitor to quit it while no icon is visible.

## Verification

```bash
swift test --triple arm64-apple-macosx12.0 --scratch-path .build/arm64
swift build --build-tests --triple x86_64-apple-macosx12.0 --scratch-path .build/x86_64
arch -x86_64 xcrun xctest .build/x86_64/out/Products/Debug/MonitorBarTests.xctest
.build/arm64/out/Products/Release/MonitorBar --probe
```

Tests cover display-to-DDC matching, value conversion, DDC packets and replies, pending-write cancellation, and overnight schedule boundaries. On the Fazeon X27F166QB, an independent DDC read confirmed brightness changes made by MonitorBar and restoration of the prior value. Independent system reads also confirmed built-in display and keyboard backlight changes on the tested MacBook. These checks establish reported values, not measured light output.

## Limits

- Apple Silicon DDC uses the private `IOAVService` interface. Built-in brightness, keyboard backlight, and Night Shift also use private Apple interfaces. A macOS update can change or remove them. The app is not prepared for Mac App Store distribution.
- Intel DDC uses the IOKit framebuffer I2C interface. Some Macs, adapters, and display links expose no usable I2C bus. Intel hardware testing is still required before claiming Intel monitor support.
- macOS Control Center does not offer a public third-party continuous brightness slider or a way to extend Apple's Displays slider. MonitorBar uses a menu bar panel for continuous control.
- Input switching, software dimming, automatic launch at login, and interception of keyboard brightness keys are outside this version.
- Cable disconnect and reconnect were not physically tested during this build. The app listens for macOS display-change and wake events and updates menu bar visibility from the external display list.

## Source research

The DDC approach was informed by [traderGK/OpenDisplay](https://github.com/traderGK/OpenDisplay) (MIT), [AppleSiliconDDC](https://github.com/waydabber/AppleSiliconDDC) (MIT), [ScreenControl](https://github.com/pushbrands/ScreenControl) (MIT), and [aquitaine/OpenDisplay](https://github.com/aquitaine/OpenDisplay) (GPL-3.0-or-later). MonitorBar is a separate source tree and contains no GPL source or assets.

Night Shift behavior was compared with [Luma](https://github.com/heymykro/luma) (MIT). No Luma code was copied.

## License

MIT. See [LICENSE](LICENSE).
