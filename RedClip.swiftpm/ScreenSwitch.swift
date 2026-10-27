import SwiftUI

// MARK: - WAVE / SPECTRUM
//
// The screen has two views of the same audio. WAVE is Gold Clip's layout: the live waveform
// (PlateScreen) with the Clip Clock and short-term loudness. SPECTRUM is the INPUT / OUTPUT
// analyser (PlateSpectrumScreen). Switching only changes what is drawn: the audio, the DSP
// and every control carry on untouched.

enum ScreenView: Int {
    case wave, spectrum
}

/// A small two-cell switch in the screen's top-left corner, drawn on the glass in the screen's
/// own units (258 high). Its touch area reaches past the drawn cells into the empty strip above
/// and below them, so it stays easy to hit on the iPhone face without growing the faceplate.
struct ScreenViewSwitch: View {
    @Binding var view: ScreenView
    static let cells: [(ScreenView, String, CGFloat)] = [(.wave, "WAVE", 46), (.spectrum, "SPECTRUM", 70)]
    static let height: CGFloat = 20
    static let touchHeight: CGFloat = 40
    /// Drawn width of both cells together.
    static let width: CGFloat = cells.reduce(0) { $0 + $1.2 }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Self.cells, id: \.1) { cell in segment(cell.0, cell.1, cell.2) }
        }
        .frame(width: Self.width, height: Self.touchHeight, alignment: .topLeading)
    }

    private func segment(_ v: ScreenView, _ title: String, _ w: CGFloat) -> some View {
        let on = view == v
        return Button { view = v } label: {
            ZStack(alignment: .topLeading) {
                Color.clear
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.1)
                    .foregroundStyle(on ? Color.white : Color(hex: 0x8a8d93))
                    .frame(width: w, height: Self.height)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(on ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xe8363b), Color(hex: 0xa3171c)],
                                                                    startPoint: .top, endPoint: .bottom))
                                     : AnyShapeStyle(Color(hex: 0x16171a))))
                    .overlay(RoundedRectangle(cornerRadius: 3)
                        .stroke(on ? Color(hex: 0xff6a6e).opacity(0.7) : Color.white.opacity(0.1), lineWidth: 1))
                    .shadow(color: on ? Plate.glow.opacity(0.55) : .clear, radius: 4)
                    .padding(.top, 5)
            }
            .frame(width: w, height: Self.touchHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(v == .wave ? "Waveform" : "Spectrum analyser")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Short-term loudness (3 s, BS.1770) going in (after Input) and coming out, in the WAVE
/// view's bottom-right corner, beside the Clip Clock. Screen units, like ClipClockPanel.
struct LoudnessPanel: View {
    let shared: SharedState
    @State private var inText = LoudnessPanel.text(-70)
    @State private var outText = LoudnessPanel.text(-70)

    static let size = CGSize(width: 76, height: 66)
    private static let label = Color(hex: 0x8a8d93)

    static func text(_ lufs: Float) -> String {
        guard lufs.isFinite, lufs > -69.9 else { return "--" }
        return String(format: "%.1f", lufs).replacingOccurrences(of: "-", with: "\u{2212}")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("LUFS S")
                .font(.system(size: 10, weight: .medium))
                .tracking(1)
                .foregroundStyle(Self.label)
            row("IN", inText)
            row("OUT", outText)
        }
        .padding(.horizontal, 8)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(hex: 0x222326).opacity(0.94))
                .shadow(color: .black.opacity(0.6), radius: 6, y: 3))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.05), lineWidth: 1))
        .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in refresh() }
        .onAppear(perform: refresh)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Short-term loudness, in \(inText), out \(outText) LUFS")
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(spacing: 0) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Self.label)
                .frame(width: 24, alignment: .leading)
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(title == "IN" ? Color(hex: 0xb3b9c2) : Color(hex: 0xff4145))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func refresh() {
        let i = Self.text(shared.meters[Meter.inLUFS.rawValue])
        let o = Self.text(shared.meters[Meter.outLUFS.rawValue])
        if i != inText { inText = i }
        if o != outText { outText = o }
    }
}
