import AVFoundation
import SwiftUI

/// Audio held in memory for looping playback. Allocated off the audio thread, read-only afterwards.
final class PlayerBuffer: @unchecked Sendable {
    let left: UnsafeMutablePointer<Float>
    let right: UnsafeMutablePointer<Float>
    let frames: Int
    let sampleRate: Double

    init(left l: [Float], right r: [Float], sampleRate: Double) {
        frames = max(1, min(l.count, r.count))
        self.sampleRate = sampleRate
        left = .allocate(capacity: frames)
        right = .allocate(capacity: frames)
        left.initialize(repeating: 0, count: frames)
        right.initialize(repeating: 0, count: frames)
        for i in 0..<min(l.count, r.count) { left[i] = l[i]; right[i] = r[i] }
    }

    deinit { left.deallocate(); right.deallocate() }
}

/// Owns the AVAudioEngine, the loaded audio and the offline exporter.
@MainActor
final class AudioController: ObservableObject {
    let face: FaceModel
    var shared: SharedState { face.shared }
    var isPowered: Bool { face.isPowered }

    @Published var isPlaying = false
    @Published var fileName = "Demo Loop"
    /// The loaded file's loudest moments, loudest first (the scrub bar's highlights; the first
    /// is the CLIP CLOCK sample).
    @Published private(set) var clipPoints: [ClipPoint] = []
    @Published var isBusy = false
    @Published var exportURL: URL?
    @Published var errorMessage: String?
    @Published private(set) var samples: [URL] = []

    /// Re-reads On My iPad › Red Clip › Samples (called on launch, on return to the app, after LOAD).
    func refreshSamples() {
        samples = SampleLibrary.list()
        face.sampleFiles = samples.map { SampleItem(url: $0, name: SampleLibrary.relativeName($0)) }
    }

    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode?
    private var buffer: PlayerBuffer?

    // lock-free transport shared with the render block: the audio thread owns the playhead and
    // publishes it; the UI asks for a seek through a mailbox the audio thread takes.
    private let playhead = AtomicInt(0)
    private let playFlag = AtomicInt(0)
    private let seekRequest = AtomicInt(-1)            // -1 = none
    private static let chunk = 1024
    private let scratchL = UnsafeMutablePointer<Float>.allocate(capacity: AudioController.chunk)
    private let scratchR = UnsafeMutablePointer<Float>.allocate(capacity: AudioController.chunk)

    init() {
        face = FaceModel(isPlugin: false)
        scratchL.initialize(repeating: 0, count: AudioController.chunk)
        scratchR.initialize(repeating: 0, count: AudioController.chunk)
        configureSession()
        SampleLibrary.prepareFolder()
        refreshSamples()
        loadDemo()
        face.onPowerChange = { [weak self] on in self?.powerChanged(on) }
        face.loadSample = { [weak self] url in self?.load(url: url) }
        face.loadDemo = { [weak self] in self?.loadDemo() }
        face.jumpToFrame = { [weak self] frame in self?.seek(toFrame: frame) }
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification,
                                               object: nil, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            Task { @MainActor in
                guard let self else { return }
                if type == .began { self.stop() } else if self.isPowered { try? self.engine.start() }
            }
        }
    }

    // MARK: Transport

    var progress: Double {
        guard let b = buffer else { return 0 }
        return Double(playhead.value) / Double(b.frames)
    }

    /// Length of the loaded audio, in seconds.
    var duration: Double {
        guard let b = buffer else { return 0 }
        return Double(b.frames) / b.sampleRate
    }

    func togglePlay() { isPlaying ? stop() : play() }

    /// Power off shuts the whole audio engine down (no processing, no battery use).
    private func powerChanged(_ on: Bool) {
        if on {
            do { try engine.start() }
            catch { errorMessage = "Audio engine failed to start: \(error.localizedDescription)" }
        } else {
            stop()
            engine.stop()
            clearScope()
        }
    }

    func play() {
        if !isPowered { face.setPowered(true) }
        if !engine.isRunning { try? engine.start() }
        if !scrubbing { playFlag.value = 1 }
        shared.songMoving.value = 1
        isPlaying = true
    }

    func stop() {
        playFlag.value = 0
        shared.songMoving.value = 0
        isPlaying = false
    }

    /// Dragging the playhead: the audio goes quiet while the finger moves and carries on from
    /// wherever it lands, so scrubbing never plays a burst of sound (or feeds the Clip Clock).
    private var scrubbing = false

    func beginScrub() {
        guard !scrubbing else { return }
        scrubbing = true
        playFlag.value = 0
    }

    func endScrub() {
        guard scrubbing else { return }
        scrubbing = false
        if isPlaying { playFlag.value = 1 }
    }

    func seek(to fraction: Double) {
        guard let b = buffer else { return }
        seek(toFrame: Int(fraction * Double(b.frames)))
    }

    /// Moves playback to exactly this frame of the file (playing carries on from there).
    func seek(toFrame frame: Int) {
        guard let b = buffer else { return }
        let target = min(b.frames - 1, max(0, frame))
        seekRequest.value = target
        playhead.value = target                      // so the bar follows the finger straight away
        shared.songFrame.value = target              // and the elapsed time jumps there
    }

    /// Stopped (power off, new audio): the screen starts again from a flat line. Paused
    /// playback just freezes it, since no new samples arrive.
    private func clearScope() { shared.scopeClearedAt.value = shared.ringTotal.acquire() }

    // MARK: Loading

    func loadDemo() {
        let sr = 48_000.0
        let (l, r) = DemoLoop.render(sampleRate: sr)
        install(PlayerBuffer(left: l, right: r, sampleRate: sr), name: "Demo Loop")
    }

    func load(url: URL) {
        isBusy = true
        let wasPlaying = isPlaying
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> Result<PlayerBuffer, Error> in
                // Files picked from elsewhere are copied into On My iPad › Red Clip › Samples.
                let source = SampleLibrary.importCopy(of: url) ?? url
                let access = source.startAccessingSecurityScopedResource()
                defer { if access { source.stopAccessingSecurityScopedResource() } }
                do {
                    let file = try AVAudioFile(forReading: source)
                    let fmt = file.processingFormat
                    guard let pcm = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(file.length)),
                          file.length > 0 else { throw LoadError.empty }
                    try file.read(into: pcm)
                    guard let data = pcm.floatChannelData else { throw LoadError.format }
                    let n = Int(pcm.frameLength)
                    let l = Array(UnsafeBufferPointer(start: data[0], count: n))
                    let r = fmt.channelCount > 1 ? Array(UnsafeBufferPointer(start: data[1], count: n)) : l
                    return .success(PlayerBuffer(left: l, right: r, sampleRate: fmt.sampleRate))
                } catch {
                    return .failure(error)
                }
            }.value
            isBusy = false
            refreshSamples()
            switch result {
            case .success(let b):
                install(b, name: url.deletingPathExtension().lastPathComponent)
                if wasPlaying { play() }
            case .failure(let e):
                errorMessage = "Couldn't open that file: \(e.localizedDescription)"
            }
        }
    }

    enum LoadError: LocalizedError {
        case empty, format
        var errorDescription: String? { self == .empty ? "The file has no audio." : "Unsupported audio format." }
    }

    /// Swaps in new audio. The engine is stopped first so the render block never sees a half-swapped buffer.
    private func install(_ b: PlayerBuffer, name: String) {
        stop()
        engine.stop()
        if let s = source { engine.detach(s); source = nil }

        let dsp = ClipDSP(sampleRate: b.sampleRate, shared: shared)
        let ph = playhead, flag = playFlag, seek = seekRequest, sL = scratchL, sR = scratchR, chunk = AudioController.chunk
        ph.value = 0          // the engine is stopped here, so nothing renders while these reset
        clearScope()
        seek.value = -1
        // the screen's elapsed time: frames into this file, published by the render block
        shared.songFrame.value = 0
        shared.songTotal.value = b.frames
        shared.songClock.value = SongClock.file.rawValue
        // CLIP CLOCK: the file's own loudest sample and where it is, before any control
        let peak = SharedState.filePeak(left: b.left, right: b.right, frames: b.frames)
        shared.setFileClipMax(peak: peak.peak, frame: peak.frame)
        clipPoints = ClipPoint.loudest(left: b.left, right: b.right, frames: b.frames, sampleRate: b.sampleRate)

        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: b.sampleRate, channels: 2) else { return }
        let node = AudioController.makeSourceNode(format: fmt, buffer: b, dsp: dsp, playhead: ph, playFlag: flag, seek: seek,
                                                  songFrame: shared.songFrame,
                                                  scratchL: sL, scratchR: sR, chunk: chunk)

        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: fmt)
        source = node
        buffer = b
        fileName = name
        exportURL = nil
        engine.prepare()
        guard isPowered else { return }
        do { try engine.start() } catch { errorMessage = "Audio engine failed to start: \(error.localizedDescription)" }
    }


    /// Built outside the main actor so the render block carries no actor isolation.
    nonisolated private static func makeSourceNode(format fmt: AVAudioFormat, buffer b: PlayerBuffer, dsp: ClipDSP,
                                                   playhead ph: AtomicInt,
                                                   playFlag flag: AtomicInt,
                                                   seek: AtomicInt,
                                                   songFrame: AtomicInt,
                                                   scratchL sL: UnsafeMutablePointer<Float>,
                                                   scratchR sR: UnsafeMutablePointer<Float>,
                                                   chunk: Int) -> AVAudioSourceNode {
        return AVAudioSourceNode(format: fmt) { isSilence, _, frameCount, abl -> OSStatus in
            let list = UnsafeMutableAudioBufferListPointer(abl)
            guard list.count >= 2,
                  let oL = list[0].mData?.assumingMemoryBound(to: Float.self),
                  let oR = list[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            let total = Int(frameCount)

            if flag.value == 0 {
                // idle: output silence and skip the DSP
                oL.update(repeating: 0, count: total)
                oR.update(repeating: 0, count: total)
                isSilence.pointee = true
                return noErr
            }

            var done = 0
            var pos = ph.value
            if seek.value >= 0 {
                let target = seek.exchange(-1)
                if target >= 0 { pos = min(target, b.frames - 1) }
            }
            while done < total {
                let n = min(total - done, chunk, b.frames - pos)
                dsp.timelineFrame = pos              // this chunk's first frame in the file (a chunk never wraps)
                for i in 0..<n {
                    sL[i] = b.left[pos]; sR[i] = b.right[pos]
                    pos += 1
                    if pos >= b.frames { pos = 0 }
                }
                dsp.process(inL: sL, inR: sR, outL: oL + done, outR: oR + done, frames: n)
                done += n
            }
            ph.value = pos
            songFrame.value = pos            // elapsed time on the screen: the audio's own position, loops included
            return noErr
        }
    }

    private func configureSession() {
        let s = AVAudioSession.sharedInstance()
        do {
            try s.setCategory(.playback, mode: .default)
            try s.setPreferredIOBufferDuration(128.0 / 48_000.0)   // 128-frame buffer, low latency
            try s.setActive(true)
        } catch {
            errorMessage = "Audio session error: \(error.localizedDescription)"
        }
    }

    // MARK: Export

    /// Renders the whole file through the current settings to a 24-bit WAV, off the main thread.
    func export() {
        guard let b = buffer else { return }
        isBusy = true
        exportURL = nil
        let snapshot = Param.allCases.map { shared[$0] }
        let name = fileName
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> Result<URL, Error> in
                do {
                    let state = SharedState(captureCapacity: 64)
                    for (i, v) in snapshot.enumerated() { state.params[i] = v }
                    state[.bypass] = 0
                    let dsp = ClipDSP(sampleRate: b.sampleRate, shared: state)

                    let url = FileManager.default.temporaryDirectory
                        .appendingPathComponent("\(name) - Red Clip.wav")
                    try? FileManager.default.removeItem(at: url)
                    let settings: [String: Any] = [
                        AVFormatIDKey: kAudioFormatLinearPCM,
                        AVSampleRateKey: b.sampleRate,
                        AVNumberOfChannelsKey: 2,
                        AVLinearPCMBitDepthKey: 24,
                        AVLinearPCMIsFloatKey: false,
                        AVLinearPCMIsBigEndianKey: false,
                        AVLinearPCMIsNonInterleaved: false
                    ]
                    let file = try AVAudioFile(forWriting: url, settings: settings,
                                               commonFormat: .pcmFormatFloat32, interleaved: false)
                    let chunk = 8192
                    guard let pcm = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                     frameCapacity: AVAudioFrameCount(chunk)),
                          let out = pcm.floatChannelData else { throw LoadError.format }
                    var pos = 0
                    while pos < b.frames {
                        let n = min(chunk, b.frames - pos)
                        dsp.process(inL: b.left + pos, inR: b.right + pos, outL: out[0], outR: out[1], frames: n)
                        pcm.frameLength = AVAudioFrameCount(n)
                        try file.write(from: pcm)
                        pos += n
                    }
                    return .success(url)
                } catch {
                    return .failure(error)
                }
            }.value
            isBusy = false
            switch result {
            case .success(let url): exportURL = url
            case .failure(let e): errorMessage = "Export failed: \(e.localizedDescription)"
            }
        }
    }
}

