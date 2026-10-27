import AudioToolbox
import AVFoundation
import CoreAudioKit

// MARK: - Red Clip as an AUv3 audio effect (Logic Pro for iPad, GarageBand, AUM, Cubasis...)
//
// Built only on GitHub, from the Xcode project in xcode/ (Swift Playgrounds can't build
// plug-ins). It runs the same ClipDSP and shows the same faceplate as the app:
//   - the host owns the audio: it hands Red Clip the track's audio on its audio thread and
//     Red Clip processes it in place (no allocation, no locks, no waiting);
//   - every control on the face is an automatable parameter in the host;
//   - the factory presets show in the host's preset menu, and the full setting is saved with
//     the host project;
//   - POWER off passes the audio through untouched without processing (saves CPU).

public final class RedClipAudioUnit: AUAudioUnit {
    let face: FaceModel
    private let shared: SharedState

    private let inBus: AUAudioUnitBus
    private let outBus: AUAudioUnitBus
    private var inputBusArray: AUAudioUnitBusArray!
    private var outputBusArray: AUAudioUnitBusArray!
    private var tree: AUParameterTree!
    private var factory: [AUAudioUnitPreset] = []
    private var chosenPreset: AUAudioUnitPreset?
    private let render = RedClipRenderState()
    private static let stateKey = "redclip.params"
    private static let powerKey = "redclip.power"

    public override init(componentDescription: AudioComponentDescription,
                         options: AudioComponentInstantiationOptions = []) throws {
        let made = RedClipAudioUnit.onMain { () -> (FaceModel, SharedState) in
            let face = FaceModel(isPlugin: true)
            return (face, face.shared)
        }
        face = made.0
        shared = made.1
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2) else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(kAudioUnitErr_FormatNotSupported))
        }
        inBus = try AUAudioUnitBus(format: format)
        outBus = try AUAudioUnitBus(format: format)
        inBus.maximumChannelCount = 2
        outBus.maximumChannelCount = 2
        try super.init(componentDescription: componentDescription, options: options)

        inputBusArray = AUAudioUnitBusArray(audioUnit: self, busType: .input, busses: [inBus])
        outputBusArray = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [outBus])
        maximumFramesToRender = 4_096

        // Parameters: host -> Red Clip
        tree = Self.makeParameterTree()
        let shared = self.shared
        tree.implementorValueObserver = { parameter, value in
            guard let p = Param(rawValue: Int(parameter.address)) else { return }
            shared[p] = min(max(value, p.range.lowerBound), p.range.upperBound)
            // the face catches up through ParamStore.syncFromShared()
        }
        tree.implementorValueProvider = { parameter in
            guard let p = Param(rawValue: Int(parameter.address)) else { return parameter.value }
            return shared[p]
        }
        tree.implementorStringFromValueCallback = { parameter, valuePointer in
            let value = valuePointer?.pointee ?? parameter.value
            guard let p = Param(rawValue: Int(parameter.address)) else { return "\(value)" }
            return Self.text(p, value)
        }

        // Parameters: Red Clip's face -> host (so moving a knob records automation)
        let paramTree = tree!
        let face = self.face
        Self.onMain {
            face.params.onChange = { p, v in
                paramTree.parameter(withAddress: AUParameterAddress(p.rawValue))?.setValue(v, originator: nil)
            }
        }

        factory = Preset.factory.enumerated().map { index, preset in
            let item = AUAudioUnitPreset()
            item.number = index
            item.name = preset.bank + " · " + preset.name
            return item
        }
    }

    // MARK: Busses

    public override var inputBusses: AUAudioUnitBusArray { inputBusArray }
    public override var outputBusses: AUAudioUnitBusArray { outputBusArray }

    /// Mono in / mono out, or stereo in / stereo out.
    public override var channelCapabilities: [NSNumber]? { [1, 1, 2, 2] }

    public override var latency: TimeInterval { 0 }
    public override var tailTime: TimeInterval { 0 }

    public override var shouldBypassEffect: Bool {
        get { render.bypassed.value != 0 }
        set { render.bypassed.value = newValue ? 1 : 0 }
    }

    // MARK: Parameters and presets

    public override var parameterTree: AUParameterTree? {
        get { tree }
        set { if let newValue { tree = newValue } }
    }

    public override var factoryPresets: [AUAudioUnitPreset]? { factory }

    public override var currentPreset: AUAudioUnitPreset? {
        get { chosenPreset }
        set {
            chosenPreset = newValue
            guard let preset = newValue, preset.number >= 0, preset.number < Preset.factory.count else { return }
            let face = self.face
            let number = preset.number
            Self.onMain { face.params.apply(number) }
        }
    }

    /// Every control (by name, so older projects still open after updates) plus POWER.
    public override var fullState: [String: Any]? {
        get {
            var state = super.fullState ?? [:]
            var values: [String: Float] = [:]
            for p in Param.allCases { values[p.id] = shared[p] }
            state[Self.stateKey] = values
            state[Self.powerKey] = shared.power.value != 0
            return state
        }
        set {
            guard let newValue else { return }
            super.fullState = newValue
            guard let saved = newValue[Self.stateKey] as? [String: Any] else { return }
            let restored = Param.allCases.map { p -> Float in
                (saved[p.id] as? NSNumber)?.floatValue ?? p.defaultValue
            }
            let power = (newValue[Self.powerKey] as? Bool) ?? true
            let face = self.face
            Self.onMain {
                face.params.restore(restored)
                face.setPowered(power)
            }
        }
    }

    // MARK: Rendering

    public override func allocateRenderResources() throws {
        try super.allocateRenderResources()
        guard inBus.format.channelCount == outBus.format.channelCount else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(kAudioUnitErr_FailedInitialization))
        }
        render.prepare(format: inBus.format, frames: maximumFramesToRender, shared: shared)
        render.transport = transportStateBlock            // the host's song position (Clip Clock, SONG screen)
        shared.scopeClearedAt.value = shared.ringTotal.acquire()     // a fresh start shows a flat line
        shared.songEpoch.value &+= 1                      // a new session: the SONG capture starts over
    }

    public override func deallocateRenderResources() {
        render.release()
        super.deallocateRenderResources()
    }

    public override var internalRenderBlock: AUInternalRenderBlock {
        let state = render
        let shared = self.shared
        return { _, timestamp, frameCount, _, outputData, events, pullInputBlock in
            // Audio thread: no locks, no allocation, no waiting, no main-thread work.
            guard let dsp = state.dsp, let inList = state.inputList, let pull = pullInputBlock else {
                return kAudioUnitErr_NoConnection
            }
            let frames = Int(frameCount)
            guard frames <= state.maxFrames else { return kAudioUnitErr_TooManyFramesToProcess }

            // 1. Get the track's audio.
            state.resetInputList(frames: frameCount)
            var pullFlags = AudioUnitRenderActionFlags(rawValue: 0)
            let status = pull(&pullFlags, timestamp, frameCount, 0, inList)
            if status != noErr { return status }

            let input = UnsafeMutableAudioBufferListPointer(inList)
            let output = UnsafeMutableAudioBufferListPointer(outputData)
            guard input.count > 0, output.count > 0,
                  let inL = input[0].mData?.assumingMemoryBound(to: Float.self) else {
                state.applyEvents(events, upTo: frames, start: timestamp.pointee.mSampleTime, frames: frames, shared: shared)
                return noErr
            }
            for i in 0..<output.count where output[i].mData == nil {
                output[i].mData = input[min(i, input.count - 1)].mData
                output[i].mDataByteSize = frameCount * UInt32(MemoryLayout<Float>.size)
            }
            guard let outL = output[0].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            let stereo = input.count > 1 && output.count > 1
            let inR = stereo ? (input[1].mData?.assumingMemoryBound(to: Float.self) ?? inL) : inL
            let outR = stereo ? (output[1].mData?.assumingMemoryBound(to: Float.self) ?? state.spareR) : state.spareR
            let passThrough = state.bypassed.value != 0 || shared.power.value == 0
            if !stereo && !passThrough {
                // Mono: copy first, so writing the output in place can't change what the
                // second (meter-only) channel reads.
                state.monoIn.update(from: inL, count: frames)
            }
            let srcL: UnsafePointer<Float> = stereo || passThrough ? UnsafePointer(inL) : UnsafePointer(state.monoIn)
            let srcR: UnsafePointer<Float> = stereo ? UnsafePointer(inR) : srcL

            // 2. Sample-accurate automation. The block is cut at every event's sample offset;
            //    while the host ramps a control, it's cut every rampStep frames and the value
            //    follows the ramp. Ramps that don't finish here carry on in the next block.
            let start = timestamp.pointee.mSampleTime
            // The host's timeline for this block. The SONG screen's playhead follows it even while
            // passing audio through; audio is captured onto it only while the transport moves.
            let timeline = state.timeline(frames: frames)
            shared.songFrame.value = timeline.frame
            shared.songMoving.value = timeline.moving ? 1 : 0
            shared.songClock.value = timeline.clock.rawValue
            let song = passThrough || !timeline.moving ? -1 : Double(timeline.frame) / dsp.sampleRate
            var event = events
            var done = 0
            while done < frames {
                event = state.applyEvents(event, upTo: done, start: start, frames: frames, shared: shared)
                var end = frames
                if let e = event { end = min(end, state.offset(of: e.pointee.head.eventSampleTime, start: start, frames: frames)) }
                let gliding = state.rampMask
                if gliding != 0 {
                    end = min(end, done + RedClipRenderState.rampStep)
                    state.advanceRamps(by: end - done, shared: shared)
                }
                let n = end - done
                if passThrough {
                    if outL != inL { (outL + done).update(from: inL + done, count: n) }
                    if stereo && outR != inR { (outR + done).update(from: inR + done, count: n) }
                } else {
                    dsp.songTime = song < 0 ? -1 : song + Double(done) / dsp.sampleRate
                    dsp.timelineFrame = song < 0 ? -1 : timeline.frame + done
                    dsp.process(inL: srcL + done, inR: srcR + done, outL: outL + done, outR: outR + done,
                                frames: n, gliding: gliding)
                }
                done = end
            }
            // events stamped at (or after) the block's end take effect from the next block
            state.applyEvents(event, upTo: Int.max, start: start, frames: frames, shared: shared)
            return noErr
        }
    }

    // MARK: Helpers

    /// Runs `work` on the main thread (directly if already there) and returns its result.
    @discardableResult
    static func onMain<T: Sendable>(_ work: @MainActor () -> T) -> T {
        if Thread.isMainThread { return MainActor.assumeIsolated { work() } }
        return DispatchQueue.main.sync { MainActor.assumeIsolated { work() } }
    }

    static func text(_ p: Param, _ value: Float) -> String {
        if let names = p.valueNames {
            let i = min(max(Int(value.rounded()), 0), names.count - 1)
            return names[i]
        }
        if p.isDecibels { return String(format: "%.1f dB", value) }
        return String(format: "%.0f %%", value)
    }

    static func makeParameterTree() -> AUParameterTree {
        let parameters: [AUParameter] = Param.allCases.map { p in
            let address = AUParameterAddress(p.rawValue)
            if let names = p.valueNames {
                let isSwitch = names.count == 2 && names[0] == "Off"
                return AUParameterTree.createParameter(
                    withIdentifier: p.id, name: p.title, address: address,
                    min: p.range.lowerBound, max: p.range.upperBound,
                    unit: isSwitch ? .boolean : .indexed, unitName: nil,
                    flags: [.flag_IsReadable, .flag_IsWritable],
                    valueStrings: isSwitch ? nil : names, dependentParameters: nil)
            }
            return AUParameterTree.createParameter(
                withIdentifier: p.id, name: p.title, address: address,
                min: p.range.lowerBound, max: p.range.upperBound,
                unit: p.isDecibels ? .decibels : .percent, unitName: nil,
                flags: [.flag_IsReadable, .flag_IsWritable, .flag_CanRamp],
                valueStrings: nil, dependentParameters: nil)
        }
        let tree = AUParameterTree.createTree(withChildren: parameters)
        for parameter in parameters {
            if let p = Param(rawValue: Int(parameter.address)) { parameter.value = p.defaultValue }
        }
        return tree
    }
}

/// Everything the render block needs, made when the host starts rendering (never on the audio
/// thread). The ramp state belongs to the audio thread alone; the UI and host reach the controls
/// only through SharedState's atomics.
final class RedClipRenderState: @unchecked Sendable {
    private(set) var dsp: ClipDSP?
    private(set) var inputList: UnsafeMutablePointer<AudioBufferList>?
    private(set) var maxFrames = 0
    let bypassed = AtomicInt(0)                  // host's "bypass effect" (any thread) -> audio
    private(set) var spareR = UnsafeMutablePointer<Float>.allocate(capacity: 1)
    private(set) var monoIn = UnsafeMutablePointer<Float>.allocate(capacity: 1)
    private var inputBuffer: AVAudioPCMBuffer?
    private let inputPointers = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: 2)
    private var inputPointerCount = 0
    /// The host's transport (set before rendering starts) and, for hosts without one, how long
    /// Red Clip has been processing. They feed the Clip Clock's song position and the SONG screen.
    var transport: AUHostTransportStateBlock?
    private var elapsed: Double = 0

    /// While a ramp runs, the block is processed in pieces this long; the DSP moves the control
    /// in a straight line across each piece, so the ramp is followed sample by sample.
    static let rampStep = 16
    /// AUEventSampleTimeImmediate: events stamped "now + n" rather than at an absolute time.
    static let immediate = AUEventSampleTime(bitPattern: 0xffff_ffff_0000_0000)

    // Ramps in progress, one slot per Param (audio thread only).
    private let count = Param.allCases.count
    private let rampValue: UnsafeMutablePointer<Float>
    private let rampStepSize: UnsafeMutablePointer<Float>
    private let rampTarget: UnsafeMutablePointer<Float>
    private let rampLeft: UnsafeMutablePointer<Int>
    private let lower: UnsafeMutablePointer<Float>
    private let upper: UnsafeMutablePointer<Float>
    private let continuous: UnsafeMutablePointer<Bool>
    /// One bit per Param that is ramping (bit = Param.rawValue).
    private(set) var rampMask: UInt32 = 0

    init() {
        rampValue = .allocate(capacity: count); rampValue.initialize(repeating: 0, count: count)
        rampStepSize = .allocate(capacity: count); rampStepSize.initialize(repeating: 0, count: count)
        rampTarget = .allocate(capacity: count); rampTarget.initialize(repeating: 0, count: count)
        rampLeft = .allocate(capacity: count); rampLeft.initialize(repeating: 0, count: count)
        lower = .allocate(capacity: count); upper = .allocate(capacity: count)
        continuous = .allocate(capacity: count)
        for p in Param.allCases {
            lower[p.rawValue] = p.range.lowerBound
            upper[p.rawValue] = p.range.upperBound
            continuous[p.rawValue] = p.valueNames == nil      // switches and selectors jump, never ramp
        }
        inputPointers.initialize(repeating: nil, count: 2)
    }

    deinit {
        bypassed.deallocate()
        spareR.deallocate()
        monoIn.deallocate()
        inputPointers.deallocate()
        for p in [rampValue, rampStepSize, rampTarget, lower, upper] { p.deallocate() }
        rampLeft.deallocate(); continuous.deallocate()
    }

    // MARK: Automation (audio thread)

    /// Where in this block an event falls, 0...frames. Handles AUEventSampleTimeImmediate
    /// (+ offset) as well as absolute sample times.
    @inline(__always) func offset(of time: AUEventSampleTime, start: Double, frames: Int) -> Int {
        let immediate = RedClipRenderState.immediate
        let raw: Int64
        if time >= immediate && time < immediate + 0x10000 { raw = time - immediate }
        else { raw = time - Int64(start) }
        return Int(min(max(raw, 0), Int64(frames)))
    }

    /// Applies every event due at or before `upTo` and returns the first one still to come.
    @discardableResult
    func applyEvents(_ first: UnsafePointer<AURenderEvent>?, upTo: Int, start: Double, frames: Int,
                     shared: SharedState) -> UnsafePointer<AURenderEvent>? {
        var event = first
        while let e = event {
            if offset(of: e.pointee.head.eventSampleTime, start: start, frames: frames) > upTo { break }
            let type = e.pointee.head.eventType
            if type == .parameter || type == .parameterRamp { apply(e.pointee.parameter, shared: shared) }
            event = UnsafePointer(e.pointee.head.next)
        }
        return event
    }

    /// A value now, or a ramp from the current value over the event's ramp duration.
    @inline(__always) private func apply(_ ev: AUParameterEvent, shared: SharedState) {
        let i = Int(ev.parameterAddress)
        guard i >= 0 && i < count else { return }
        let target = min(max(ev.value, lower[i]), upper[i])
        let frames = Int(ev.rampDurationSampleFrames)
        let bit: UInt32 = 1 << UInt32(i)
        if frames > 1 && continuous[i] {
            let from = shared.params[i]
            rampValue[i] = from
            rampTarget[i] = target
            rampStepSize[i] = (target - from) / Float(frames)
            rampLeft[i] = frames
            rampMask |= bit
        } else {
            rampLeft[i] = 0
            rampMask &= ~bit
            shared.params[i] = target
        }
    }

    /// Moves every running ramp on by `frames` and publishes the new values.
    @inline(__always) func advanceRamps(by frames: Int, shared: SharedState) {
        var m = rampMask
        while m != 0 {
            let i = m.trailingZeroBitCount
            m &= m - 1
            rampLeft[i] -= frames
            if rampLeft[i] <= 0 {
                rampValue[i] = rampTarget[i]
                rampLeft[i] = 0
                rampMask &= ~(UInt32(1) << UInt32(i))
            } else {
                rampValue[i] += rampStepSize[i] * Float(frames)
            }
            shared.params[i] = rampValue[i]
        }
    }

    /// Audio thread: the timeline position of this block's first sample. With a host transport,
    /// its sample position (reported while stopped too, so the playhead sits where the host's
    /// does) and whether it is moving. Without one there is no song position to be had, only
    /// the frames Red Clip has processed since it started, reported as such (SongClock.relative).
    func timeline(frames: Int) -> (frame: Int, moving: Bool, clock: SongClock) {
        defer { elapsed += Double(frames) }
        if let transport {
            var flags = AUHostTransportStateFlags(rawValue: 0)
            var position: Double = 0
            if transport(&flags, &position, nil, nil), position.isFinite, abs(position) < 1e15 {
                return (Int(position.rounded()), flags.contains(.moving), .host)
            }
        }
        return (Int(elapsed), true, .relative)
    }

    /// Off the audio thread (render resources being reset): forget ramps in progress.
    func clearRamps() {
        rampMask = 0
        for i in 0..<count { rampLeft[i] = 0 }
    }

    func prepare(format: AVAudioFormat, frames: AUAudioFrameCount, shared: SharedState) {
        let count = Int(max(frames, 4_096))
        maxFrames = count
        dsp = ClipDSP(sampleRate: format.sampleRate, shared: shared)
        elapsed = 0
        clearRamps()
        spareR.deallocate()
        spareR = .allocate(capacity: count)
        spareR.initialize(repeating: 0, count: count)
        monoIn.deallocate()
        monoIn = .allocate(capacity: count)
        monoIn.initialize(repeating: 0, count: count)
        guard let pcmFormat = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate,
                                            channels: format.channelCount),
              let buffer = AVAudioPCMBuffer(pcmFormat: pcmFormat, frameCapacity: AVAudioFrameCount(count)) else {
            inputList = nil
            return
        }
        inputBuffer = buffer
        inputList = buffer.mutableAudioBufferList
        let list = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        inputPointerCount = min(list.count, 2)
        for i in 0..<inputPointerCount { inputPointers[i] = list[i].mData }
    }

    func release() {
        dsp = nil
        inputList = nil
        inputBuffer = nil
        inputPointerCount = 0
        clearRamps()
    }

    /// Audio thread: the host may have pointed our input buffers elsewhere last time; point them
    /// back at our memory and set this block's size.
    func resetInputList(frames: AUAudioFrameCount) {
        guard let inputList else { return }
        let list = UnsafeMutableAudioBufferListPointer(inputList)
        let bytes = frames * UInt32(MemoryLayout<Float>.size)
        for i in 0..<list.count where i < inputPointerCount {
            list[i].mData = inputPointers[i]
            list[i].mDataByteSize = bytes
        }
    }
}
