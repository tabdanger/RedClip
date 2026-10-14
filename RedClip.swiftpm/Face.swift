import SwiftUI

/// Everything the faceplate needs, shared by the app and the AUv3 plug-in.
@MainActor
final class FaceModel: ObservableObject {
    let shared: SharedState
    let params: ParamStore
    let meters: MeterReader
    let isPlugin: Bool

    @Published private(set) var isPowered = true
    /// The "?" help mode and the control whose explanation is showing.
    @Published var helpMode = false
    @Published var helpTopic: HelpTopic?
    /// The app stops / starts its audio engine here; the plug-in just passes audio through.
    var onPowerChange: ((Bool) -> Void)?

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
