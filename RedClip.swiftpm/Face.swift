import SwiftUI

/// Everything the faceplate needs, shared by the app and the AUv3 plug-in.
@MainActor
final class FaceModel: ObservableObject {
    let shared: SharedState
    let params: ParamStore
    let meters: MeterReader
    let isPlugin: Bool

    @Published private(set) var isPowered = true
    /// The "?" help switch (remembered between launches) and the control whose bubble is showing.
    private static let helpKey = "RedClip.HelpBubbles"
    @Published var helpEnabled: Bool = UserDefaults.standard.bool(forKey: FaceModel.helpKey) {
        didSet {
            UserDefaults.standard.set(helpEnabled, forKey: Self.helpKey)
            if !helpEnabled { helpTopic = nil }
        }
    }
    @Published private(set) var helpTopic: HelpTopic?

    /// Which finish the faceplate shows: Face1 (red) or Face1_platinum. Remembered between launches.
    private static let faceKey = "RedClip.Faceplate"
    @Published var faceplate: Faceplate = Faceplate(rawValue: UserDefaults.standard.string(forKey: FaceModel.faceKey) ?? "") ?? .face1 {
        didSet { UserDefaults.standard.set(faceplate.rawValue, forKey: Self.faceKey) }
    }
    var theme: PlateTheme { faceplate == .face1Platinum ? .platinum : .red }
    private var helpHide: DispatchWorkItem?
    /// The app stops / starts its audio engine here; the plug-in just passes audio through.
    var onPowerChange: ((Bool) -> Void)?

    // Audio page of the top menu (standalone app only; in a DAW the host supplies the audio)
    @Published var sampleFiles: [SampleItem] = []
    @Published var importRequested = false
    var loadSample: ((URL) -> Void)?
    var loadDemo: (() -> Void)?

    init(isPlugin: Bool) {
        let state = SharedState()
        shared = state
        params = ParamStore(shared: state)
        meters = MeterReader(shared: state)
        self.isPlugin = isPlugin
    }

    func setPowered(_ on: Bool) {
        guard on != isPowered else { return }
        isPowered = on
        shared.power.pointee = on ? 1 : 0
        onPowerChange?(on)
    }

    func togglePower() { setPowered(!isPowered) }

    /// Shows a control's bubble (only while help is switched on); it fades after 6 seconds.
    func showHelp(_ topic: HelpTopic) {
        guard helpEnabled else { return }
        if helpTopic != topic { helpTopic = topic }
        scheduleHelpHide(topic, after: 6)
    }

    /// The pointer left a control: keep the bubble a moment so it can still be read.
    func hoverEnded(_ topic: HelpTopic) {
        guard helpTopic == topic else { return }
        scheduleHelpHide(topic, after: 1.5)
    }

    private func scheduleHelpHide(_ topic: HelpTopic, after seconds: Double) {
        helpHide?.cancel()
        let hide = DispatchWorkItem { [weak self] in
            if self?.helpTopic == topic { self?.helpTopic = nil }
        }
        helpHide = hide
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: hide)
    }
}

/// One file in the Samples folder, for the top menu.
struct SampleItem: Identifiable, Hashable {
    let url: URL
    let name: String
    var id: URL { url }
}

// MARK: - Names and units for the host (Logic shows these in automation lanes)

extension Param {
    /// Stable identifier, used for saved projects. Never rename these.
    var id: String { String(describing: self) }

    var title: String {
        switch self {
        case .inputDB: return "Input"
        case .driveDB: return "Drive"
        case .ceilingDB: return "Ceiling"
        case .mix: return "Mix"
        case .outputDB: return "Output"
        case .clipMode: return "Clip Mode"
        case .oversampling: return "Oversampling"
        case .link: return "Link"
        case .bypass: return "Bypass"
        case .gold: return "Red"
        case .goldMode: return "Red Mode"
        case .unity: return "Unity Gain"
        case .alchemy: return "Fire"
        case .boxTone: return "Box Tone"
        case .delta: return "Delta"
        }
    }

    /// Names for stepped controls, nil for continuous ones.
    var valueNames: [String]? {
        switch self {
        case .clipMode: return ["Hard", "Classic", "Modern"]
        case .oversampling: return ["1x", "2x", "4x"]
        case .goldMode: return ["Modern", "Classic"]
        case .boxTone: return ["Flat", "Modern", "Classic"]
        case .link, .bypass, .unity, .delta: return ["Off", "On"]
        default: return nil
        }
    }

    var isDecibels: Bool { self == .inputDB || self == .driveDB || self == .ceilingDB || self == .outputDB }
}
