import Foundation

// MARK: - Note value

/// The rhythmic value of each note in the drill, relative to one beat.
enum NoteValue: String, CaseIterable, Identifiable, Sendable {
    case whole = "Whole"
    case half = "Half"
    case quarter = "Quarter"
    case eighth = "Eighth"
    case sixteenth = "16th"
    case thirtySecond = "32nd"

    var id: String { rawValue }

    /// Duration in beats.
    var beats: Double {
        switch self {
        case .whole: return 4
        case .half: return 2
        case .quarter: return 1
        case .eighth: return 0.5
        case .sixteenth: return 0.25
        case .thirtySecond: return 0.125
        }
    }
}

// MARK: - Captured sample

/// A voiced microphone measurement, already converted to the clarinetist's
/// *written* reference frame, kept for scoring and tone analysis.
struct CapturedSample: Sendable {
    let audioTime: TimeInterval   // seconds since capture began (audio clock)
    let writtenMidi: Double       // fractional written MIDI the player produced
    let frequency: Double         // sounding Hz
    let clarity: Double           // YIN periodicity 0...1
    let rms: Double
    let brightness: Double?       // harmonic-number centroid
    let oddEvenRatio: Double?     // odd/even harmonic energy ratio
}

// MARK: - Practice session

/// Drives one scale run: owns the transport clock, metronome, microphone
/// capture, and the per-note tempo/pitch scoring. Observable for SwiftUI.
@MainActor
@Observable
final class PracticeSession {
    enum Phase: Sendable { case idle, countIn, leadIn, playing, finished }

    // Configuration (bindable from the UI).
    var tempo: Double = 80
    var noteValue: NoteValue = .quarter
    var metronomeOn: Bool = true
    /// When true, the metronome drives only the on-screen beat flash — no audible
    /// click — so it can't bleed through the speakers into the recording/analysis.
    var metronomeSilent: Bool = false

    /// Increments on every metronome beat so the UI can flash a beat indicator,
    /// independent of whether the click is audible.
    private(set) var beatTick: Int = 0

    // Published state.
    private(set) var scale: Scale
    private(set) var notes: [ScoredNote] = []
    private(set) var currentIndex: Int?
    private(set) var phase: Phase = .idle
    private(set) var countInBeat: Int?
    /// Current beat (0..<4) of the one-bar rest lead-in, nil otherwise.
    private(set) var leadInBeat: Int?

    let audio = AudioEngine()

    /// The instrument being practiced, taken from the current scale. Drives
    /// transposition and the pitch-tracker bounds.
    var instrument: InstrumentKind { scale.instrument }

    private var captured: [CapturedSample] = []
    private var audioTimeOrigin: TimeInterval?
    /// The most recent analyzed window's timestamp (voiced or not), used to
    /// anchor the transport timeline to the audio clock when playing starts.
    private var lastSampleTime: TimeInterval = 0
    private var runTask: Task<Void, Never>?

    init(scale: Scale) {
        self.scale = scale
        rebuildNotes()
    }

    var secondsPerNote: TimeInterval { (60.0 / tempo) * noteValue.beats }
    var secondsPerBeat: TimeInterval { 60.0 / tempo }

    /// Number of beats in the count-in (one 4/4 bar).
    let countInBeats = 4
    /// Descending film-leader number for the current count-in beat (4, 3, 2, 1).
    var countdownNumber: Int? { countInBeat.map { countInBeats - $0 + 1 } }

    /// All samples captured during the last run, in the transport timeline.
    /// Used by tone analysis after the scale finishes.
    var capturedSamples: [CapturedSample] { captured }
    var transportOrigin: TimeInterval? { audioTimeOrigin }

    // MARK: Configuration

    func setScale(_ scale: Scale) {
        guard phase == .idle || phase == .finished else { return }
        self.scale = scale
        rebuildNotes()
    }

    private func rebuildNotes() {
        notes = scale.notes.enumerated().map { ScoredNote(index: $0.offset, target: $0.element) }
        currentIndex = nil
        countInBeat = nil
        leadInBeat = nil
        phase = .idle
    }

    // MARK: Transport

    func startStop() {
        switch phase {
        case .idle, .finished: Task { await start() }
        case .countIn, .leadIn, .playing: stop()
        }
    }

    func start() async {
        guard phase == .idle || phase == .finished else { return }
        rebuildNotes()
        captured.removeAll()
        audioTimeOrigin = nil
        lastSampleTime = 0

        guard await audio.requestPermission() else { phase = .idle; return }
        audio.pitchFrequencyRange = (instrument.pitchMinFrequency, instrument.pitchMaxFrequency)
        audio.onSample = { [weak self] sample in self?.ingest(sample) }
        do {
            try audio.start()
        } catch {
            phase = .idle
            return
        }
        runTask = Task { await run() }
    }

    func stop() {
        runTask?.cancel()
        runTask = nil
        audio.stop()
        audio.onSample = nil
        currentIndex = nil
        countInBeat = nil
        leadInBeat = nil
        if phase != .finished { phase = .idle }
    }

    /// Minimum YIN clarity to trust a window. The singing voice is less
    /// perfectly periodic than a clarinet (vibrato, breath), so it's a touch
    /// more lenient.
    private var minClarity: Double { instrument == .voice ? 0.78 : 0.85 }
    private let minRMS = 0.02

    private func ingest(_ sample: PitchSample) {
        // Track the audio clock for every window so the transport origin can be
        // anchored to "now" when playing begins, independent of what's voiced.
        lastSampleTime = sample.time
        // Demand a confident, loud-enough voiced window — otherwise silence and
        // faint metronome bleed get mistaken for (often very high) notes.
        guard let frequency = sample.frequency, sample.clarity > minClarity, sample.rms > minRMS else { return }
        captured.append(CapturedSample(
            audioTime: sample.time,
            writtenMidi: instrument.writtenMidi(forSoundingFrequency: frequency),
            frequency: frequency,
            clarity: sample.clarity,
            rms: sample.rms,
            brightness: sample.brightness,
            oddEvenRatio: sample.oddEvenRatio
        ))
    }

    private func run() async {
        let clock = ContinuousClock()
        let beat = 60.0 / tempo

        // One-bar count-in so the player can find the tempo.
        phase = .countIn
        let countStart = clock.now
        for b in 0..<countInBeats {
            try? await clock.sleep(until: countStart.advanced(by: .seconds(Double(b) * beat)))
            if Task.isCancelled { return }
            countInBeat = b + 1
            if metronomeOn {
                beatTick += 1
                if !metronomeSilent { audio.playClick(accent: b == 0) }
            }
        }
        try? await clock.sleep(until: countStart.advanced(by: .seconds(Double(countInBeats) * beat)))
        if Task.isCancelled { return }
        countInBeat = nil

        // One bar of rests, with the cursor stepping across the staff, so the
        // player settles into the tempo before the first note.
        phase = .leadIn
        let leadStart = clock.now
        for b in 0..<countInBeats {
            try? await clock.sleep(until: leadStart.advanced(by: .seconds(Double(b) * beat)))
            if Task.isCancelled { return }
            leadInBeat = b
            if metronomeOn {
                beatTick += 1
                if !metronomeSilent { audio.playClick(accent: b == 0) }
            }
        }
        try? await clock.sleep(until: leadStart.advanced(by: .seconds(Double(countInBeats) * beat)))
        if Task.isCancelled { return }
        leadInBeat = nil

        // Anchor the transport timeline to the audio clock at the instant the
        // first note begins: `lastSampleTime` is the newest analyzed window, so
        // a constant input latency cancels out and the per-note slots line up
        // regardless of the (silent) count-in and lead-in that preceded this.
        audioTimeOrigin = lastSampleTime
        phase = .playing
        let playStart = clock.now
        let spn = secondsPerNote

        for i in 0..<notes.count {
            try? await clock.sleep(until: playStart.advanced(by: .seconds(Double(i) * spn)))
            if Task.isCancelled { return }
            currentIndex = i
            if metronomeOn && isBeatBoundary(i) {
                beatTick += 1
                if !metronomeSilent { audio.playClick(accent: i == 0) }
            }
            if i > 0 { scoreNote(i - 1) }   // the note we just passed is complete
        }
        try? await clock.sleep(until: playStart.advanced(by: .seconds(Double(notes.count) * spn)))
        scoreNote(notes.count - 1)

        currentIndex = nil
        phase = .finished
        audio.stop()
        audio.onSample = nil
    }

    private func isBeatBoundary(_ index: Int) -> Bool {
        let beatsIn = Double(index) * noteValue.beats
        return abs(beatsIn.rounded() - beatsIn) < 0.001
    }

    // MARK: Scoring

    /// Classify the tempo accuracy and intonation of note `i` from the samples
    /// that fell in its time slot.
    private func scoreNote(_ i: Int) {
        guard notes.indices.contains(i), let origin = audioTimeOrigin else { return }
        let spn = secondsPerNote
        let center = Double(i) * spn

        func transport(_ s: CapturedSample) -> Double { s.audioTime - origin }

        let slot = captured.filter { s in
            let t = transport(s)
            return s.clarity > minClarity && s.rms > minRMS && t >= center - spn * 0.5 && t < center + spn * 0.5
        }
        // Treat too-few or unstable windows as "not played" (gray) rather than
        // inventing a note from noise or a stray detection.
        guard slot.count >= 2 else {
            notes[i].tempo = .notPlayed
            return
        }

        // Pitch from the stable middle of the note, avoiding onset transients
        // and any ring-over from the previous note.
        let core = slot.filter { let t = transport($0); return t >= center + spn * 0.12 && t <= center + spn * 0.6 }
        let pitchPool = core.isEmpty ? slot : core
        let median = medianWrittenMidi(pitchPool)

        // If the pitch never settles (windows disagree by more than a tone), the
        // player didn't sustain a real note here — mark it not played.
        let spread = (pitchPool.map(\.writtenMidi).max() ?? 0) - (pitchPool.map(\.writtenMidi).min() ?? 0)
        guard spread < 2.0 else {
            notes[i].tempo = .notPlayed
            return
        }

        let cents = (median - Double(notes[i].target.midi)) * 100

        // Onset = earliest sample whose pitch belongs to this note (not leftover).
        let belonging = slot.filter { abs($0.writtenMidi - median) < 1.5 }
        let onset = (belonging.isEmpty ? slot : belonging).map { transport($0) }.min() ?? center
        let error = abs(onset - center) / spn

        let tempo: TempoAccuracy
        switch error {
        case ..<Scoring.perfectTempo: tempo = .perfect
        case ..<Scoring.slightTempo: tempo = .slight
        case ..<Scoring.moderateTempo: tempo = .moderate
        default: tempo = .off
        }

        notes[i].tempo = tempo
        notes[i].centsOff = cents
        notes[i].playedWrittenMidi = median
    }

    private func medianWrittenMidi(_ samples: [CapturedSample]) -> Double {
        let sorted = samples.map(\.writtenMidi).sorted()
        guard !sorted.isEmpty else { return 0 }
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }
}
