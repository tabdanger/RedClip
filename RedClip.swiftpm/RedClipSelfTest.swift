import Foundation
import SwiftUI

// MARK: - Self-Test (REDCLIP MENU › Settings › Self-Test)
//
// An on-device check of Red Clip's own logic, for builds that can't run the XCTest suite (there
// is no Mac). It runs the meaningful checks from Tests/RedClipTests as plain code, plus checks of
// its own, and reports how many checks ran and what failed, in plain language.
//
// Nothing here touches the live engine: every audio check builds its own SharedState and ClipDSP
// (like the exporter and the SONG preview do), renders on a background task and throws them
// away. The settings checks use their own ParamStore. The live sound, settings, undo history,
// meters and screen are never read or written, and the audio thread never sees any of this.

/// What one run found. `text` is the version the Copy button puts on the clipboard.
struct SelfTestReport: Sendable {
    let checks: Int
    let failures: [String]
    let seconds: Double
    let isPlugin: Bool

    var passed: Bool { failures.isEmpty && checks > 0 }

    var text: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        var lines = [
            "Red Clip Self-Test: \(passed ? "PASSED" : "FAILED")",
            "\(checks) checks, \(failures.count) failed, \(String(format: "%.1f", seconds)) s",
            "Red Clip \(version) (build \(build)), \(isPlugin ? "AUv3 plug-in" : "app"), "
                + ProcessInfo.processInfo.operatingSystemVersionString
        ]
        if !failures.isEmpty {
            lines.append("")
            lines.append("Failures:")
            lines += failures.map { "- " + $0 }
        }
        return lines.joined(separator: "\n")
    }
}

/// Counts checks and collects the failures. Each check returns nil when it passes, or a
/// plain-language reason when it doesn't.
struct SelfTestTally: Sendable {
    private(set) var count = 0
    private(set) var failures: [String] = []

    mutating func check(_ name: String, _ problem: () -> String?) {
        count += 1
        if let reason = problem() { failures.append("\(name): \(reason)") }
    }
}

/// Runs the Self-Test and keeps the last result (one per process: the app, or the plug-in).
@MainActor
final class SelfTestRunner: ObservableObject {
    static let shared = SelfTestRunner()

    @Published private(set) var running = false
    @Published private(set) var report: SelfTestReport?

    func start(isPlugin: Bool) {
        guard !running else { return }
        running = true
        report = nil
        let started = Date()
        Task {
            await Task.yield()                          // let the spinner show first
            // ParamStore lives on the main actor; this part uses a fresh store and takes a few ms
            let settings = RedClipSelfTest.settingsChecks()
            // all the audio rendering runs off the main thread, on private engines
            let tally = await Task.detached(priority: .userInitiated) { () -> SelfTestTally in
                var t = settings
                RedClipSelfTest.engineChecks(&t)
                return t
            }.value
            report = SelfTestReport(checks: tally.count, failures: tally.failures,
                                    seconds: Date().timeIntervalSince(started), isPlugin: isPlugin)
            running = false
        }
    }
}

// MARK: - The checks

enum RedClipSelfTest {

    // MARK: Settings (main actor: a fresh ParamStore, never the live one)

    @MainActor
    static func settingsChecks() -> SelfTestTally {
        var t = SelfTestTally()
        let store = ParamStore(shared: SharedState(captureCapacity: 64))

        t.check("Parameter map") {
            if store.snapshot.count != Param.allCases.count {
                return "the settings store holds \(store.snapshot.count) values for \(Param.allCases.count) controls"
            }
            for p in Param.allCases {
                if store[p] != p.defaultValue { return "\(p.title) starts at \(num(store[p])) instead of its default \(num(p.defaultValue))" }
                if store.shared[p] != p.defaultValue { return "the engine starts with \(p.title) at \(num(store.shared[p])) instead of \(num(p.defaultValue))" }
            }
            return nil
        }

        // Every factory preset brings back exactly the settings it was made with, in the face
        // and in the engine, and leaves Bypass alone.
        store[.bypass] = 1
        for (index, preset) in Preset.factory.enumerated() {
            t.check("Preset \"\(preset.name)\"") {
                store.apply(index)
                if store.presetIndex != index || store.presetName != preset.name {
                    return "loading it selected \"\(store.presetName)\" instead"
                }
                for p in Param.allCases where p != .bypass {
                    let want = preset.values[p] ?? p.defaultValue
                    if !p.range.contains(want) { return "\(p.title) is set to \(num(want)), outside its range" }
                    if p.valueNames != nil && want != want.rounded() { return "\(p.title) is set between two steps (\(num(want)))" }
                    if store[p] != want { return "\(p.title) came back as \(num(store[p])) instead of \(num(want))" }
                    if store.shared[p] != want { return "the engine got \(p.title) = \(num(store.shared[p])) instead of \(num(want))" }
                }
                if store[.bypass] != 1 { return "loading it changed Bypass" }
                return nil
            }
        }
        store[.bypass] = 0

        t.check("Saved state") {
            let n = Preset.factory.count
            store.apply(min(3, n - 1))
            store[.driveDB] = 7.5
            store[.ceilingDB] = -4.25
            let saved = store.snapshot
            store.apply(min(10, n - 1))
            store[.mix] = 20
            store.restore(saved)
            for p in Param.allCases {
                let want = saved[p.rawValue]
                if store[p] != want { return "after restoring, \(p.title) is \(num(store[p])) instead of \(num(want))" }
                if store.shared[p] != want { return "after restoring, the engine has \(p.title) = \(num(store.shared[p])) instead of \(num(want))" }
            }
            return nil
        }

        t.check("A / B") {
            store.apply(0)
            store.selectSlot(b: false)
            store[.driveDB] = 5
            store.selectSlot(b: true)
            store[.driveDB] = 9
            store.selectSlot(b: false)
            if store[.driveDB] != 5 { return "A came back with Drive \(num(store[.driveDB])) instead of 5" }
            store.selectSlot(b: true)
            if store[.driveDB] != 9 { return "B came back with Drive \(num(store[.driveDB])) instead of 9" }
            store.selectSlot(b: false)
            return nil
        }

        t.check("Undo") {
            let before = store.snapshot
            store.apply(min(1, Preset.factory.count - 1))
            let loaded = store.snapshot
            store[.driveDB] = 11
            guard store.canUndo else { return "nothing to undo after a change" }
            store.undo()
            // the preset and the knob move may count as one step (they were less than 0.6 s apart)
            if store.snapshot != before && store.snapshot != loaded { return "undo didn't go back to an earlier state" }
            return nil
        }

        t.check("Link") {
            store.apply(0)
            store[.link] = 1
            store[.inputDB] = 3
            if store[.outputDB] != -3 { return "Input +3 dB moved Output to \(num(store[.outputDB])) instead of -3" }
            store[.outputDB] = -5
            if store[.inputDB] != 5 { return "Output -5 dB moved Input to \(num(store[.inputDB])) instead of +5" }
            store[.link] = 0
            store[.inputDB] = 0
            if store[.outputDB] != -5 { return "with Link off, Input still moved Output" }
            return nil
        }

        t.check("Linked / Unlinked mixer") {
            store.apply(0)
            store[.mix] = 30
            store[.mixUnlink] = 1
            if store[.wet] != 30 || store[.dry] != 70 {
                return "unlinking at Mix 30 % gave Wet \(num(store[.wet])) / Dry \(num(store[.dry])) instead of 30 / 70"
            }
            store[.dry] = 100
            store[.wet] = 50
            store[.mixUnlink] = 0
            if store[.mix] != 33 { return "relinking Dry 100 / Wet 50 gave Mix \(num(store[.mix])) instead of 33" }
            store.mixerBinding(wet: false).wrappedValue = 80
            if store[.mix] != 20 { return "linked, Dry 80 % gave Mix \(num(store[.mix])) instead of 20" }
            return nil
        }
        return t
    }

    // MARK: Engine and logic (any thread: private engines only)

    static func engineChecks(_ t: inout SelfTestTally) {
        parameterMapChecks(&t)
        curveChecks(&t)
        ceilingChecks(&t)
        redChecks(&t)
        finiteChecks(&t)
        silenceChecks(&t)
        oversamplingChecks(&t)
        mixerChecks(&t)
        meterAndClipChecks(&t)
        screenAndLayoutChecks(&t)
        knobChecks(&t)
    }

    // MARK: Knobs: readout = engine at every 1 %, even % knobs, 5 ms response (KnobTaperTests)

    private static func knobChecks(_ t: inout SelfTestTally) {
        for p in KnobAudit.knobs {
            let name = KnobAudit.name(p)
            let r = KnobAudit.audit(p)
            t.check("\(name) knob readout, 1 to 100 %") {
                let limit = p.isDecibels ? 0.01 : 0.1
                if !(r.worstError <= limit) {
                    return "at \(r.worstAt) % it shows \(r.worstText) but the engine does \(String(format: "%.3f", r.worstMeasured))"
                }
                return nil
            }
            if !p.isDecibels {
                t.check("\(name) knob is even (no dead zone)") {
                    r.worstEvenness <= 0.1 ? nil : "it is off by \(String(format: "%.2f", r.worstEvenness)) % of its full effect somewhere"
                }
            }
        }
        for (p, a, b) in [(Param.outputDB, Float(0), Float(-12)), (.inputDB, 6, 0), (.driveDB, 0, 12),
                          (.ceilingDB, -12, 0), (.wet, 100, 0)] {
            t.check("\(KnobAudit.name(p)) responds within 5 ms") {
                let ms = KnobAudit.responseMS(p, from: a, to: b)
                return ms <= 5 ? nil : "it took \(String(format: "%.1f", ms)) ms"
            }
        }
    }

    // MARK: One parameter map

    private static func parameterMapChecks(_ t: inout SelfTestTally) {
        t.check("Parameter numbers") {
            for (i, p) in Param.allCases.enumerated() where p.rawValue != i {
                return "\(p.title) has number \(p.rawValue) but sits at \(i) in the list"
            }
            let state = SharedState(captureCapacity: 64)
            if state.params.count != Param.allCases.count {
                return "the engine has \(state.params.count) slots for \(Param.allCases.count) controls"
            }
            for p in Param.allCases where state[p] != p.defaultValue {
                return "the engine starts \(p.title) at \(num(state[p])) instead of \(num(p.defaultValue))"
            }
            return nil
        }
        t.check("Parameter names") {
            var ids = Set<String>(), titles = Set<String>()
            for p in Param.allCases {
                if p.id.isEmpty || p.title.isEmpty { return "control number \(p.rawValue) has no name" }
                if !ids.insert(p.id).inserted { return "two controls are saved under \"\(p.id)\"" }
                if !titles.insert(p.title).inserted { return "two controls are called \"\(p.title)\"" }
            }
            return nil
        }
        t.check("Parameter ranges") {
            for p in Param.allCases {
                if !p.range.contains(p.defaultValue) { return "\(p.title)'s default \(num(p.defaultValue)) is outside its range" }
                if let names = p.valueNames {
                    let steps = Int(p.range.upperBound - p.range.lowerBound) + 1
                    if p.range.lowerBound != 0 || names.count != steps {
                        return "\(p.title) has \(names.count) names for \(steps) steps"
                    }
                    if p.defaultValue != p.defaultValue.rounded() { return "\(p.title)'s default is between two steps" }
                }
            }
            if Param.ceilingDB.range != -36...0 { return "Ceiling's range is no longer 0 to -36 dB" }
            return nil
        }
        t.check("Mixer levels") {
            let state = SharedState(captureCapacity: 64)
            state[.mix] = 30
            var l = ClipDSP.mixLevels(state.params)
            if abs(l.wet - 0.3) > 1e-6 || abs(l.dry - 0.7) > 1e-6 { return "Mix 30 % gives wet \(num(l.wet)) / dry \(num(l.dry))" }
            state[.mixUnlink] = 1; state[.dry] = 100; state[.wet] = 40
            l = ClipDSP.mixLevels(state.params)
            if abs(l.wet - 0.4) > 1e-6 || abs(l.dry - 1) > 1e-6 { return "unlinked Dry 100 / Wet 40 gives wet \(num(l.wet)) / dry \(num(l.dry))" }
            return nil
        }
        t.check("Settings fingerprint") {
            func stamp(_ s: [Param: Float]) -> Int {
                let state = SharedState(captureCapacity: 64)
                for (p, v) in s { state[p] = v }
                return SongStamp.of(state.params)
            }
            if stamp([.ceilingDB: -6]) == stamp([.ceilingDB: -3]) { return "a Ceiling change doesn't redraw the SONG view" }
            if stamp([.ceilingDB: -6]) != stamp([.ceilingDB: -6, .link: 1]) { return "Link alone redraws the SONG view" }
            return nil
        }
    }

    // MARK: Shaping curves (CurveTests, BroilTests)

    private static func curveChecks(_ t: inout SelfTestTally) {
        t.check("Red curve") {
            let c: Float = 0.9
            let shape = Curves.redShape(6)
            func gainDB(_ inDB: Float) -> Float {
                let x = c * dbToGain(inDB)
                return gainToDB(Curves.red(x, ceiling: c, g: shape.g, k: shape.k) / x)
            }
            if abs(gainDB(-60) - 6) > 0.05 { return "quiet material gets \(num(gainDB(-60))) dB instead of 6" }
            if abs(gainDB(-0.001)) > 0.01 { return "it still adds \(num(gainDB(-0.001))) dB at the ceiling" }
            if abs(gainDB(3)) > 1e-5 { return "it changes the level above the ceiling" }
            var last: Float = 0
            for i in 1...2000 {
                let x = c * Float(i) / 2000
                let y = Curves.red(x, ceiling: c, g: shape.g, k: shape.k)
                if y > c + 1e-5 { return "it pushes \(num(x, 3)) past the ceiling" }
                if y <= last { return "it folds back near \(num(x, 3))" }
                last = y
            }
            return nil
        }
        t.check("Unity curve") {
            let loud = Curves.gold(1, ceiling: 1, amount: 1, classic: true, unity: true)
            if abs(gainToDB(loud) + 6) > 0.01 { return "a peak on the ceiling comes down \(num(-gainToDB(loud))) dB instead of 6" }
            let quiet: Float = 0.001
            let q = Curves.gold(quiet, ceiling: 1, amount: 1, classic: true, unity: true)
            if abs(q - quiet) > quiet * 0.01 { return "quiet material changes level by \(num(gainToDB(q / quiet))) dB" }
            return nil
        }
        t.check("Hard curve") {
            let c: Float = 0.5, th = c * Curves.hardThreshold
            if Curves.clip(th * 0.99, ceiling: c, knee: 0) != th * 0.99 { return "it touches audio under its threshold" }
            if Curves.clip(c * 2, ceiling: c, knee: 0) != c || Curves.clip(-c * 2, ceiling: c, knee: 0) != -c {
                return "a hot peak isn't held on the ceiling"
            }
            var last: Float = 0, lastSlope: Float = 1
            let step: Float = c / 4000
            for i in 1...12000 {
                let y = Curves.clip(Float(i) * step, ceiling: c, knee: 0)
                if y > c { return "it goes over the ceiling" }
                if y < last { return "it folds back" }
                let slope = (y - last) / step
                if abs(slope - lastSlope) >= 0.01 { return "it has a corner at \(num(Float(i) * step, 3))" }
                last = y; lastSlope = slope
            }
            return nil
        }
        t.check("Classic and Modern curves") {
            for mode in [1, 2] {
                let c: Float = 0.5, knee = Curves.knee(mode), th = c * (1 - knee)
                if Curves.clip(th * 0.99, ceiling: c, knee: knee) != th * 0.99 { return "\(styleName(mode)) touches audio under its knee" }
                var last: Float = 0
                for i in 1...4000 {
                    let y = Curves.clip(Float(i) * c / 1000, ceiling: c, knee: knee)
                    if y > c { return "\(styleName(mode)) goes over the ceiling" }
                    if y < last { return "\(styleName(mode)) folds back" }
                    last = y
                }
            }
            if !(Curves.knee(1) > Curves.knee(2) && Curves.knee(2) > 0 && Curves.knee(0) == 0) {
                return "the knees are no longer Hard < Modern < Classic"
            }
            return nil
        }
        t.check("Broil curve") {
            let c: Float = 0.8
            func curve(_ x: Float, _ amount: Float) -> Float {
                let a = amount * Curves.broilMax
                return Curves.broil(x, ceiling: c, a: a, norm: 1 / tanh(a))
            }
            if abs(curve(c, 1) - c) > 1e-5 || abs(curve(-c, 1) + c) > 1e-5 { return "a peak on the ceiling moves" }
            let quiet = c * dbToGain(-40)
            let lift = gainToDB(curve(quiet, 1) / quiet)
            if lift < 7.5 { return "quiet material only comes up \(num(lift)) dB at 100 % (about 8 expected)" }
            for amount: Float in [0.1, 0.5, 1] {
                var last: Float = 0
                for i in 1...2000 {
                    let x = c * Float(i) / 2000
                    let y = curve(x, amount)
                    if y > c + 1e-5 { return "it goes over the ceiling at \(Int(amount * 100)) %" }
                    if y <= last { return "it folds back at \(Int(amount * 100)) %" }
                    last = y
                }
            }
            return nil
        }
        t.check("Broil in the engine") {
            func settled(_ broil: Float) -> [Float] {
                let e = SelfTestEngine([.driveDB: 6, .ceilingDB: -3, .clipMode: 0, .oversampling: 0, .broil: broil])
                e.render(12_288, SelfTestSignal.tones)
                return e.render(1024, SelfTestSignal.tones).l
            }
            let off = settled(0), on = settled(100)
            let peakOff = peak(off), peakOn = peak(on)
            if peakOn > dbToGain(-3) + 1e-4 { return "it pushes the output past a -3 dB ceiling" }
            if gainToDB(rms(on) / rms(off)) <= 1 { return "the body only got \(num(gainToDB(rms(on) / rms(off)))) dB louder" }
            if abs(peakOn - peakOff) > 1e-4 { return "it moved the peaks on the ceiling" }
            return nil
        }
    }

    // MARK: The ceiling holds (Hard, Classic, Modern; 0 to -12 dB; every oversampling)

    private static func ceilingChecks(_ t: inout SelfTestTally) {
        let extras: [Param: Float] = [.gold: 100, .goldMode: 1, .alchemy: 100, .broil: 100, .boxTone: 2]
        for mode in 0...2 {
            for step in 0...12 {
                let ceiling = -Float(step)
                t.check("\(styleName(mode)) at a \(Int(ceiling)) dB ceiling") {
                    let c = dbToGain(ceiling)
                    for os in 0...2 {
                        for withExtras in [false, true] {
                            var s: [Param: Float] = [.clipMode: Float(mode), .ceilingDB: ceiling, .oversampling: Float(os),
                                                     .inputDB: 6, .driveDB: 12]
                            if withExtras { s.merge(extras) { $1 } }
                            let e = SelfTestEngine(s)
                            let out = e.render(4096, SelfTestSignal.rising)
                            let top = max(peak(out.l), peak(out.r))
                            let label = "\(osName(os))\(withExtras ? ", Red/Fire/Broil/Box on" : "")"
                            if let bad = badOutput(out) { return "\(bad) (\(label))" }
                            if top > c * (1 + 1e-5) { return "the output went \(num(gainToDB(top / c), 3)) dB over it (\(label))" }
                            if !withExtras && top < c * dbToGain(-0.5) {
                                return "a hot signal only reached \(num(gainToDB(top))) dB (\(label))"
                            }
                        }
                    }
                    return nil
                }
            }
        }
    }

    // MARK: Red adds at most 2.5 dB (Modern) / 6 dB (Classic); Unity takes it back off

    private static func redChecks(_ t: inout SelfTestTally) {
        for classic in [false, true] {
            let style = classic ? "Classic" : "Modern"
            let most = Curves.goldMaxDB(classic: classic)
            t.check("Red \(style) gain limit") {
                if most != (classic ? 6 : 2.5) { return "it allows \(num(most)) dB instead of \(classic ? "6" : "2.5")" }
                for ceilingDB: Float in [0, -6, -12] {
                    let c = dbToGain(ceilingDB)
                    for amount: Float in [0.25, 0.5, 1] {
                        var level: Float = -80
                        while level <= 6 {
                            let x = c * dbToGain(level)
                            let g = gainToDB(abs(Curves.gold(x, ceiling: c, amount: amount, classic: classic, unity: false)) / x)
                            if g > most * amount + 0.001 { return "it adds \(num(g)) dB at \(num(level)) dB (ceiling \(Int(ceilingDB)) dB)" }
                            if g < -0.001 { return "it turns audio down at \(num(level)) dB" }
                            level += 0.25
                        }
                    }
                }
                let full = gainToDB(Curves.gold(dbToGain(-60), ceiling: 1, amount: 1, classic: classic, unity: false) / dbToGain(-60))
                if abs(full - most) > 0.05 { return "quiet material gets \(num(full)) dB instead of \(num(most))" }
                return nil
            }
            t.check("Red \(style) in the engine") {
                for level: Float in [-40, -20, -10, -6] {
                    let g = engineGainDB([.gold: 100, .goldMode: classic ? 1 : 0], level: level)
                    if !g.isFinite { return "the output went invalid" }
                    if g > most + 0.01 { return "a \(Int(level)) dBFS tone came up \(num(g)) dB (limit \(num(most)))" }
                    if level == -40 && g < most - 0.15 { return "a quiet tone only came up \(num(g)) dB (expected about \(num(most)))" }
                }
                return nil
            }
            t.check("Unity with Red \(style)") {
                let g = engineGainDB([.gold: 100, .goldMode: classic ? 1 : 0, .unity: 1], level: -40)
                if !g.isFinite || abs(g) > 0.1 { return "a quiet tone changed level by \(num(g)) dB instead of staying put" }
                // a hot signal on a -6 dB ceiling: Unity brings the peaks down by Red's gain
                let e = SelfTestEngine([.gold: 100, .goldMode: classic ? 1 : 0, .unity: 1, .ceilingDB: -6,
                                        .driveDB: 12, .oversampling: 0, .clipMode: 0])
                e.render(12_288, SelfTestSignal.tones)
                let top = peak(e.render(4096, SelfTestSignal.tones).l)
                let want = dbToGain(-6 - most)
                if top > want * (1 + 1e-4) || top < want * dbToGain(-0.3) {
                    return "peaks sit at \(num(gainToDB(top))) dB instead of \(num(gainToDB(want))) dB"
                }
                return nil
            }
        }
    }

    // MARK: Finite output at 128-frame buffers

    private static func finiteChecks(_ t: inout SelfTestTally) {
        for preset in Preset.factory {
            t.check("\"\(preset.name)\" at 128-frame buffers") {
                let e = SelfTestEngine(preset.values)
                return badOutput(e.render(6144, SelfTestSignal.tones))
            }
        }
        t.check("Every control at its limits") {
            for top in [false, true] {
                for delta: Float in [0, 1] {
                    var s: [Param: Float] = [:]
                    for p in Param.allCases where p != .bypass { s[p] = top ? p.range.upperBound : p.range.lowerBound }
                    s[.delta] = delta
                    let e = SelfTestEngine(s)
                    if let bad = badOutput(e.render(6144, SelfTestSignal.loud)) {
                        return "\(top ? "everything up" : "everything down")\(delta > 0 ? " with Delta" : ""): \(bad)"
                    }
                }
            }
            return nil
        }
        t.check("Random settings") {
            var seed: UInt32 = 2026
            func rnd() -> Float { seed = seed &* 1_664_525 &+ 1_013_904_223; return Float(seed >> 8) / Float(1 << 24) }
            for run in 0..<24 {
                var s: [Param: Float] = [:]
                for p in Param.allCases {
                    let v = p.range.lowerBound + rnd() * (p.range.upperBound - p.range.lowerBound)
                    s[p] = p.valueNames != nil ? v.rounded() : v
                }
                let e = SelfTestEngine(s)
                // change the settings half way, as automation would
                let first = e.render(1024, SelfTestSignal.loud)
                for p in [Param.driveDB, .ceilingDB, .gold, .mix, .outputDB, .broil] {
                    e.shared[p] = p.range.lowerBound + rnd() * (p.range.upperBound - p.range.lowerBound)
                }
                if let bad = badOutput(first) ?? badOutput(e.render(1024, SelfTestSignal.loud)) {
                    return "setting \(run + 1): \(bad)"
                }
            }
            return nil
        }
        t.check("Other sample rates") {
            for sr in [44_100.0, 88_200.0, 96_000.0, 192_000.0] {
                for s: [Param: Float] in [[:], [.driveDB: 12, .gold: 100, .goldMode: 1, .alchemy: 100, .oversampling: 2]] {
                    let e = SelfTestEngine(s, sampleRate: sr)
                    let signal: (Int, Int) -> Float = { n, ch in SelfTestSignal.tonesAt(n, ch, sampleRate: sr) }
                    if let bad = badOutput(e.render(Int(sr / 10), signal)) { return "\(Int(sr)) Hz: \(bad)" }
                    if s.isEmpty, peak(e.render(Int(sr / 10), signal).l) > dbToGain(-0.3) * (1 + 1e-5) {
                        return "\(Int(sr)) Hz: the output went over the default ceiling"
                    }
                }
            }
            return nil
        }
    }

    // MARK: Silence in, silence out

    private static func silenceChecks(_ t: inout SelfTestTally) {
        let busy: [Param: Float] = [.driveDB: 12, .inputDB: 6, .gold: 100, .goldMode: 1, .alchemy: 100,
                                    .broil: 100, .boxTone: 2, .outputDB: 6]
        for os in 0...2 {
            t.check("Silence in, silence out (\(osName(os)))") {
                for mode in 0...2 {
                    for extra: [Param: Float] in [[:], busy, busy.merging([.delta: 1]) { $1 },
                                                   busy.merging([.mixUnlink: 1, .dry: 100, .wet: 100]) { $1 }] {
                        let e = SelfTestEngine(extra.merging([.oversampling: Float(os), .clipMode: Float(mode)]) { $1 })
                        let out = e.render(4096) { _, _ in 0 }
                        let top = max(peak(out.l), peak(out.r))
                        if !(top == 0) { return "\(styleName(mode)) put out \(num(gainToDB(top))) dBFS from silence" }
                    }
                }
                // after audio stops, the filters ring out to silence
                let e = SelfTestEngine([.oversampling: Float(os), .driveDB: 9])
                e.render(8192, SelfTestSignal.tones)
                e.render(12_288) { _, _ in 0 }
                let tail = e.render(1024) { _, _ in 0 }
                if max(peak(tail.l), peak(tail.r)) > 1e-5 { return "the output didn't fall silent after the audio stopped" }
                return nil
            }
        }
    }

    // MARK: Oversampling renders cleanly

    private static func oversamplingChecks(_ t: inout SelfTestTally) {
        for os in 0...2 {
            t.check("Oversampling \(osName(os))") {
                // a clean tone under the clipper comes through at its own level
                let g = engineGainDB([.oversampling: Float(os), .ceilingDB: 0], level: -20, frequency: 1000)
                if !g.isFinite || abs(g) > 0.12 { return "a clean -20 dBFS tone came out \(num(g)) dB off" }
                // the output is late by exactly the latency the exporter and the host are told
                let e = SelfTestEngine([.oversampling: Float(os), .ceilingDB: 0], block: 4096)
                let out = e.render(4096) { n, _ in n >= 2000 ? 0.1 : 0 }
                let first = out.l.firstIndex { $0 > 0.05 } ?? -1
                let want = 2000 + ClipDSP.latencyFrames(oversampling: Float(os))
                if first != want { return "the output is \(first - 2000) frames late instead of \(want - 2000)" }
                // Mix 0 %: the screen's output trace sits on its input trace (ScopeTests)
                let tolerance: Float = [1e-6, 0.012, 0.06][os]
                let s = SelfTestEngine([.mix: 0, .oversampling: Float(os)])
                s.render(12_288, SelfTestSignal.tones)
                let r = ScopeReader()
                r.update(s.shared, columns: Int(48_000 * ScopeReader.window))
                if r.samplesPerColumn != 1 { return "the screen reader didn't give one sample per column" }
                var worst: Float = 0
                for c in 0..<r.columns { worst = max(worst, abs(r.outMax[c] - r.inMax[c])) }
                if worst > tolerance { return "the screen's output and input traces are \(num(worst, 4)) apart" }
                // a hard-clipped tone stays clean: no runaway or invalid samples
                let hot = SelfTestEngine([.oversampling: Float(os), .driveDB: 12, .inputDB: 6, .clipMode: 0])
                if let bad = badOutput(hot.render(8192, SelfTestSignal.loud)) { return "hard clipping: \(bad)" }
                return nil
            }
        }
        t.check("Bypass") {
            let e = SelfTestEngine([.oversampling: 2, .inputDB: 6, .driveDB: 12, .ceilingDB: -9, .bypass: 1])
            e.render(12_288, SelfTestSignal.tones)
            let t0 = e.time
            let out = e.render(1024, SelfTestSignal.tones)
            for i in 0..<out.l.count where abs(out.l[i] - SelfTestSignal.tones(t0 + i, 0)) > 1e-5 {
                return "bypassed, the output isn't the input (sample \(i))"
            }
            return nil
        }
    }

    // MARK: The parallel mixer (MixerTests)

    private static func mixerChecks(_ t: inout SelfTestTally) {
        let crush: [Param: Float] = [.driveDB: 12, .ceilingDB: -6, .clipMode: 0, .gold: 80]
        func output(_ s: [Param: Float]) -> [Float] {
            let e = SelfTestEngine(s)
            e.render(12_288, SelfTestSignal.tones)
            return e.render(1024, SelfTestSignal.tones).l
        }
        func worst(_ a: [Float], _ b: [Float]) -> Float { zip(a, b).map { abs($0 - $1) }.max() ?? 0 }
        for os in 0...2 {
            t.check("Dry / Wet mixer (\(osName(os)))") {
                let o: [Param: Float] = [.oversampling: Float(os)]
                let linked = output(crush.merging(o) { $1 }.merging([.mix: 40]) { $1 })
                let unlinked = output(crush.merging(o) { $1 }.merging([.mixUnlink: 1, .dry: 60, .wet: 40]) { $1 })
                if worst(linked, unlinked) > 1e-5 { return "unlinked Dry 60 / Wet 40 doesn't match Mix 40 %" }
                let base = crush.merging([.oversampling: Float(os), .mixUnlink: 1]) { $1 }
                let both = output(base.merging([.dry: 100, .wet: 100]) { $1 })
                let dry = output(base.merging([.dry: 100, .wet: 0]) { $1 })
                let wet = output(base.merging([.dry: 0, .wet: 100]) { $1 })
                if worst(both, zip(dry, wet).map { $0 + $1 }) > 1e-5 { return "Dry and Wet don't add up sample for sample" }
                // nothing clips here, so Dry + Wet must be exactly twice Dry if they're in phase
                let clean: [Param: Float] = [.oversampling: Float(os), .mixUnlink: 1, .ceilingDB: 0]
                let d = output(clean.merging([.dry: 100, .wet: 0]) { $1 })
                let dw = output(clean.merging([.dry: 100, .wet: 100]) { $1 })
                if worst(dw, d.map { $0 * 2 }) > 1e-4 { return "Dry and Wet are out of phase (they comb-filter)" }
                return nil
            }
        }
        t.check("Full Dry at 1x") {
            let e = SelfTestEngine(crush.merging([.oversampling: 0, .mixUnlink: 1, .dry: 100, .wet: 0]) { $1 })
            e.render(12_288, SelfTestSignal.tones)
            let t0 = e.time
            let out = e.render(1024, SelfTestSignal.tones).l
            for i in 0..<out.count where abs(out[i] - SelfTestSignal.tones(t0 + i, 0)) > 1e-6 {
                return "100 % Dry isn't the untouched input (sample \(i))"
            }
            return nil
        }
    }

    // MARK: Meters, CLIP readout, Clip Clock (SongOverviewTests, ClipClockTests, WaveScreenTests)

    private static func meterAndClipChecks(_ t: inout SelfTestTally) {
        /// One block through a fresh 1x engine; the CLIP reading for it.
        func clipDB(_ values: [Float], _ s: [Param: Float]) -> (db: Float, shared: SharedState) {
            let e = SelfTestEngine(s.merging([.oversampling: 0]) { $1 }, block: values.count)
            e.render(values.count) { n, _ in values[n] }
            return (e.shared.meters.exchange(Meter.reductionDB.rawValue, 0), e.shared)
        }
        t.check("CLIP readout") {
            let ceiling: Float = -6, c = dbToGain(ceiling)
            for mode in 0...2 {
                let knee = Curves.knee(mode)
                for x: Float in [c * 0.8, c * 0.95, c, c * 1.3, c * 3] {
                    let want = 20 * log10(x / Curves.clip(x, ceiling: c, knee: knee))
                    let got = clipDB([0, x, 0, -x * 0.5], [.ceilingDB: ceiling, .clipMode: Float(mode)]).db
                    if abs(got - want) > 0.01 { return "\(styleName(mode)) reads \(num(got)) dB where it took off \(num(want)) dB" }
                }
                if clipDB([c * 0.6, -c * 0.6], [.ceilingDB: ceiling, .clipMode: Float(mode)]).db != 0 {
                    return "\(styleName(mode)) reads a cut under its threshold"
                }
            }
            let x: [Float] = [0.2, 1.4, -1.1, 0.7]
            let plain = clipDB(x, [.ceilingDB: -3]).db
            for s: [Param: Float] in [[.outputDB: 12], [.mix: 0], [.mixUnlink: 1, .dry: 100, .wet: 20], [.broil: 100, .alchemy: 100]] {
                if abs(clipDB(x, s.merging([.ceilingDB: -3]) { $1 }).db - plain) > 1e-5 {
                    return "Wet / Dry, Output, Broil or Fire changed the reading"
                }
            }
            let bad = clipDB([.nan, .infinity, -.infinity, 0.5], [:])
            if !bad.db.isFinite || !bad.shared.clipMaxDB.value.isFinite { return "invalid input made the readout invalid" }
            return nil
        }
        t.check("Clip Clock") {
            let e = SelfTestEngine([.oversampling: 0, .ceilingDB: 0], block: 512)
            e.songStart = 0
            let spikes = [Int(1.25 * 48_000): dbToGain(2), Int(3.5 * 48_000): dbToGain(6), Int(4.1 * 48_000): dbToGain(3)]
            e.render(5 * 48_000) { n, _ in spikes[n] ?? Float(0.3 * sin(2 * .pi * 220 * Double(n) / 48_000)) }
            let clock = e.shared.clipClock
            if abs(clock.maxDB.value - 6) > 0.05 { return "the biggest clip reads \(num(clock.maxDB.value)) dB instead of 6" }
            if abs(clock.seconds.value - 3.5) > 0.001 { return "it was placed at \(num(clock.seconds.value, 3)) s instead of 3.5 s" }
            if ClipClockState.timeText(clock.seconds.value) != "0:03:50" { return "the time reads \(ClipClockState.timeText(clock.seconds.value))" }
            // MAX CLIP: the original input's loudest sample, before Input and Drive, and where it is
            let m = SelfTestEngine([.oversampling: 0, .ceilingDB: -6, .inputDB: 6, .driveDB: 9], block: 2048)
            m.dsp.timelineFrame = 48_000
            m.dsp.timelineClock = SongClock.file.rawValue
            m.render(2048) { n, _ in n == 500 ? 0.7 : (n == 1000 ? -0.9 : 0.1) }
            guard let maxClip = m.shared.clipMax() else { return "MAX CLIP was mid-update" }
            if abs(maxClip.db - gainToDB(0.9)) > 0.01 || maxClip.frame != 49_000 || maxClip.clock != .file {
                return "MAX CLIP reads \(num(maxClip.db)) dB at frame \(maxClip.frame) instead of \(num(gainToDB(0.9))) dB at 49000"
            }
            return nil
        }
        t.check("Readout text") {
            let cases: [(String, String)] = [
                (ClipClockState.timeText(-1), "-:--:--"), (ClipClockState.timeText(193), "3:13:00"),
                (ClipClockState.timeText(59.994), "0:59:99"), (ClipClockState.timeText(59.999), "1:00:00"),
                (ClipClockState.dbText(0), "-- dB"), (ClipClockState.dbText(3), "3.0 dB"),
                (WaveTime.tenths(44.25), "0:44.2"), (WaveTime.tenths(127), "2:07.0"),
                (WaveTime.dBFS(-9.6), "\u{2212}9.6")
            ]
            for (got, want) in cases where got != want { return "shows \"\(got)\" instead of \"\(want)\"" }
            return nil
        }
        t.check("Loudness meter") {
            // EBU Tech 3341 case 1: a 1 kHz sine at -23 dBFS in both channels reads -23 LUFS
            let e = SelfTestEngine([.oversampling: 0, .ceilingDB: 0], block: 1024)
            let a = dbToGain(-23)
            e.render(48_000 * 7 / 2) { n, _ in a * Float(sin(2 * .pi * 1000 * Double(n) / 48_000)) }
            let meters = e.shared.meters
            for (name, m) in [("momentary", Meter.inLUFSM), ("short-term", Meter.inLUFS), ("integrated", Meter.inLUFSI)] {
                let v = meters[m.rawValue]
                if !v.isFinite || abs(v + 23) > 0.2 { return "the \(name) input reading is \(num(v)) LUFS instead of -23" }
            }
            return nil
        }
    }

    // MARK: Screen, help and menu layout (MeterZoomTests, WaveColumnTests, HelpTests, MenuPlacementTests)

    private static func screenAndLayoutChecks(_ t: inout SelfTestTally) {
        t.check("Hard clipping on the screen") {
            let c = dbToGain(-6)
            let e = SelfTestEngine([.oversampling: 0, .clipMode: 0, .driveDB: 9, .ceilingDB: -6])
            e.render(12_288, SelfTestSignal.tones)
            let r = ScopeReader()
            r.update(e.shared, columns: Int(48_000 * ScopeReader.window))
            let top = r.outMax.max() ?? 0
            if abs(top - c) > 1e-4 { return "the output tops out at \(num(gainToDB(top))) dB instead of -6" }
            let flat = (0..<r.columns).filter { abs(r.outMax[$0] - top) < 1e-6 }.count
            let cut = (0..<r.columns).filter { r.removed($0).top > 0.01 }.count
            if flat <= r.columns / 20 { return "no flat tops on the ceiling" }
            if cut <= r.columns / 20 { return "the screen doesn't see what the clipper removed" }
            // Gold Clip-style low-level clipping: the ceiling comes down to the signal
            let low = SelfTestEngine([.oversampling: 0, .clipMode: 0, .ceilingDB: -30])
            low.render(12_288, SelfTestSignal.tones)
            let lr = ScopeReader()
            lr.update(low.shared, columns: Int(48_000 * ScopeReader.window))
            if abs((lr.outMax.max() ?? 0) - dbToGain(-30)) > 1e-4 { return "a -30 dB ceiling doesn't hold" }
            return nil
        }
        t.check("Waveform zoom") {
            if MeterZoom.allCases.map({ $0.topDB }) != [6, 4, 2] || MeterZoom.allCases.map({ $0.floorDB }) != [-36, -24, -12] {
                return "the zoom tiers are no longer +6/-36, +4/-24, +2/-12"
            }
            if MeterZoom.full.next != .zoom1 || MeterZoom.zoom1.next != .zoom2 || MeterZoom.zoom2.next != .full {
                return "double-tap doesn't step Full, Zoom 1, Zoom 2, Full"
            }
            for z in MeterZoom.allCases {
                if z.position(z.topDB) != 1 || z.position(z.floorDB) != 0 || z.position(z.topDB + 10) != 1 || z.position(-120) != 0 {
                    return "the scale's ends are wrong at \(z.label)"
                }
                if abs(z.position((z.topDB + z.floorDB) / 2) - 0.5) > 1e-6 { return "the scale isn't linear in dB at \(z.label)" }
                if abs(z.position(sample: -0.5) + z.position(sample: 0.5)) > 1e-6 { return "the scale isn't mirrored at \(z.label)" }
            }
            return nil
        }
        t.check("Waveform columns") {
            var a = WaveTicks(written: 1000, count: 1000)
            for j in 0..<1000 { a.frames[j] = WaveFeed.tickFrames; a.inPeak[j] = j == 537 ? 1 : 0.01; a.outPeak[j] = 0.01 }
            let cols = WaveColumns.make(a, count: 100, window: 1000)
            if cols[53].inPeak != 1 { return "a one-tick transient got lost" }
            var b = WaveTicks(written: 100, count: 100)
            for j in 0..<100 { b.frames[j] = WaveFeed.tickFrames; b.outPeak[j] = 1; b.outSquares[j] = Float(WaveFeed.tickFrames) * 0.5 }
            let l = WaveColumns.peakAndRMS(b)
            if abs(l.peak) > 1e-5 || abs(l.rms + 3.01) > 0.01 { return "a full-scale sine reads \(num(l.peak)) peak / \(num(l.rms)) RMS" }
            return nil
        }
        t.check("Scrub bar") {
            if ScrubMath.speed(distance: 10) != 1 || ScrubMath.speed(distance: 60) != 0.5
                || ScrubMath.speed(distance: 100) != 0.25 || ScrubMath.speed(distance: 300) != 0.1 {
                return "the scrub speeds are wrong"
            }
            let pts = [ClipPoint(frame: 50, fraction: 0.5, db: 0, rank: 0)]
            if ScrubMath.snap(0.505, to: pts, reach: 0.01) != 0.5 || ScrubMath.snap(0.52, to: pts, reach: 0.01) != 0.52 {
                return "the dot doesn't snap onto a nearby mark only"
            }
            return nil
        }
        t.check("Help") {
            let areas = HelpAreas([
                .screen: [CGRect(x: 0, y: 0, width: 400, height: 200)],
                .clipReadout: [CGRect(x: 100, y: 50, width: 40, height: 20)],
                .presets: [CGRect(x: 500, y: 0, width: 20, height: 20), CGRect(x: 600, y: 0, width: 20, height: 20)]
            ])
            if areas.topic(at: CGPoint(x: 10, y: 10)) != .screen { return "a touch on the screen finds the wrong control" }
            if areas.topic(at: CGPoint(x: 110, y: 60)) != .clipReadout { return "a small control on a panel doesn't win" }
            if areas.topic(at: CGPoint(x: 610, y: 10)) != .presets { return "a control's second area isn't found" }
            if areas.topic(at: CGPoint(x: 550, y: 100)) != nil { return "an empty spot finds a control" }
            if Set(HelpTopic.tourOrder).count != HelpTopic.tourOrder.count { return "the tour visits a control twice" }
            if Set(HelpTopic.tourOrder) != Set(HelpTopic.allCases) { return "the tour misses a control" }
            for topic in HelpTopic.allCases where topic.title.isEmpty || topic.text.isEmpty {
                return "\(topic.rawValue) has no help text"
            }
            return nil
        }
        let menuCases: [(String, CGSize, EdgeInsets, CGRect)] = [
            ("iPad landscape", CGSize(width: 1366, height: 1024), EdgeInsets(top: 24, leading: 0, bottom: 20, trailing: 0), CGRect(x: 520, y: 40, width: 360, height: 40)),
            ("iPad portrait", CGSize(width: 1024, height: 1366), EdgeInsets(top: 24, leading: 0, bottom: 20, trailing: 0), CGRect(x: 380, y: 300, width: 280, height: 30)),
            ("narrow iPad window", CGSize(width: 320, height: 1024), EdgeInsets(top: 24, leading: 0, bottom: 20, trailing: 0), CGRect(x: 120, y: 420, width: 90, height: 12)),
            ("iPhone portrait", CGSize(width: 393, height: 852), EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0), CGRect(x: 120, y: 90, width: 160, height: 34)),
            ("iPhone landscape", CGSize(width: 852, height: 393), EdgeInsets(top: 0, leading: 59, bottom: 21, trailing: 59), CGRect(x: 340, y: 18, width: 170, height: 24)),
            ("compact AUv3 view", CGSize(width: 480, height: 300), EdgeInsets(), CGRect(x: 180, y: 12, width: 120, height: 20))
        ]
        t.check("Menu placement") {
            let m = RCMenuPlacement.margin
            for (name, size, safe, trigger) in menuCases {
                for largeText in [false, true] {
                    let f = RCMenuPlacement.frame(size: size, safe: safe, anchor: trigger, largeText: largeText)
                    if f.minX < safe.leading + m - 0.001 || f.minY < safe.top + m - 0.001
                        || f.maxX > size.width - safe.trailing - m + 0.001 || f.maxY > size.height - safe.bottom - m + 0.001 {
                        return "the menu goes outside the safe area (\(name))"
                    }
                    if f.height <= 200 { return "the menu is too short (\(name))" }
                }
            }
            return nil
        }
    }

    // MARK: Helpers

    /// Steady-state gain of a sine at `level` dBFS through a private 1x engine (unless the
    /// settings pick another oversampling), in dB.
    private static func engineGainDB(_ s: [Param: Float], level: Float, frequency: Double = 997) -> Float {
        let base: [Param: Float] = [.oversampling: 0, .ceilingDB: 0]
        let e = SelfTestEngine(base.merging(s) { $1 })
        let a = dbToGain(level)
        let signal: (Int, Int) -> Float = { n, _ in a * Float(sin(2 * .pi * frequency * Double(n) / 48_000)) }
        e.render(14_400, signal)                       // 300 ms: every smoother has settled
        let t0 = e.time
        let out = e.render(9600, signal).l             // 200 ms
        let input = (0..<out.count).map { signal(t0 + $0, 0) }
        return gainToDB(rms(out) / rms(input))
    }

    /// nil if every sample is finite and sane, else what went wrong.
    private static func badOutput(_ out: (l: [Float], r: [Float])) -> String? {
        for (side, samples) in [("left", out.l), ("right", out.r)] {
            if let i = samples.firstIndex(where: { !$0.isFinite }) { return "invalid audio (NaN or infinity) on the \(side) at sample \(i)" }
            if let i = samples.firstIndex(where: { abs($0) > 200 }) { return "runaway level on the \(side) at sample \(i)" }
        }
        return nil
    }

    private static func peak(_ x: [Float]) -> Float { x.reduce(0) { max($0, abs($1)) } }

    private static func rms(_ x: [Float]) -> Float {
        guard !x.isEmpty else { return 0 }
        return Float((x.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(x.count)).squareRoot())
    }

    private static func styleName(_ mode: Int) -> String { ["Hard", "Classic", "Modern"][min(max(mode, 0), 2)] }
    private static func osName(_ os: Int) -> String { ["1x", "2x", "4x"][min(max(os, 0), 2)] + " oversampling" }
}

/// A number for a failure message: "-3.25", "6".
private func num(_ v: Float, _ digits: Int = 2) -> String {
    guard v.isFinite else { return v.isNaN ? "NaN" : (v > 0 ? "+inf" : "-inf") }
    var s = String(format: "%.\(digits)f", Double(v))
    while s.contains(".") && (s.hasSuffix("0") || s.hasSuffix(".")) { s.removeLast() }
    return s == "-0" ? "0" : s
}

// MARK: - A private engine for one check

/// Its own SharedState and ClipDSP, made for one check and thrown away: the live engine, its
/// meters and its screen are never touched. Renders in `block`-frame buffers (128 by default,
/// a common host buffer).
private final class SelfTestEngine {
    let shared: SharedState
    let dsp: ClipDSP
    let sampleRate: Double
    let block: Int
    /// Clip Clock song position of frame 0 (nil: transport stopped).
    var songStart: Double?
    private(set) var time = 0
    private let inL: UnsafeMutablePointer<Float>
    private let inR: UnsafeMutablePointer<Float>
    private let outL: UnsafeMutablePointer<Float>
    private let outR: UnsafeMutablePointer<Float>

    init(_ settings: [Param: Float] = [:], sampleRate: Double = 48_000, block: Int = 128) {
        let state = SharedState(captureCapacity: 64)
        for (p, v) in settings { state[p] = v }
        let size = max(1, block)
        shared = state
        dsp = ClipDSP(sampleRate: sampleRate, shared: state)
        self.sampleRate = sampleRate
        self.block = size
        inL = .allocate(capacity: size); inR = .allocate(capacity: size)
        outL = .allocate(capacity: size); outR = .allocate(capacity: size)
    }

    deinit { inL.deallocate(); inR.deallocate(); outL.deallocate(); outR.deallocate() }

    /// Renders `frames` frames of `signal(frame, channel)`; returns what came out.
    @discardableResult
    func render(_ frames: Int, _ signal: (Int, Int) -> Float) -> (l: [Float], r: [Float]) {
        var l: [Float] = [], r: [Float] = []
        l.reserveCapacity(frames); r.reserveCapacity(frames)
        var done = 0
        while done < frames {
            let n = min(block, frames - done)
            for i in 0..<n { inL[i] = signal(time + i, 0); inR[i] = signal(time + i, 1) }
            if let songStart { dsp.songTime = songStart + Double(time) / sampleRate }
            dsp.process(inL: inL, inR: inR, outL: outL, outR: outR, frames: n)
            l.append(contentsOf: UnsafeBufferPointer(start: outL, count: n))
            r.append(contentsOf: UnsafeBufferPointer(start: outR, count: n))
            time += n
            done += n
        }
        return (l, r)
    }
}

/// Test signals (the same two tones the XCTest harness uses).
private enum SelfTestSignal {
    /// Two tones, a little different per channel; peaks about 0.65.
    static func tones(_ n: Int, _ channel: Int) -> Float { tonesAt(n, channel, sampleRate: 48_000) }

    static func tonesAt(_ n: Int, _ channel: Int, sampleRate: Double) -> Float {
        let t = Double(n) / sampleRate
        return Float(0.45 * sin(2 * .pi * 220 * t + Double(channel)) + 0.2 * sin(2 * .pi * 3_300 * t))
    }

    /// The tones rising from -26 dB to about +3 dB over 4096 frames, then held: every curve
    /// is crossed from untouched, through its knee, to flat out.
    static func rising(_ n: Int, _ channel: Int) -> Float {
        tones(n, channel) * (0.05 + 1.45 * Float(min(n, 4096)) / 4096)
    }

    /// The tones at full scale.
    static func loud(_ n: Int, _ channel: Int) -> Float { tones(n, channel) * 1.5 }
}
