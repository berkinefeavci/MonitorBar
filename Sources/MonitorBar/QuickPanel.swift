import AppKit
import SwiftUI

struct QuickPanel: View {
    @ObservedObject var model: MonitorModel
    var onSizeChange: (CGSize) -> Void = { _ in }
    @AppStorage("externalBarColor") private var externalBarColor = "#36DADD"
    @AppStorage("builtInBarColor") private var builtInBarColor = "#36DADD"
    @AppStorage("keyboardBarColor") private var keyboardBarColor = "#36DADD"
    @AppStorage("contrastBarColor") private var contrastBarColor = "#36DADD"
    @AppStorage("glassButtons") private var glassButtons = true
    @State private var showDetails = false
    @State private var showSettings = false

    private var display: DisplayIdentity? { model.selectedProbe?.display ?? model.displays.first }
    private var subtitle: String {
        guard let display else { return "Harici ekran" }
        return "\(CGDisplayPixelsWide(display.id)) × \(CGDisplayPixelsHigh(display.id))"
    }

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

    private var controls: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "display")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(.blue)
                    .frame(width: 38, height: 38)
                    .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 2) {
                    Text(display?.name ?? "Harici ekran")
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                Button { showSettings = true } label: {
                    Image(systemName: "slider.horizontal.3")
                        .frame(width: 30, height: 30)
                }
                .modifier(PanelButtonStyle(glass: glassButtons))
                .clipShape(Circle())
                .accessibilityLabel("Ayarlar")
            }

            if model.displays.count > 1 {
                Picker("Ekran", selection: Binding(
                    get: { model.selectedID ?? 0 },
                    set: { model.selectDisplay($0) }
                )) {
                    ForEach(model.displays, id: \.id) { item in
                        Text(item.name).tag(item.id)
                    }
                }
                .padding(.top, 12)
            }

            HStack(alignment: .firstTextBaseline) {
                Text(model.linkBrightness && model.canChangeBuiltInBrightness ? "İki ekranın parlaklığı" : "Parlaklık")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text("\(Int(model.brightnessValue.rounded()))%")
                    .font(.system(size: 24, weight: .medium))
                    .monospacedDigit()
            }
            .padding(.top, 25)

            brightnessSlider(
                value: Binding(get: { model.brightnessValue }, set: { model.setBrightness($0) }),
                enabled: model.canChangeBrightness,
                label: model.linkBrightness && model.canChangeBuiltInBrightness ? "İki ekranın parlaklığı" : "Monitörün donanım parlaklığı",
                tint: barColor(externalBarColor)
            )
            .padding(.top, 8)

            if let builtInDisplay = model.builtInDisplay {
                Divider().padding(.top, 16)
                if !model.linkBrightness {
                    HStack {
                        Label(builtInDisplay.name, systemImage: "laptopcomputer")
                            .lineLimit(1)
                        Spacer()
                        Text(model.builtInBrightnessValue.map { "\(Int($0.rounded()))%" } ?? "—")
                            .monospacedDigit()
                    }
                    .font(.system(size: 12, weight: .medium))
                    .padding(.top, 13)
                    brightnessSlider(
                        value: Binding(
                            get: { model.builtInBrightnessValue ?? 0 },
                            set: { model.setBuiltInBrightness($0) }
                        ),
                        enabled: model.canChangeBuiltInBrightness,
                        label: "Yerleşik ekran parlaklığı",
                        tint: barColor(builtInBarColor)
                    )
                    .padding(.top, 6)
                }
                HStack {
                    Text("İki ekranı birlikte ayarla")
                    Spacer()
                    Toggle("İki ekranı birlikte ayarla", isOn: Binding(
                        get: { model.linkBrightness },
                        set: { model.setLinkBrightness($0) }
                    ))
                    .labelsHidden()
                    .accessibilityLabel("İki ekranı birlikte ayarla")
                }
                .font(.system(size: 12))
                .toggleStyle(.switch)
                .disabled(!model.canChangeBrightness || !model.canChangeBuiltInBrightness)
                .padding(.top, 9)
            }

            if model.canChangeKeyboardBrightness {
                Divider().padding(.top, 16)
                HStack {
                    Label("Klavye ışığı", systemImage: "keyboard")
                    Spacer()
                    Text("\(Int((model.keyboardBrightnessValue ?? 0).rounded()))%")
                        .monospacedDigit()
                }
                .font(.system(size: 12, weight: .medium))
                .padding(.top, 13)
                brightnessSlider(
                    value: Binding(
                        get: { model.keyboardBrightnessValue ?? 0 },
                        set: { model.setKeyboardBrightness($0) }
                    ),
                    enabled: true,
                    label: "Klavye ışığı parlaklığı",
                    tint: barColor(keyboardBarColor),
                    lowSymbol: "keyboard",
                    highSymbol: "sun.max.fill"
                )
                .padding(.top, 6)
                if model.keyboardAutoBrightnessEnabled != nil {
                    Toggle("Klavye ışığını sabit tut", isOn: Binding(
                        get: { model.keyboardAutoBrightnessEnabled == false },
                        set: { model.setKeyboardBrightnessPinned($0) }
                    ))
                    .font(.system(size: 11))
                    .toggleStyle(.switch)
                    .padding(.top, 7)
                    .help("Açıkken macOS'un otomatik klavye ışığı kapanır.")
                }
            }

            Divider().padding(.top, 16)

            if let message = model.errorMessage ?? model.selectedProbe?.issue {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .padding(.top, 10)
            }

            Button {
                withAnimation(.easeInOut(duration: 0.18)) { showDetails.toggle() }
            } label: {
                HStack {
                    Text("Diğer kontroller")
                    Spacer()
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(showDetails ? 180 : 0))
                }
                .font(.system(size: 12, weight: .medium))
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 7)

            if showDetails { secondaryControls.padding(.top, 6) }
        }
    }

    private func preset(_ title: String, value: Double) -> some View {
        Button(title) { model.setBrightness(value) }
            .font(.system(size: 11, weight: .medium))
            .modifier(PanelButtonStyle(glass: glassButtons))
            .frame(maxWidth: .infinity)
            .disabled(!model.canChangeBrightness)
            .accessibilityLabel("Parlaklık \(title)")
    }

    private func brightnessSlider(value: Binding<Double>, enabled: Bool, label: String,
                                  tint: Color, lowSymbol: String = "sun.min.fill",
                                  highSymbol: String = "sun.max.fill") -> some View {
        HStack(spacing: 10) {
            Image(systemName: lowSymbol)
                .font(.system(size: 11))
                .frame(width: 16)
            ColorSlider(value: value, tint: tint, enabled: enabled, label: label)
            Image(systemName: highSymbol)
                .font(.system(size: 16))
                .frame(width: 16)
        }
        .foregroundStyle(.secondary)
    }

    private var secondaryControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                preset("Gece 25%", value: 25)
                preset("Çalışma 60%", value: 60)
                preset("Tam 100%", value: 100)
            }
            if model.canChangeContrast {
                HStack {
                    Text("Kontrast")
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
                    ), tint: barColor(contrastBarColor), enabled: true,
                       label: "Monitör kontrastı")
                    Image(systemName: "circle.righthalf.filled")
                        .font(.system(size: 16))
                        .frame(width: 16)
                }
                .foregroundStyle(.secondary)
            }
            if let input = model.selectedProbe?.input {
                HStack {
                    Text("Giriş")
                    Spacer()
                    Text(inputName(input))
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 12, weight: .medium))
                .padding(.top, model.canChangeContrast ? 6 : 0)
            }
        }
    }

    private func barColor(_ hex: String) -> Color {
        guard hex.count == 7, hex.first == "#",
              let rgb = UInt32(hex.dropFirst(), radix: 16) else { return .cyan }
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

    private func scheduleTime(night: Bool) -> Binding<Date> {
        Binding(
            get: {
                let minutes = night ? model.nightStart : model.nightEnd
                return Calendar.current.date(byAdding: .minute, value: minutes,
                                             to: Calendar.current.startOfDay(for: Date())) ?? Date()
            },
            set: {
                let hour = Calendar.current.component(.hour, from: $0)
                let minute = Calendar.current.component(.minute, from: $0)
                model.setScheduleTime(hour * 60 + minute, night: night)
            }
        )
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button { showSettings = false } label: {
                    Label("Geri", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                Spacer()
                Text("Ayarlar")
                    .font(.system(size: 15, weight: .semibold))
            }
            Divider().padding(.vertical, 12)
            VStack(alignment: .leading, spacing: 10) {
                Text("Görünüm")
                    .font(.system(size: 12, weight: .semibold))
                ColorPicker("Tüm çubuklara uygula", selection: colorBinding(allBarColors), supportsOpacity: false)
                Divider().padding(.vertical, 2)
                ColorPicker("Harici ekran çubuğu", selection: colorBinding($externalBarColor), supportsOpacity: false)
                if model.builtInDisplay != nil {
                    ColorPicker("Yerleşik ekran çubuğu", selection: colorBinding($builtInBarColor), supportsOpacity: false)
                }
                if model.canChangeKeyboardBrightness {
                    ColorPicker("Klavye ışığı çubuğu", selection: colorBinding($keyboardBarColor), supportsOpacity: false)
                }
                if model.canChangeContrast {
                    ColorPicker("Kontrast çubuğu", selection: colorBinding($contrastBarColor), supportsOpacity: false)
                }
                if #available(macOS 26, *) {
                    Toggle("Cam düğmeler", isOn: $glassButtons)
                }

                Divider().padding(.vertical, 5)
                Text("Otomasyon")
                    .font(.system(size: 12, weight: .semibold))
                Toggle("Saatle parlaklık", isOn: Binding(
                    get: { model.scheduleEnabled },
                    set: { model.setScheduleEnabled($0) }
                ))
                if model.scheduleEnabled {
                    DatePicker("Gece başlar", selection: scheduleTime(night: true), displayedComponents: .hourAndMinute)
                    Stepper("Gece \(Int(model.nightBrightness))%", value: Binding(
                        get: { model.nightBrightness },
                        set: { model.setScheduleBrightness($0, night: true) }
                    ), in: 0...100, step: 5)
                    DatePicker("Gündüz başlar", selection: scheduleTime(night: false), displayedComponents: .hourAndMinute)
                    Stepper("Gündüz \(Int(model.dayBrightness))%", value: Binding(
                        get: { model.dayBrightness },
                        set: { model.setScheduleBrightness($0, night: false) }
                    ), in: 0...100, step: 5)
                }
                if let nightShiftWarm = model.nightShiftWarm {
                    Toggle("Sıcak ışık şimdi", isOn: Binding(
                        get: { model.nightShiftWarm ?? nightShiftWarm },
                        set: { model.setNightShiftWarm($0) }
                    ))
                }
                Button("Night Shift ayarları…") { openDisplaySettings() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)

                Divider().padding(.vertical, 5)
                Text("Yardım ve güncelleme")
                    .font(.system(size: 12, weight: .semibold))
                Link("Hata bildir", destination: URL(string: "https://github.com/berkinefeavci/PanelLight/issues/new?title=Hata%3A%20")!)
                Link("Öneri gönder", destination: URL(string: "https://github.com/berkinefeavci/PanelLight/issues/new?title=%C3%96neri%3A%20")!)
                Link("Güncellemeleri denetle", destination: URL(string: "https://github.com/berkinefeavci/PanelLight/releases/latest")!)
                Text("Bağlantılar tarayıcıda açılır. Tanı verisi otomatik gönderilmez.")
                    .foregroundStyle(.secondary)

                Divider().padding(.vertical, 5)
                Text("Bağlantı")
                    .font(.system(size: 12, weight: .semibold))
                Label(display?.name ?? "Harici ekran", systemImage: "display")
                Text(model.canChangeBrightness ? "DDC/CI yanıt veriyor." :
                        "DDC/CI yanıt vermiyor. Monitör ayarını ve bağlantıyı kontrol et.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Yenile") { model.refresh() }
                        .modifier(PanelButtonStyle(glass: glassButtons))
                    Spacer()
                    Button("Çıkış") { NSApp.terminate(nil) }
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

    var body: some View {
        GeometryReader { geometry in
            let trackWidth = max(0, geometry.size.width - 20)
            let progress = min(1, max(0, value / 100))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.18))
                    .frame(width: trackWidth, height: 6)
                    .overlay(alignment: .leading) {
                        Capsule().fill(tint).frame(width: trackWidth * progress, height: 6)
                    }
                    .offset(x: 10)
                sliderThumb
                    .offset(x: trackWidth * progress)
                Slider(value: $value, in: 0...100)
                    .opacity(0.01)
                    .disabled(!enabled)
                    .accessibilityLabel(label)
            }
            .frame(height: 22)
            .contentShape(Rectangle())
            .highPriorityGesture(DragGesture(minimumDistance: 0).onChanged { gesture in
                guard enabled, trackWidth > 0 else { return }
                value = min(100, max(0, (gesture.location.x - 10) / trackWidth * 100))
            })
            .opacity(enabled ? 1 : 0.45)
        }
        .frame(height: 22)
    }

    @ViewBuilder private var sliderThumb: some View {
        if #available(macOS 26, *) {
            Circle().fill(.white.opacity(0.72))
                .frame(width: 20, height: 20)
                .glassEffect(.regular, in: Circle())
        } else {
            Circle().fill(.white).frame(width: 20, height: 20)
        }
    }
}
