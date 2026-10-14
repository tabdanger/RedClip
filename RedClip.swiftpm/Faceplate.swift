import SwiftUI

/// The Red Clip faceplate at its design size (1448 x 1276). The app and the AUv3 plug-in
/// both show this; each scales it to fit its window.
@MainActor
struct FaceplateView: View {
    @ObservedObject var face: FaceModel
    @ObservedObject var params: ParamStore

    static let size = CGSize(width: 1448, height: 1276)

    var body: some View {
        faceplate.frame(width: Self.size.width, height: Self.size.height)
    }

    // MARK: Faceplate

    private var faceplate: some View {
        VStack(spacing: 0) {
            header.frame(height: 108)
            Groove()
            displaySection.frame(height: 440)
            Groove()
            knobRow.frame(height: 360)
            Groove()
            goldRow.frame(height: 190)
            Groove()
            bottomRow.frame(height: 166)
        }
        .background(BrushedRed())
        .overlay(alignment: .topLeading) { Screw().padding(12) }
        .overlay(alignment: .topTrailing) { Screw().padding(12) }
        .overlay(alignment: .bottomLeading) { Screw().padding(12) }
        .overlay(alignment: .bottomTrailing) { Screw().padding(12) }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text("RED CLIP")
                .font(.system(size: 30, weight: .regular))
                .tracking(13)
                .foregroundStyle(Theme.text)
                .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
                .frame(width: 440, alignment: .leading)
                .padding(.leading, 62)

            // preset selector
            HStack {
                Button { params.stepPreset(-1) } label: {
                    Image(systemName: "chevron.left").frame(width: 50, height: 56)
                }
                Spacer()
                Menu {
                    ForEach(Preset.factory.indices, id: \.self) { i in
                        Button(Preset.factory[i].name) { params.apply(i) }
                    }
                } label: {
                    Text(params.presetName).font(.system(size: 23, weight: .regular)).foregroundStyle(Theme.text)
                }
                Spacer()
                Button { params.stepPreset(1) } label: {
                    Image(systemName: "chevron.right").frame(width: 50, height: 56)
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 24, weight: .medium))
            .foregroundStyle(Theme.text)
            .frame(width: 400, height: 54)
            .well(radius: 10)
            .helpTarget(.presets, face)

            Spacer().frame(width: 46)

            // A / B
            HStack(spacing: 0) {
                abButton("A", on: !params.onB) { params.selectSlot(b: false) }
                abButton("B", on: params.onB) { params.selectSlot(b: true) }
            }
            .padding(4)
            .frame(width: 124, height: 54)
            .well(radius: 10)
            .helpTarget(.ab, face)

            Spacer().frame(width: 44)
            VGroove().frame(height: 54)
            Spacer().frame(width: 24)
            IconButton(icon: "arrow.uturn.backward", enabled: params.canUndo) { params.undo() }
                .helpTarget(.undo, face)
            Spacer().frame(width: 14)
            HelpButton(face: face)
            Spacer().frame(width: 24)
            VGroove().frame(height: 54)
            Spacer().frame(width: 26)
            PowerButton(isOn: face.isPowered) { face.togglePower() }
                .helpTarget(.power, face)
            Spacer()
        }
    }

    private func abButton(_ t: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(t)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(on ? Theme.glow : Theme.dimOnDark)
                .shadow(color: on ? Theme.glow : .clear, radius: 5)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 7)
                    .fill(on ? Theme.redDark.opacity(0.75) : .clear))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(on ? Theme.glow.opacity(0.6) : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var displaySection: some View {
        HStack(alignment: .top, spacing: 0) {
            LEDMeter(title: "Input", reader: face.meters, isInput: true)
                .frame(width: 150, height: 370)
                .helpTarget(.inputMeter, face)
                .padding(.leading, 40)
                .padding(.top, 28)
            VStack(spacing: 14) {
                WaveformView(shared: face.shared, ceilingDB: params[.ceilingDB], reader: face.meters)
                    .frame(width: 1030, height: 335)
                    .helpTarget(.screen, face)
                ClipReadout(reader: face.meters)
                    .helpTarget(.clipReadout, face)
            }
            .padding(.top, 24)
            .frame(maxWidth: .infinity)
            LEDMeter(title: "Output", reader: face.meters, isInput: false)
                .frame(width: 150, height: 370)
                .helpTarget(.outputMeter, face)
                .padding(.trailing, 28)
                .padding(.top, 28)
        }
    }

    private var knobRow: some View {
        HStack(spacing: 0) {
            knob("Input", .inputDB, "-12", "+12", Fmt.db, .input)
            knob("Drive", .driveDB, "0", "12", Fmt.dbPlain, .drive)
            knob("Ceiling", .ceilingDB, "-12", "0", Fmt.dbPlain, .ceiling)
            knob("Mix", .mix, "0", "100", Fmt.pct, .mix)
            knob("Output", .outputDB, "-12", "+12", Fmt.db, .output)
        }
        .padding(.horizontal, 30)
    }

    private func knob(_ title: String, _ p: Param, _ lo: String, _ hi: String,
                      _ f: @escaping (Float) -> String, _ topic: HelpTopic) -> some View {
        Knob(title: title, value: params.binding(p), range: p.range, defaultValue: p.defaultValue,
             diameter: 200, minLabel: lo, maxLabel: hi, format: f)
            .helpTarget(topic, face)
            .frame(maxWidth: .infinity)
    }

    /// Gold Clip's extra processing, built in the same style as the face.
    private var goldRow: some View {
        HStack(alignment: .center, spacing: 0) {
            // GOLD
            HStack(spacing: 22) {
                Knob(title: "Red", value: params.binding(.gold), range: Param.gold.range, defaultValue: 0,
                     diameter: 110, minLabel: "0", maxLabel: "100", format: Fmt.pct)
                    .helpTarget(.red, face)
                VStack(spacing: 12) {
                    Segments(options: ["Modern", "Classic"], selection: params.binding(.goldMode),
                             height: 46, fontSize: 16)
                        .frame(width: 230)
                        .helpTarget(.redStyle, face)
                    GlowButton(title: "Unity Gain", isOn: params.flag(.unity), height: 46, fontSize: 16)
                        .helpTarget(.unity, face)
                }
            }
            .frame(maxWidth: .infinity)

            VGroove().frame(height: 130)

            // ALCHEMY
            Knob(title: "Fire", value: params.binding(.alchemy), range: Param.alchemy.range, defaultValue: 0,
                 diameter: 110, minLabel: "0", maxLabel: "100", format: Fmt.pct)
                .helpTarget(.fire, face)
                .frame(width: 260)

            VGroove().frame(height: 130)

            // BOX TONE
            VStack(spacing: 14) {
                Theme.label("Box Tone", size: 18)
                Segments(options: ["Flat", "Modern", "Classic"], selection: params.binding(.boxTone),
                         height: 50, fontSize: 16)
                    .frame(width: 320)
            }
            .helpTarget(.boxTone, face)
            .frame(width: 380)

            VGroove().frame(height: 130)

            // DELTA
            VStack(spacing: 14) {
                Theme.label("Listen", size: 18)
                GlowButton(title: "Delta", icon: "triangle", isOn: params.flag(.delta), height: 54, fontSize: 18)
                    .helpTarget(.delta, face)
            }
            .frame(width: 230)
        }
        .padding(.horizontal, 30)
    }

    private var bottomRow: some View {
        HStack(spacing: 0) {
            VStack(spacing: 14) {
                Theme.label("Clip Mode", size: 18)
                Segments(options: ["Hard", "Classic", "Modern"], selection: params.binding(.clipMode))
                    .frame(width: 390)
            }
            .helpTarget(.clipMode, face)
            .frame(width: 470)
            VGroove().frame(height: 80)
            GlowButton(title: "Link", icon: "link", isOn: params.flag(.link))
                .helpTarget(.link, face)
                .frame(width: 230)
            VGroove().frame(height: 80)
            VStack(spacing: 14) {
                Theme.label("Oversampling", size: 18)
                Segments(options: ["1x", "2x", "4x"], selection: params.binding(.oversampling))
                    .frame(width: 356)
            }
            .helpTarget(.oversampling, face)
            .frame(width: 430)
            VGroove().frame(height: 80)
            LEDButton(title: "Bypass", isOn: params.flag(.bypass))
                .helpTarget(.bypass, face)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 30)
        .padding(.top, 6)
    }

}
