import SwiftUI

/// Pulls the clip reading from the audio thread at display rate and applies its ballistics, and
/// owns the readers behind the LED strips and the screen. The audio thread only ever writes
/// "max since last read"; the UI reads and clears.
final class MeterReader {
    let shared: SharedState
    private(set) var reduction: Float = 0
    private var last = Date.distantPast
    let stereo = StereoMeterState()
    let scope = ScopeReader()

    init(shared: SharedState) { self.shared = shared }

    /// Safe to call from several views in the same frame; only the first call per frame reads.
    func update(_ now: Date) {
        guard now.timeIntervalSince(last) > 0.008 else { return }
        let dt = Float(min(now.timeIntervalSince(last), 0.1))
        last = now
        let r = shared.meters.exchange(Meter.reductionDB.rawValue, 0)   // read and clear in one atomic step
        reduction = max(r, reduction - 12 * dt)
    }
}
