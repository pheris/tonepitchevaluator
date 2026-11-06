import Foundation

// MARK: - Note letters & accidentals

/// A letter name on the musical staff. The raw value doubles as the diatonic
/// step index within an octave (C = 0 ... B = 6), which drives vertical layout.
enum NoteLetter: Int, CaseIterable, Sendable {
    case c = 0, d, e, f, g, a, b

    /// Semitone offset of the natural pitch above C within one octave.
    var semitone: Int { [0, 2, 4, 5, 7, 9, 11][rawValue] }
    var name: String { ["C", "D", "E", "F", "G", "A", "B"][rawValue] }
}

/// A chromatic alteration applied to a letter. Raw value is the semitone offset.
enum Accidental: Int, Sendable {
    case doubleFlat = -2, flat = -1, natural = 0, sharp = 1, doubleSharp = 2

    /// Glyph drawn to the left of a notehead. Natural renders as empty by
    /// default because scales show accidentals only where a letter is altered.
    var symbol: String {
        switch self {
        case .doubleFlat: return "\u{1D12B}"   // 𝄫
        case .flat: return "\u{266D}"           // ♭
        case .natural: return ""
        case .sharp: return "\u{266F}"          // ♯
        case .doubleSharp: return "\u{1D12A}"   // 𝄪
        }
    }

    /// Explicit glyph including a natural sign, used for shadow (played) notes.
    var explicitSymbol: String {
        self == .natural ? "\u{266E}" : symbol   // ♮
    }
}

// MARK: - Spelled pitch

/// A fully spelled pitch: a letter, an accidental, and a scientific-notation
/// octave (middle C = C4). Spelling is preserved so the staff can draw the
/// correct line/space and the correct sharp/flat, independent of MIDI number.
struct SpelledPitch: Equatable, Hashable, Sendable {
    var letter: NoteLetter
    var accidental: Accidental
    var octave: Int

    /// MIDI note number. C4 = 60, A4 = 69.
    var midi: Int { (octave + 1) * 12 + letter.semitone + accidental.rawValue }

    /// Equal-tempered frequency in Hz.
    var frequency: Double { Pitch.frequency(forMidi: Double(midi)) }

    /// Absolute diatonic staff position (C4 = 28). Each unit is one line-or-space
    /// step. Differences between two pitches give their vertical offset on a staff.
    var diatonicStep: Int { octave * 7 + letter.rawValue }

    /// Human-readable name, e.g. "B♭4".
    var name: String { "\(letter.name)\(accidental.symbol)\(octave)" }

    /// Build a spelled pitch for a target MIDI number on a chosen letter/octave,
    /// deriving the accidental needed to reach that MIDI. Returns nil if the
    /// required accidental exceeds a double sharp/flat.
    static func spelled(letter: NoteLetter, octave: Int, targetMidi: Int) -> SpelledPitch? {
        let naturalMidi = (octave + 1) * 12 + letter.semitone
        guard let accidental = Accidental(rawValue: targetMidi - naturalMidi) else { return nil }
        return SpelledPitch(letter: letter, accidental: accidental, octave: octave)
    }
}

// MARK: - Equal temperament & cents

enum Pitch {
    /// A4 reference. Clarinet tuning is commonly A=442 in orchestras, but 440 is
    /// the neutral default for a practice tool.
    static let referenceA = 440.0

    static func frequency(forMidi midi: Double) -> Double {
        referenceA * pow(2.0, (midi - 69.0) / 12.0)
    }

    static func midi(forFrequency frequency: Double) -> Double {
        69.0 + 12.0 * log2(frequency / referenceA)
    }

    /// Signed cents of `frequency` relative to the equal-tempered `targetMidi`.
    /// Positive = sharp, negative = flat. 100 cents = one semitone.
    static func cents(ofFrequency frequency: Double, relativeToMidi targetMidi: Double) -> Double {
        (midi(forFrequency: frequency) - targetMidi) * 100.0
    }
}

// MARK: - Clarinet transposition & range

/// The B♭ soprano clarinet is a transposing instrument: written pitch sounds a
/// major second (2 semitones) lower than concert pitch. All on-screen notation
/// is *written*; all microphone analysis is *sounding*, so we convert between
/// the two whenever comparing the player to the score.
enum Clarinet {
    /// Written minus sounding, in semitones. Written C sounds concert B♭.
    static let transposition = 2

    /// Lowest written note: E3 (sounds concert D3).
    static let lowestWrittenMidi = 52
    /// Practical top of the written range for scale study (~C7 altissimo).
    static let highestWrittenMidi = 96

    static func soundingMidi(forWrittenMidi written: Int) -> Int { written - transposition }
    static func soundingFrequency(forWritten pitch: SpelledPitch) -> Double {
        Pitch.frequency(forMidi: Double(pitch.midi - transposition))
    }

    /// Convert a sounding frequency captured from the mic into the equivalent
    /// *written* MIDI (fractional) the player is reading.
    static func writtenMidi(forSoundingFrequency frequency: Double) -> Double {
        Pitch.midi(forFrequency: frequency) + Double(transposition)
    }
}
