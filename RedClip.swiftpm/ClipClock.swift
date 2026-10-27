import SwiftUI

// MARK: - Clip Clock
//
// Superseded: the CLIP CLOCK readout on the WAVEFORM screen (SharedState.clipMax) now shows the
// original audio's loudest sample and where it is, before any control. This older panel and its
// state are no longer shown anywhere; ClipDSP still fills ClipClockState from songTime in a DAW.

/// One of a file's loudest moments, for the scrub bar's highlights.
struct ClipPoint: Identifiable, Equatable {
    let frame: Int
    let fraction: Double      // frame / file length
    let db: Float             // the original audio's sample peak there, dBFS
    let rank: Int             // 0 = the loudest (the CLIP CLOCK sample)
    var id: Int { frame }

    /// The `count` loudest moments of the original audio, at least `spacing` seconds apart,
    /// loudest first. The first is the file's loudest sample (the same one SharedState.filePeak
    /// finds). Off the audio thread; one pass over the file.
    static func loudest(left: UnsafePointer<Float>, right: UnsafePointer<Float>, frames: Int,
                        sampleRate: Double, count: Int = 5, spacing: Double = 1) -> [ClipPoint] {
        guard frames > 0 else { return [] }
        let block = max(1, Int(sampleRate * 0.05))           // 50 ms
        var peaks: [(peak: Float, frame: Int)] = []
        peaks.reserveCapacity(frames / block + 1)
        var start = 0
        while start < frames {
            let end = min(frames, start + block)
            var p: Float = 0, at = start
            for i in start..<end {
                let a = max(abs(left[i]), abs(right[i]))
                if a > p && a.isFinite { p = a; at = i }
            }
            if p > 0 { peaks.append((p, at)) }
            start = end
        }
        peaks.sort { $0.peak != $1.peak ? $0.peak > $1.peak : $0.frame < $1.frame }
        let gap = Int(sampleRate * spacing)
        var chosen: [(peak: Float, frame: Int)] = []
        for p in peaks where chosen.count < count {
            if chosen.allSatisfy({ abs($0.frame - p.frame) >= gap }) { chosen.append(p) }
        }
        return chosen.enumerated().map { i, p in
            ClipPoint(frame: p.frame, fraction: Double(p.frame) / Double(frames), db: gainToDB(p.peak), rank: i)
        }
    }
}

/// The scrub bar's arithmetic (Scrubber.swift is app-only).
enum ScrubMath {
    /// Scrub speed for how far (in this view's units) the finger is from the bar.
    static func speed(distance: CGFloat) -> Double {
        distance < 40 ? 1 : (distance < 80 ? 0.5 : (distance < 120 ? 0.25 : 0.1))
    }

    static func speedName(_ s: Double) -> String {
        s >= 1 ? "" : (s >= 0.5 ? "HALF SPEED" : (s >= 0.25 ? "QUARTER SPEED" : "FINE"))
    }

    /// Where `fraction` lands after snapping onto a mark within `reach` (fractions of the bar).
    static func snap(_ fraction: Double, to points: [ClipPoint], reach: Double) -> Double {
        let near = points.min { abs($0.fraction - fraction) < abs($1.fraction - fraction) }
        if let near, abs(near.fraction - fraction) <= reach { return near.fraction }
        return fraction
    }
}

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
