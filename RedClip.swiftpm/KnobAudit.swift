import Foundation

// MARK: - Knob audit
//
// Checks every knob against the engine itself, at every 1 % of its travel (1 ... 100):
//   1. the readout under the knob is exactly what the engine does (measured on real audio);
//   2. and 3. the % knobs are even: n % of the knob gives n % of the full effect, so there is no
//      dead zone at the bottom;
//   5. the sound follows a knob move within about 5 ms.
// Used by the Self-Test (REDCLIP MENU › Settings › Self-Test) and Tests/RedClipTests/KnobTaperTests.
// Private engines only; never the live one. Off the main thread.

enum KnobAudit {
    /// The faceplate's knobs, in face order.
    static let knobs: [Param] = [.inputDB, .driveDB, .ceilingDB, .outputDB, .gold, .alchemy, .broil, .wet, .dry]

    /// Display name on the face (Red = gold, Fire = alchemy).
    static func name(_ p: Param) -> String {
        switch p {
        case .inputDB: return "Input"
        case .driveDB: return "Drive"
        case .ceilingDB: return "Ceiling"
        case .outputDB: return "Output"
        case .gold: return "Red"
        case .alchemy: return "Fire"
        case .broil: return "Broil"
        case .wet: return "Wet"
        case .dry: return "Dry"
        default: return "\(p)"
        }
    }

    struct Result {
        let param: Param
        /// Largest |readout - measured| over the 100 positions, in the readout's unit (dB or %).
        var worstError = 0.0
        var worstAt = 0
        var worstText = ""
        var worstMeasured = 0.0
        /// % knobs: largest |measured % of full effect - knob %| (0 for dB knobs).
        var worstEvenness = 0.0
        /// Measured effect at 10 % and 20 % of the knob (dB or % of full effect).
        var at10 = 0.0, at20 = 0.0
    }

    /// The knob at `percent` of its travel, as a stored value (what a turn there sets).
    static func storedValue(_ p: Param, percent: Int) -> Float {
        let r = p.knobRange
        return p.fromKnob(p.snapKnob(r.lowerBound + Float(percent) / 100 * (r.upperBound - r.lowerBound)))
    }

    /// Checks one knob at every 1 %.
    static func audit(_ p: Param, sampleRate: Double = 48_000) -> Result {
        var r = Result(param: p)
        let m = Meter(p, sampleRate: sampleRate)
        for pct in 1...100 {
            let v = storedValue(p, percent: pct)
            let text = p.readout(v)
            let shown = Double(text.split(separator: " ").first ?? "") ?? .nan
            let real = m.effect(v)
            let err = abs(real - shown)
            if !(err <= r.worstError) { r.worstError = err; r.worstAt = pct; r.worstText = text; r.worstMeasured = real }
            if !p.isDecibels { r.worstEvenness = max(r.worstEvenness, abs(real - Double(pct))) }
            if pct == 10 { r.at10 = real }
            if pct == 20 { r.at20 = real }
        }
        return r
    }

    /// Milliseconds until the sound has made 95 % of a knob move (measured in the knob's own
    /// unit: dB for dB knobs, level for % knobs), counted from the block the move lands in.
    /// Ceiling is probed driven into the Hard curve (the output sits on the ceiling); Wet and Dry
    /// unlinked, with the other side at 0; the rest with a quiet steady level.
    static func responseMS(_ p: Param, from a: Float, to b: Float, sampleRate: Double = 48_000) -> Double {
        var s: [Param: Float] = [.oversampling: 0, p: a]
        if p == .wet || p == .dry { s[.mixUnlink] = 1; s[p == .wet ? .dry : .wet] = 0 }
        if p == .ceilingDB { s[.clipMode] = 0 }
        let e = Engine(s, sampleRate: sampleRate)
        let probe: Float = p == .ceilingDB ? 2 : 0.01
        let scale: Float = p == .ceilingDB ? 1 : probe
        e.render(Int(sampleRate / 10)) { _ in probe }
        e.shared[p] = b
        let out = e.render(Int(sampleRate / 10)) { _ in probe }
        let g0 = p.isDecibels ? Double(a) : Double(a) / 100, g1 = p.isDecibels ? Double(b) : Double(b) / 100
        for (i, x) in out.enumerated() {
            let now = p.isDecibels ? 20 * log10(max(Double(abs(x)), 1e-12) / Double(scale)) : Double(x) / Double(scale)
            if abs(now - g1) <= 0.05 * abs(g1 - g0) { return Double(i) / sampleRate * 1000 }
        }
        return .infinity
    }

    // MARK: Measuring the engine

    /// Measures one knob's real effect in the engine, in its readout's unit.
    private struct Meter {
        let p: Param
        let sampleRate: Double
        private var fireNone: [Float] = [], fireFull: [Float] = []

        init(_ p: Param, sampleRate: Double) {
            self.p = p
            self.sampleRate = sampleRate
            if p == .alchemy { fireNone = fire(0); fireFull = fire(100) }
        }

        private var settle: Int { Int(sampleRate / 10) }       // 100 ms
        private var window: Int { Int(sampleRate / 20) }       // then 50 ms measured

        private func sine(_ amp: Float, _ f: Double) -> (Int) -> Float {
            let sr = sampleRate
            return { i in amp * Float(sin(2 * .pi * f * Double(i) / sr)) }
        }

        /// Gain in dB a quiet 1 kHz tone gets with these settings.
        private func quietGainDB(_ s: [Param: Float], amp: Float) -> Double {
            let e = Engine([.oversampling: 0, .ceilingDB: 0, .clipMode: 2].merging(s) { $1 }, sampleRate: sampleRate)
            e.render(settle, sine(amp, 1000))
            let o = e.render(window, sine(amp, 1000))
            return 20 * log10(KnobAudit.rms(o) / (Double(amp) / 2.0.squareRoot()))
        }

        private func fire(_ v: Float) -> [Float] {
            let e = Engine([.oversampling: 0, .ceilingDB: 0, .clipMode: 2, .alchemy: v], sampleRate: sampleRate)
            let sr = sampleRate
            let sig: (Int) -> Float = { i in
                let t = Double(i) / sr
                return Float(0.6 * sin(2 * .pi * 200 * t) + 0.35 * sin(2 * .pi * 8000 * t))
            }
            e.render(settle, sig)
            return e.render(window, sig)
        }

        func effect(_ v: Float) -> Double {
            switch p {
            case .inputDB, .driveDB, .outputDB:
                return quietGainDB([p: v], amp: 0.01)                       // dB
            case .ceilingDB:
                // driven far past the ceiling with the Hard curve: the output peak is the ceiling
                let e = Engine([.oversampling: 0, .clipMode: 0, .driveDB: 12, p: v], sampleRate: sampleRate)
                e.render(settle, sine(1, 997))
                let o = e.render(window, sine(1, 997))
                return 20 * log10(Double(o.reduce(0) { max($0, abs($1)) }))  // dB
            case .gold:
                // a quiet tone gets Red's full lift: % of the 2.5 dB (Modern) maximum
                return quietGainDB([p: v], amp: 0.001) / Double(Curves.goldMaxDB(classic: false)) * 100
            case .broil:
                // a quiet tone gets Broil's full lift: % of the lift at 100 %
                return quietGainDB([p: v], amp: 0.001) / BroilTaper.fullLiftDB * 100
            case .wet, .dry:
                // unlinked, the other side at 0: level of that side, %
                return pow(10, quietGainDB([.mixUnlink: 1, .wet: 0, .dry: 0, p: v], amp: 0.01) / 20) * 100
            case .alchemy:
                // how much of Fire's full change to the sound this setting makes, %
                let o = fire(v)
                return KnobAudit.rms(zip(o, fireNone).map { $0 - $1 }) / KnobAudit.rms(zip(fireFull, fireNone).map { $0 - $1 }) * 100
            default:
                return .nan
            }
        }
    }

    /// A private engine (its own SharedState and ClipDSP), rendering 64-frame blocks, mono.
    private final class Engine {
        let shared = SharedState(captureCapacity: 64)
        let dsp: ClipDSP
        private var time = 0
        private let block = 64
        private let inBuf: UnsafeMutablePointer<Float>
        private let outL: UnsafeMutablePointer<Float>
        private let outR: UnsafeMutablePointer<Float>

        init(_ settings: [Param: Float], sampleRate: Double) {
            for (p, v) in settings { shared[p] = v }
            dsp = ClipDSP(sampleRate: sampleRate, shared: shared)
            inBuf = .allocate(capacity: block); outL = .allocate(capacity: block); outR = .allocate(capacity: block)
        }

        deinit { inBuf.deallocate(); outL.deallocate(); outR.deallocate() }

        @discardableResult
        func render(_ frames: Int, _ signal: (Int) -> Float) -> [Float] {
            var out: [Float] = []
            out.reserveCapacity(frames)
            var done = 0
            while done < frames {
                let n = min(block, frames - done)
                for i in 0..<n { inBuf[i] = signal(time + i) }
                dsp.process(inL: inBuf, inR: inBuf, outL: outL, outR: outR, frames: n)
                out.append(contentsOf: UnsafeBufferPointer(start: outL, count: n))
                time += n
                done += n
            }
            return out
        }
    }

    fileprivate static func rms(_ x: [Float]) -> Double {
        guard !x.isEmpty else { return 0 }
        return (x.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(x.count)).squareRoot()
    }
}
