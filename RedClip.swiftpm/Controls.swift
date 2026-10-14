import SwiftUI

// MARK: - Theme (Red Clip faceplate)

enum Theme {
    static let red = Color(red: 0.74, green: 0.07, blue: 0.10)
    static let redLight = Color(red: 0.86, green: 0.15, blue: 0.18)
    static let redDark = Color(red: 0.45, green: 0.03, blue: 0.05)
    static let glow = Color(red: 1.0, green: 0.33, blue: 0.33)
    static let glowSoft = Color(red: 1.0, green: 0.55, blue: 0.52)
    static let screen = Color(red: 0.05, green: 0.045, blue: 0.05)
    static let well = Color(red: 0.09, green: 0.07, blue: 0.075)
    static let text = Color(red: 0.98, green: 0.94, blue: 0.93)
    static let textDim = Color(red: 0.98, green: 0.86, blue: 0.85).opacity(0.85)
    static let dimOnDark = Color(white: 0.62)
    static let cream = Color(red: 0.98, green: 0.92, blue: 0.86)

    static func label(_ s: String, size: CGFloat = 21) -> some View {
        Text(s.uppercased())
            .font(.system(size: size, weight: .semibold))
            .tracking(size * 0.16)
            .foregroundStyle(text)
            .shadow(color: .black.opacity(0.35), radius: 1, y: 1)
    }
}

/// Brushed red metal. Has no inputs, so SwiftUI draws it once.
struct BrushedRed: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.redLight, Theme.red, Theme.redDark.opacity(0.95), Theme.red],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Canvas { g, size in
                var seed: UInt64 = 0x5EED
                func rnd() -> CGFloat {
                    seed = seed &* 6364136223846793005 &+ 1442695040888963407
                    return CGFloat(seed >> 33) / CGFloat(UInt32.max >> 1)
                }
                var y: CGFloat = 0
                while y < size.height {
                    let alpha = rnd() * 0.10
                    let light = rnd() > 0.5
                    var p = Path()
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: size.width, y: y))
                    g.stroke(p, with: .color((light ? Color.white : Color.black).opacity(alpha)), lineWidth: 0.7)
                    y += 0.9 + rnd() * 1.4
                }
            }
            RadialGradient(colors: [Color.white.opacity(0.10), .clear], center: .init(x: 0.3, y: 0.05),
                           startRadius: 10, endRadius: 900)
        }
        .drawingGroup()
    }
}

/// Engraved horizontal divider between face sections.
struct Groove: View {
    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.black.opacity(0.35)).frame(height: 1.5)
            Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
        }
    }
}

struct VGroove: View {
    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(Color.black.opacity(0.35)).frame(width: 1.5)
            Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1)
        }
    }
}

struct Screw: View {
    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [Theme.redLight, Theme.redDark], center: .init(x: 0.35, y: 0.3),
                                         startRadius: 1, endRadius: 9))
            Circle().stroke(Color.black.opacity(0.45), lineWidth: 1)
            Rectangle().fill(Color.black.opacity(0.5)).frame(width: 9, height: 1.5).rotationEffect(.degrees(35))
        }
        .frame(width: 15, height: 15)
    }
}

/// Dark recessed housing used for the screen, readouts, and button wells.
struct Well: ViewModifier {
    var radius: CGFloat = 10
    var lit = false
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius)
                    .fill(LinearGradient(colors: [Color(white: 0.03), Theme.well], startPoint: .top, endPoint: .bottom))
                    .shadow(color: .black.opacity(0.55), radius: 3, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .stroke(lit ? Theme.glow.opacity(0.85) : Color.black.opacity(0.7), lineWidth: lit ? 2 : 1.5)
                    .shadow(color: lit ? Theme.glow.opacity(0.8) : .clear, radius: 6)
            )
    }
}

extension View {
    func well(radius: CGFloat = 10, lit: Bool = false) -> some View { modifier(Well(radius: radius, lit: lit)) }
}

// MARK: - Knob

/// Black brushed knob in a glowing red ring with a tick scale. Drag up/down, double-tap to reset.
struct Knob: View {
    let title: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    let defaultValue: Float
    var diameter: CGFloat = 190
    var minLabel: String = ""
    var maxLabel: String = ""
    var format: (Float) -> String = { String(format: "%.1f", $0) }

    @State var dragStart: Float?

    private var norm: Double { Double((value - range.lowerBound) / (range.upperBound - range.lowerBound)) }

    var body: some View {
        VStack(spacing: diameter * 0.04) {
            Theme.label(title, size: diameter * 0.115)
            ZStack {
                ticks
                // red ring
                Circle()
                    .fill(AngularGradient(colors: [Theme.redLight, Theme.redDark, Theme.glow, Theme.redDark, Theme.redLight],
                                          center: .center))
                    .frame(width: diameter * 0.80, height: diameter * 0.80)
                    .shadow(color: Theme.glow.opacity(0.55), radius: diameter * 0.04)
                    .shadow(color: .black.opacity(0.5), radius: diameter * 0.05, y: diameter * 0.03)
                Circle()
                    .stroke(Color.black.opacity(0.6), lineWidth: diameter * 0.012)
                    .frame(width: diameter * 0.70, height: diameter * 0.70)
                // brushed black cap
                Circle()
                    .fill(AngularGradient(colors: [Color(white: 0.10), Color(white: 0.24), Color(white: 0.08),
                                                   Color(white: 0.20), Color(white: 0.07), Color(white: 0.22),
                                                   Color(white: 0.10)], center: .center))
                    .overlay(Circle().fill(RadialGradient(colors: [Color.white.opacity(0.08), .clear],
                                                          center: .init(x: 0.4, y: 0.3), startRadius: 1,
                                                          endRadius: diameter * 0.35)))
                    .frame(width: diameter * 0.68, height: diameter * 0.68)
                // pointer
                Capsule()
                    .fill(Theme.cream)
                    .frame(width: diameter * 0.022, height: diameter * 0.12)
                    .offset(y: -diameter * 0.235)
                    .rotationEffect(.degrees(-135 + 270 * norm))
                    .shadow(color: .white.opacity(0.3), radius: 2)
            }
            .frame(width: diameter, height: diameter)
            .overlay(alignment: .bottom) {
                HStack {
                    Text(minLabel)
                    Spacer()
                    Text(maxLabel)
                }
                .font(.system(size: diameter * 0.085, weight: .regular))
                .foregroundStyle(Theme.textDim)
                .offset(y: diameter * 0.07)
                .padding(.horizontal, -diameter * 0.04)
            }
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        if dragStart == nil { dragStart = value }
                        let span = range.upperBound - range.lowerBound
                        // Tension: a full sweep takes 600 points of drag on every knob, big or small
                        let delta = Float(-g.translation.height + g.translation.width * 0.3) / 600 * span
                        value = min(max((dragStart ?? value) + delta, range.lowerBound), range.upperBound)
                    }
                    .onEnded { _ in dragStart = nil }
            )
            .simultaneousGesture(TapGesture(count: 2).onEnded { value = defaultValue })
            .padding(.bottom, diameter * 0.06)

            Text(format(value))
                .font(.system(size: diameter * 0.14, weight: .medium))
                .foregroundStyle(Theme.text)
                .shadow(color: .black.opacity(0.35), radius: 1, y: 1)
                .monospacedDigit()
        }
    }

    private var ticks: some View {
        Canvas { g, size in
            let cx: CGFloat = size.width / 2
            let cy: CGFloat = size.height / 2
            let count = 25
            for i in 0..<count {
                let f = CGFloat(i) / CGFloat(count - 1)
                let degrees: CGFloat = -225 + 270 * f
                let a: CGFloat = degrees * .pi / 180
                let ca: CGFloat = cos(a)
                let sa: CGFloat = sin(a)
                let major = i % 3 == 0
                let r1: CGFloat = size.width * (major ? 0.445 : 0.455)
                let r2: CGFloat = size.width * 0.495
                var p = Path()
                p.move(to: CGPoint(x: cx + r1 * ca, y: cy + r1 * sa))
                p.addLine(to: CGPoint(x: cx + r2 * ca, y: cy + r2 * sa))
                g.stroke(p, with: .color(Theme.text.opacity(major ? 0.9 : 0.6)), lineWidth: major ? 2.2 : 1.4)
            }
        }
    }
}

// MARK: - Segmented selector

struct Segments: View {
    let options: [String]
    @Binding var selection: Float
    var height: CGFloat = 58
    var fontSize: CGFloat = 19

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { i in
                let on = Int(selection.rounded()) == i
                Button { selection = Float(i) } label: {
                    Text(options[i].uppercased())
                        .font(.system(size: fontSize, weight: .semibold))
                        .tracking(fontSize * 0.1)
                        .foregroundStyle(on ? Color(red: 0.35, green: 0.0, blue: 0.02) : Theme.text)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(on ? AnyShapeStyle(LinearGradient(colors: [Theme.glowSoft, Theme.glow, Color(red: 0.9, green: 0.2, blue: 0.22)],
                                                                         startPoint: .top, endPoint: .bottom))
                                         : AnyShapeStyle(Color.clear))
                                .shadow(color: on ? Theme.glow.opacity(0.8) : .clear, radius: 8)
                                .padding(4)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: height)
        .well(radius: 9)
    }
}

// MARK: - Buttons

/// Dark well button that glows red when on (LINK, DELTA, UNITY).
struct GlowButton: View {
    let title: String
    var icon: String? = nil
    @Binding var isOn: Bool
    var height: CGFloat = 66
    var fontSize: CGFloat = 20

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: 10) {
                if let icon { Image(systemName: icon).font(.system(size: fontSize * 1.1, weight: .semibold)) }
                Text(title.uppercased()).font(.system(size: fontSize, weight: .semibold)).tracking(fontSize * 0.12)
            }
            .foregroundStyle(isOn ? Theme.glow : Theme.glow.opacity(0.55))
            .shadow(color: isOn ? Theme.glow.opacity(0.9) : .clear, radius: 6)
            .padding(.horizontal, 26)
            .frame(height: height)
            .well(radius: 9, lit: isOn)
        }
        .buttonStyle(.plain)
    }
}

/// BYPASS: grey LED that turns red when bypassed.
struct LEDButton: View {
    let title: String
    @Binding var isOn: Bool
    var height: CGFloat = 70

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: 18) {
                Circle()
                    .fill(isOn ? AnyShapeStyle(Theme.glow) : AnyShapeStyle(RadialGradient(colors: [Color(white: 0.55), Color(white: 0.25)],
                                                                                  center: .init(x: 0.35, y: 0.3), startRadius: 1, endRadius: 10)))
                    .frame(width: 18, height: 18)
                    .shadow(color: isOn ? Theme.glow : .clear, radius: 7)
                Text(title.uppercased())
                    .font(.system(size: 20, weight: .semibold)).tracking(2.4)
                    .foregroundStyle(Theme.text)
            }
            .padding(.horizontal, 30)
            .frame(height: height)
            .well(radius: 9)
        }
        .buttonStyle(.plain)
    }
}

/// Square icon button in a dark well (undo).
struct IconButton: View {
    let icon: String
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(Theme.text.opacity(enabled ? 0.9 : 0.35))
                .frame(width: 62, height: 54)
                .well(radius: 9)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// Round glowing power button. On = engine running.
struct PowerButton: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(LinearGradient(colors: [Color(white: 0.16), Color(white: 0.04)], startPoint: .top, endPoint: .bottom))
                Circle().stroke(isOn ? Theme.glow.opacity(0.9) : Color.black.opacity(0.7), lineWidth: 3)
                    .shadow(color: isOn ? Theme.glow : .clear, radius: 10)
                Image(systemName: "power")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(isOn ? Theme.glow : Color(white: 0.4))
                    .shadow(color: isOn ? Theme.glow : .clear, radius: 6)
            }
            .frame(width: 66, height: 66)
            .shadow(color: .black.opacity(0.5), radius: 4, y: 3)
        }
        .buttonStyle(.plain)
    }
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
