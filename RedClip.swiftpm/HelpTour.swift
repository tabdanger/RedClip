import SwiftUI

// MARK: - First-launch tour
//
// The first time the app opens, the faceplate dims and a card walks through every knob and button
// in turn, lighting the control it is talking about. Next / Back step through it (a tap anywhere
// else on the plate also goes on), SKIP ends it at once. Either way it never comes back by itself.
// The text is the same as the "?" help bubbles, so the two always agree.

extension HelpTopic {
    /// The tour's order: the header left to right, the displays, the knob rows, the switches,
    /// then the transport. Only the controls the current face shows are visited.
    static let tourOrder: [HelpTopic] = [
        .power, .presets, .ab, .undo, .help,
        .inputMeter, .screen, .clipReadout, .clipClock, .outputMeter,
        .input, .drive, .ceiling, .wet, .dry, .mixLink, .output,
        .red, .redStyle, .unity, .fire, .broil, .boxTone, .delta,
        .clipMode, .link, .oversampling, .bypass,
        .play, .load, .samples, .demo, .export
    ]

    /// The tour's steps for a face that shows `available`: every one of them, none twice.
    static func tourSteps(available: Set<HelpTopic>) -> [HelpTopic] {
        let ordered = tourOrder.filter(available.contains)
        let rest = available.subtracting(ordered).sorted { $0.rawValue < $1.rawValue }
        return ordered + rest
    }
}

struct HelpTour: View {
    @ObservedObject var face: FaceModel
    let areas: HelpAreas
    let size: CGSize
    let scale: CGFloat

    static let welcomeTitle = "Welcome to Red Clip"
    static let welcomeText = "Here's a quick tour of every knob and button. Tap NEXT to step through it, or SKIP to start using Red Clip straight away. Any time later, tap ? and touch a control to see what it does."

    private var steps: [HelpTopic] { HelpTopic.tourSteps(available: Set(areas.rects.keys)) }

    var body: some View {
        let steps = self.steps
        let index = min(face.tourStep ?? 0, steps.count)
        let topic: HelpTopic? = index == 0 ? nil : steps[index - 1]
        let lit = topic.flatMap { areas.frame($0) }?.insetBy(dx: -8 * scale, dy: -8 * scale)

        ZStack(alignment: .topLeading) {
            // dim everything but the control being explained; the plate can't be changed mid-tour
            Path { p in
                p.addRect(CGRect(origin: .zero, size: size))
                if let lit { p.addRoundedRect(in: lit, cornerSize: CGSize(width: 12 * scale, height: 12 * scale)) }
            }
            .fill(Color.black.opacity(0.62), style: FillStyle(eoFill: true))
            .contentShape(Rectangle())
            .onTapGesture { advance(steps.count) }
            .accessibilityHidden(true)

            if let lit {
                RoundedRectangle(cornerRadius: 12 * scale)
                    .stroke(Plate.glow, lineWidth: 3 * scale)
                    .shadow(color: Plate.glow, radius: 8 * scale)
                    .frame(width: lit.width, height: lit.height)
                    .position(x: lit.midX, y: lit.midY)
                    .allowsHitTesting(false)
            }

            card(topic: topic, index: index, count: steps.count)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private func card(topic: HelpTopic?, index: Int, count: Int) -> some View {
        let width: CGFloat = 400
        let title = topic?.title ?? Self.welcomeTitle
        let text = topic?.text ?? Self.welcomeText
        let height = HelpBubble.estimatedHeight(text, width: width) + 82
        let center: CGPoint
        if let topic, let r = areas.frame(topic) {
            center = HelpBubble.center(for: r.insetBy(dx: -8 * scale, dy: -8 * scale),
                                       width: width * scale, height: height * scale, in: size)
        } else {
            center = CGPoint(x: size.width / 2, y: size.height / 2)
        }
        let last = index >= count

        return VStack(alignment: .leading, spacing: 6) {
            Text(index == 0 ? "TOUR" : "\(index) OF \(count)")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(Theme.cream.opacity(0.55))
            Text(title.uppercased())
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(Theme.glow)
            Text(text)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Theme.cream)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                if !last { tourButton("SKIP", lit: false) { face.endTour() } }
                Spacer(minLength: 0)
                if index > 0 { tourButton("BACK", lit: false) { face.tourStep = index - 1 } }
                tourButton(last ? "DONE" : "NEXT", lit: true) { advance(count) }
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
        .frame(width: width, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(LinearGradient(colors: [Color(red: 0.15, green: 0.12, blue: 0.13).opacity(0.98),
                                              Color(red: 0.06, green: 0.05, blue: 0.05).opacity(0.98)],
                                     startPoint: .top, endPoint: .bottom)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.22), lineWidth: 1.5))
        .overlay(RoundedRectangle(cornerRadius: 9).inset(by: 3).stroke(Color.black.opacity(0.7), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.75), radius: 9, x: 3, y: 6)
        .scaleEffect(scale)
        .position(center)
        .id(index)
        .transition(.opacity)
        .accessibilityElement(children: .contain)
    }

    private func tourButton(_ label: String, lit: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(lit ? Plate.glowHot : Theme.cream.opacity(0.8))
                .padding(.horizontal, 16).frame(height: 40)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.black.opacity(0.55)))
                .overlay(RoundedRectangle(cornerRadius: 7)
                    .stroke(lit ? Plate.glow.opacity(0.9) : Color.white.opacity(0.18), lineWidth: 1.5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func advance(_ count: Int) {
        let next = (face.tourStep ?? 0) + 1
        if next > count { face.endTour() } else { face.tourStep = next }
    }
}
