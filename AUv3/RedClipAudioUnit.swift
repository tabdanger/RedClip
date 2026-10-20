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
        get { render.bypassed.pointee != 0 }
        set { render.bypassed.pointee = newValue ? 1 : 0 }
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
            state[Self.powerKey] = shared.power.pointee != 0
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
    }

    public override func deallocateRenderResources() {
        render.release()
        super.deallocateRenderResources()
    }

    public override var internalRenderBlock: AUInternalRenderBlock {
        let state = render
        let shared = self.shared
        let paramCount = Param.allCases.count
        return { _, timestamp, frameCount, _, outputData, events, pullInputBlock in
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

            // 2. Automation that arrives with this block.
            var event = events
            while let e = event {
                let type = e.pointee.head.eventType
                if type == .parameter || type == .parameterRamp {
                    let address = Int(e.pointee.parameter.parameterAddress)
                    if address >= 0 && address < paramCount { shared.params[address] = e.pointee.parameter.value }
                }
                event = UnsafePointer(e.pointee.head.next)
            }

            // 3. Process (in place when the host gives no output memory).
            let input = UnsafeMutableAudioBufferListPointer(inList)
            let output = UnsafeMutableAudioBufferListPointer(outputData)
            guard input.count > 0, output.count > 0,
                  let inL = input[0].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            for i in 0..<output.count where output[i].mData == nil {
                output[i].mData = input[min(i, input.count - 1)].mData
                output[i].mDataByteSize = frameCount * UInt32(MemoryLayout<Float>.size)
            }
            guard let outL = output[0].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            let stereo = input.count > 1 && output.count > 1
            let inR = stereo ? (input[1].mData?.assumingMemoryBound(to: Float.self) ?? inL) : inL
            let outR = stereo ? (output[1].mData?.assumingMemoryBound(to: Float.self) ?? state.spareR) : state.spareR

            if state.bypassed.pointee != 0 || shared.power.pointee == 0 {
                if outL != inL { outL.update(from: inL, count: frames) }
                if stereo && outR != inR { outR.update(from: inR, count: frames) }
                return noErr
            }
            if stereo {
                dsp.process(inL: inL, inR: inR, outL: outL, outR: outR, frames: frames)
            } else {
                // Mono: copy first, so writing the output in place can't change what the
                // second (meter-only) channel reads.
                state.monoIn.update(from: inL, count: frames)
                dsp.process(inL: state.monoIn, inR: state.monoIn, outL: outL, outR: state.spareR, frames: frames)
            }
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

/// Everything the render block needs, made when the host starts rendering (never on the audio thread).
final class RedClipRenderState: @unchecked Sendable {
    private(set) var dsp: ClipDSP?
    private(set) var inputList: UnsafeMutablePointer<AudioBufferList>?
    private(set) var maxFrames = 0
    let bypassed = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
    private(set) var spareR = UnsafeMutablePointer<Float>.allocate(capacity: 1)
    private(set) var monoIn = UnsafeMutablePointer<Float>.allocate(capacity: 1)
    private var inputBuffer: AVAudioPCMBuffer?
    private var inputPointers: [UnsafeMutableRawPointer?] = []

    init() { bypassed.initialize(to: 0) }

    deinit {
        bypassed.deallocate()
        spareR.deallocate()
        monoIn.deallocate()
    }

    func prepare(format: AVAudioFormat, frames: AUAudioFrameCount, shared: SharedState) {
        let count = Int(max(frames, 4_096))
        maxFrames = count
        dsp = ClipDSP(sampleRate: format.sampleRate, shared: shared)
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
        inputPointers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList).map { $0.mData }
    }

    func release() {
        dsp = nil
        inputList = nil
        inputBuffer = nil
        inputPointers = []
    }

    /// Audio thread: the host may have pointed our input buffers elsewhere last time; point them
    /// back at our memory and set this block's size.
    func resetInputList(frames: AUAudioFrameCount) {
        guard let inputList else { return }
        let list = UnsafeMutableAudioBufferListPointer(inputList)
        let bytes = frames * UInt32(MemoryLayout<Float>.size)
        for i in 0..<list.count where i < inputPointers.count {
            list[i].mData = inputPointers[i]
            list[i].mDataByteSize = bytes
        }
    }
}
