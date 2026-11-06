import Foundation

// MARK: - Scale quality

/// The scale flavors a clarinetist practices. Melodic minor is the only one
/// that differs ascending vs. descending (raised 6/7 up, natural down).
enum ScaleQuality: String, CaseIterable, Identifiable, Sendable {
    case major = "Major"
    case naturalMinor = "Natural Minor"
    case harmonicMinor = "Harmonic Minor"
    case melodicMinor = "Melodic Minor"

    var id: String { rawValue }
    var shortName: String {
        switch self {
        case .major: return "maj"
        case .naturalMinor: return "min"
        case .harmonicMinor: return "harm"
        case .melodicMinor: return "mel"
        }
    }

    /// Cumulative semitones for degrees 1–7 (index 0–6) when ascending.
    var ascendingSemitones: [Int] {
        switch self {
        case .major: return [0, 2, 4, 5, 7, 9, 11]
        case .naturalMinor: return [0, 2, 3, 5, 7, 8, 10]
        case .harmonicMinor: return [0, 2, 3, 5, 7, 8, 11]
        case .melodicMinor: return [0, 2, 3, 5, 7, 9, 11]
        }
    }

    /// Cumulative semitones when descending. Melodic minor reverts to natural.
    var descendingSemitones: [Int] {
        switch self {
        case .melodicMinor: return [0, 2, 3, 5, 7, 8, 10]
        default: return ascendingSemitones
        }
    }
}

// MARK: - Tonic choices

/// A tonic spelling for a scale. Two curated lists keep every key within the
/// conventional ≤7-accidental signatures with no double accidentals: the major
/// list spells the black keys as D♭/A♭ etc., while the minor list uses the
/// spellings minor keys conventionally take (C♯ minor, not D♭ minor; G♯ minor,
/// not A♭ minor).
struct Tonic: Identifiable, Hashable, Sendable {
    var letter: NoteLetter
    var accidental: Accidental
    var id: String { "\(letter.name)\(accidental.rawValue)" }
    var name: String { "\(letter.name)\(accidental.symbol)" }

    /// 0–11 pitch class, used to keep the selection on the same key when the
    /// mode changes between the major and minor spelling lists.
    var pitchClass: Int { (((letter.semitone + accidental.rawValue) % 12) + 12) % 12 }

    /// Conventional tonic spellings for major keys (C, D♭, D, E♭, …).
    static let major: [Tonic] = [
        Tonic(letter: .c, accidental: .natural),
        Tonic(letter: .d, accidental: .flat),
        Tonic(letter: .d, accidental: .natural),
        Tonic(letter: .e, accidental: .flat),
        Tonic(letter: .e, accidental: .natural),
        Tonic(letter: .f, accidental: .natural),
        Tonic(letter: .f, accidental: .sharp),
        Tonic(letter: .g, accidental: .natural),
        Tonic(letter: .a, accidental: .flat),
        Tonic(letter: .a, accidental: .natural),
        Tonic(letter: .b, accidental: .flat),
        Tonic(letter: .b, accidental: .natural),
    ]

    /// Conventional tonic spellings for minor keys (C♯ minor over D♭ minor,
    /// G♯ minor over A♭ minor — both keep the signature to five accidentals).
    static let minor: [Tonic] = [
        Tonic(letter: .c, accidental: .natural),
        Tonic(letter: .c, accidental: .sharp),
        Tonic(letter: .d, accidental: .natural),
        Tonic(letter: .e, accidental: .flat),
        Tonic(letter: .e, accidental: .natural),
        Tonic(letter: .f, accidental: .natural),
        Tonic(letter: .f, accidental: .sharp),
        Tonic(letter: .g, accidental: .natural),
        Tonic(letter: .g, accidental: .sharp),
        Tonic(letter: .a, accidental: .natural),
        Tonic(letter: .b, accidental: .flat),
        Tonic(letter: .b, accidental: .natural),
    ]

    /// The tonic in `list` sharing a pitch class with `self`, falling back to the
    /// original if none matches.
    func mapped(into list: [Tonic]) -> Tonic {
        list.first { $0.pitchClass == pitchClass } ?? self
    }

    static func options(forMinor isMinor: Bool) -> [Tonic] { isMinor ? minor : major }
}

// MARK: - Scale

/// A concrete two-octave scale, ascending then descending, spelled as *written*
/// pitches for a B♭ clarinet and starting on the lowest tonic that fits the
/// written range.
struct Scale: Identifiable, Sendable {
    var tonic: Tonic
    var quality: ScaleQuality
    var instrument: InstrumentKind
    var notes: [SpelledPitch]

    var id: String { "\(tonic.id)-\(quality.id)-\(instrument.id)" }
    var name: String { "\(tonic.name) \(quality.rawValue)" }

    /// How many octaves the scale spans (1 or 2). Voice scales shrink to one
    /// octave when two won't fit the singer's measured range.
    private(set) var octaves: Int = 2

    init(tonic: Tonic, quality: ScaleQuality, instrument: InstrumentKind = .clarinet,
         range: ClosedRange<Int>? = nil) {
        self.tonic = tonic
        self.quality = quality
        self.instrument = instrument
        let placement = Scale.placement(tonic: tonic, instrument: instrument, range: range)
        self.octaves = placement.octaves
        self.notes = Scale.build(tonic: tonic, quality: quality,
                                 baseOctave: placement.baseOctave, octaves: placement.octaves)
    }

    private static func tonicMidi(_ tonic: Tonic, octave: Int) -> Int {
        (octave + 1) * 12 + tonic.letter.semitone + tonic.accidental.rawValue
    }

    /// Choose the starting octave and octave count. With no range (clarinet, or
    /// voice before range-finding) it's the usual two octaves from the lowest
    /// tonic in the instrument's range. With a measured vocal range it picks the
    /// best-centered placement that fits, preferring two octaves, then one, then
    /// a best-effort one-octave fallback.
    private static func placement(tonic: Tonic, instrument: InstrumentKind,
                                  range: ClosedRange<Int>?) -> (baseOctave: Int, octaves: Int) {
        guard let range else {
            return (lowestTonicOctave(for: tonic, instrument: instrument), 2)
        }
        let low = range.lowerBound, high = range.upperBound
        let rangeMid = (low + high) / 2
        for octaves in [2, 1] {
            let span = 12 * octaves
            var best: Int?
            var bestScore = Int.max
            for octave in 1...7 {
                let t = tonicMidi(tonic, octave: octave)
                guard t >= low, t + span <= high else { continue }
                let score = abs((t + span / 2) - rangeMid)
                if score < bestScore { bestScore = score; best = octave }
            }
            if let best { return (best, octaves) }
        }
        // Range narrower than an octave: start at the lowest tonic at or above
        // the singer's floor so at least the bottom of the scale is reachable.
        for octave in 1...7 where tonicMidi(tonic, octave: octave) >= max(low, instrument.lowestWrittenMidi) {
            return (octave, 1)
        }
        return (lowestTonicOctave(for: tonic, instrument: instrument), 1)
    }

    /// The lowest octave at which this tonic sits within the instrument's
    /// written range.
    private static func lowestTonicOctave(for tonic: Tonic, instrument: InstrumentKind) -> Int {
        for octave in 2...6 {
            let midi = (octave + 1) * 12 + tonic.letter.semitone + tonic.accidental.rawValue
            if midi >= instrument.lowestWrittenMidi { return octave }
        }
        return 3
    }

    /// Spell one scale degree. `degree` counts letters above the tonic (0 = tonic,
    /// 7 = octave, 14 = two octaves); `semitonesInOctave` is the 7-element pattern
    /// to use for this direction.
    private static func pitch(forDegree degree: Int,
                              tonic: Tonic,
                              baseOctave: Int,
                              semitonesInOctave: [Int]) -> SpelledPitch {
        let tonicMidi = (baseOctave + 1) * 12 + tonic.letter.semitone + tonic.accidental.rawValue
        let letterRaw = tonic.letter.rawValue + degree
        let letter = NoteLetter(rawValue: letterRaw % 7)!
        let octave = baseOctave + letterRaw / 7
        let targetMidi = tonicMidi + semitonesInOctave[degree % 7] + 12 * (degree / 7)
        // Fall back to a derived accidental; spelling stays within ±2 for the
        // supported keys so the force unwrap below is safe in practice.
        return SpelledPitch.spelled(letter: letter, octave: octave, targetMidi: targetMidi)
            ?? SpelledPitch(letter: letter, accidental: .natural, octave: octave)
    }

    private static func build(tonic: Tonic, quality: ScaleQuality,
                              baseOctave: Int, octaves: Int) -> [SpelledPitch] {
        var result: [SpelledPitch] = []
        let top = 7 * octaves   // top tonic: degree 7 (one octave) or 14 (two)

        // Ascending: tonic (degree 0) up to the top tonic.
        for degree in 0...top {
            result.append(pitch(forDegree: degree,
                                 tonic: tonic,
                                 baseOctave: baseOctave,
                                 semitonesInOctave: quality.ascendingSemitones))
        }
        // Descending: from one below the top back to the tonic.
        for degree in stride(from: top - 1, through: 0, by: -1) {
            result.append(pitch(forDegree: degree,
                                 tonic: tonic,
                                 baseOctave: baseOctave,
                                 semitonesInOctave: quality.descendingSemitones))
        }
        return result
    }
}
