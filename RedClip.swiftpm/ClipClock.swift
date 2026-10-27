import SwiftUI

// MARK: - Clip Clock
//
// Where in the song the clipper works hardest: MAX CLIP is the most gain the clipper has taken
// off a sample (the same measure as the CLIP readout, held at its peak), MIN:SEC is the song
// position of that peak. Play the record through once, jump to that spot and dial Drive, Red and
// Fire in against the loudest moment. RESET starts a new pass.
//
// In the app the whole loaded file is scanned in the background with the current settings
// (AudioController.scanClipClock), and scanned again whenever a setting that feeds the clipper
// changes, so the readout is the loudest moment of the entire song, not just what has played.
// In a DAW the host owns the audio, so the audio thread (ClipDSP) keeps a running best while the
// host's transport plays and publishes it here only when it grows. The panel reads these at
// display rate.

/// Shared between the audio thread and the UI (lock-free, allocated once).
final class ClipClockState: @unchecked Sendable {
    let maxDB = AtomicFloat(0)        // dB past the ceiling; 0 = nothing clipped since the reset
    let seconds = AtomicFloat(-1)     // song position of that peak; -1 = unknown
    let reset = AtomicInt(0)          // UI sets 1, the audio thread takes it
    let scanning = AtomicInt(0)       // 1 while the app is scanning the whole file

    deinit { maxDB.deallocate(); seconds.deallocate(); reset.deallocate(); scanning.deallocate() }

    /// Any thread: start a new pass. The audio thread clears its own best on the next block.
    func requestReset() {
        reset.value = 1
        maxDB.value = 0
        seconds.value = -1
    }

    /// "3:13:04": minutes, seconds, hundredths.
    static func timeText(_ s: Float) -> String {
        guard s >= 0, s.isFinite else { return "-:--:--" }
        let hundredths = Int((Double(s) * 100).rounded())
        return String(format: "%d:%02d:%02d", hundredths / 6000, hundredths / 100 % 60, hundredths % 100)
    }

    static func dbText(_ db: Float) -> String {
        db > 0.05 ? String(format: "%.1f dB", db) : "-- dB"
    }
}

/// The Clip Clock panel, drawn on the screen's glass in the screen's own units (258 high).
struct ClipClockPanel: View {
    let clock: ClipClockState
    /// The app scans the file again; nil in a DAW, where reset starts a new live pass.
    var onReset: (() -> Void)? = nil
    @State private var dbText = ClipClockState.dbText(0)
    @State private var timeText = ClipClockState.timeText(-1)

    static let size = CGSize(width: 264, height: 66)
    private static let label = Color(hex: 0x8a8d93)
    private static let time = Color(hex: 0x8ea6ff)

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            column("MAX CLIP", dbText, color: Color(hex: 0xf1f1f3), width: 82)
            column("MIN:SEC", timeText, color: Self.time, width: 92)
            Button {
                if let onReset { onReset() } else { clock.requestReset() }
                refresh()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Self.label)
                    .frame(width: 30, height: 28)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(hex: 0x141518)))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Reset Clip Clock")
        }
        .padding(.horizontal, 12)
        .frame(width: Self.size.width, height: Self.size.height)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(hex: 0x222326).opacity(0.94))
                .shadow(color: .black.opacity(0.6), radius: 6, y: 3))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.05), lineWidth: 1))
        .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in refresh() }
        .onAppear(perform: refresh)
    }

    private func column(_ title: String, _ value: String, color: Color, width: CGFloat) -> some View {
        VStack(spacing: 5) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .tracking(1.2)
                .foregroundStyle(Self.label)
            Text(value)
                .font(.system(size: 15, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: width, height: 28)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(hex: 0x141518)))
        }
    }

    private func refresh() {
        let busy = clock.scanning.value != 0
        let d = busy ? "···" : ClipClockState.dbText(clock.maxDB.value)
        let t = busy ? "···" : ClipClockState.timeText(clock.seconds.value)
        if d != dbText { dbText = d }
        if t != timeText { timeText = t }
    }
}
