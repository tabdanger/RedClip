import SwiftUI

// MARK: - The transport's scrub bar (app only)
//
// The progress groove at the bottom of the faceplate, made precise:
//   - drag the dot (or touch anywhere on the bar to jump there first); the audio stays quiet
//     while the finger moves and plays on from wherever it lands;
//   - slide the finger up, away from the bar, for finer control, like iOS's scrubbing: full
//     speed near the bar, then half, quarter and fine (a tenth);
//   - a bubble over the dot shows the exact time (to a tenth of a second) and the speed;
//   - red marks show the file's loudest moments; the tall one with the triangle is the CLIP
//     CLOCK sample. At full speed the dot snaps onto a mark it passes close to, so touching
//     near a mark lands exactly on it.
// A DAW owns its own transport, so the plug-in has no scrub bar (this file is app-only; the
// arithmetic is ScrubMath, in ClipClock.swift, so the tests can reach it).

struct PrecisionScrubber: View {
    @ObservedObject var audio: AudioController
    var fontSize: CGFloat = 16

    @State private var dragging = false
    @State private var fraction: Double = 0
    @State private var lastX: CGFloat = 0
    @State private var speed: Double = 1

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { _ in
            GeometryReader { geo in
                let w = max(geo.size.width, 1), h = geo.size.height
                let p = CGFloat(dragging ? fraction : audio.progress)
                let dot = fontSize * 0.7
                ZStack(alignment: .topLeading) {
                    // the loudest moments; the CLIP CLOCK one tallest, with a triangle
                    ForEach(audio.clipPoints) { pt in
                        let x = CGFloat(pt.fraction) * w
                        Rectangle()
                            .fill(Plate.glow.opacity(pt.rank == 0 ? 1 : 0.55))
                            .frame(width: pt.rank == 0 ? 2.5 : 2, height: pt.rank == 0 ? h * 0.95 : h * 0.55)
                            .position(x: x, y: h / 2)
                        if pt.rank == 0 {
                            Triangle().fill(Plate.glow)
                                .frame(width: 9, height: 6)
                                .position(x: x, y: h * 0.025)
                        }
                    }
                    Capsule().fill(Plate.glow.opacity(0.85))
                        .frame(width: max(3, p * w), height: 3)
                        .shadow(color: Plate.glow, radius: 3)
                        .position(x: max(3, p * w) / 2, y: h / 2)
                    Circle().fill(Plate.glow)
                        .frame(width: dragging ? dot * 1.35 : dot, height: dragging ? dot * 1.35 : dot)
                        .shadow(color: Plate.glow, radius: 5)
                        .position(x: p * w, y: h / 2)
                    if dragging { bubble(at: p * w, width: w) }
                }
                .frame(width: w, height: h)
                .contentShape(Rectangle())
                .gesture(drag(width: w, height: h))
                .accessibilityElement()
                .accessibilityLabel("Song position")
                .accessibilityValue(WaveTime.tenths(Double(p) * audio.duration))
                .accessibilityAdjustableAction { direction in
                    // a second either way, from VoiceOver's swipe up / down
                    let step = audio.duration > 0 ? 1 / audio.duration : 0
                    let now = audio.progress
                    audio.seek(to: min(max(direction == .increment ? now + step : now - step, 0), 1))
                }
            }
        }
    }

    private func bubble(at x: CGFloat, width w: CGFloat) -> some View {
        let name = ScrubMath.speedName(speed)
        return VStack(spacing: 1) {
            Text(WaveTime.tenths(fraction * audio.duration))
                .font(.system(size: fontSize * 0.95, weight: .semibold)).monospacedDigit()
                .foregroundStyle(Color.white)
            if !name.isEmpty {
                Text(name).font(.system(size: fontSize * 0.55, weight: .semibold)).tracking(1)
                    .foregroundStyle(Color(hex: 0xf0a43a))
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(hex: 0x16171a).opacity(0.95)))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Plate.glow.opacity(0.6), lineWidth: 1))
        .fixedSize()
        .position(x: min(max(x, 50), w - 50), y: -fontSize * 1.4)
        .allowsHitTesting(false)
    }

    private func drag(width w: CGFloat, height h: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                if !dragging {
                    dragging = true
                    audio.beginScrub()                  // silent while dragging
                    let now = audio.progress
                    // the dot is grabbed where it is; anywhere else jumps there first
                    fraction = abs(g.startLocation.x - CGFloat(now) * w) <= 22 ? now : Double(g.startLocation.x / w)
                    lastX = g.startLocation.x
                }
                speed = ScrubMath.speed(distance: abs(g.location.y - h / 2))
                var f = fraction + Double((g.location.x - lastX) / w) * speed
                lastX = g.location.x
                f = min(max(f, 0), 1)
                if speed >= 1 { f = ScrubMath.snap(f, to: audio.clipPoints, reach: Double(6 / w)) }
                fraction = f
                audio.seek(to: f)
            }
            .onEnded { _ in
                dragging = false
                speed = 1
                audio.endScrub()
            }
    }
}

private struct Triangle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY)); p.closeSubpath()
        return p
    }
}
