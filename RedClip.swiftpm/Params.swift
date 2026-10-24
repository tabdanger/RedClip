import SwiftUI

// MARK: - Parameters for the UI

/// Holds every control value, plus A/B slots, undo history and Gold Clip-style Input/Output trim linking.
@MainActor
final class ParamStore: ObservableObject {
    let shared: SharedState
    @Published private(set) var values: [Float]
    @Published private(set) var onB = false
    @Published private(set) var presetIndex = 0
    @Published private(set) var canUndo = false

    /// Called for every change made on the face (knob, preset, A/B, undo) so the plug-in can
    /// pass it to the host for automation. Not called for changes that came from the host.
    var onChange: ((Param, Float) -> Void)?

    private var slots: [[Float]]
    private var undoStack: [[Float]] = []
    private var lastEdit = Date.distantPast

    init(shared: SharedState) {
        self.shared = shared
        let defaults = Param.allCases.map { $0.defaultValue }
        values = defaults
        slots = [defaults, defaults]
        push(defaults)
    }

    var presetName: String { Preset.factory[presetIndex].name }

    subscript(p: Param) -> Float {
        get { values[p.rawValue] }
        set {
            let v = clamp(p, newValue)
            let old = values[p.rawValue]
            guard v != old else { return }
            if p != .bypass { registerUndo() }
            if p == .mixUnlink { handOverMixer(unlinking: v > 0.5) }
            write(p, v)
            // LINK: Input and Output trims move in opposite directions, so level stays put
            if values[Param.link.rawValue] > 0.5 {
                if p == .inputDB { write(.outputDB, clamp(.outputDB, self[.outputDB] - (v - old))) }
                if p == .outputDB { write(.inputDB, clamp(.inputDB, self[.inputDB] - (v - old))) }
            }
        }
    }

    /// MIXER: unlinking starts Dry and Wet where Mix had them, so the sound doesn't jump;
    /// relinking keeps the same dry / wet balance. Written before the switch itself, so the
    /// audio never sees the new mode with the old levels.
    private func handOverMixer(unlinking: Bool) {
        let mix = self[.mix], dry = self[.dry], wet = self[.wet]
        if unlinking {
            write(.wet, mix)
            write(.dry, 100 - mix)
        } else if dry + wet > 0 {
            write(.mix, clamp(.mix, (wet / (dry + wet) * 100).rounded()))
        }
    }

    var mixUnlinked: Bool { self[.mixUnlink] > 0.5 }

    /// One side of the parallel mixer (the faceplate's Wet and Dry knobs). Linked, both move the Mix level (Dry = 100 - Mix);
    /// unlinked, each side is its own control.
    func mixerBinding(wet: Bool) -> Binding<Float> {
        Binding(get: {
            if self.mixUnlinked { return self[wet ? .wet : .dry] }
            return wet ? self[.mix] : 100 - self[.mix]
        }, set: { v in
            if self.mixUnlinked { self[wet ? .wet : .dry] = v } else { self[.mix] = wet ? v : 100 - v }
        })
    }

    func binding(_ p: Param) -> Binding<Float> {
        Binding(get: { self[p] }, set: { self[p] = $0 })
    }

    func flag(_ p: Param) -> Binding<Bool> {
        Binding(get: { self[p] > 0.5 }, set: { self[p] = $0 ? 1 : 0 })
    }

    // MARK: Presets, A/B, undo

    func apply(_ index: Int) {
        let n = Preset.factory.count
        presetIndex = ((index % n) + n) % n
        let preset = Preset.factory[presetIndex]
        lastEdit = .distantPast
        registerUndo()
        var v = Param.allCases.map { preset.values[$0] ?? $0.defaultValue }
        v[Param.bypass.rawValue] = values[Param.bypass.rawValue]   // presets don't touch bypass
        push(v)
    }

    func stepPreset(_ d: Int) { apply(presetIndex + d) }

    func selectSlot(b: Bool) {
        guard b != onB else { return }
        slots[onB ? 1 : 0] = values
        onB = b
        var v = slots[b ? 1 : 0]
        v[Param.bypass.rawValue] = values[Param.bypass.rawValue]
        push(v)
    }

    func undo() {
        guard let last = undoStack.popLast() else { return }
        push(last)
        lastEdit = .distantPast
        canUndo = !undoStack.isEmpty
    }

    /// One undo step per gesture: edits closer together than 0.6 s are grouped.
    private func registerUndo() {
        let now = Date()
        if now.timeIntervalSince(lastEdit) > 0.6 {
            undoStack.append(values)
            if undoStack.count > 50 { undoStack.removeFirst() }
            canUndo = true
        }
        lastEdit = now
    }

    private func clamp(_ p: Param, _ v: Float) -> Float { min(max(v, p.range.lowerBound), p.range.upperBound) }

    private func write(_ p: Param, _ v: Float) {
        values[p.rawValue] = v
        shared[p] = v
        onChange?(p, v)
    }

    private func push(_ v: [Float], notify: Bool = true) {
        values = v
        for p in Param.allCases {
            shared[p] = v[p.rawValue]
            if notify { onChange?(p, v[p.rawValue]) }
        }
    }

    // MARK: Host (AUv3)

    /// A value the host set (automation, a host preset). The audio side already has it.
    func applyFromHost(_ p: Param, _ v: Float) {
        let v = clamp(p, v)
        guard values[p.rawValue] != v else { return }
        values[p.rawValue] = v
        shared[p] = v
    }

    /// Restores a saved state (host project) without adding an undo step.
    func restore(_ v: [Float]) {
        guard v.count == Param.allCases.count else { return }
        push(Param.allCases.map { clamp($0, v[$0.rawValue]) }, notify: false)
    }

    var snapshot: [Float] { values }

    /// Plug-in: picks up values the host changed on the audio side (automation playback),
    /// so knobs follow Logic's automation lanes. Called about 10 times a second.
    func syncFromShared() {
        var v = values
        var changed = false
        for p in Param.allCases where shared[p] != v[p.rawValue] {
            v[p.rawValue] = shared[p]
            changed = true
        }
        if changed { values = v }
    }
}

struct Preset: Identifiable {
    let bank: String
    let name: String
    let values: [Param: Float]
    var id: String { bank + "/" + name }

    /// Bank names in menu order (factory list order).
    static let banks: [String] = {
        var seen: [String] = []
        for p in factory where !seen.contains(p.bank) { seen.append(p.bank) }
        return seen
    }()
}
