import Foundation

// MARK: - Parameters

/// One parameter map used by the UI, the audio thread and the exporter.
enum Param: Int, CaseIterable {
    // faceplate
    case inputDB, driveDB, ceilingDB, mix, outputDB, clipMode, oversampling, link, bypass
    // Gold Clip extras
    case gold, goldMode, unity, alchemy, boxTone, delta

    var range: ClosedRange<Float> {
        switch self {
        case .inputDB, .outputDB: return -12...12
        case .driveDB: return 0...12
        case .ceilingDB: return -12...0
        case .mix, .gold, .alchemy: return 0...100
        case .clipMode: return 0...2        // 0 Hard, 1 Classic (soft knee), 2 Modern (medium knee)
        case .oversampling: return 0...2   // 1x, 2x, 4x
        case .goldMode: return 0...1        // 0 Modern (up to +2.5 dB), 1 Classic (up to +6 dB)
        case .boxTone: return 0...2         // 0 Flat, 1 Modern, 2 Classic
        case .link, .bypass, .unity, .delta: return 0...1
        }
    }

    var defaultValue: Float {
        switch self {
        case .ceilingDB: return -0.3
        case .mix: return 100
        case .clipMode: return 2
        case .oversampling: return 1
        default: return 0
        }
    }
}

enum Meter: Int {
    // inLUFS / outLUFS are short-term (3 s); M = momentary (400 ms), I = integrated (gated, since reset)
    case inPeakL, inPeakR, outPeakL, outPeakR, inLUFS, outLUFS, clip, reductionDB
    case inLUFSM, outLUFSM, inLUFSI, outLUFSI
    static let count = 12
}

/// Memory shared between the audio thread and the UI. Allocated once, never resized.
/// Single Float reads/writes are used as lock-free mailboxes (no locks in the audio callback).
final class SharedState: @unchecked Sendable {
    static let waveColumns = 1024          // about 10 s of history at 100 columns per second

    let params: UnsafeMutablePointer<Float>
    let meters: UnsafeMutablePointer<Float>
    let waveIn: UnsafeMutablePointer<Float>    // peak going INTO the clipper per column (after Input, Drive, Gold)
    let waveOut: UnsafeMutablePointer<Float>   // output peak per column
    let waveWrite: UnsafeMutablePointer<Int>   // next column to write
    let waveTotal: UnsafeMutablePointer<Int>   // columns written so far (never wraps; the screen scrolls by it)
    let waveRate: UnsafeMutablePointer<Float>  // columns per second
    let power: UnsafeMutablePointer<Int32>     // 0 = power button off (plug-in passes audio through untouched)
    let loudnessReset: UnsafeMutablePointer<Int32>  // UI sets 1 to restart the integrated LUFS readings

    init() {
        params = .allocate(capacity: Param.allCases.count)
        for p in Param.allCases { params[p.rawValue] = p.defaultValue }
        meters = .allocate(capacity: Meter.count)
        meters.initialize(repeating: 0, count: Meter.count)
        for m in [Meter.inLUFS, .outLUFS, .inLUFSM, .outLUFSM, .inLUFSI, .outLUFSI] { meters[m.rawValue] = -70 }
        waveIn = .allocate(capacity: SharedState.waveColumns)
        waveIn.initialize(repeating: 0, count: SharedState.waveColumns)
        waveOut = .allocate(capacity: SharedState.waveColumns)
        waveOut.initialize(repeating: 0, count: SharedState.waveColumns)
        waveWrite = .allocate(capacity: 1)
        waveWrite.initialize(to: 0)
        waveTotal = .allocate(capacity: 1)
        waveTotal.initialize(to: 0)
        waveRate = .allocate(capacity: 1)
        waveRate.initialize(to: 100)
        power = .allocate(capacity: 1)
        power.initialize(to: 1)
        loudnessReset = .allocate(capacity: 1)
        loudnessReset.initialize(to: 0)
    }

    deinit {
        params.deallocate(); meters.deallocate()
        waveIn.deallocate(); waveOut.deallocate(); waveWrite.deallocate(); waveTotal.deallocate(); waveRate.deallocate(); power.deallocate(); loudnessReset.deallocate()
    }

    subscript(p: Param) -> Float {
        get { params[p.rawValue] }
        set { params[p.rawValue] = newValue }
    }
}

// MARK: - Building blocks

@inline(__always) func dbToGain(_ db: Float) -> Float { pow(10, db / 20) }
@inline(__always) func gainToDB(_ g: Float) -> Float { 20 * log10(max(g, 1e-9)) }

struct Biquad {
    var b0: Float = 1, b1: Float = 0, b2: Float = 0, a1: Float = 0, a2: Float = 0
    var z1: Float = 0, z2: Float = 0

    @inline(__always) mutating func process(_ x: Float) -> Float {
        let y = b0 * x + z1
        z1 = b1 * x - a1 * y + z2
        z2 = b2 * x - a2 * y
        return y
    }

    mutating func reset() { z1 = 0; z2 = 0 }

    // RBJ cookbook designs (computed in Double, stored as Float)
    static func lowpass(fs: Double, f: Double, q: Double) -> Biquad {
        let w = 2 * Double.pi * f / fs, c = cos(w), al = sin(w) / (2 * q)
        let a0 = 1 + al
        return Biquad(b0: Float((1 - c) / 2 / a0), b1: Float((1 - c) / a0), b2: Float((1 - c) / 2 / a0),
                      a1: Float(-2 * c / a0), a2: Float((1 - al) / a0))
    }

    static func highpass(fs: Double, f: Double, q: Double) -> Biquad {
        let w = 2 * Double.pi * f / fs, c = cos(w), al = sin(w) / (2 * q)
        let a0 = 1 + al
        return Biquad(b0: Float((1 + c) / 2 / a0), b1: Float(-(1 + c) / a0), b2: Float((1 + c) / 2 / a0),
                      a1: Float(-2 * c / a0), a2: Float((1 - al) / a0))
    }

    static func highShelf(fs: Double, f: Double, gainDB: Double, q: Double) -> Biquad {
        let A = pow(10, gainDB / 40), w = 2 * Double.pi * f / fs, c = cos(w), s = sin(w)
        let al = s / (2 * q), sq = 2 * sqrt(A) * al
        let a0 = (A + 1) - (A - 1) * c + sq
        return Biquad(b0: Float(A * ((A + 1) + (A - 1) * c + sq) / a0),
                      b1: Float(-2 * A * ((A - 1) + (A + 1) * c) / a0),
                      b2: Float(A * ((A + 1) + (A - 1) * c - sq) / a0),
                      a1: Float(2 * ((A - 1) - (A + 1) * c) / a0),
                      a2: Float(((A + 1) - (A - 1) * c - sq) / a0))
    }

    static func peak(fs: Double, f: Double, gainDB: Double, q: Double) -> Biquad {
        let A = pow(10, gainDB / 40), w = 2 * Double.pi * f / fs, c = cos(w), al = sin(w) / (2 * q)
        let a0 = 1 + al / A
        return Biquad(b0: Float((1 + al * A) / a0), b1: Float(-2 * c / a0), b2: Float((1 - al * A) / a0),
                      a1: Float(-2 * c / a0), a2: Float((1 - al / A) / a0))
    }
}

/// Elliptic anti-imaging / anti-aliasing low-pass (0.05 dB ripple to 0.4375 x base rate,
/// 90 dB down at the base Nyquist), 6 sections per oversampling factor. The coefficients
/// depend only on the ratio between rates, so they hold for 44.1, 48, 96 kHz alike.
private let maxStages = 6
private let ellipticSOS: [Biquad] = [
    // 2x
    Biquad(b0: 0.0028408921100816016, b1: 0.0042498632557416991, b2: 0.0028408921100816012, a1: -0.53423437523040573, a2: 0),
    Biquad(b0: 1, b1: 0.7351106760278352, b2: 1, a1: -0.95814760013747502, a2: 0.38073006866017695),
    Biquad(b0: 1, b1: 1, b2: 0, a1: -0.72969943243994739, a2: 0.57982715876866453),
    Biquad(b0: 1, b1: 0.2654150568978707, b2: 1, a1: -0.52992024766639423, a2: 0.75959133707964599),
    Biquad(b0: 1, b1: 0.035728055067805277, b2: 1, a1: -0.40849225330532768, a2: 0.88253433205744714),
    Biquad(b0: 1, b1: -0.055460253271234994, b2: 1.0000000000000002, a1: -0.35855478619386905, a2: 0.96493605864199283),
    // 4x
    Biquad(b0: 0.00020967994987201597, b1: 0.0002726405465972759, b2: 0.00020967994987201595, a1: -1.540900464034425, a2: 0.60703358195865864),
    Biquad(b0: 1, b1: -0.48064334744511811, b2: 1.0000000000000002, a1: -1.5323065843629911, a2: 0.69051593361802432),
    Biquad(b0: 1, b1: -1.1046850504950838, b2: 1.0000000000000002, a1: -1.5218998319652899, a2: 0.79920463914056983),
    Biquad(b0: 1, b1: -1.3231558590766284, b2: 1, a1: -1.5156105520461611, a2: 0.88708122417029889),
    Biquad(b0: 1, b1: -1.4092857059469537, b2: 1.0000000000000002, a1: -1.5161907136151218, a2: 0.94531716787371833),
    Biquad(b0: 1, b1: -1.4407755324826823, b2: 0.99999999999999989, a1: -1.5261531579549696, a2: 0.98384787562341824),
    // 8x
    Biquad(b0: 6.0141742037010795e-05, b1: 6.2268936964080645e-06, b2: 6.0141742037010795e-05, a1: -1.7673994972320051, a2: 0.78495025569205523),
    Biquad(b0: 1, b1: -1.4963821701509792, b2: 1, a1: -1.7895738092321376, a2: 0.83137658562809091),
    Biquad(b0: 1, b1: -1.7459566505988029, b2: 0.99999999999999989, a1: -1.8183900683499417, a2: 0.89123368869741482),
    Biquad(b0: 1, b1: -1.8171624459562543, b2: 1, a1: -1.8420708820589013, a2: 0.939148839841212),
    Biquad(b0: 1, b1: -1.8433914394211748, b2: 0.99999999999999956, a1: -1.8590089081108239, a2: 0.97066132794662852),
    Biquad(b0: 1, b1: -1.852739501560448, b2: 1, a1: -1.8728758396166278, a2: 0.99137654526740004),
]

// MARK: - Shaping curves (also used by the UI transfer display)

enum Curves {
    /// Knee fraction per clip style: 0 Hard (no knee), 1 Classic (soft knee), 2 Modern (medium knee).
    static func knee(_ mode: Int) -> Float { mode == 1 ? 0.35 : (mode == 2 ? 0.15 : 0) }

    /// Clipper: unity below the knee, tanh rounding into the ceiling, never above it.
    @inline(__always) static func clip(_ x: Float, ceiling c: Float, knee: Float) -> Float {
        let a = abs(x)
        let y: Float
        if knee <= 0 {
            y = min(a, c)
        } else {
            let t = c * (1 - knee)
            if a <= t { y = a } else { let r = c - t; y = t + r * tanh((a - t) / r) }
        }
        return x < 0 ? -y : y
    }

    /// Most gain each Gold style adds at 100 %: Modern 2.5 dB, Classic 6 dB.
    static func goldMaxDB(classic: Bool) -> Float { classic ? 6 : 2.5 }

    /// Gold, modelled on Lavry Gold soft saturation. For G dB of Gold (relative to the ceiling):
    /// untouched below -2G dB, peaks above that rounded off progressively (tape-like, no time
    /// constants) so they never pass -G dB, then G dB of make-up gain lifts everything back so
    /// the peaks land on the ceiling. Lavry's +6 dB mode is exactly this with G = 6 (threshold
    /// -12 dBFS, peaks held under -6 dBFS). Returns the saturated sample BEFORE make-up gain.
    @inline(__always) static func goldSaturate(_ x: Float, threshold t: Float, limit l: Float) -> Float {
        let a = abs(x)
        if a <= t { return x }
        let r = l - t
        let y = t + r * tanh((a - t) / r)
        return x < 0 ? -y : y
    }

    /// The whole Gold stage as the UI's transfer display would draw it.
    static func gold(_ x: Float, ceiling c: Float, amount: Float, classic: Bool, unity: Bool) -> Float {
        let g = amount * goldMaxDB(classic: classic)
        guard g > 0.01 else { return x }
        let y = goldSaturate(x, threshold: c * dbToGain(-2 * g), limit: c * dbToGain(-g))
        return unity ? y : y * dbToGain(g)
    }
}

/// BS.1770-4 / EBU R128 loudness for one signal (stereo summed): momentary (400 ms), short-term
/// (3 s) and integrated (absolute -70 LUFS gate + relative -10 LU gate, 0.1 LU histogram).
/// All memory is allocated in init; `addBlock` runs on the audio thread.
final class LoudnessMeter {
    private let ring = UnsafeMutablePointer<Double>.allocate(capacity: 30)
    private var ringPos = 0
    private var filled = 0
    private static let bins = 1000          // -70 ... +30 LUFS in 0.1 LU steps
    private let hist = UnsafeMutablePointer<Int32>.allocate(capacity: LoudnessMeter.bins)
    private let histE = UnsafeMutablePointer<Double>.allocate(capacity: LoudnessMeter.bins)  // exact energy per bin
    private(set) var momentary: Float = -70
    private(set) var shortTerm: Float = -70
    private(set) var integrated: Float = -70

    init() {
        ring.initialize(repeating: 0, count: 30)
        hist.initialize(repeating: 0, count: LoudnessMeter.bins)
        histE.initialize(repeating: 0, count: LoudnessMeter.bins)
    }
    deinit { ring.deallocate(); hist.deallocate(); histE.deallocate() }

    func reset() {
        for i in 0..<30 { ring[i] = 0 }
        for i in 0..<LoudnessMeter.bins { hist[i] = 0; histE[i] = 0 }
        ringPos = 0; filled = 0
        momentary = -70; shortTerm = -70; integrated = -70
    }

    @inline(__always) static func lufs(_ energy: Double) -> Float {
        energy > 1e-12 ? Float(-0.691 + 10 * log10(energy)) : -70
    }

    /// One 100 ms block: the mean square of each K-weighted channel, summed over channels.
    func addBlock(_ energy: Double) {
        ring[ringPos] = energy
        ringPos = (ringPos + 1) % 30
        filled = min(filled + 1, 30)

        var m: Double = 0
        let mCount = min(filled, 4)
        for i in 1...mCount { m += ring[(ringPos - i + 30) % 30] }
        m /= Double(mCount)
        var st: Double = 0
        for i in 1...filled { st += ring[(ringPos - i + 30) % 30] }
        st /= Double(filled)
        momentary = max(-70, Self.lufs(m))
        shortTerm = max(-70, Self.lufs(st))

        // Integrated: every 100 ms step closes a 400 ms gating block (75 % overlap)
        guard filled >= 4 else { return }
        let blockLUFS = Self.lufs(m)
        if blockLUFS > -70 {
            let bin = min(max(Int((blockLUFS + 70) * 10), 0), LoudnessMeter.bins - 1)
            hist[bin] &+= 1
            histE[bin] += m
        }
        var sumE: Double = 0, n: Double = 0
        for b in 0..<LoudnessMeter.bins where hist[b] > 0 {
            sumE += histE[b]; n += Double(hist[b])
        }
        guard n > 0 else { integrated = -70; return }
        let relative = Self.lufs(sumE / n) - 10
        let first = min(max(Int((relative + 70) * 10), 0), LoudnessMeter.bins - 1)
        sumE = 0; n = 0
        for b in first..<LoudnessMeter.bins where hist[b] > 0 {
            sumE += histE[b]; n += Double(hist[b])
        }
        integrated = n > 0 ? max(-70, Self.lufs(sumE / n)) : -70
    }
}

/// Exact BS.1770-4 K-weighting coefficients for any sample rate (same derivation as libebur128).
enum KWeighting {
    static func preFilter(fs: Double) -> Biquad {
        let f0 = 1681.974450955533, g = 3.999843853973347, q = 0.7071752369554196
        let k = tan(Double.pi * f0 / fs)
        let vh = pow(10, g / 20), vb = pow(vh, 0.4996667741545416)
        let a0 = 1 + k / q + k * k
        return Biquad(b0: Float((vh + vb * k / q + k * k) / a0), b1: Float(2 * (k * k - vh) / a0),
                      b2: Float((vh - vb * k / q + k * k) / a0),
                      a1: Float(2 * (k * k - 1) / a0), a2: Float((1 - k / q + k * k) / a0))
    }

    static func rlb(fs: Double) -> Biquad {
        let f0 = 38.13547087602444, q = 0.5003270373238773
        let k = tan(Double.pi * f0 / fs)
        let a0 = 1 + k / q + k * k
        return Biquad(b0: 1, b1: -2, b2: 1, a1: Float(2 * (k * k - 1) / a0), a2: Float((1 - k / q + k * k) / a0))
    }
}

// MARK: - Per-channel state

private final class Channel {
    // oversampling filters (6 sections each): wet path and a matched dry/reference path (keeps parallel mix and delta phase-aligned)
    let upW = UnsafeMutablePointer<Biquad>.allocate(capacity: maxStages)
    let dnW = UnsafeMutablePointer<Biquad>.allocate(capacity: maxStages)
    let upR = UnsafeMutablePointer<Biquad>.allocate(capacity: maxStages)
    let dnR = UnsafeMutablePointer<Biquad>.allocate(capacity: maxStages)
    var alchLP: Float = 0
    var box1 = Biquad(), box2 = Biquad()
    var kIn1 = Biquad(), kIn2 = Biquad(), kOut1 = Biquad(), kOut2 = Biquad()

    init() {
        for p in [upW, dnW, upR, dnR] { p.initialize(repeating: Biquad(), count: maxStages) }
    }
    deinit { for p in [upW, dnW, upR, dnR] { p.deallocate() } }

    func load(_ coeffs: UnsafePointer<Biquad>) {
        for i in 0..<maxStages {
            upW[i] = coeffs[i]; dnW[i] = coeffs[i]; upR[i] = coeffs[i]; dnR[i] = coeffs[i]
        }
        alchLP = 0
    }
}

// MARK: - The processor

/// Realtime-safe clipper. All memory is allocated in init; `process` never allocates or locks.
final class ClipDSP: @unchecked Sendable {
    let sampleRate: Double
    let shared: SharedState

    private let ch = [Channel(), Channel()]
    private let osCoeffs = UnsafeMutablePointer<Biquad>.allocate(capacity: 4 * maxStages)  // per factor 1,2,4,8
    private var alchCoef: (Float, Float, Float, Float) = (0, 0, 0, 0)
    private var curOS = -1
    private var curBox = -1

    // smoothed controls
    private var sIn: Float = 1, sDrive: Float = 1, sOut: Float = 1, sMix: Float = 1
    private var sCeil: Float = 1, sGold: Float = 0, sAlch: Float = 0, sBypass: Float = 0
    private var sUnity: Float = 0
    private let smooth: Float

    // Gold (per base-rate sample, shared by both channels and every oversampled sub-sample)
    private var goldOn = false
    private var goldT: Float = 1, goldL: Float = 1, goldMakeup: Float = 1
    private var clipOver: Float = 1   // largest (signal into clipper / ceiling) this block

    // loudness: 100 ms blocks, K-weighted, double-precision sums
    private let lufsBlock: Int
    private var lufsCount = 0
    private var accIn: Double = 0, accOut: Double = 0
    private let loudIn = LoudnessMeter()
    private let loudOut = LoudnessMeter()

    // waveform columns
    private let colSamples: Int
    private var colCount = 0
    private var colIn: Float = 0, colOut: Float = 0
    private var colPre: Float = 0     // peak into the clipper, gathered in shape()

    init(sampleRate: Double, shared: SharedState) {
        self.sampleRate = sampleRate
        self.shared = shared
        smooth = 1 - Float(exp(-1 / (0.015 * sampleRate)))
        lufsBlock = max(1, Int((sampleRate / 10).rounded()))
        colSamples = max(1, Int((sampleRate / 100).rounded()))
        shared.waveRate.pointee = Float(sampleRate / Double(max(1, Int((sampleRate / 100).rounded()))))

        var a: [Float] = []
        for (i, factor) in [1, 2, 4, 8].enumerated() {
            let fsOS = sampleRate * Double(factor)
            for s in 0..<maxStages {
                osCoeffs[i * maxStages + s] = i == 0 ? Biquad() : ellipticSOS[(i - 1) * maxStages + s]
            }
            a.append(Float(exp(-2 * Double.pi * 4000 / fsOS)))
        }
        alchCoef = (a[0], a[1], a[2], a[3])

        // K-weighting (BS.1770-4 pre-filter + RLB high-pass), exact for this sample rate
        let shelf = KWeighting.preFilter(fs: sampleRate)
        let rlb = KWeighting.rlb(fs: sampleRate)
        for c in ch { c.kIn1 = shelf; c.kIn2 = rlb; c.kOut1 = shelf; c.kOut2 = rlb }

        let p = shared.params
        sIn = dbToGain(p[Param.inputDB.rawValue])
        sOut = dbToGain(p[Param.outputDB.rawValue])
        sCeil = dbToGain(p[Param.ceilingDB.rawValue])
    }

    deinit { osCoeffs.deallocate() }

    private func configureOversampling(_ idx: Int) {
        curOS = idx
        for c in ch { c.load(osCoeffs + idx * maxStages) }
    }

    private func configureBox(_ mode: Int) {
        curBox = mode
        let fs = sampleRate
        for c in ch {
            switch mode {
            case 1: // Modern: gentle air trim
                c.box1 = .highShelf(fs: fs, f: 9000, gainDB: -0.4, q: 0.7)
                c.box2 = .peak(fs: fs, f: 2500, gainDB: 0.15, q: 0.9)
            case 2: // Classic: a bit darker, starts lower
                c.box1 = .highShelf(fs: fs, f: 3500, gainDB: -0.6, q: 0.6)
                c.box2 = .peak(fs: fs, f: 12000, gainDB: -0.3, q: 0.8)
            default:
                c.box1 = Biquad(); c.box2 = Biquad()
            }
        }
    }

    /// Process one block. Inputs may alias each other (mono files pass the same pointer twice).
    func process(inL: UnsafePointer<Float>, inR: UnsafePointer<Float>,
                 outL: UnsafeMutablePointer<Float>, outR: UnsafeMutablePointer<Float>, frames: Int) {
        let p = shared.params
        let osIdx = Int(p[Param.oversampling.rawValue].rounded()).clamped(0, 2)
        if osIdx != curOS { configureOversampling(osIdx) }
        let box = Int(p[Param.boxTone.rawValue].rounded()).clamped(0, 2)
        if box != curBox { configureBox(box) }

        let factor = 1 << osIdx
        let fFactor = Float(factor)
        let aCoef: Float
        switch osIdx {
        case 0: aCoef = alchCoef.0
        case 1: aCoef = alchCoef.1
        case 2: aCoef = alchCoef.2
        default: aCoef = alchCoef.3
        }
        let knee = Curves.knee(Int(p[Param.clipMode.rawValue].rounded()))
        let goldClassic = p[Param.goldMode.rawValue] > 0.5
        let unity = p[Param.unity.rawValue] > 0.5
        let delta = p[Param.delta.rawValue] > 0.5

        let tIn = dbToGain(p[Param.inputDB.rawValue])
        let tDrive = dbToGain(p[Param.driveDB.rawValue])
        let tOut = dbToGain(p[Param.outputDB.rawValue])
        let tCeil = dbToGain(p[Param.ceilingDB.rawValue])
        let tGold = p[Param.gold.rawValue] / 100 * Curves.goldMaxDB(classic: goldClassic)   // in dB
        let tUnity: Float = unity ? 1 : 0
        let tAlch = p[Param.alchemy.rawValue] / 100
        let tMix = p[Param.mix.rawValue] / 100
        let tBypass: Float = p[Param.bypass.rawValue] > 0.5 ? 1 : 0

        if shared.loudnessReset.pointee != 0 {
            shared.loudnessReset.pointee = 0
            loudIn.reset(); loudOut.reset()
        }

        var inPeak: (Float, Float) = (0, 0), outPeak: (Float, Float) = (0, 0)
        clipOver = 1
        let k = smooth

        for n in 0..<frames {
            sIn += k * (tIn - sIn); sOut += k * (tOut - sOut)
            sDrive += k * (tDrive - sDrive); sMix += k * (tMix - sMix)
            sCeil += k * (tCeil - sCeil); sGold += k * (tGold - sGold)
            sAlch += k * (tAlch - sAlch); sBypass += k * (tBypass - sBypass)
            sUnity += k * (tUnity - sUnity)
            let c = sCeil

            // Gold for this sample: threshold -2G, peak limit -G (re ceiling), make-up +G unless Unity
            goldOn = sGold > 0.01
            if goldOn {
                goldT = c * dbToGain(-2 * sGold)
                goldL = c * dbToGain(-sGold)
                goldMakeup = dbToGain(sGold * (1 - sUnity))
            }

            var kIn: Float = 0, kOut: Float = 0
            var colOutMax: Float = 0

            for chIdx in 0..<2 {
                let s = ch[chIdx]
                let raw = chIdx == 0 ? inL[n] : inR[n]
                let x = raw * sIn                 // input trim (what the input meter shows)
                let ax = abs(x)
                if chIdx == 0 { inPeak.0 = max(inPeak.0, ax) } else { inPeak.1 = max(inPeak.1, ax) }
                let xd = x * sDrive               // drive pushes into the clipper only

                // --- oversampled nonlinear section ---
                var wet: Float = 0, ref: Float = 0
                if factor == 1 {
                    wet = shape(xd, s, c, knee, goldClassic, aCoef)
                    ref = x
                } else {
                    for j in 0..<factor {
                        var u: Float = j == 0 ? xd * fFactor : 0
                        var r: Float = j == 0 ? x * fFactor : 0
                        for i in 0..<maxStages { u = s.upW[i].process(u); r = s.upR[i].process(r) }
                        var w = shape(u, s, c, knee, goldClassic, aCoef)
                        for i in 0..<maxStages { w = s.dnW[i].process(w); r = s.dnR[i].process(r) }
                        if j == 0 { wet = w; ref = r }
                    }
                }

                // Box Tone (post-clip converter colour, wet only)
                if curBox != 0 { wet = s.box2.process(s.box1.process(wet)) }

                // anti-overshoot: filter ringing after downsampling can't poke past the ceiling
                wet = min(max(wet, -c), c)

                var out: Float
                if delta {
                    out = (wet - ref * sDrive) * sOut      // only what the clipper changed
                } else {
                    out = (wet * sMix + ref * (1 - sMix)) * sOut
                }
                out = out + sBypass * (raw - out)

                let ao = abs(out)
                if chIdx == 0 { outPeak.0 = max(outPeak.0, ao); outL[n] = out }
                else { outPeak.1 = max(outPeak.1, ao); outR[n] = out }
                colOutMax = max(colOutMax, ao)

                let ki = s.kIn2.process(s.kIn1.process(x)); kIn += ki * ki
                let ko = s.kOut2.process(s.kOut1.process(out)); kOut += ko * ko
            }

            // loudness: 100 ms blocks into the BS.1770 meters
            accIn += Double(kIn); accOut += Double(kOut)
            lufsCount += 1
            if lufsCount >= lufsBlock {
                loudIn.addBlock(accIn / Double(lufsCount))
                loudOut.addBlock(accOut / Double(lufsCount))
                let m = shared.meters
                m[Meter.inLUFSM.rawValue] = loudIn.momentary
                m[Meter.inLUFS.rawValue] = loudIn.shortTerm
                m[Meter.inLUFSI.rawValue] = loudIn.integrated
                m[Meter.outLUFSM.rawValue] = loudOut.momentary
                m[Meter.outLUFS.rawValue] = loudOut.shortTerm
                m[Meter.outLUFSI.rawValue] = loudOut.integrated
                accIn = 0; accOut = 0; lufsCount = 0
            }

            // waveform columns
            colIn = max(colIn, colPre); colOut = max(colOut, colOutMax)
            colCount += 1
            if colCount >= colSamples {
                let total = shared.waveTotal.pointee
                let w = total % SharedState.waveColumns
                shared.waveIn[w] = colIn
                shared.waveOut[w] = colOut
                shared.waveWrite.pointee = (w + 1) % SharedState.waveColumns
                shared.waveTotal.pointee = total &+ 1      // published last, after the column is filled
                colIn = 0; colOut = 0; colPre = 0; colCount = 0
            }
        }

        // meters: audio thread keeps the max, UI reads and resets
        let m = shared.meters
        m[Meter.inPeakL.rawValue] = max(m[Meter.inPeakL.rawValue], inPeak.0)
        m[Meter.inPeakR.rawValue] = max(m[Meter.inPeakR.rawValue], inPeak.1)
        m[Meter.outPeakL.rawValue] = max(m[Meter.outPeakL.rawValue], outPeak.0)
        m[Meter.outPeakR.rawValue] = max(m[Meter.outPeakR.rawValue], outPeak.1)
        if clipOver > 1 { m[Meter.clip.rawValue] = 1 }
        m[Meter.reductionDB.rawValue] = max(m[Meter.reductionDB.rawValue], gainToDB(clipOver))
    }

    /// Gold (Lavry-style soft saturation + make-up) -> clipper -> Alchemy, at the oversampled rate.
    @inline(__always) private func shape(_ x: Float, _ s: Channel, _ c: Float, _ knee: Float,
                                         _ goldClassic: Bool, _ aCoef: Float) -> Float {
        var y = x
        if goldOn { y = Curves.goldSaturate(y, threshold: goldT, limit: goldL) * goldMakeup }
        let a = abs(y)
        colPre = max(colPre, a)
        if a > c { clipOver = max(clipOver, a / c) }     // CLIP readout: how far past the ceiling
        y = Curves.clip(y, ceiling: c, knee: knee)

        // Alchemy: amplitude-dependent tilt around 4 kHz. Near the ceiling the highs dip up to
        // about 1 dB and the lows lift slightly, softening the edge clipping leaves behind.
        s.alchLP = y + aCoef * (s.alchLP - y)
        if sAlch > 0.0001 {
            let lo = s.alchLP, hi = y - lo
            let e = min(abs(y) / c, 1), e2 = e * e
            y = lo * (1 + sAlch * 0.035 * e2) + hi * (1 - sAlch * 0.109 * e2)
        }
        return y
    }

    /// Clears filter memory (used before an offline export).
    func reset() {
        curOS = -1; curBox = -1
        for c in ch {
            c.kIn1.reset(); c.kIn2.reset(); c.kOut1.reset(); c.kOut2.reset()
        }
        loudIn.reset(); loudOut.reset()
    }
}

extension Comparable {
    @inline(__always) func clamped(_ lo: Self, _ hi: Self) -> Self { min(max(self, lo), hi) }
}

// MARK: - Built-in demo loop (so the app makes sound before a file is loaded)

enum DemoLoop {
    /// A 4-bar 120 BPM beat with kick, snare, hats and a saw bass. Returns (left, right).
    static func render(sampleRate sr: Double) -> ([Float], [Float]) {
        let beat = 0.5
        let length = Int(sr * beat * 16)
        var l = [Float](repeating: 0, count: length)
        var r = [Float](repeating: 0, count: length)
        var seed: UInt32 = 22222
        func noise() -> Float {
            seed = seed &* 1664525 &+ 1013904223
            return Float(Int32(bitPattern: seed)) / Float(Int32.max)
        }
        func add(_ i: Int, _ v: Float, pan: Float = 0) {
            guard i < length else { return }
            l[i] += v * (1 - max(pan, 0)); r[i] += v * (1 + min(pan, 0))
        }
        // kick on every beat
        for b in 0..<16 {
            let start = Int(Double(b) * beat * sr)
            var phase = 0.0
            for i in 0..<Int(0.35 * sr) {
                let t = Double(i) / sr
                let f = 45 + 110 * exp(-t * 28)
                phase += 2 * Double.pi * f / sr
                add(start + i, Float(sin(phase) * exp(-t * 7)) * 0.95)
            }
        }
        // snare on 2 and 4
        for b in stride(from: 1, to: 16, by: 2) {
            let start = Int(Double(b) * beat * sr)
            for i in 0..<Int(0.22 * sr) {
                let t = Double(i) / sr
                let body = Float(sin(2 * Double.pi * 190 * t) * exp(-t * 30)) * 0.5
                add(start + i, (noise() * 0.55 * Float(exp(-t * 18))) + body)
            }
        }
        // hats on 8ths
        for e in 0..<32 {
            let start = Int(Double(e) * beat / 2 * sr)
            var hp: Float = 0, last: Float = 0
            for i in 0..<Int(0.05 * sr) {
                let n = noise(); hp = 0.6 * (hp + n - last); last = n
                add(start + i, hp * 0.22 * Float(exp(-Double(i) / sr * 70)), pan: e % 2 == 0 ? 0.3 : -0.3)
            }
        }
        // saw bass
        let notes: [Double] = [41.2, 41.2, 49.0, 36.7]
        for bar in 0..<4 {
            for e in 0..<8 {
                let start = Int((Double(bar) * 4 + Double(e) / 2) * beat * sr)
                let f = notes[bar] * (e == 7 ? 2 : 1)
                var ph = 0.0, lp: Float = 0
                let len = Int(beat / 2 * sr * 0.9)
                for i in 0..<len {
                    ph += f / sr; if ph >= 1 { ph -= 1 }
                    let saw = Float(2 * ph - 1)
                    lp += 0.08 * (saw - lp)
                    let env = Float(min(1, Double(i) / 60) * min(1, Double(len - i) / 200))
                    add(start + i, lp * 0.4 * env)
                }
            }
        }
        // normalise so peaks sit around -1 dBFS (hot enough to hit the clipper)
        let peak = max(l.map { abs($0) }.max() ?? 1, r.map { abs($0) }.max() ?? 1)
        let g = 0.89 / max(peak, 1e-6)
        for i in 0..<length { l[i] *= g; r[i] *= g }
        return (l, r)
    }
}
