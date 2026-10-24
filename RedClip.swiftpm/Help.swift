import SwiftUI

// MARK: - Help: the "?" button next to Undo
//
// Works the same as Console E's "?" key: it switches help bubbles on and off (remembered between
// launches). With help on, every control still works normally, and touching it, or hovering over
// it with a trackpad, mouse or Apple Pencil, pops up a small bubble beside it explaining what it
// does. The bubble fades 3.5 seconds after it appears. Meters and readouts show theirs when touched.

enum HelpTopic: String, CaseIterable {
    case help, presets, ab, undo, power
    case inputMeter, outputMeter, screen, clipReadout
    case input, drive, ceiling, wet, dry, mixLink, output
    case red, redStyle, unity, fire, broil, boxTone, delta
    case clipMode, link, oversampling, bypass
    case play, load, samples, demo, export
    case clipClock

    var title: String {
        switch self {
        case .help: return "Help"
        case .presets: return "Presets"
        case .ab: return "A / B"
        case .undo: return "Undo"
        case .power: return "Power"
        case .inputMeter: return "Input Meter"
        case .outputMeter: return "Output Meter"
        case .screen:
            return "The last 120 ms of audio in dBFS. Grey is the signal going into the clipper, red is the clipped output, both lined up in time. The dashed lines are the ceiling, above and below zero: anything grey poking past them is what gets clipped off. Double-tap to zoom."
        case .clipReadout: return "Clip"
        case .input: return "Input"
        case .drive: return "Drive"
        case .ceiling: return "Ceiling"
        case .wet: return "Wet"
        case .dry: return "Dry"
        case .mixLink: return "Linked / Unlinked"
        case .output: return "Output"
        case .red: return "Red"
        case .redStyle: return "Red Style"
        case .unity: return "Unity Gain"
        case .fire: return "Fire"
        case .broil: return "Broil"
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
        case .clipClock: return "Clip Clock"
        }
    }

    var text: String {
        switch self {
        case .help:
            return "Turns these help bubbles on and off. With help on, touch or hover over any control to learn what it does."
        case .presets:
            return "Step through the presets with the arrows, or tap the name to pick one from the list."
        case .ab:
            return "Two separate setups. Dial in A, switch to B and try something different, then flip between them to compare."
        case .undo:
            return "Steps back through your last changes, one move at a time."
        case .power:
            return "Turns the Red Clip engine off. In a DAW the audio passes straight through untouched and uses no CPU."
        case .inputMeter:
            return "Level coming in, left and right, after the Input knob. The bar shows the average (RMS) level; the pink marker holds the last peak for a moment. Double-tap it to zoom the screen."
        case .outputMeter:
            return "Level going out, left and right. The bar shows the average (RMS) level; the pink marker holds the last peak for a moment. Double-tap it to zoom the screen."
        case .screen:
            return "The last 120 ms of audio in dBFS. Grey is the signal going into the clipper, so turning Input up pushes it toward the dashed ceiling lines; red is the final output. Anything grey past the lines is what gets clipped off. Double-tap the screen or either meter to zoom: +6 to -36, +4 to -24, +2 to -12 dB."
        case .clipReadout:
            return "How far the signal is going past the ceiling right now, in dB. 0.0 means nothing is being clipped."
        case .input:
            return "Sets the level coming into Red Clip. The input meter shows the result."
        case .drive:
            return "Pushes the signal harder into Red and the clipper without changing the input meter. More Drive means more clipping."
        case .ceiling:
            return "The level where clipping starts, from 0 down to -36 dB. The clipped signal never goes above it. Pulling it down moves the clip line (and Red and Fire with it) down to meet a quiet track, instead of turning the track up into it."
        case .wet:
            return "How much of the clipped, processed signal you hear. LINKED, it crossfades with Dry: more Wet means less Dry. UNLINKED, it is a level of its own."
        case .dry:
            return "How much of the original, unclipped signal you hear alongside the processed one. It stays perfectly in time with Wet, so blending never sounds phasey."
        case .mixLink:
            return "LINKED: Wet and Dry move together as one crossfade, always adding up to 100%. UNLINKED: set them separately, e.g. 100% Dry under a heavily driven Wet for bottom-up distortion, or clip gently and bring the peaks back with Dry."
        case .output:
            return "The final level after everything else. With LINK on, it moves the opposite way to Input."
        case .red:
            return "Adds up to 2.5 dB (Modern) or 6 dB (Classic) of non-linear gain. Quiet material gets the full boost, and the boost fades away to nothing as the signal reaches the ceiling, so the track gets louder while the peaks below the clip point stay intact."
        case .redStyle:
            return "How much Red can add: up to 2.5 dB in Modern, up to 6 dB in Classic. Either way the extra gain fades out to 0 dB right at the ceiling."
        case .unity:
            return "Takes the gain Red adds back off after all other processing. If Red adds 6 dB, the peaks come down 6 dB while the track keeps its perceived loudness, so you gain headroom without touching your transients."
        case .fire:
            return "Smooths the bright, edgy top end that clipping can leave. It dips the highs by up to about 1 dB, only when the signal is close to the ceiling."
        case .broil:
            return "Instant compression with no attack or release, like the squeeze of tape saturation but without changing the tone. The body of the sound gets denser and louder while peaks and transients at the ceiling stay exactly where they are."
        case .boxTone:
            return "A subtle converter-style tone above 1 kHz. Flat leaves it alone, Modern trims a little air, Classic is slightly darker."
        case .delta:
            return "Plays only the difference between the input and the processed sound, so you hear exactly what Red Clip is adding or taking away."
        case .clipMode:
            return "Hard works like Fruity Soft Clipper: clean up to 3 dB under the ceiling, then a smooth bend that lands flat on it. Classic has a soft knee and rounds peaks off gently. Modern sits in between with a medium knee."
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
            return "Everything in Files › On My iPad (or On My iPhone) › Red Clip › Samples. Drop your own audio in there and it shows up here."
        case .demo:
            return "Loads the built-in drum loop so you can try Red Clip straight away."
        case .export:
            return "Renders the whole file through your current settings to a 24-bit WAV you can save or share."
        case .clipClock:
            return "Finds the spot in the song where Red Clip clips hardest. MAX CLIP is the most the signal goes past the ceiling, MIN:SEC is where it happens. In the app it scans the whole file with your current settings and scans again whenever you change Input, Drive, Ceiling, Red or oversampling. In a DAW it follows playback, so play the song through; the arrow starts a new pass."
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

/// Marks a control for help. The control keeps working as usual; touching or hovering over it
/// shows its bubble while help is switched on.
struct HelpTarget: ViewModifier {
    @ObservedObject var face: FaceModel
    let topic: HelpTopic

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in face.showHelp(topic) }
                .onEnded { _ in face.helpTouchEnded(topic) })
            .onHover { inside in
                if inside { face.showHelp(topic) } else { face.hoverEnded(topic) }
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
    /// `scale` enlarges the bubble for faces drawn at a higher pixel density (the iPhone face).
    func helpBubbles(_ face: FaceModel, scale: CGFloat = 1) -> some View {
        overlayPreferenceValue(HelpAnchorKey.self) { anchors in
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    Color.clear
                    if let topic = face.helpTopic, let anchor = anchors[topic] {
                        let r = geo[anchor]
                        let width: CGFloat = 360
                        let height = HelpBubble.estimatedHeight(topic.text, width: width)
                        let c = HelpBubble.center(for: r, width: width * scale, height: height * scale, in: geo.size)
                        HelpBubble(topic: topic)
                            .frame(width: width)
                            .scaleEffect(scale)
                            .position(c)
                            .transition(.opacity)
                            .id(topic)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                .allowsHitTesting(false)
            }
            .animation(.easeOut(duration: 0.15), value: face.helpTopic)
        }
    }
}

/// A small smoked-glass plate with a red legend, in the faceplate's style.
struct HelpBubble: View {
    let topic: HelpTopic

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(topic.title.uppercased())
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(Theme.glow)
            Text(topic.text)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Theme.cream)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(LinearGradient(colors: [Color(red: 0.15, green: 0.12, blue: 0.13).opacity(0.97),
                                              Color(red: 0.06, green: 0.05, blue: 0.05).opacity(0.97)],
                                     startPoint: .top, endPoint: .bottom)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.22), lineWidth: 1.5))
        .overlay(RoundedRectangle(cornerRadius: 9).inset(by: 3).stroke(Color.black.opacity(0.7), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.75), radius: 9, x: 3, y: 6)
    }

    /// Beside the control (right if there is room, else left); under it for the top row.
    /// Always kept inside the faceplate.
    static func center(for rect: CGRect, width: CGFloat, height: CGFloat, in size: CGSize) -> CGPoint {
        if rect.maxY < 120 {
            let x = min(size.width - width / 2 - 12, max(width / 2 + 12, rect.midX))
            return CGPoint(x: x, y: rect.maxY + 16 + height / 2)
        }
        if width > size.width * 0.55 {
            // narrow face (iPhone): under the control if it fits, otherwise above it
            let x = size.width / 2
            let below = rect.maxY + 16 + height / 2
            if below + height / 2 < size.height - 12 { return CGPoint(x: x, y: below) }
            return CGPoint(x: x, y: max(height / 2 + 12, rect.minY - 16 - height / 2))
        }
        var x = rect.maxX + 16 + width / 2
        if x + width / 2 > size.width - 12 { x = rect.minX - 16 - width / 2 }
        x = min(size.width - width / 2 - 12, max(width / 2 + 12, x))
        let y = min(size.height - height / 2 - 12, max(height / 2 + 12, rect.midY))
        return CGPoint(x: x, y: y)
    }

    static func estimatedHeight(_ text: String, width: CGFloat) -> CGFloat {
        let perLine = max(1, Int((width - 32) / 9.4))
        let lines = (text.count + perLine - 1) / perLine
        return 52 + CGFloat(lines) * 23
    }
}

/// The "?" key in the header: lit while help bubbles are on.
struct HelpButton: View {
    @ObservedObject var face: FaceModel

    var body: some View {
        Button {
            face.helpEnabled.toggle()
            if face.helpEnabled { face.showHelp(.help) }
        } label: {
            Text("?")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(face.helpEnabled ? Theme.glow : Theme.text.opacity(0.9))
                .shadow(color: face.helpEnabled ? Theme.glow : .clear, radius: 6)
                .frame(width: 62, height: 54)
                .well(radius: 9, lit: face.helpEnabled)
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { face.showHelp(.help) } else { face.hoverEnded(.help) }
        }
        .anchorPreference(key: HelpAnchorKey.self, value: .bounds) { [.help: $0] }
        .accessibilityLabel("Help bubbles")
        .accessibilityValue(face.helpEnabled ? "On" : "Off")
    }
}
