import AppKit
import SwiftUI

struct QuickPanel: View {
    @ObservedObject var model: MonitorModel
    @State private var showDetails = false
    @State private var showDiagnostics = false

    private var display: DisplayIdentity? { model.selectedProbe?.display ?? model.displays.first }
    private var subtitle: String {
        guard let display else { return "Harici ekran" }
        let resolution = "\(CGDisplayPixelsWide(display.id)) × \(CGDisplayPixelsHigh(display.id))"
        return display.name == "X27F166QB" ? "Fazeon · \(resolution)" : "Harici ekran · \(resolution)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showDiagnostics { diagnostics } else { controls }
        }
        .padding(18)
        .frame(width: 350)
        .fixedSize(horizontal: false, vertical: true)
        .glassEffect(.clear, in: .rect(cornerRadius: 22))
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
                Button { showDiagnostics = true } label: {
                    Image(systemName: "slider.horizontal.3")
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.glass)
                .clipShape(Circle())
                .accessibilityLabel("Ayarlar ve bağlantı")
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
                Text("Parlaklık")
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
                label: "Monitörün donanım parlaklığı"
            )
            .padding(.top, 8)

            HStack(spacing: 7) {
                preset("Gece 25%", value: 25)
                preset("Çalışma 60%", value: 60)
                preset("Tam 100%", value: 100)
            }
            .padding(.top, 10)

            if let builtInDisplay = model.builtInDisplay {
                Divider().padding(.top, 16)
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
                    label: "Yerleşik ekran parlaklığı"
                )
                .padding(.top, 6)
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
                Text("Mac parlaklığı değişince harici ekran da takip eder.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider().padding(.vertical, 17)

            HStack {
                Text(model.canChangeBrightness ? "Monitörün kendi parlaklığı" : "Donanım kontrolü kullanılamıyor")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("DDC/CI")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .glassEffect(in: .capsule)
            }

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
            .buttonStyle(.glass)
            .frame(maxWidth: .infinity)
            .disabled(!model.canChangeBrightness)
            .accessibilityLabel("Parlaklık \(title)")
    }

    private func brightnessSlider(value: Binding<Double>, enabled: Bool, label: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "sun.min.fill")
                .font(.system(size: 11))
                .frame(width: 16)
            Slider(value: value, in: 0...100)
                .tint(.blue)
                .disabled(!enabled)
                .accessibilityLabel(label)
            Image(systemName: "sun.max.fill")
                .font(.system(size: 16))
                .frame(width: 16)
        }
        .foregroundStyle(.secondary)
    }

    private var secondaryControls: some View {
        VStack(alignment: .leading, spacing: 10) {
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
                    Slider(value: Binding(
                        get: { model.contrastValue },
                        set: { model.setContrast($0) }
                    ), in: 0...100)
                    .tint(.blue)
                    .accessibilityLabel("Monitör kontrastı")
                    Image(systemName: "circle.righthalf.filled")
                        .font(.system(size: 16))
                        .frame(width: 16)
                }
                .foregroundStyle(.secondary)
            }
            HStack {
                Text("Giriş")
                Spacer()
                Text(inputName(model.selectedProbe?.input))
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.top, model.canChangeContrast ? 6 : 0)

            Divider().padding(.vertical, 5)
            HStack {
                Text("Saatle parlaklık")
                Spacer()
                Toggle("Saatle parlaklık", isOn: Binding(
                    get: { model.scheduleEnabled },
                    set: { model.setScheduleEnabled($0) }
                ))
                .labelsHidden()
                .accessibilityLabel("Saatle parlaklık")
            }
            .toggleStyle(.switch)
            .font(.system(size: 12, weight: .medium))
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
                Text("Seçili monitör ve yerleşik ekrana uygulanır.")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 11))
            }
            Button("Night Shift ayarları…") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(.blue)
        }
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

    private var diagnostics: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button { showDiagnostics = false } label: {
                    Label("Geri", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                Spacer()
                Text("Bağlantı")
                    .font(.system(size: 15, weight: .semibold))
            }
            Divider()
            Label(display?.name ?? "Harici ekran", systemImage: "display")
                .font(.system(size: 13, weight: .medium))
            Text(model.canChangeBrightness ? "DDC/CI yanıt veriyor. Parlaklık monitörün donanımından değişiyor." :
                    "DDC/CI yanıt vermiyor. Monitör menüsündeki DDC/CI ayarını ve doğrudan bağlantıyı kontrol et.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Yenile") { model.refresh() }
                    .buttonStyle(.glass)
                Spacer()
                Button("Çıkış") { NSApp.terminate(nil) }
                    .buttonStyle(.glass)
            }
        }
    }

    private func inputName(_ code: UInt16?) -> String {
        switch code {
        case 0x11: "HDMI 1"
        case 0x12: "HDMI 2"
        case 0x0f: "DisplayPort 1"
        case 0x10: "DisplayPort 2"
        case .some(let value): String(format: "0x%02X", value)
        case nil: "Kullanılamıyor"
        }
    }
}
