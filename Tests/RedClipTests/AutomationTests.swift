import AudioToolbox
import AVFoundation
import XCTest

// Regression tests for the AUv3 render path. Each test builds the real RedClipAudioUnit,
// allocates its render resources and renders through `renderBlock`, with automation sent
// through `scheduleParameterBlock`, the way Logic and other hosts drive a plug-in.
// build.yml runs these on the iOS Simulator with the Thread Sanitizer switched on.

/// One Red Clip instance plus the buffers and test signal to drive it.
final class Harness: @unchecked Sendable {
    let unit: RedClipAudioUnit
    let shared: SharedState
    static let maxFrames = 1024
    private let block: AURenderBlock
    private let list: UnsafeMutableAudioBufferListPointer
    private let outL = UnsafeMutablePointer<Float>.allocate(capacity: Harness.maxFrames)
    private let outR = UnsafeMutablePointer<Float>.allocate(capacity: Harness.maxFrames)
    private let pull: AURenderPullInputBlock
    /// Sample time of the next block (only the thread that renders touches it).
    private(set) var time: Double = 0

    init() throws {
        let desc = AudioComponentDescription(componentType: kAudioUnitType_Effect,
                                             componentSubType: Harness.fourCC("rclp"),
                                             componentManufacturer: Harness.fourCC("Tdgr"),
                                             componentFlags: 0, componentFlagsMask: 0)
        unit = try RedClipAudioUnit(componentDescription: desc, options: [])
        shared = unit.face.shared
        unit.maximumFramesToRender = AUAudioFrameCount(Harness.maxFrames)
        try unit.allocateRenderResources()
        block = unit.renderBlock
        list = AudioBufferList.allocate(maximumBuffers: 2)
        pull = { _, timestamp, frames, _, abl in
            let buffers = UnsafeMutableAudioBufferListPointer(abl)
            let t0 = Int(timestamp.pointee.mSampleTime)
            for c in 0..<buffers.count {
                guard let p = buffers[c].mData?.assumingMemoryBound(to: Float.self) else { continue }
                for i in 0..<Int(frames) { p[i] = Harness.signal(t0 + i, channel: c) }
            }
            return noErr
        }
    }

    deinit {
        unit.deallocateRenderResources()
        outL.deallocate(); outR.deallocate()
        free(list.unsafeMutablePointer)
    }

    static func fourCC(_ s: String) -> FourCharCode { s.utf8.reduce(0) { $0 << 8 | FourCharCode($1) } }

    /// Two tones, a little different per channel; peaks about 0.65, so Drive pushes it into the clipper.
    static func signal(_ n: Int, channel: Int) -> Float {
        let t = Double(n) / 48_000
        return Float(0.45 * sin(2 * .pi * 220 * t + Double(channel)) + 0.2 * sin(2 * .pi * 3_300 * t))
    }

    /// Automation at `offset` frames into the next block (as a host schedules it).
    func schedule(_ p: Param, _ value: Float, atOffset offset: Int, ramp: Int = 0) {
        unit.scheduleParameterBlock(AUEventSampleTime(time) + AUEventSampleTime(offset),
                                    AUAudioFrameCount(ramp), AUParameterAddress(p.rawValue), value)
    }

    /// Automation stamped "immediate + offset" (safe from any thread).
    func scheduleImmediate(_ p: Param, _ value: Float, offset: Int, ramp: Int = 0) {
        unit.scheduleParameterBlock(RedClipRenderState.immediate + AUEventSampleTime(offset),
                                    AUAudioFrameCount(ramp), AUParameterAddress(p.rawValue), value)
    }

    /// Renders one block through the plug-in; returns (left, right).
    @discardableResult
    func render(_ frames: Int) -> (l: [Float], r: [Float]) {
        precondition(frames <= Harness.maxFrames)
        let bytes = UInt32(frames * MemoryLayout<Float>.size)
        list[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: bytes, mData: outL)
        list[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: bytes, mData: outR)
        var flags = AudioUnitRenderActionFlags(rawValue: 0)
        var ts = AudioTimeStamp()
        ts.mSampleTime = time
        ts.mFlags = .sampleTimeValid
        let status = block(&flags, &ts, AUAudioFrameCount(frames), 0, list.unsafeMutablePointer, pull)
        precondition(status == noErr, "render failed: \(status)")
        time += Double(frames)
        return (Array(UnsafeBufferPointer(start: outL, count: frames)),
                Array(UnsafeBufferPointer(start: outR, count: frames)))
    }
}

@MainActor
final class AutomationTests: XCTestCase {

    private func dbToGain(_ db: Float) -> Float { pow(10, db / 20) }

    // MARK: 1. An event lands on its own sample, not at the start of the buffer

    func testEventAtNonzeroOffsetTakesEffectOnThatSample() throws {
        let a = try Harness(), b = try Harness()
        a.render(1024); b.render(1024)                    // same warm-up for both

        b.schedule(.outputDB, -12, atOffset: 77)
        let ref = a.render(128), out = b.render(128)

        for i in 0..<77 {
            XCTAssertEqual(out.l[i], ref.l[i], "sample \(i) changed before the event at 77")
            XCTAssertEqual(out.r[i], ref.r[i], "sample \(i) changed before the event at 77")
        }
        XCTAssertNotEqual(out.l[77], ref.l[77], "the change didn't start on sample 77")
        for i in 78..<128 where abs(ref.l[i]) > 1e-3 {
            XCTAssertLessThan(abs(out.l[i]), abs(ref.l[i]), "output should be falling after 77 (sample \(i))")
        }
        XCTAssertEqual(b.shared[.outputDB], -12)
    }

    // MARK: 2. Several events in one buffer = the same events at the starts of split buffers

    func testMultipleEventsInOneBufferMatchSplitBuffers() throws {
        let events: [(Int, Param, Float)] = [
            (30, .outputDB, -6),
            (100, .driveDB, 6),        // into the clipper
            (101, .mix, 50),           // the very next sample
            (150, .clipMode, 0),       // a selector: Hard
            (200, .ceilingDB, -6),     // two at the same sample
            (200, .gold, 40),
        ]
        let one = try Harness(), split = try Harness()
        one.render(512); split.render(512)

        // all six events inside one 256-frame block
        for (offset, p, v) in events { one.schedule(p, v, atOffset: offset) }
        let whole = one.render(256)

        // the same events, each at the start of its own block
        var pieces: (l: [Float], r: [Float]) = ([], [])
        let cuts = [0, 30, 100, 101, 150, 200, 256]
        for k in 0..<(cuts.count - 1) {
            for (offset, p, v) in events where offset == cuts[k] { split.schedule(p, v, atOffset: 0) }
            let part = split.render(cuts[k + 1] - cuts[k])
            pieces.l += part.l; pieces.r += part.r
        }

        XCTAssertEqual(whole.l.count, 256)
        for i in 0..<256 {
            XCTAssertEqual(whole.l[i], pieces.l[i], "left differs at sample \(i)")
            XCTAssertEqual(whole.r[i], pieces.r[i], "right differs at sample \(i)")
        }
        for (_, p, v) in events { XCTAssertEqual(one.shared[p], v, "\(p) didn't end at its value") }
        // and the events really changed the sound
        let plain = try Harness(); plain.render(512)
        XCTAssertNotEqual(plain.render(256).l[220], whole.l[220])
    }

    // MARK: 3. A ramp keeps going across buffers and ends exactly on its target

    func testRampCarriesAcrossBuffersAndLandsOnTarget() throws {
        let ref = try Harness(), h = try Harness()
        ref.render(1024); h.render(1024)
        let start = 100, length = 300, target: Float = -12

        h.schedule(.outputDB, target, atOffset: start, ramp: length)   // only event; nothing in later blocks
        var a: [Float] = [], b: [Float] = []
        var valueAfter: [Float] = []
        for _ in 0..<4 {
            a += ref.render(128).l
            b += h.render(128).l
            valueAfter.append(h.shared[.outputDB])
        }

        // the control's value at the end of each block follows the ramp
        func rampDB(_ t: Int) -> Float { target * Float(min(max(t - start, 0), length)) / Float(length) }
        XCTAssertEqual(valueAfter[0], rampDB(128), accuracy: 1e-3)
        XCTAssertEqual(valueAfter[1], rampDB(256), accuracy: 1e-3)
        XCTAssertEqual(valueAfter[2], rampDB(384), accuracy: 1e-3)
        XCTAssertEqual(valueAfter[3], target, "ramp must end exactly on its target")

        // the gain heard, sample by sample: untouched before the ramp, a straight line in each
        // 16-frame piece, exactly the target from the end of the ramp on
        for i in 0..<512 where abs(a[i]) > 1e-3 {
            let heard = b[i] / a[i]
            let expected: Float
            if i < start {
                expected = 1
            } else if i >= start + length {
                expected = dbToGain(target)
            } else {
                // pieces: 16 frames from the ramp start, cut again at each block edge
                // (block 0 ends at 128), then every 16 frames from each block's start
                let edges = [100, 116, 128] + Array(stride(from: 144, through: 400, by: 16))
                let k = edges.lastIndex { $0 <= i }!
                let pieceStart = edges[k], pieceEnd = edges[k + 1]
                let g0 = dbToGain(rampDB(pieceStart)), g1 = dbToGain(rampDB(pieceEnd))
                expected = g0 + (g1 - g0) * Float(i - pieceStart + 1) / Float(pieceEnd - pieceStart)
            }
            XCTAssertEqual(heard, expected, accuracy: 2e-3, "gain at sample \(i)")
        }
    }

    // MARK: 4. Switches and selectors jump at the event's sample even if a ramp was asked for

    func testSelectorsJumpEvenWhenRamped() throws {
        let ramped = try Harness(), jumped = try Harness()
        ramped.render(512); jumped.render(512)
        ramped.shared[.driveDB] = 9; jumped.shared[.driveDB] = 9
        for _ in 0..<2 { ramped.render(1024); jumped.render(1024) }   // let Drive settle in both

        ramped.schedule(.clipMode, 0, atOffset: 40, ramp: 200)
        jumped.schedule(.clipMode, 0, atOffset: 40)
        let x = ramped.render(128), y = jumped.render(128)
        XCTAssertEqual(ramped.shared[.clipMode], 0)
        XCTAssertEqual(x.l, y.l)
        XCTAssertEqual(x.r, y.r)
    }

    // MARK: 5. Automation still runs while the host bypasses the effect

    func testRampKeepsRunningWhileBypassed() throws {
        let h = try Harness()
        h.render(256)
        h.unit.shouldBypassEffect = true
        h.schedule(.outputDB, -12, atOffset: 10, ramp: 200)
        let t0 = Int(h.time)
        let out = h.render(128)
        for i in 0..<128 { XCTAssertEqual(out.l[i], Harness.signal(t0 + i, channel: 0), "bypass must pass audio through") }
        XCTAssertEqual(h.shared[.outputDB], -12 * 118 / 200, accuracy: 1e-3)
        h.render(128)
        XCTAssertEqual(h.shared[.outputDB], -12)
    }

    // MARK: 6. Knobs, host automation, meters and the screen all at once, from three threads

    func testConcurrentControlAndMeterAccess() throws {
        let h = try Harness()
        let face = h.unit.face
        let stop = AtomicInt(0)
        let blocks = AtomicInt(0)
        let bad = AtomicInt(0)
        let finished = DispatchSemaphore(value: 0)

        // the host's audio thread
        let audio = Thread {
            var n = 0
            while stop.value == 0 {
                let out = h.render(128)
                for v in out.l + out.r where !v.isFinite || abs(v) > 20 { bad.value = 1 }
                n += 1
            }
            blocks.value = n
            finished.signal()
        }
        audio.qualityOfService = .userInteractive

        // the host's automation thread
        let host = Thread {
            var seed: UInt32 = 7
            func rnd() -> Float { seed = seed &* 1_664_525 &+ 1_013_904_223; return Float(seed >> 8) / Float(1 << 24) }
            let ps = Param.allCases
            while stop.value == 0 {
                let p = ps[Int(rnd() * Float(ps.count)) % ps.count]
                let v = p.range.lowerBound + rnd() * (p.range.upperBound - p.range.lowerBound)
                h.scheduleImmediate(p, v, offset: Int(rnd() * 127), ramp: rnd() > 0.5 ? Int(rnd() * 600) : 0)
                usleep(300)
            }
            finished.signal()
        }

        audio.start(); host.start()

        // the UI (this thread): knobs, presets, A/B, meters, the screen and the LED strips
        var seed: UInt32 = 99
        func rnd() -> Float { seed = seed &* 1_664_525 &+ 1_013_904_223; return Float(seed >> 8) / Float(1 << 24) }
        let deadline = Date().addingTimeInterval(3)
        var i = 0
        while Date() < deadline {
            let p = Param.allCases[i % Param.allCases.count]
            face.params[p] = p.range.lowerBound + rnd() * (p.range.upperBound - p.range.lowerBound)
            if i % 97 == 0 { face.params.apply(i % Preset.factory.count) }
            if i % 53 == 0 { face.params.selectSlot(b: i % 2 == 0) }
            face.meters.update(Date())
            face.meters.stereo.update(h.shared, now: Date())
            let total = h.shared.ringTotal.acquire()
            var peak: Float = 0
            for k in 0..<256 { peak = max(peak, abs(h.shared.scopePost[(total - 1 - k) & SharedState.ringMask])) }
            if !peak.isFinite { bad.value = 1 }
            if i % 10 == 0 { face.params.syncFromShared() }
            if i % 211 == 0 { h.shared.loudnessReset.value = 1 }
            i += 1
        }
        stop.value = 1
        XCTAssertEqual(finished.wait(timeout: .now() + 5), .success)
        XCTAssertEqual(finished.wait(timeout: .now() + 5), .success)

        XCTAssertGreaterThan(blocks.value, 100, "the audio thread should have kept rendering")
        XCTAssertEqual(bad.value, 0, "output or screen data went non-finite or out of bounds")
        for p in Param.allCases {
            XCTAssertTrue(p.range.contains(h.shared[p]), "\(p) = \(h.shared[p]) is outside its range")
        }
        for m in 0..<Meter.count { XCTAssertTrue(h.shared.meters[m].isFinite, "meter \(m) is not finite") }
        XCTAssertTrue(face.meters.reduction.isFinite)
    }
}
