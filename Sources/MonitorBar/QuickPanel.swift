import AppKit
import SwiftUI

struct QuickPanel: View {
    @ObservedObject var model: MonitorModel
    var onSizeChange: (CGSize) -> Void = { _ in }
    @AppStorage("externalBarColor") private var externalBarColor = "#3489FC"
    @AppStorage("builtInBarColor") private var builtInBarColor = "#3489FC"
    @AppStorage("keyboardBarColor") private var keyboardBarColor = "#3489FC"
    @AppStorage("contrastBarColor") private var contrastBarColor = "#3489FC"
    @AppStorage("glassButtons") private var glassButtons = true
    @State private var showSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showSettings { settings } else { controls }
        }
        .padding(18)
        .frame(width: 350)
        .fixedSize(horizontal: false, vertical: true)
        .modifier(PanelBackground())
        .preferredColorScheme(.dark)
        .background(GeometryReader { geometry in
            Color.clear.preference(key: PanelSizeKey.self, value: geometry.size)
        })
        .onPreferenceChange(PanelSizeKey.self, perform: onSizeChange)
    }

    private var screenCount: Int { model.displays.count + (model.builtInDisplay == nil ? 0 : 1) }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "display.2")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.blue)
                    .frame(width: 38, height: 38)
                    .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Displays")
                        .font(.system(size: 15, weight: .semibold))
                    Group {
                        if screenCount == 1 { Text("1 display connected") }
                        else { Text("\(screenCount) displays connected") }
                    }
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
                if model.canLinkBrightness {
                    HStack(spacing: 8) {
                        Text("Link")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Toggle("Adjust all together", isOn: Binding(
                            get: { model.linkBrightness },
                            set: { model.setLinkBrightness($0) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .accessibilityLabel("Adjust all together")
                    }
                    .help("Control every display with one slider")
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                if model.linkBrightness && model.canLinkBrightness {
                    displayRow(title: String(localized: "All displays"), icon: "display.2", badge: nil,
                               value: { model.linkedBrightnessValue },
                               enabled: !model.isLoading,
                               tint: barColor(externalBarColor)) { model.setAllBrightness($0) }
                } else {
                if let builtInDisplay = model.builtInDisplay {
                    displayRow(title: builtInDisplay.name, icon: "laptopcomputer", badge: nil,
                               value: { model.builtInBrightnessValue },
                               enabled: model.canChangeBuiltInBrightness,
                               tint: barColor(builtInBarColor)) { model.setBuiltInBrightness($0) }
                }
                ForEach(model.displays, id: \.id) { item in
                    displayRow(title: title(item), icon: icon(item),
                               badge: model.softwareDimmed.contains(item.id) ? String(localized: "Software") : nil,
                               value: { model.brightness(of: item.id) },
                               enabled: model.canChangeBrightness(of: item.id),
                               tint: barColor(externalBarColor)) { model.setBrightness($0, of: item.id) }
                }
                }
            }
            .padding(.top, 18)

            if model.canChangeKeyboardBrightness {
                Divider().padding(.top, 14)
                displayRow(title: String(localized: "Keyboard backlight"), icon: "keyboard", badge: nil,
                           value: { model.keyboardBrightnessValue },
                           enabled: true,
                           tint: barColor(keyboardBarColor)) { model.setKeyboardBrightness($0) }
                    .padding(.top, 13)
            }

            Divider().padding(.top, 16)

            if let message = model.errorMessage {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .padding(.top, 10)
            }

            if model.canChangeContrast || model.probes.contains(where: { $0.input != nil }) {
                secondaryControls.padding(.top, 13)
                Divider().padding(.top, 14)
            }

            Button { showSettings = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12))
                        .frame(width: 16)
                    Text("Settings")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 12, weight: .medium))
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 5)
        }
    }

    private func displayRow(title: String, icon: String, badge: String?, value: @escaping () -> Double?,
                            enabled: Bool, tint: Color,
                            set: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let badge {
                    Text(badge)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(.white.opacity(0.08), in: Capsule())
                }
                Spacer(minLength: 8)
                Text(value().map { "\(Int($0.rounded()))%" } ?? "—")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 12, weight: .medium))
            brightnessSlider(value: Binding(get: { value() ?? 0 }, set: set),
                             enabled: enabled && value() != nil, label: String(localized: "\(title) brightness"), tint: tint)
        }
    }

    private func title(_ display: DisplayIdentity) -> String {
        guard display.isVirtual else { return display.name }
        if display.name.localizedCaseInsensitiveContains("Sidecar") { return "iPad" }
        return display.name.replacingOccurrences(of: " (AirPlay)", with: "")
    }

    private func icon(_ display: DisplayIdentity) -> String {
        guard display.isVirtual else { return "display" }
        return display.name.localizedCaseInsensitiveContains("Sidecar") ? "ipad.landscape" : "airplayvideo"
    }

    private func brightnessSlider(value: Binding<Double>, enabled: Bool, label: String,
                                  tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "sun.min.fill")
                .font(.system(size: 11))
                .frame(width: 16)
            ColorSlider(value: value, tint: tint, enabled: enabled, label: label)
                .frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32)
            Image(systemName: "sun.max.fill")
                .font(.system(size: 16))
                .frame(width: 16)
        }
        .foregroundStyle(.secondary)
    }

    private var secondaryControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.canChangeContrast {
                HStack(spacing: 8) {
                    Image(systemName: "circle.lefthalf.filled")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Text("Contrast")
                    Spacer()
                    Text("\(Int(model.contrastValue.rounded()))%")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 12, weight: .medium))
                HStack(spacing: 10) {
                    Image(systemName: "circle.lefthalf.filled")
                        .font(.system(size: 11))
                        .frame(width: 16)
                    ColorSlider(value: Binding(
                        get: { model.contrastValue },
                        set: { model.setContrast($0) }
                    ), tint: barColor(contrastBarColor), enabled: true, label: String(localized: "Contrast"))
                    .frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32)
                    Image(systemName: "circle.righthalf.filled")
                        .font(.system(size: 16))
                        .frame(width: 16)
                }
                .foregroundStyle(.secondary)
            }
            ForEach(model.probes.filter { $0.input != nil }, id: \.display.id) { probe in
                HStack {
                    Text("\(title(probe.display)) input")
                        .lineLimit(1)
                    Spacer()
                    Text(inputName(probe.input ?? 0))
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 12, weight: .medium))
            }
        }
    }

    private func barColor(_ hex: String) -> Color {
        guard hex.count == 7, hex.first == "#",
              let rgb = UInt32(hex.dropFirst(), radix: 16) else { return .blue }
        return Color(red: Double((rgb >> 16) & 0xFF) / 255,
                     green: Double((rgb >> 8) & 0xFF) / 255,
                     blue: Double(rgb & 0xFF) / 255)
    }

    private func colorBinding(_ hex: Binding<String>) -> Binding<Color> {
        Binding(
            get: { barColor(hex.wrappedValue) },
            set: { color in
                guard let rgb = NSColor(color).usingColorSpace(.deviceRGB) else { return }
                func byte(_ component: CGFloat) -> Int {
                    Int((min(1, max(0, component)) * 255).rounded())
                }
                hex.wrappedValue = String(format: "#%02X%02X%02X",
                                          byte(rgb.redComponent), byte(rgb.greenComponent),
                                          byte(rgb.blueComponent))
            }
        )
    }

    private var allBarColors: Binding<String> {
        Binding(
            get: { externalBarColor },
            set: { color in
                externalBarColor = color
                builtInBarColor = color
                keyboardBarColor = color
                contrastBarColor = color
            }
        )
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button { showSettings = false } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                Spacer()
                Text("Settings")
                    .font(.system(size: 15, weight: .semibold))
            }
            Divider().padding(.vertical, 12)
            VStack(alignment: .leading, spacing: 10) {
                if #available(macOS 13, *) {
                    Text("General")
                        .font(.system(size: 12, weight: .semibold))
                    Toggle("Open at login", isOn: Binding(
                        get: { model.launchAtLogin },
                        set: { model.setLaunchAtLogin($0) }
                    ))
                    Divider().padding(.vertical, 5)
                }
                Text("Appearance")
                    .font(.system(size: 12, weight: .semibold))
                ColorPicker("Apply to all sliders", selection: colorBinding(allBarColors), supportsOpacity: false)
                Divider().padding(.vertical, 2)
                ColorPicker("External display slider", selection: colorBinding($externalBarColor), supportsOpacity: false)
                if model.builtInDisplay != nil {
                    ColorPicker("Built-in display slider", selection: colorBinding($builtInBarColor), supportsOpacity: false)
                }
                if model.canChangeKeyboardBrightness {
                    ColorPicker("Keyboard backlight slider", selection: colorBinding($keyboardBarColor), supportsOpacity: false)
                }
                if model.canChangeContrast {
                    ColorPicker("Contrast slider", selection: colorBinding($contrastBarColor), supportsOpacity: false)
                }
                if #available(macOS 26, *) {
                    Toggle("Glass buttons", isOn: $glassButtons)
                }

                Divider().padding(.vertical, 5)
                Text("Display color")
                    .font(.system(size: 12, weight: .semibold))
                if let nightShiftWarm = model.nightShiftWarm {
                    Toggle("Warm light now", isOn: Binding(
                        get: { model.nightShiftWarm ?? nightShiftWarm },
                        set: { model.setNightShiftWarm($0) }
                    ))
                }
                Button("Night Shift settings…") { openDisplaySettings() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)

                Divider().padding(.vertical, 5)
                Text("Help and updates")
                    .font(.system(size: 12, weight: .semibold))
                Link("Report a bug", destination: URL(string: "https://github.com/berkinefeavci/PanelLight/issues/new?template=bug_report.yml")!)
                Link("Suggest a feature", destination: URL(string: "https://github.com/berkinefeavci/PanelLight/issues/new?template=feature_request.yml")!)
                Link("Check for updates", destination: URL(string: "https://github.com/berkinefeavci/PanelLight/releases/latest")!)
                Text("Links open in your browser. No diagnostic data is sent automatically.")
                    .foregroundStyle(.secondary)

                Divider().padding(.vertical, 5)
                Text("Connection")
                    .font(.system(size: 12, weight: .semibold))
                ForEach(model.displays, id: \.id) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Label(title(item), systemImage: icon(item))
                            .lineLimit(1)
                        Text(model.softwareDimmed.contains(item.id) ?
                                (item.isVirtual ? String(localized: "Dimmed in software; this display has no hardware brightness.") :
                                    String(localized: "No DDC/CI response, dimmed in software. Check the monitor's DDC/CI setting and cable.")) :
                                String(localized: "Hardware brightness over DDC/CI."))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                HStack {
                    Button("Refresh") { model.refresh() }
                        .modifier(PanelButtonStyle(glass: glassButtons))
                    Spacer()
                    Button("Quit") { NSApp.terminate(nil) }
                        .modifier(PanelButtonStyle(glass: glassButtons))
                }
            }
            .font(.system(size: 12))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func openDisplaySettings() {
        let address = if #available(macOS 13, *) {
            "x-apple.systempreferences:com.apple.Displays-Settings.extension"
        } else {
            "x-apple.systempreferences:com.apple.preference.displays"
        }
        if let url = URL(string: address) { NSWorkspace.shared.open(url) }
    }

    private func inputName(_ code: UInt16) -> String {
        switch code {
        case 0x11: "HDMI 1"
        case 0x12: "HDMI 2"
        case 0x0f: "DisplayPort 1"
        case 0x10: "DisplayPort 2"
        default: String(format: "0x%02X", code)
        }
    }
}

private struct PanelBackground: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(.regular.tint(.black.opacity(0.04)),
                                in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        } else {
            content.background(.ultraThinMaterial,
                               in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        }
    }
}

private struct PanelSizeKey: PreferenceKey {
    static let defaultValue = CGSize.zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

private struct PanelButtonStyle: ViewModifier {
    let glass: Bool

    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26, *), glass {
            content.foregroundStyle(.white).buttonStyle(.glass)
        } else {
            content.foregroundStyle(.white).buttonStyle(.bordered)
        }
    }
}

private struct ColorSlider: View {
    @Binding var value: Double
    let tint: Color
    let enabled: Bool
    let label: String
    @State private var isHovered = false
    @State private var isDragging = false
    private let thumbWidth: CGFloat = 34
    private let thumbHeight: CGFloat = 22

    var body: some View {
        GeometryReader { geometry in
            let trackWidth = max(0, geometry.size.width - thumbWidth)
            let progress = min(1, max(0, value / 100))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.18))
                    .frame(width: trackWidth, height: 6)
                    .overlay(alignment: .leading) {
                        Capsule().fill(tint).frame(width: trackWidth * progress, height: 6)
                    }
                    .offset(x: thumbWidth / 2)
                sliderThumb
                    .offset(x: trackWidth * progress)
                    .opacity(isHovered || isDragging ? 1 : 0)
                Slider(value: $value, in: 0...100)
                    .opacity(0.01)
                    .disabled(!enabled)
                    .accessibilityLabel(label)
                    .onHover { isHovered = $0 }
            }
            .frame(height: 32)
            .contentShape(Rectangle())
            .highPriorityGesture(DragGesture(minimumDistance: 0).onChanged { gesture in
                guard enabled, trackWidth > 0 else { return }
                isDragging = true
                value = min(100, max(0, (gesture.location.x - thumbWidth / 2) / trackWidth * 100))
            }.onEnded { _ in isDragging = false })
            .animation(.easeInOut(duration: 0.15), value: isHovered)
            .animation(.easeInOut(duration: 0.15), value: isDragging)
            .opacity(enabled ? 1 : 0.45)
        }
        .frame(height: 32)
    }

    @ViewBuilder private var sliderThumb: some View {
        if #available(macOS 26, *) {
            Capsule()
                .fill(.white.opacity(isDragging ? 0.14 : 0.66))
                .frame(width: thumbWidth, height: thumbHeight)
                .glassEffect(isDragging ? .clear.interactive() : .identity, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(isDragging ? 0.22 : 0.35), lineWidth: 0.7))
                .shadow(color: .black.opacity(0.2), radius: isDragging ? 0 : 4, y: isDragging ? 0 : 3)
        } else {
            Capsule()
                .fill(.white)
                .frame(width: thumbWidth, height: thumbHeight)
                .shadow(color: .black.opacity(0.2), radius: 4, y: 3)
        }
    }
}
