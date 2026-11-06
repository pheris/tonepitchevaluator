import Foundation

// MARK: - Voice type

/// The classic voice classifications, ordered low → high. Classification here is
/// a rough tessitura guess from a measured range midpoint, not a studio audition.
enum VoiceType: String, Codable, CaseIterable, Sendable {
    case bass = "Bass"
    case baritone = "Baritone"
    case tenor = "Tenor"
    case alto = "Alto"
    case mezzo = "Mezzo-soprano"
    case soprano = "Soprano"

    /// Classify from the lowest and highest sung concert MIDI notes by the
    /// midpoint of the range against conventional voice-type centers.
    static func classify(lowMidi: Int, highMidi: Int) -> VoiceType {
        let mid = Double(lowMidi + highMidi) / 2
        switch mid {
        case ..<54: return .bass          // center below ~F#3
        case 54..<58: return .baritone
        case 58..<63: return .tenor
        case 63..<67: return .alto
        case 67..<71: return .mezzo
        default: return .soprano          // center C5 and up
        }
    }
}

// MARK: - Voice profile

/// The singer's measured range and chosen locale, persisted in `UserDefaults`
/// by the range-finder and read back by the analyzer and the singer match.
struct VoiceProfile: Codable, Equatable, Sendable {
    var lowMidi: Int
    var highMidi: Int
    /// A locale region identifier (e.g. "US", "GB"), defaulting to the system
    /// region. Overridable in settings.
    var regionCode: String

    enum Keys {
        static let low = "voiceLowMidi"
        static let high = "voiceHighMidi"
        static let region = "voiceRegionCode"
    }

    var voiceType: VoiceType { VoiceType.classify(lowMidi: lowMidi, highMidi: highMidi) }
    var rangeSemitones: Int { max(0, highMidi - lowMidi) }
    var lowName: String { SpelledPitch.nearestSpelling(forMidi: lowMidi, preferSharps: false).name }
    var highName: String { SpelledPitch.nearestSpelling(forMidi: highMidi, preferSharps: false).name }

    /// A human-readable region name for display and for the Claude prompt.
    var regionName: String {
        Locale.current.localizedString(forRegionCode: regionCode) ?? regionCode
    }

    /// The region to default to from the current system locale.
    static var defaultRegionCode: String {
        Locale.current.region?.identifier ?? "US"
    }

    /// Load a measured profile from `UserDefaults`, or nil if the range has not
    /// been measured yet.
    static func load(from defaults: UserDefaults = .standard) -> VoiceProfile? {
        let low = defaults.integer(forKey: Keys.low)
        let high = defaults.integer(forKey: Keys.high)
        guard low > 0, high > low else { return nil }
        let region = defaults.string(forKey: Keys.region) ?? defaultRegionCode
        return VoiceProfile(lowMidi: low, highMidi: high, regionCode: region)
    }
}
