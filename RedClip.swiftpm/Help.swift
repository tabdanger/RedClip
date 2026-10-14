import SwiftUI

// MARK: - Help: the "?" button next to Undo
//
// Tap "?" to turn help on. Every control then gets a dashed outline; tap it (or hover over it
// with a trackpad, mouse or Apple Pencil) and a bubble explains what it does. While help is on,
// taps only show help, so nothing gets changed by accident. Tap "?" again to turn it off.

enum HelpTopic: String, CaseIterable {
    case help, presets, ab, undo, power
    case inputMeter, outputMeter, screen, clipReadout
    case input, drive, ceiling, mix, output
    case red, redStyle, unity, fire, boxTone, delta
    case clipMode, link, oversampling, bypass
    case play, load, samples, demo, export

    var title: String {
        switch self {
        case .help: return "Help"
        case .presets: return "Presets"
        case .ab: return "A / B"
        case .undo: return "Undo"
        case .power: return "Power"
        case .inputMeter: return "Input Meter"
        case .outputMeter: return "Output Meter"
        case .screen: return "Screen"
        case .clipReadout: return "Clip"
        case .input: return "Input"
        case .drive: return "Drive"
        case .ceiling: return "Ceiling"
        case .mix: return "Mix"
        case .output: return "Output"
        case .red: return "Red"
        case .redStyle: return "Red Style"
        case .unity: return "Unity Gain"
        case .fire: return "Fire"
        case .boxTone: return "Box Tone"
        case .delta: return "Delta"
        case .clipMode: return "Clip Mode"
        case .link: return "Link"
        case .oversampling: return "Oversampling"
        case .bypass: return "Bypass"
        case .play: return "Play / Stop"
        case .load: return "Load"
        case .samples: return "Samples"
        case .demo: return "Demo"
        case .export: return "Export"
        }
    }

    var text: String {
        switch self {
        case .help:
            return "Help is on. Tap or hover over any control to see what it does. Tap ? again to turn help off."
        case .presets:
            return "Step through the presets with the arrows, or tap the name to pick one from the list."
        case .ab:
            return "Two separate setups. Dial in A, switch to B and try something different, then flip between them to compare."
        case .undo:
            return "Steps back through your last changes, one move at a time."
        case .power:
            return "Turns the Red Clip engine off. In a DAW the audio passes straight through untouched and uses no CPU."
        case .inputMeter:
            return "Peak level coming in, left and right, after the Input knob. The marker above the bar holds the last peak."
        case .outputMeter:
            return "Peak level going out, left and right. The top lights flash white when the output reaches 0 dB."
        case .screen:
            return "The last 10 seconds of audio. The dim trace is what goes into the clipper and the bright trace is the output. Anything above the dashed ceiling line glows white and lights up the line: that's the part being clipped off."
        case .clipReadout:
            return "How far the signal is going past the ceiling right now, in dB. 0.0 means nothing is being clipped."
        case .input:
            return "Sets the level coming into Red Clip. The input meter shows the result."
        case .drive:
            return "Pushes the signal harder into Red and the clipper without changing the input meter. More Drive means more clipping."
        case .ceiling:
            return "The level where clipping starts, from 0 down to -12 dB. The clipped signal never goes above it."
        case .mix:
            return "Blends the processed sound with the dry signal. 100% is fully processed, lower brings back some of the original."
        case .output:
            return "The final level after everything else. With LINK on, it moves the opposite way to Input."
        case .red:
            return "Converter saturation modelled on the Lavry Gold. It rounds off peaks above a threshold, then adds the gain back, so the track gets denser and louder. Up to +2.5 dB in Modern and +6 dB in Classic."
        case .redStyle:
            return "Modern adds up to 2.5 dB and starts rounding 5 dB below the ceiling. Classic adds up to 6 dB and starts 12 dB below, like Lavry's +6 dB mode."
        case .unity:
            return "Takes away the gain Red adds. The body of the track stays at the same loudness while the peaks come down. Handy for hearing what Red does without it just sounding louder."
        case .fire:
            return "Smooths the bright, edgy top end that clipping can leave. It dips the highs by up to about 1 dB, only when the signal is close to the ceiling."
        case .boxTone:
            return "A subtle converter-style tone above 1 kHz. Flat leaves it alone, Modern trims a little air, Classic is slightly darker."
        case .delta:
            return "Plays only the difference between the input and the processed sound, so you hear exactly what Red Clip is adding or taking away."
        case .clipMode:
            return "Hard clips straight at the ceiling. Classic has a soft knee and rounds peaks off gently. Modern sits in between with a medium knee."
        case .link:
            return "Ties Input and Output together. Turn Input up and Output comes down by the same amount, so you can drive harder at the same level."
        case .oversampling:
            return "Runs the clipper at 2x or 4x the sample rate to cut harsh aliasing. Higher sounds cleaner but uses more CPU."
        case .bypass:
            return "Switches the processing out so you hear the original. A quick before-and-after check."
        case .play:
            return "Plays or stops the loaded audio through Red Clip. It loops until you stop it."
        case .load:
            return "Opens the Files app to pick any audio file. It gets copied into your Red Clip Samples folder."
        case .samples:
            return "Everything in Files › On My iPad › Red Clip › Samples. Drop your own audio in there and it shows up here."
        case .demo:
            return "Loads the built-in drum loop so you can try Red Clip straight away."
        case .export:
            return "Renders the whole file through your current settings to a 24-bit WAV you can save or share."
        }
    }
}

/// Where each control sits, so one bubble can be drawn above whichever is selected.
struct HelpAnchorKey: PreferenceKey {
    static let defaultValue: [HelpTopic: Anchor<CGRect>] = [:]
    static func reduce(value: inout [HelpTopic: Anchor<CGRect>], nextValue: () -> [HelpTopic: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Marks a control for help: dashed outline + tap/hover target while help is on.
struct HelpTarget: ViewModifier {
    @ObservedObject var face: FaceModel
    let topic: HelpTopic

    func body(content: Content) -> some View {
        content
            .overlay {
                if face.helpMode {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Theme.glowSoft.opacity(face.helpTopic == topic ? 1 : 0.5),
                                      style: StrokeStyle(lineWidth: face.helpTopic == topic ? 3 : 2, dash: [7, 5]))
                        .background(Color.white.opacity(0.001))   // catches taps across the whole control
                        .contentShape(Rectangle())
                        .onTapGesture { face.helpTopic = topic }
                        .padding(-6)
                }
            }
            .onHover { inside in
                if inside && face.helpMode { face.helpTopic = topic }
            }
            .anchorPreference(key: HelpAnchorKey.self, value: .bounds) { [topic: $0] }
    }
}

extension View {
    func helpTarget(_ topic: HelpTopic, _ face: FaceModel) -> some View {
        modifier(HelpTarget(face: face, topic: topic))
    }

    /// Draws the help bubble. Put it on the unscaled design-size container (the faceplate, or the
    /// faceplate plus the transport strip).
    func helpBubbles(_ face: FaceModel) -> some View {
        overlayPreferenceValue(HelpAnchorKey.self) { anchors in
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    Color.clear
                    if face.helpMode, let topic = face.helpTopic, let anchor = anchors[topic] {
                        let r = geo[anchor]
                        let width: CGFloat = 420
                        let above = r.minY > 230
                        let x = min(max(r.midX - width / 2, 16), geo.size.width - width - 16)
                        HelpBubble(topic: topic, pointsDown: above, arrowX: min(max(r.midX - x, 30), width - 30))
                            .frame(width: width)
                            .fixedSize(horizontal: false, vertical: true)
                            .alignmentGuide(.top) { d in above ? d[.bottom] : d[.top] }
                            .offset(x: x, y: above ? r.minY - 10 : r.maxY + 10)
                            .onTapGesture { face.helpTopic = nil }
                            .transition(.opacity)
                            .id(topic)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            }
            .animation(.easeOut(duration: 0.15), value: face.helpTopic)
        }
    }
}

/// The bubble itself: dark screen glass with a red edge, like the faceplate's displays.
struct HelpBubble: View {
    let topic: HelpTopic
    let pointsDown: Bool
    let arrowX: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(topic.title.uppercased())
                .font(.system(size: 17, weight: .semibold))
                .tracking(2.5)
                .foregroundStyle(Theme.glow)
            Text(topic.text)
                .font(.system(size: 19))
                .foregroundStyle(Theme.text)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Theme.screen.opacity(0.97))
                .shadow(color: .black.opacity(0.6), radius: 12, y: 6)
        )
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.glow.opacity(0.8), lineWidth: 1.5))
        .overlay(alignment: pointsDown ? .bottomLeading : .topLeading) {
            Triangle()
                .fill(Theme.glow.opacity(0.9))
                .frame(width: 22, height: 11)
                .rotationEffect(.degrees(pointsDown ? 180 : 0))
                .offset(x: arrowX - 11, y: pointsDown ? 11 : -11)
        }
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// The "?" button in the header.
struct HelpButton: View {
    @ObservedObject var face: FaceModel

    var body: some View {
        Button {
            face.helpMode.toggle()
            face.helpTopic = face.helpMode ? .help : nil
        } label: {
            Text("?")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(face.helpMode ? Theme.glow : Theme.text.opacity(0.9))
                .shadow(color: face.helpMode ? Theme.glow : .clear, radius: 6)
                .frame(width: 62, height: 54)
                .well(radius: 9, lit: face.helpMode)
        }
        .buttonStyle(.plain)
        .anchorPreference(key: HelpAnchorKey.self, value: .bounds) { [.help: $0] }
    }
}
