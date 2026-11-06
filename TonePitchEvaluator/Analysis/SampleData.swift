#if DEBUG
import Foundation

// Fabricated analysis/coaching data for SwiftUI previews and tests, so the
// results and coaching UI can be exercised without a microphone. Compiled only
// in DEBUG builds.

extension ToneReport {
    /// A plausible voice run: a singer slightly sharp up top, with a measured
    /// range and voice characterization.
    static let sampleVoice = ToneReport(
        instrument: .voice,
        region: "United States",
        scaleName: "B♭ Major",
        tempoBPM: 80,
        noteValue: "Eighth",
        playedNoteCount: 26,
        missedNoteCount: 3,
        evaluatedNoteCount: 24,
        meanAbsCents: 14.2,
        meanSignedCents: 6.5,
        centsStdDev: 11.3,
        onTempoPercent: 82,
        perfectNotePercent: 41,
        meanClarity: 0.88,
        clarityStdDev: 0.06,
        meanBrightness: 2.9,
        meanOddEvenRatio: 3.1,
        dynamicSteadiness: 0.74,
        registerIntonation: [
            RegisterStat(registerName: "Lower-middle", noteCount: 8, meanSignedCents: -3.2),
            RegisterStat(registerName: "Upper-middle", noteCount: 10, meanSignedCents: 7.1),
            RegisterStat(registerName: "High", noteCount: 6, meanSignedCents: 18.4),
        ],
        problemNotes: [
            ProblemNote(noteName: "F5", occurrences: 3, meanSignedCents: 22.0),
            ProblemNote(noteName: "E♭5", occurrences: 2, meanSignedCents: -19.5),
        ],
        professionalCloseness: 0.62,
        gearGuess: nil,
        voice: VoiceAnalysis(
            voiceType: "Tenor",
            rangeLowName: "C3",
            rangeHighName: "A4",
            rangeSemitones: 21,
            vibratoRateHz: 5.4,
            vibratoExtentCents: 38,
            breathiness: 0.31,
            brightness: 2.9,
            warmth: 0.68,
            dynamicSteadiness: 0.74,
            meanClarity: 0.88
        )
    )

    /// A plausible clarinet run, for the original gear-guess path.
    static let sampleClarinet = ToneReport(
        instrument: .clarinet,
        region: "",
        scaleName: "B♭ Major",
        tempoBPM: 92,
        noteValue: "Eighth",
        playedNoteCount: 29,
        missedNoteCount: 0,
        evaluatedNoteCount: 28,
        meanAbsCents: 8.1,
        meanSignedCents: 3.0,
        centsStdDev: 9.4,
        onTempoPercent: 90,
        perfectNotePercent: 55,
        meanClarity: 0.94,
        clarityStdDev: 0.04,
        meanBrightness: 3.1,
        meanOddEvenRatio: 5.2,
        dynamicSteadiness: 0.86,
        registerIntonation: [
            RegisterStat(registerName: "Chalumeau", noteCount: 10, meanSignedCents: -2.0),
            RegisterStat(registerName: "Throat tones", noteCount: 4, meanSignedCents: 15.0),
            RegisterStat(registerName: "Clarion", noteCount: 14, meanSignedCents: 4.0),
        ],
        problemNotes: [
            ProblemNote(noteName: "A4", occurrences: 2, meanSignedCents: 21.0),
        ],
        professionalCloseness: 0.78,
        gearGuess: GearGuess(
            closestInstrument: "Buffet R13 (French / orchestral)",
            instrumentCharacter: "focused, singing, even",
            reedStrengthGuess: "a medium reed (around 3 to 3.5)",
            confidence: 0.45
        ),
        voice: nil
    )
}

extension CoachingFeedback {
    static let sampleVoice = CoachingFeedback(
        headline: "A warm, promising tenor with a touch of sharpness up high.",
        summary: "Solid through the middle; add air support up top where you creep sharp.",
        positives: ["Steady lower-middle intonation", "Pleasant, warm tone"],
        issues: [
            Tip(area: "Breath support", tip: "Engage more air on the top notes to stop them creeping sharp."),
            Tip(area: "Passaggio", tip: "Ease the weight off as you cross into the upper-middle to keep the tone free."),
        ],
        problemNoteComment: "F5 ran about 22¢ sharp — a common squeeze point; relax the jaw and keep the vowel open.",
        clarinetGuess: nil,
        reedGuess: nil,
        voiceType: "Your range and tessitura read as a tenor.",
        rangeComment: "A solid ~21-semitone range from C3 to A4; comfortable through the middle.",
        singerMatch: "A playful match: your range is reminiscent of a lyric tenor in the vein of a well-known pop-tenor from your region.",
        styleComparison: "Leans lyrical rather than belty.",
        encouragement: "Lovely instrument — a little air support and the top will bloom.",
        references: []
    )

    static let sampleClarinet = CoachingFeedback(
        headline: "Clean, even playing that's close to the pro benchmark.",
        summary: "Strong, focused tone; the main fix is taming sharp throat tones.",
        positives: ["Excellent tonal focus", "Very steady dynamics"],
        issues: [Tip(area: "Throat tones", tip: "A4/B♭4 run sharp — try a lighter voicing and open throat.")],
        problemNoteComment: "A4 averaged about 21¢ sharp — typical throat-tone tendency.",
        clarinetGuess: "Sounds like a focused French-style setup.",
        reedGuess: "Probably a medium reed around 3 to 3.5.",
        voiceType: nil,
        rangeComment: nil,
        singerMatch: nil,
        styleComparison: "Orchestral, singing line.",
        encouragement: "Really polished — keep after those throat tones!",
        references: []
    )
}
#endif
