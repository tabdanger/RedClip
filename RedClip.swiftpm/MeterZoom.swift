import Foundation
import CoreGraphics

/// The screen's dB scale, after Gold Clip's meter zoom. Double-tapping the screen or either
/// meter steps through three tiers; each one magnifies the waveform and the Ceiling guides
/// together, so peaks can be dialled in more precisely:
///   - Full (default): +6 dBFS to -36 dBFS
///   - Zoom 1:         +4 dBFS to -24 dBFS
///   - Zoom 2:         +2 dBFS to -12 dBFS
/// The waveform is mirrored around the centre line: the top of the range sits on the outer edge,
/// the bottom of the range (and anything quieter) on the centre line, linear in dB between.
/// The LED strips keep the scale printed on the faceplate.
enum MeterZoom: Int, CaseIterable {
    case full, zoom1, zoom2

    var topDB: Float { [6, 4, 2][rawValue] }
    var floorDB: Float { [-36, -24, -12][rawValue] }

    /// Labelled grid lines, drawn in both halves; the centre line is labelled with floorDB.
    var marks: [Float] {
        switch self {
        case .full: return [6, 0, -6, -12, -24]
        case .zoom1: return [4, 0, -6, -12, -18]
        case .zoom2: return [2, 0, -3, -6, -9]
        }
    }

    /// The next tier, wrapping back to Full after Zoom 2.
    var next: MeterZoom { MeterZoom(rawValue: (rawValue + 1) % MeterZoom.allCases.count) ?? .full }

    var label: String { String(format: "dBFS  %+.0f / %.0f", topDB, floorDB) }

    /// 0 on the centre line (floorDB and below) … 1 on the edge (topDB and above).
    func position(_ db: Float) -> CGFloat {
        CGFloat(min(max((db - floorDB) / (topDB - floorDB), 0), 1))
    }

    /// Where a sample sits, -1 (bottom edge) … 1 (top edge).
    func position(sample v: Float) -> CGFloat {
        let p = position(20 * log10(max(abs(v), 1e-6)))
        return v < 0 ? -p : p
    }
}
