import Foundation

// MARK: - Scoring thresholds

/// Tunable thresholds for turning raw measurements into feedback categories.
enum Scoring {
    /// Within this many cents of the target counts as "on pitch" (rainbow-eligible).
    static let onPitchCents = 18.0
    /// Timing error as a fraction of one note's duration.
    static let perfectTempo = 0.06
    static let slightTempo = 0.15
    static let moderateTempo = 0.30
}

// MARK: - Feedback categories

/// How close a note's onset was to its scheduled beat.
enum TempoAccuracy: Sendable {
    case notPlayed      // no onset detected in this slot
    case off            // far from the beat
    case moderate       // noticeably early/late
    case slight         // a hair off
    case perfect        // dead on
}

/// The visual treatment a notehead receives.
enum NoteHighlight: Sendable {
    case neutral        // not yet played
    case gray           // off tempo
    case yellow         // moderately off tempo
    case green          // close on tempo (or perfect tempo but imperfect pitch)
    case rainbow        // perfect tempo AND on pitch
}

// MARK: - Scored note

/// One note of the scale together with how the player performed it. Scoring
/// fills these in; the staff renderer reads the derived visual properties.
struct ScoredNote: Identifiable, Sendable {
    let index: Int
    let target: SpelledPitch
    var tempo: TempoAccuracy = .notPlayed
    /// Signed intonation error in cents, expressed in the *written* reference
    /// frame. Positive = sharp. nil until the note is evaluated.
    var centsOff: Double? = nil
    /// The fractional written MIDI the player actually produced for this slot.
    var playedWrittenMidi: Double? = nil

    var id: Int { index }

    var wasPlayed: Bool { tempo != .notPlayed }

    /// True when intonation is within tolerance of the target.
    var onPitch: Bool {
        guard let cents = centsOff else { return false }
        return abs(cents) <= Scoring.onPitchCents
    }

    var highlight: NoteHighlight {
        switch tempo {
        case .notPlayed: return .neutral
        case .off: return .gray
        case .moderate: return .yellow
        case .slight: return .green
        case .perfect: return onPitch ? .rainbow : .green
        }
    }

    /// When the player clearly played a *different* note (≥ ~one semitone away),
    /// the pitch to draw as a translucent "shadow" note, spelled with the
    /// accidental appropriate to the direction of the error.
    var shadowPitch: SpelledPitch? {
        guard let played = playedWrittenMidi, wasPlayed else { return nil }
        let rounded = Int(played.rounded())
        guard rounded != target.midi else { return nil }
        return SpelledPitch.nearestSpelling(forMidi: rounded, preferSharps: played > Double(target.midi))
    }

    /// Sub-semitone intonation error, expressed as a vertical nudge in staff
    /// steps (positive = sharp = move up). Only applies when the right note was
    /// played but slightly out of tune.
    var microShiftSteps: Double {
        guard shadowPitch == nil, let cents = centsOff, abs(cents) > Scoring.onPitchCents else { return 0 }
        return (cents / 100.0) * 0.5
    }
}

// MARK: - Chromatic spelling for played notes

extension SpelledPitch {
    private static let sharpTable: [(NoteLetter, Accidental)] = [
        (.c, .natural), (.c, .sharp), (.d, .natural), (.d, .sharp), (.e, .natural),
        (.f, .natural), (.f, .sharp), (.g, .natural), (.g, .sharp), (.a, .natural),
        (.a, .sharp), (.b, .natural),
    ]
    private static let flatTable: [(NoteLetter, Accidental)] = [
        (.c, .natural), (.d, .flat), (.d, .natural), (.e, .flat), (.e, .natural),
        (.f, .natural), (.g, .flat), (.g, .natural), (.a, .flat), (.a, .natural),
        (.b, .flat), (.b, .natural),
    ]

    /// Spell an absolute MIDI number, choosing sharps or flats by direction hint.
    static func nearestSpelling(forMidi midi: Int, preferSharps: Bool) -> SpelledPitch {
        let pitchClass = ((midi % 12) + 12) % 12
        let octave = midi / 12 - 1
        let (letter, accidental) = (preferSharps ? sharpTable : flatTable)[pitchClass]
        return SpelledPitch(letter: letter, accidental: accidental, octave: octave)
    }
}
