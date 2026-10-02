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
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
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

            HStack(spacing: 10) {
                Image(systemName: "sun.min.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Slider(value: Binding(
                    get: { model.brightnessValue },
                    set: { model.setBrightness($0) }
                ), in: 0...100)
                .tint(.blue)
                .disabled(!model.canChangeBrightness)
                .accessibilityLabel("Monitörün donanım parlaklığı")
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)

            HStack(spacing: 7) {
                preset("Gece 25%", value: 25)
                preset("Çalışma 60%", value: 60)
                preset("Tam 100%", value: 100)
            }
            .padding(.top, 10)

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
                Slider(value: Binding(
                    get: { model.contrastValue },
                    set: { model.setContrast($0) }
                ), in: 0...100)
                .tint(.blue)
                .accessibilityLabel("Monitör kontrastı")
            }
            HStack {
                Text("Giriş")
                Spacer()
                Text(inputName(model.selectedProbe?.input))
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.top, model.canChangeContrast ? 6 : 0)
        }
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
