import Atomics

// MARK: - Lock-free memory shared by the audio thread and the UI
//
// Every value that one thread writes and another reads goes through these atomics, so there are
// no data races and nothing ever locks or waits. Plain values (knob settings, meter samples) use
// relaxed atomics, which compile to ordinary loads and stores on Apple silicon. Counters that
// publish a batch of samples use release (writer) / acquire (reader) ordering, so a reader that
// sees the new count also sees every sample written before it.

/// A fixed array of Floats, each one atomic. Allocated once, never resized.
struct AtomicFloats: @unchecked Sendable {
    private let base: UnsafeMutablePointer<UnsafeAtomic<UInt32>.Storage>
    let count: Int

    init(count: Int, initial: Float = 0) {
        self.count = count
        base = .allocate(capacity: count)
        for i in 0..<count { (base + i).initialize(to: .init(initial.bitPattern)) }
    }

    func deallocate() {
        base.deinitialize(count: count)
        base.deallocate()
    }

    @inline(__always) private func cell(_ i: Int) -> UnsafeAtomic<UInt32> { UnsafeAtomic(at: base + i) }

    @inline(__always) subscript(i: Int) -> Float {
        get { Float(bitPattern: cell(i).load(ordering: .relaxed)) }
        nonmutating set { cell(i).store(newValue.bitPattern, ordering: .relaxed) }
    }

    /// Reads the value and replaces it in one step (the UI's "take the peak and clear it").
    @inline(__always) func exchange(_ i: Int, _ value: Float) -> Float {
        Float(bitPattern: cell(i).exchange(value.bitPattern, ordering: .relaxed))
    }

    /// Raises the value to `value` if it's higher, without losing a concurrent clear.
    /// Lock-free: it only retries if the UI cleared the value in the same instant.
    @inline(__always) func storeMax(_ i: Int, _ value: Float) {
        let c = cell(i)
        var current = c.load(ordering: .relaxed)
        while value > Float(bitPattern: current) {
            let (done, seen) = c.weakCompareExchange(expected: current, desired: value.bitPattern, ordering: .relaxed)
            if done { return }
            current = seen
        }
    }
}

/// One atomic Int.
struct AtomicInt: @unchecked Sendable {
    private let atom: UnsafeAtomic<Int>

    init(_ value: Int = 0) { atom = .create(value) }
    func deallocate() { _ = atom.destroy() }

    /// Plain value (flags, settings).
    @inline(__always) var value: Int {
        get { atom.load(ordering: .relaxed) }
        nonmutating set { atom.store(newValue, ordering: .relaxed) }
    }

    /// Publishing a count after writing the data it covers.
    @inline(__always) func publish(_ v: Int) { atom.store(v, ordering: .releasing) }
    /// Reading a published count before reading the data it covers.
    @inline(__always) func acquire() -> Int { atom.load(ordering: .acquiring) }

    @inline(__always) func exchange(_ v: Int) -> Int { atom.exchange(v, ordering: .acquiringAndReleasing) }
}

/// One atomic Float (sample rates, column rates).
struct AtomicFloat: @unchecked Sendable {
    private let atom: UnsafeAtomic<UInt32>

    init(_ value: Float = 0) { atom = .create(value.bitPattern) }
    func deallocate() { _ = atom.destroy() }

    @inline(__always) var value: Float {
        get { Float(bitPattern: atom.load(ordering: .relaxed)) }
        nonmutating set { atom.store(newValue.bitPattern, ordering: .relaxed) }
    }
}

/// A fixed array of Ints, each one atomic (frame positions and stamps in the song capture ring).
struct AtomicInts: @unchecked Sendable {
    private let base: UnsafeMutablePointer<UnsafeAtomic<Int>.Storage>
    let count: Int

    init(count: Int, initial: Int = 0) {
        self.count = count
        base = .allocate(capacity: count)
        for i in 0..<count { (base + i).initialize(to: .init(initial)) }
    }

    func deallocate() {
        base.deinitialize(count: count)
        base.deallocate()
    }

    @inline(__always) subscript(i: Int) -> Int {
        get { UnsafeAtomic(at: base + i).load(ordering: .relaxed) }
        nonmutating set { UnsafeAtomic(at: base + i).store(newValue, ordering: .relaxed) }
    }
}
