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
    @AppStorage("showKeyboard") private var showKeyboard = true
    @AppStorage("showContrast") private var showContrast = true
    @AppStorage("showNightShift") private var showNightShift = true
    @AppStorage("showInputs") private var showInputs = true
    @State private var showSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showSettings { settings } else { controls }
        }
        .padding(14)
        .frame(width: 300)
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
            HStack(spacing: 9) {
                Image(systemName: "display.2")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.blue)
                    .frame(width: 30, height: 30)
                    .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Displays")
                        .font(.system(size: 13, weight: .semibold))
                    Group {
                        if screenCount == 1 { Text("1 display connected") }
                        else { Text("\(screenCount) displays connected") }
                    }
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
                if model.canLinkBrightness {
                    HStack(spacing: 6) {
                        Text("Link")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Toggle("Adjust all together", isOn: Binding(
                            get: { model.linkBrightness },
                            set: { model.setLinkBrightness($0) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .accessibilityLabel("Adjust all together")
                    }
                    .help("Control every display with one slider")
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                if model.linkBrightness && model.canLinkBrightness {
                    sliderRow(title: String(localized: "All displays"), icon: "display.2",
                              value: { model.linkedBrightnessValue },
                              enabled: true,
                              tint: barColor(externalBarColor)) { model.setAllBrightness($0) }
                } else {
                    if let builtInDisplay = model.builtInDisplay {
                        sliderRow(title: builtInDisplay.name, icon: "laptopcomputer",
                                  value: { model.builtInBrightnessValue },
                                  enabled: model.canChangeBuiltInBrightness,
                                  tint: barColor(builtInBarColor)) { model.setBuiltInBrightness($0) }
                    }
                    ForEach(model.displays, id: \.id) { item in
                        sliderRow(title: title(item), icon: icon(item),
                                  badge: model.softwareDimmed.contains(item.id) ? String(localized: "Software") : nil,
                                  value: { model.brightness(of: item.id) },
                                  enabled: model.canChangeBrightness(of: item.id),
                                  tint: barColor(externalBarColor)) { model.setBrightness($0, of: item.id) }
                    }
                }
            }
            .padding(.top, 12)

            if hasExtraControls {
                Divider().padding(.vertical, 8)
                VStack(alignment: .leading, spacing: 6) {
                    if showKeyboard && model.canChangeKeyboardBrightness {
                        sliderRow(title: String(localized: "Keyboard backlight"), icon: "keyboard",
                                  value: { model.keyboardBrightnessValue },
                                  enabled: true,
                                  tint: barColor(keyboardBarColor)) { model.setKeyboardBrightness($0) }
                    }
                    if showContrast && model.canChangeContrast {
                        sliderRow(title: String(localized: "Contrast"), icon: "circle.lefthalf.filled",
                                  low: "circle.lefthalf.filled", high: "circle.righthalf.filled",
                                  value: { model.contrastValue },
                                  enabled: true,
                                  tint: barColor(contrastBarColor)) { model.setContrast($0) }
                    }
                    if showNightShift, let nightShiftWarm = model.nightShiftWarm {
                        HStack(spacing: 8) {
                            Image(systemName: "moon.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .frame(width: 16)
                            Text("Night Shift")
                            Spacer()
                            Toggle("Night Shift", isOn: Binding(
                                get: { model.nightShiftWarm ?? nightShiftWarm },
                                set: { model.setNightShiftWarm($0) }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                        }
                        .font(.system(size: 12, weight: .medium))
                        .padding(.vertical, 2)
                    }
                    if showInputs {
                        ForEach(model.probes.filter { $0.input != nil }, id: \.display.id) { probe in
                            HStack(spacing: 8) {
                                Image(systemName: "cable.connector")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 16)
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
            }

            if let message = model.errorMessage {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .padding(.top, 8)
            }

            Divider().padding(.top, 8)

            Button { showSettings = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11))
                        .frame(width: 16)
                    Text("Settings")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 12, weight: .medium))
                .padding(.top, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var hasExtraControls: Bool {
        (showKeyboard && model.canChangeKeyboardBrightness) || (showContrast && model.canChangeContrast) ||
            (showNightShift && model.nightShiftWarm != nil) ||
            (showInputs && model.probes.contains { $0.input != nil })
    }

    private func sliderRow(title: String, icon: String, badge: String? = nil,
                           low: String = "sun.min.fill", high: String = "sun.max.fill",
                           value: @escaping () -> Double?, enabled: Bool, tint: Color,
                           set: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let badge {
                    Text(badge)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.white.opacity(0.08), in: Capsule())
                }
                Spacer(minLength: 8)
                Text(value().map { "\(Int($0.rounded()))%" } ?? "—")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 12, weight: .medium))
            HStack(spacing: 8) {
                Image(systemName: low)
                    .font(.system(size: 9))
                    .frame(width: 16)
                ColorSlider(value: Binding(get: { value() ?? 0 }, set: set), tint: tint,
                            enabled: enabled && value() != nil, label: String(localized: "\(title) brightness"))
                    .frame(maxWidth: .infinity)
                Image(systemName: high)
                    .font(.system(size: 13))
                    .frame(width: 16)
            }
            .foregroundStyle(.secondary)
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
                    .font(.system(size: 13, weight: .semibold))
            }
            Divider().padding(.vertical, 8)
            VStack(alignment: .leading, spacing: 6) {
                if #available(macOS 13, *) {
                    sectionTitle("General")
                    Toggle("Open at login", isOn: Binding(
                        get: { model.launchAtLogin },
                        set: { model.setLaunchAtLogin($0) }
                    ))
                    Divider().padding(.vertical, 3)
                }

                sectionTitle("Show in panel")
                Toggle("Keyboard backlight", isOn: $showKeyboard)
                Toggle("Contrast", isOn: $showContrast)
                Toggle("Night Shift", isOn: $showNightShift)
                Toggle("Monitor inputs", isOn: $showInputs)
                Text("Hiding a control only removes it from the panel. The light or setting stays as it is.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Divider().padding(.vertical, 3)

                sectionTitle("Appearance")
                colorRow("Apply to all sliders", colorBinding(allBarColors))
                colorRow("External display slider", colorBinding($externalBarColor))
                if model.builtInDisplay != nil {
                    colorRow("Built-in display slider", colorBinding($builtInBarColor))
                }
                if model.canChangeKeyboardBrightness {
                    colorRow("Keyboard backlight slider", colorBinding($keyboardBarColor))
                }
                if model.canChangeContrast {
                    colorRow("Contrast slider", colorBinding($contrastBarColor))
                }
                if #available(macOS 26, *) {
                    Toggle("Glass buttons", isOn: $glassButtons)
                }
                Button("Night Shift settings…") { openDisplaySettings() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                Divider().padding(.vertical, 3)

                sectionTitle("Connection")
                ForEach(model.displays, id: \.id) { item in
                    VStack(alignment: .leading, spacing: 1) {
                        Label(title(item), systemImage: icon(item))
                            .lineLimit(1)
                        Text(model.softwareDimmed.contains(item.id) ?
                                (item.isVirtual ? String(localized: "Dimmed in software; this display has no hardware brightness.") :
                                    String(localized: "No DDC/CI response, dimmed in software. Check the monitor's DDC/CI setting and cable.")) :
                                String(localized: "Hardware brightness over DDC/CI."))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Divider().padding(.vertical, 3)

                sectionTitle("Help and updates")
                HStack(spacing: 12) {
                    Link("Report a bug", destination: URL(string: "https://github.com/berkinefeavci/PanelLight/issues/new?template=bug_report.yml")!)
                    Link("Suggest a feature", destination: URL(string: "https://github.com/berkinefeavci/PanelLight/issues/new?template=feature_request.yml")!)
                }
                Link("Check for updates", destination: URL(string: "https://github.com/berkinefeavci/PanelLight/releases/latest")!)
                Text("Links open in your browser. No diagnostic data is sent automatically.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Refresh") { model.refresh() }
                        .modifier(PanelButtonStyle(glass: glassButtons))
                    Spacer()
                    Button("Quit") { NSApp.terminate(nil) }
                        .modifier(PanelButtonStyle(glass: glassButtons))
                }
                .controlSize(.small)
                .padding(.top, 4)
            }
            .font(.system(size: 11))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func colorRow(_ key: LocalizedStringKey, _ color: Binding<Color>) -> some View {
        HStack {
            Text(key)
            Spacer()
            ColorPicker(key, selection: color, supportsOpacity: false)
                .labelsHidden()
                .controlSize(.small)
        }
    }

    private func sectionTitle(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
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
    private let thumbWidth: CGFloat = 28
    private let thumbHeight: CGFloat = 18

    var body: some View {
        GeometryReader { geometry in
            let trackWidth = max(0, geometry.size.width - thumbWidth)
            let progress = min(1, max(0, value / 100))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.18))
                    .frame(width: trackWidth, height: 5)
                    .overlay(alignment: .leading) {
                        Capsule().fill(tint).frame(width: trackWidth * progress, height: 5)
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
            .frame(height: 24)
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
        .frame(height: 24)
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
