import Foundation

/// Turns the audio thread's scope rings (SharedState) into display columns for the screen.
/// UI thread only; it never writes anything the audio thread reads.
///
/// - The window is the newest ~120 ms, cut into one column per display unit. Each column keeps
///   the lowest and highest sample in it (min/max), so short transients are never lost.
/// - Gray = the original input, red = the final output, both on the same fixed scale (never
///   normalised). clip* = the clipper's own input and output, used to show what it removed.
/// - The window's end snaps to a whole column, so the picture scrolls without shimmering.
/// - Nothing new arriving (paused) leaves the picture as it is; samples from before the last
///   stop (scopeClearedAt) read as silence, so stopping clears it; silence is a flat line.
final class ScopeReader {
    static let window = 0.12                  // seconds shown

    private(set) var columns = 0
    private(set) var inMin: [Float] = [], inMax: [Float] = []
    private(set) var outMin: [Float] = [], outMax: [Float] = []
    private(set) var clipInMin: [Float] = [], clipInMax: [Float] = []
    private(set) var clipOutMin: [Float] = [], clipOutMax: [Float] = []
    private(set) var samplesPerColumn = 1
    private(set) var lastTotal = -1
    private(set) var lastCleared = -1

    /// Reads the newest window into about `wanted` columns (exactly as many as fit ~120 ms in
    /// whole samples per column; `columns` says how many). Returns false when nothing changed
    /// since the last call (paused, or the same audio), so the caller can skip work.
    @discardableResult
    func update(_ shared: SharedState, columns wanted: Int) -> Bool {
        let rate = Double(max(shared.sampleRate.value, 8_000))
        let span = min(SharedState.ringSize - 64, Int(rate * Self.window))
        let per = max(1, Int((Double(span) / Double(max(1, min(wanted, span)))).rounded()))
        let n = max(1, span / per)
        if n != columns { resize(n) }
        samplesPerColumn = per
        let total = shared.ringTotal.acquire()          // samples before this are complete
        let cleared = shared.scopeClearedAt.value
        if total == lastTotal && cleared == lastCleared && lastTotal >= 0 { return false }
        lastTotal = total; lastCleared = cleared

        let end = (total / per) * per
        let start = end - per * n
        let mask = SharedState.ringMask

        for c in 0..<n {
            var iLo = Float.infinity, iHi = -Float.infinity
            var oLo = Float.infinity, oHi = -Float.infinity
            var pLo = Float.infinity, pHi = -Float.infinity
            var qLo = Float.infinity, qHi = -Float.infinity
            let from = start + c * per
            for t in from..<(from + per) {
                var a: Float = 0, b: Float = 0, p: Float = 0, q: Float = 0
                if t >= 0 && t >= cleared {
                    let i = t & mask
                    a = shared.scopeIn[i]; b = shared.scopeOut[i]
                    p = shared.clipIn[i]; q = shared.clipOut[i]
                }
                iLo = min(iLo, a); iHi = max(iHi, a)
                oLo = min(oLo, b); oHi = max(oHi, b)
                pLo = min(pLo, p); pHi = max(pHi, p)
                qLo = min(qLo, q); qHi = max(qHi, q)
            }
            inMin[c] = iLo; inMax[c] = iHi
            outMin[c] = oLo; outMax[c] = oHi
            clipInMin[c] = pLo; clipInMax[c] = pHi
            clipOutMin[c] = qLo; clipOutMax[c] = qHi
        }
        return true
    }

    /// How much the clipper took off the top / bottom of column `c` (0 when it didn't touch it).
    func removed(_ c: Int) -> (top: Float, bottom: Float) {
        (max(0, clipInMax[c] - clipOutMax[c]), max(0, clipOutMin[c] - clipInMin[c]))
    }

    private func resize(_ n: Int) {
        columns = n
        let zeros = [Float](repeating: 0, count: n)
        inMin = zeros; inMax = zeros; outMin = zeros; outMax = zeros
        clipInMin = zeros; clipInMax = zeros; clipOutMin = zeros; clipOutMax = zeros
        lastTotal = -1
    }
}
