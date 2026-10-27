import SwiftUI

// MARK: - Help: the "?" button next to Undo
//
// The "?" key switches help mode on and off (remembered between launches). While it is lit, one
// clear layer over the faceplate takes every touch and every trackpad, mouse or Apple Pencil hover:
// whatever control is under it gets a small bubble explaining what it does, and the control itself
// is left alone. The bubble fades 3.5 seconds after it appears. Tap "?" again to switch help off.
// Finding the control from the layer, rather than from gestures on each control, means it works
// the same on knobs, buttons, meters and the screen, whatever gestures they have of their own.
//
// The first time the app opens, a tour (HelpTour) steps through every knob and button using the
// same bubbles; it can be skipped and never comes back by itself.

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
        case .screen: return "Waveform"
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
            return "Help mode. While ? is lit, touch or hover over any knob or button and a bubble explains what it does, without changing it. Tap ? again to switch help off and get back to work."
        case .presets:
            return "Step through the presets with the arrows, or tap the name to pick one from the list."
        case .ab:
            return "Two separate setups. Dial in A, switch to B and try something different, then flip between them to compare."
        case .undo:
            return "Steps back through your last changes, one move at a time."
        case .power:
            return "Turns the Red Clip engine off. In a DAW the audio passes straight through untouched and uses no CPU."
        case .inputMeter:
            return "Level coming in, left and right, after the Input knob. The bar shows the average (RMS) level; the pink marker holds the last peak for a moment. Double-tap it to zoom the waveform."
        case .outputMeter:
            return "Level going out, left and right. The bar shows the average (RMS) level; the pink marker holds the last peak for a moment. Double-tap it to zoom the waveform."
        case .screen:
            return "The last few seconds as they play, in dBFS, like Gold Clip's display. Grey is the signal going into the clipper (after Input and Drive), white is the clipped signal coming out of it (before Wet / Dry and Output), and red marks where the clipper is cutting. The amber line and the needle on the right are the Ceiling. The red marker is where the biggest clip since the last reset happened; turning a knob that changes the clipping, or loading new audio, starts a new count. Double-tap the scale or either meter to zoom: +6 to -36, +4 to -24, +2 to -12 dBFS."
        case .clipReadout:
            return "How much the clipper is taking off right now, in dB: the biggest cut it makes to any single sample, measured straight across the clipper with the Clip Mode you picked. Hard only starts 3 dB under the ceiling and Classic and Modern bend in softly, so it can read above 0 before the signal reaches the ceiling. Wet / Dry and Output don't change it. 0.0 means nothing is being clipped."
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
            return "The loudest point of your original audio and when it happens, measured before Input, Drive or any other control, so turning knobs never changes or restarts it. In the app it reads the whole file the moment it loads. In a DAW it follows playback, so play the song through; the arrow starts a new pass."
        }
    }
}

/// Where each control sits, so one bubble can be drawn above whichever is selected. A topic can
/// cover more than one area (the preset arrows and name are all "Presets").
struct HelpAnchorKey: PreferenceKey {
    static let defaultValue: [HelpTopic: [Anchor<CGRect>]] = [:]
    static func reduce(value: inout [HelpTopic: [Anchor<CGRect>]], nextValue: () -> [HelpTopic: [Anchor<CGRect>]]) {
        value.merge(nextValue()) { $0 + $1 }
    }
}

/// Marks a control for help: records where it is. The help layer over the faceplate does the rest,
/// so the control's own gestures are untouched.
struct HelpTarget: ViewModifier {
    let topic: HelpTopic

    func body(content: Content) -> some View {
        content.anchorPreference(key: HelpAnchorKey.self, value: .bounds) { [topic: [$0]] }
    }
}

extension View {
    func helpTarget(_ topic: HelpTopic, _ face: FaceModel) -> some View {
        modifier(HelpTarget(topic: topic))
    }

    /// Draws the help layer, the bubble and the first-launch tour. Put it on the unscaled
    /// design-size container (the faceplate, or the faceplate plus the transport strip).
    /// `scale` enlarges the bubble for faces drawn at a higher pixel density (the iPhone face).
    func helpBubbles(_ face: FaceModel, scale: CGFloat = 1) -> some View {
        overlayPreferenceValue(HelpAnchorKey.self) { anchors in
            GeometryReader { geo in
                HelpLayer(face: face, areas: HelpAreas(anchors.mapValues { $0.map { geo[$0] } }),
                          size: geo.size, scale: scale)
            }
        }
    }
}

/// Every help area in the container's coordinates.
struct HelpAreas {
    let rects: [HelpTopic: [CGRect]]

    init(_ rects: [HelpTopic: [CGRect]]) { self.rects = rects }

    /// The whole area of a topic, for placing its bubble.
    func frame(_ topic: HelpTopic) -> CGRect? {
        guard let first = rects[topic]?.first else { return nil }
        return rects[topic]!.dropFirst().reduce(first) { $0.union($1) }
    }

    /// The control under a point: the smallest area that holds it, so a button on top of a bigger
    /// panel wins over the panel.
    func topic(at p: CGPoint) -> HelpTopic? {
        var best: (HelpTopic, CGFloat)?
        for (topic, list) in rects {
            for r in list where r.contains(p) {
                let area = r.width * r.height
                if best == nil || area < best!.1 { best = (topic, area) }
            }
        }
        return best?.0
    }
}

/// The help mode catcher, the bubble and the tour.
struct HelpLayer: View {
    @ObservedObject var face: FaceModel
    let areas: HelpAreas
    let size: CGSize
    let scale: CGFloat
    @State private var touched: HelpTopic?
    @State private var hovered: HelpTopic?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            if face.tourStep != nil {
                HelpTour(face: face, areas: areas, size: size, scale: scale)
            } else {
                if face.helpEnabled { catcher }
                bubble.allowsHitTesting(false)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .animation(.easeOut(duration: 0.15), value: face.helpTopic)
        .animation(.easeOut(duration: 0.2), value: face.tourStep)
    }

    /// Help mode: takes the touch or hover instead of the control and shows that control's bubble.
    private var catcher: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let t = areas.topic(at: v.location)
                        if t != touched, let old = touched { face.helpTouchEnded(old) }
                        touched = t
                        if let t { face.showHelp(t) }
                    }
                    .onEnded { v in
                        if let t = touched { face.helpTouchEnded(t) }
                        touched = nil
                        // tapping "?" again switches help mode off
                        if let r = areas.frame(.help), r.contains(v.location), r.contains(v.startLocation) {
                            face.helpEnabled = false
                        }
                    }
            )
            .onContinuousHover { phase in
                var t: HelpTopic?
                if case .active(let p) = phase { t = areas.topic(at: p) }
                guard t != hovered else { return }
                if let old = hovered { face.hoverEnded(old) }
                hovered = t
                if let t { face.showHelp(t) }
            }
            .accessibilityHidden(true)
    }

    @ViewBuilder private var bubble: some View {
        if let topic = face.helpTopic, let r = areas.frame(topic) {
            let width: CGFloat = 360
            let height = HelpBubble.estimatedHeight(topic.text, width: width)
            let c = HelpBubble.center(for: r, width: width * scale, height: height * scale, in: size)
            HelpBubble(topic: topic)
                .frame(width: width)
                .scaleEffect(scale)
                .position(c)
                .transition(.opacity)
                .id(topic)
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
        .anchorPreference(key: HelpAnchorKey.self, value: .bounds) { [.help: [$0]] }
        .accessibilityLabel("Help bubbles")
        .accessibilityValue(face.helpEnabled ? "On" : "Off")
    }
}
