import SwiftUI

// MARK: - Theme

/// The two colours the help bubbles and the guided tour still draw with (the faceplate itself
/// is a picture; its live colours are in Plate and PlateTheme).
enum Theme {
    static let glow = Color(red: 1.0, green: 0.33, blue: 0.33)
    static let cream = Color(red: 0.98, green: 0.92, blue: 0.86)
}

// MARK: - Formatting

enum Fmt {
    static func db(_ v: Float) -> String {
        let r = (v * 10).rounded() / 10
        return r == 0 ? "0.0 dB" : String(format: "%+.1f dB", r)
    }
    static func dbPlain(_ v: Float) -> String { String(format: "%.1f dB", (v * 10).rounded() / 10 + 0) }
    static func pct(_ v: Float) -> String { String(format: "%.0f %%", v) }
}
