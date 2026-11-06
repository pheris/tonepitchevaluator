import Foundation

/// The instruments the trainer supports. This abstracts the handful of places
/// that used to assume a B♭ clarinet (transposition, range, pitch-tracker
/// bounds, acoustic registers) so the capture/scoring pipeline can serve either
/// a clarinet or the singing voice. Voice is a concert-pitch instrument, so its
/// written and sounding pitch coincide.
enum InstrumentKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case clarinet = "Clarinet"
    case voice = "Voice"

    var id: String { rawValue }

    /// Written minus sounding, in semitones. The clarinet transposes down a
    /// major second; the voice reads and sounds the same pitch.
    var transposition: Int {
        switch self {
        case .clarinet: return Clarinet.transposition
        case .voice: return 0
        }
    }

    /// Lowest written note used when choosing the starting octave for a scale.
    var lowestWrittenMidi: Int {
        switch self {
        case .clarinet: return Clarinet.lowestWrittenMidi   // E3
        case .voice: return 48                               // C3
        }
    }

    /// Practical top of the written range for scale study.
    var highestWrittenMidi: Int {
        switch self {
        case .clarinet: return Clarinet.highestWrittenMidi   // ~C7
        case .voice: return 84                               // C6
        }
    }

    /// Fundamental-frequency search bounds for the YIN tracker. The voice runs
    /// lower than the clarinet (basses reach down near E2 ≈ 82 Hz) and doesn't
    /// need the altissimo ceiling.
    var pitchMinFrequency: Double {
        switch self {
        case .clarinet: return 110
        case .voice: return 70
        }
    }
    var pitchMaxFrequency: Double {
        switch self {
        case .clarinet: return 2600
        case .voice: return 1200
        }
    }

    var soundsAtConcertPitch: Bool { transposition == 0 }

    func soundingMidi(forWrittenMidi written: Int) -> Int { written - transposition }

    /// Convert a sounding frequency captured from the mic into the equivalent
    /// *written* MIDI (fractional) the player reads from the staff. For voice
    /// this is just the concert MIDI.
    func writtenMidi(forSoundingFrequency frequency: Double) -> Double {
        Pitch.midi(forFrequency: frequency) + Double(transposition)
    }

    /// Human-readable register/zone name for a written MIDI note, used to group
    /// intonation tendencies in the report.
    func registerName(forWrittenMidi midi: Int) -> String {
        switch self {
        case .clarinet:
            return ClarinetRegister.of(writtenMidi: midi).rawValue
        case .voice:
            // Written == concert for the voice.
            switch midi {
            case ..<52: return "Low"             // below E3
            case 52..<60: return "Lower-middle"  // E3–B3
            case 60..<72: return "Upper-middle"  // C4–B4
            default: return "High"               // C5 and up
            }
        }
    }
}
