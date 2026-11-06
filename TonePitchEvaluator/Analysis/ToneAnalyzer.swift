import Foundation

// MARK: - Clarinet registers

/// The four acoustic registers of the B♭ clarinet, by *written* pitch. Each has
/// well-known intonation tendencies a teacher would listen for.
enum ClarinetRegister: String, Codable, CaseIterable, Sendable {
    case chalumeau = "Chalumeau"   // low, E3–F#4
    case throat = "Throat tones"   // G4–B♭4, notoriously stuffy/sharp
    case clarion = "Clarion"       // B4–C6
    case altissimo = "Altissimo"   // above C6, tends sharp

    static func of(writtenMidi midi: Int) -> ClarinetRegister {
        switch midi {
        case ..<67: return .chalumeau
        case 67...70: return .throat
        case 71...84: return .clarion
        default: return .altissimo
        }
    }
}

// MARK: - Report pieces

struct RegisterStat: Codable, Sendable {
    /// Register/zone name — clarinet acoustic register or voice range zone.
    let registerName: String
    let noteCount: Int
    let meanSignedCents: Double
}

struct ProblemNote: Codable, Sendable {
    let noteName: String          // written pitch, e.g. "A4"
    let occurrences: Int
    let meanSignedCents: Double   // + sharp, - flat
}

/// A playful, curated archetype used to ground the "guess the gear" feature.
/// Values are illustrative of each instrument family's timbre, not measured
/// from copyrighted recordings.
struct InstrumentProfile: Codable, Sendable {
    let name: String
    let character: String
    let brightness: Double
    let oddEvenRatio: Double
}

struct GearGuess: Codable, Sendable {
    let closestInstrument: String
    let instrumentCharacter: String
    let reedStrengthGuess: String   // e.g. "around 3 to 3.5"
    let confidence: Double          // 0...1 (low — this is for fun)
}

// MARK: - Tone report

/// The full objective analysis of one scale run. Codable so it can be serialized
/// straight into the Claude prompt, and also drives the on-screen summary.
struct ToneReport: Codable, Sendable {
    let instrument: InstrumentKind
    /// Locale region name for the voice singer match (empty for clarinet).
    let region: String

    let scaleName: String
    let tempoBPM: Int
    let noteValue: String

    let playedNoteCount: Int
    let missedNoteCount: Int
    let evaluatedNoteCount: Int

    // Intonation (cents, written reference; + = sharp).
    let meanAbsCents: Double
    let meanSignedCents: Double
    let centsStdDev: Double

    // Tempo.
    let onTempoPercent: Double          // perfect or slight
    let perfectNotePercent: Double      // rainbow notes

    // Tone.
    let meanClarity: Double             // periodicity / tonal focus
    let clarityStdDev: Double
    let meanBrightness: Double
    let meanOddEvenRatio: Double
    let dynamicSteadiness: Double       // 0...1

    let registerIntonation: [RegisterStat]
    let problemNotes: [ProblemNote]

    // Comparisons.
    let professionalCloseness: Double   // 0...1 blended score
    /// Clarinet-only playful gear inference (nil for voice).
    let gearGuess: GearGuess?
    /// Voice-only tone characterization (nil for clarinet).
    let voice: VoiceAnalysis?
}

// MARK: - Analyzer

enum ToneAnalyzer {
    /// Benchmarks a confident advanced/professional player would hit, used to
    /// scale the "how close to a pro" score.
    private enum Pro {
        static let meanAbsCents = 6.0
        static let centsStdDev = 8.0
        static let clarity = 0.95
        static let dynamicSteadiness = 0.9
        static let onTempo = 0.95
    }

    /// Curated instrument archetypes for the gear guess.
    static let profiles: [InstrumentProfile] = [
        InstrumentProfile(name: "Buffet R13 (French / orchestral)", character: "focused, singing, even", brightness: 3.0, oddEvenRatio: 5.5),
        InstrumentProfile(name: "Yamaha CSG / intermediate", character: "balanced and flexible", brightness: 3.2, oddEvenRatio: 4.0),
        InstrumentProfile(name: "Wurlitzer (German / Oehler)", character: "dark, round, broad", brightness: 2.6, oddEvenRatio: 6.5),
        InstrumentProfile(name: "Student plastic (Buffet B12 etc.)", character: "bright, edgy, direct", brightness: 3.7, oddEvenRatio: 3.3),
    ]

    static func analyze(session: PracticeSession) -> ToneReport? {
        let notes = session.notes
        guard notes.contains(where: { $0.wasPlayed }) else { return nil }

        let played = notes.filter { $0.wasPlayed }
        let missed = notes.filter { !$0.wasPlayed }

        // Ignore missed notes and anything "completely off" (likely a crack or
        // wrong note) from the intonation/tone judgment, per the spec.
        let evaluated = played.filter { note in
            guard let cents = note.centsOff else { return false }
            return abs(cents) <= 150
        }
        guard !evaluated.isEmpty else { return nil }

        let cents = evaluated.compactMap { $0.centsOff }
        let meanSigned = cents.reduce(0, +) / Double(cents.count)
        let meanAbs = cents.map(abs).reduce(0, +) / Double(cents.count)
        let centsStd = standardDeviation(cents, mean: meanSigned)

        let onTempo = Double(played.filter { $0.tempo == .perfect || $0.tempo == .slight }.count) / Double(played.count)
        let perfect = Double(played.filter { $0.highlight == .rainbow }.count) / Double(played.count)

        // Tone descriptors from voiced samples.
        let voiced = session.capturedSamples.filter { $0.clarity > 0.6 }
        let clarities = voiced.map(\.clarity)
        let meanClarity = mean(clarities)
        let brightnesses = voiced.compactMap(\.brightness)
        let oddEvens = voiced.compactMap(\.oddEvenRatio)
        let rmsValues = voiced.map(\.rms)
        let rmsMean = mean(rmsValues)
        let rmsCV = rmsMean > 0 ? standardDeviation(rmsValues, mean: rmsMean) / rmsMean : 1
        let dynamicSteadiness = max(0, min(1, 1 - rmsCV))

        let meanBrightness = brightnesses.isEmpty ? 0 : mean(brightnesses)
        let meanOddEven = oddEvens.isEmpty ? 0 : mean(oddEvens)

        // Instrument-specific characterization.
        let instrument = session.instrument
        let gearGuess: GearGuess?
        let voiceAnalysis: VoiceAnalysis?
        let region: String
        switch instrument {
        case .clarinet:
            gearGuess = guessGear(brightness: meanBrightness, oddEven: meanOddEven,
                                  clarity: meanClarity, steadiness: dynamicSteadiness)
            voiceAnalysis = nil
            region = ""
        case .voice:
            let profile = VoiceProfile.load()
            gearGuess = nil
            voiceAnalysis = VoiceAnalyzer.analyze(voiced: voiced, profile: profile,
                                                  meanClarity: meanClarity,
                                                  meanBrightness: meanBrightness,
                                                  dynamicSteadiness: dynamicSteadiness)
            region = profile?.regionName ?? (Locale.current.localizedString(forRegionCode: VoiceProfile.defaultRegionCode) ?? "")
        }

        let report = ToneReport(
            instrument: instrument,
            region: region,
            scaleName: session.scale.name,
            tempoBPM: Int(session.tempo.rounded()),
            noteValue: session.noteValue.rawValue,
            playedNoteCount: played.count,
            missedNoteCount: missed.count,
            evaluatedNoteCount: evaluated.count,
            meanAbsCents: meanAbs.rounded(to: 1),
            meanSignedCents: meanSigned.rounded(to: 1),
            centsStdDev: centsStd.rounded(to: 1),
            onTempoPercent: (onTempo * 100).rounded(to: 0),
            perfectNotePercent: (perfect * 100).rounded(to: 0),
            meanClarity: meanClarity.rounded(to: 2),
            clarityStdDev: standardDeviation(clarities, mean: meanClarity).rounded(to: 2),
            meanBrightness: meanBrightness.rounded(to: 2),
            meanOddEvenRatio: meanOddEven.rounded(to: 2),
            dynamicSteadiness: dynamicSteadiness.rounded(to: 2),
            registerIntonation: registerStats(evaluated, instrument: instrument),
            problemNotes: problemNotes(evaluated),
            professionalCloseness: closeness(meanAbs: meanAbs, centsStd: centsStd,
                                             clarity: meanClarity, steadiness: dynamicSteadiness,
                                             onTempo: onTempo).rounded(to: 2),
            gearGuess: gearGuess,
            voice: voiceAnalysis
        )
        return report
    }

    // MARK: Breakdowns

    private static func registerStats(_ notes: [ScoredNote], instrument: InstrumentKind) -> [RegisterStat] {
        // Group by register name, preserving first-seen (low → high) order.
        var order: [String] = []
        var groups: [String: [ScoredNote]] = [:]
        for note in notes.sorted(by: { $0.target.midi < $1.target.midi }) {
            let name = instrument.registerName(forWrittenMidi: note.target.midi)
            if groups[name] == nil { order.append(name) }
            groups[name, default: []].append(note)
        }
        return order.map { name in
            let members = groups[name] ?? []
            let signed = members.compactMap { $0.centsOff }
            return RegisterStat(registerName: name, noteCount: members.count,
                                meanSignedCents: mean(signed).rounded(to: 1))
        }
    }

    private static func problemNotes(_ notes: [ScoredNote]) -> [ProblemNote] {
        let groups = Dictionary(grouping: notes) { $0.target.name }
        return groups.compactMap { name, members -> ProblemNote? in
            let signed = members.compactMap { $0.centsOff }
            guard !signed.isEmpty else { return nil }
            let avg = mean(signed)
            guard abs(avg) > 18 else { return nil }   // only flag consistently-off notes
            return ProblemNote(noteName: name, occurrences: members.count, meanSignedCents: avg.rounded(to: 1))
        }
        .sorted { abs($0.meanSignedCents) > abs($1.meanSignedCents) }
    }

    // MARK: Comparisons

    private static func closeness(meanAbs: Double, centsStd: Double, clarity: Double,
                                  steadiness: Double, onTempo: Double) -> Double {
        func score(_ value: Double, target: Double, lowerIsBetter: Bool) -> Double {
            if lowerIsBetter {
                return max(0, min(1, target / max(value, 0.0001)))
            } else {
                return max(0, min(1, value / target))
            }
        }
        let intonation = score(meanAbs, target: Pro.meanAbsCents, lowerIsBetter: true)
        let spread = score(centsStd, target: Pro.centsStdDev, lowerIsBetter: true)
        let focus = score(clarity, target: Pro.clarity, lowerIsBetter: false)
        let dynamics = score(steadiness, target: Pro.dynamicSteadiness, lowerIsBetter: false)
        let timing = score(onTempo, target: Pro.onTempo, lowerIsBetter: false)
        return 0.3 * intonation + 0.2 * spread + 0.2 * focus + 0.15 * dynamics + 0.15 * timing
    }

    private static func guessGear(brightness: Double, oddEven: Double,
                                  clarity: Double, steadiness: Double) -> GearGuess {
        // Nearest curated instrument profile in (brightness, oddEven) space.
        let nearest = profiles.min { a, b in
            distance(brightness, oddEven, a) < distance(brightness, oddEven, b)
        } ?? profiles[0]

        // Softer reeds tend brighter and less stable; harder reeds darker, steadier.
        let reedScore = brightness * 0.6 + (1 - steadiness) * 1.5 - (clarity - 0.8)
        let reed: String
        switch reedScore {
        case ..<2.4: reed = "a harder reed (around 3.5–4) or a close-facing mouthpiece"
        case 2.4..<3.2: reed = "a medium reed (around 3 to 3.5)"
        default: reed = "a softer reed (around 2 to 2.5) or an open mouthpiece"
        }

        let confidence = max(0.2, min(0.6, 0.6 - distance(brightness, oddEven, nearest) / 10))
        return GearGuess(closestInstrument: nearest.name, instrumentCharacter: nearest.character,
                         reedStrengthGuess: reed, confidence: confidence.rounded(to: 2))
    }

    private static func distance(_ brightness: Double, _ oddEven: Double, _ profile: InstrumentProfile) -> Double {
        let db = brightness - profile.brightness
        let do_ = (oddEven - profile.oddEvenRatio) * 0.3
        return (db * db + do_ * do_).squareRoot()
    }

    // MARK: Math helpers

    private static func mean(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }

    private static func standardDeviation(_ values: [Double], mean m: Double) -> Double {
        guard values.count > 1 else { return 0 }
        let variance = values.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(values.count)
        return variance.squareRoot()
    }
}

private extension Double {
    func rounded(to places: Int) -> Double {
        let factor = pow(10.0, Double(places))
        return (self * factor).rounded() / factor
    }
}
