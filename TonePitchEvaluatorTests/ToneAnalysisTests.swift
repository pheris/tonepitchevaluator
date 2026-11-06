import Testing
import Foundation
@testable import TonePitchEvaluator

/// Behavior-focused tests for the music-theory and analysis layer. These feed
/// synthesized inputs and assert on observable outcomes (spellings, highlights,
/// classifications, filtering) rather than on hard-coded constants.
@MainActor
struct ToneAnalysisTests {

    // MARK: Transposition (round-trip behavior, not a constant check)

    @Test func soundingAndWrittenAreInverses() {
        for inst in [InstrumentKind.clarinet, .voice] {
            for written in [52, 60, 71, 84] {
                let soundingFreq = Pitch.frequency(forMidi: Double(inst.soundingMidi(forWrittenMidi: written)))
                let roundTrip = inst.writtenMidi(forSoundingFrequency: soundingFreq)
                #expect(abs(roundTrip - Double(written)) < 0.001)
            }
        }
    }

    @Test func clarinetWrittenSoundsAMajorSecondLower() {
        // Behavior: the same written note sounds lower on clarinet than voice.
        let written = 72
        let clarinetSounding = InstrumentKind.clarinet.soundingMidi(forWrittenMidi: written)
        let voiceSounding = InstrumentKind.voice.soundingMidi(forWrittenMidi: written)
        #expect(voiceSounding - clarinetSounding == 2)
    }

    // MARK: Cents

    @Test func centsTrackPitchDirection() {
        #expect(abs(Pitch.cents(ofFrequency: 440, relativeToMidi: 69)) < 0.001)
        #expect(Pitch.cents(ofFrequency: 466.16, relativeToMidi: 69) > 90)   // ~+1 semitone
        #expect(Pitch.cents(ofFrequency: 415.30, relativeToMidi: 69) < -90)  // ~-1 semitone
    }

    // MARK: Scale spelling

    @Test func cMajorScaleIsAllNaturals() {
        let scale = Scale(tonic: Tonic(letter: .c, accidental: .natural), quality: .major)
        let firstOctave = Array(scale.notes.prefix(8))
        #expect(firstOctave.map(\.letter.name) == ["C", "D", "E", "F", "G", "A", "B", "C"])
        #expect(firstOctave.allSatisfy { $0.accidental == .natural })
    }

    @Test func bFlatMajorSpellsFlatsNotSharps() {
        let scale = Scale(tonic: Tonic(letter: .b, accidental: .flat), quality: .major)
        #expect(scale.notes.contains { $0.letter == .b && $0.accidental == .flat })
        #expect(scale.notes.contains { $0.letter == .e && $0.accidental == .flat })
        #expect(!scale.notes.contains { $0.accidental == .sharp })
    }

    @Test func harmonicMinorRaisesTheSeventh() {
        // A harmonic minor should contain G♯ (raised 7th), not G♮.
        let scale = Scale(tonic: Tonic(letter: .a, accidental: .natural), quality: .harmonicMinor)
        #expect(scale.notes.contains { $0.letter == .g && $0.accidental == .sharp })
    }

    @Test func scaleGoesUpThenBackDown() {
        let scale = Scale(tonic: Tonic(letter: .c, accidental: .natural), quality: .major)
        let midis = scale.notes.map(\.midi)
        #expect(midis.first == midis.last)                 // starts and ends on the tonic
        #expect(midis.max() == midis[midis.count / 2])     // peak in the middle
    }

    // MARK: Key signatures

    @Test func keySignaturesMatchTheCircleOfFifths() {
        func sig(_ letter: NoteLetter, _ acc: Accidental, minor: Bool = false) -> KeySignature {
            KeySignature.forTonic(Tonic(letter: letter, accidental: acc), isMinor: minor)
        }
        #expect(sig(.c, .natural).kind == .none)
        #expect(sig(.c, .natural).elements.isEmpty)

        let g = sig(.g, .natural)
        #expect(g.kind == .sharps)
        #expect(g.elements.map(\.letter) == [.f])

        let d = sig(.d, .natural)
        #expect(d.elements.map(\.letter) == [.f, .c])

        let f = sig(.f, .natural)
        #expect(f.kind == .flats)
        #expect(f.elements.map(\.letter) == [.b])
    }

    // MARK: Scored-note feedback behavior

    @Test func highlightReflectsTempoAndPitch() {
        var note = ScoredNote(index: 0, target: SpelledPitch(letter: .c, accidental: .natural, octave: 4))

        note.tempo = .notPlayed
        #expect(note.highlight == .neutral)
        #expect(note.wasPlayed == false)

        note.tempo = .perfect; note.centsOff = 5
        #expect(note.onPitch)
        #expect(note.highlight == .rainbow)        // perfect + in tune

        note.centsOff = 45
        #expect(!note.onPitch)
        #expect(note.highlight == .green)          // perfect tempo, out of tune

        note.tempo = .moderate
        #expect(note.highlight == .yellow)
        note.tempo = .off
        #expect(note.highlight == .gray)
    }

    @Test func shadowNoteOnlyForAWrongNote() {
        var note = ScoredNote(index: 0, target: SpelledPitch(letter: .c, accidental: .natural, octave: 4)) // midi 60
        note.tempo = .perfect

        note.playedWrittenMidi = 60.1          // essentially the same note
        #expect(note.shadowPitch == nil)

        note.playedWrittenMidi = 62            // a whole step off → a different note
        #expect(note.shadowPitch != nil)
        #expect(note.shadowPitch?.midi == 62)
    }

    // MARK: Register classification

    @Test func clarinetRegistersByWrittenPitch() {
        let c = InstrumentKind.clarinet
        #expect(c.registerName(forWrittenMidi: 60) == "Chalumeau")
        #expect(c.registerName(forWrittenMidi: 68) == "Throat tones")
        #expect(c.registerName(forWrittenMidi: 76) == "Clarion")
        #expect(c.registerName(forWrittenMidi: 90) == "Altissimo")
    }

    @Test func voiceZonesByPitch() {
        let v = InstrumentKind.voice
        #expect(v.registerName(forWrittenMidi: 48) == "Low")
        #expect(v.registerName(forWrittenMidi: 55) == "Lower-middle")
        #expect(v.registerName(forWrittenMidi: 65) == "Upper-middle")
        #expect(v.registerName(forWrittenMidi: 75) == "High")
    }

    // MARK: Voice type + range-fitting

    @Test func voiceTypeFollowsRangeCenter() {
        #expect(VoiceType.classify(lowMidi: 40, highMidi: 64) == .bass)
        #expect(VoiceType.classify(lowMidi: 48, highMidi: 72) == .tenor)
        #expect(VoiceType.classify(lowMidi: 60, highMidi: 84) == .soprano)
        // A higher range should never classify lower than a lower range.
        let low = VoiceType.classify(lowMidi: 40, highMidi: 60)
        let high = VoiceType.classify(lowMidi: 60, highMidi: 84)
        #expect(VoiceType.allCases.firstIndex(of: low)! < VoiceType.allCases.firstIndex(of: high)!)
    }

    @Test func voiceScaleFitsMeasuredRange() {
        // Narrow baritone range → one octave, entirely inside the range.
        let bari = Scale(tonic: Tonic(letter: .b, accidental: .flat), quality: .major,
                         instrument: .voice, range: 45...69)
        #expect(bari.octaves == 1)
        #expect(bari.notes.allSatisfy { 45...69 ~= $0.midi })

        // A two-octave-wide range keeps two octaves.
        let wide = Scale(tonic: Tonic(letter: .c, accidental: .natural), quality: .major,
                         instrument: .voice, range: 60...84)
        #expect(wide.octaves == 2)

        // Clarinet (no range) is always the full two octaves.
        let clar = Scale(tonic: Tonic(letter: .b, accidental: .flat), quality: .major)
        #expect(clar.octaves == 2)
        #expect(clar.notes.count == 29)
    }

    // MARK: Voice analysis

    @Test func vibratoRecoveredFromOscillatingTrack() {
        let samples = syntheticTrack(centerMidi: 69, vibratoHz: 5.5, extentCents: 40, count: 120)
        let analysis = VoiceAnalyzer.analyze(voiced: samples, profile: nil,
            meanClarity: 0.9, meanBrightness: 2.8, dynamicSteadiness: 0.8)
        #expect(4...7 ~= analysis.vibratoRateHz)
        #expect(analysis.vibratoExtentCents > 20)
    }

    @Test func steadyToneReportsNoVibrato() {
        let samples = syntheticTrack(centerMidi: 69, vibratoHz: 0, extentCents: 0, count: 120)
        let analysis = VoiceAnalyzer.analyze(voiced: samples, profile: nil,
            meanClarity: 0.95, meanBrightness: 2.5, dynamicSteadiness: 0.9)
        #expect(analysis.vibratoRateHz == 0)
    }

    @Test func breathinessRisesAsClarityFalls() {
        let clear = VoiceAnalyzer.analyze(voiced: [], profile: nil, meanClarity: 0.97,
                                          meanBrightness: 2.5, dynamicSteadiness: 0.9)
        let breathy = VoiceAnalyzer.analyze(voiced: [], profile: nil, meanClarity: 0.75,
                                            meanBrightness: 2.5, dynamicSteadiness: 0.9)
        #expect(breathy.breathiness > clear.breathiness)
    }

    // MARK: Reference link safety (the empty-YouTube-channel fix)

    @Test func channelAndHandleLinksAreFiltered() {
        let feedback = makeFeedback(references: [
            .init(title: "Channel", url: "https://www.youtube.com/user/tomridenour"),
            .init(title: "Handle", url: "https://www.youtube.com/@someteacher"),
            .init(title: "Watch", url: "https://www.youtube.com/watch?v=abc123"),
            .init(title: "Short link", url: "https://youtu.be/abc123"),
            .init(title: "Homepage", url: "https://www.buffet-crampon.com"),
        ])
        let kept = Set(feedback.safeReferences.map(\.title))
        #expect(kept == ["Watch", "Short link", "Homepage"])
    }

    // MARK: Copyable analysis text

    @Test func analysisTextContainsKeyFacts() {
        let text = AnalysisText.make(report: .sampleVoice, coaching: .sampleVoice)
        #expect(text.contains("B♭ Major"))
        #expect(text.contains("F5"))          // a flagged problem note
        #expect(text.contains("Summary:"))    // coaching TL;DR included
        #expect(text.contains("Tenor"))       // voice characterization
    }

    @Test func reportBranchesByInstrument() {
        #expect(ToneReport.sampleVoice.gearGuess == nil)
        #expect(ToneReport.sampleVoice.voice != nil)
        #expect(ToneReport.sampleClarinet.voice == nil)
        #expect(ToneReport.sampleClarinet.gearGuess != nil)
    }

    // MARK: Helpers

    private func syntheticTrack(centerMidi: Double, vibratoHz: Double, extentCents: Double, count: Int) -> [CapturedSample] {
        (0..<count).map { i in
            let t = Double(i) * 0.0213
            let cents = vibratoHz > 0 ? extentCents * sin(2 * .pi * vibratoHz * t) : 0
            let midi = centerMidi + cents / 100
            return CapturedSample(audioTime: t, writtenMidi: midi,
                                  frequency: Pitch.frequency(forMidi: midi),
                                  clarity: 0.9, rms: 0.1, brightness: 2.8, oddEvenRatio: 3.0)
        }
    }

    private func makeFeedback(references: [CoachingFeedback.Reference]) -> CoachingFeedback {
        CoachingFeedback(headline: "", summary: "", positives: [], issues: [],
                         problemNoteComment: "", clarinetGuess: nil, reedGuess: nil,
                         voiceType: nil, rangeComment: nil, singerMatch: nil,
                         styleComparison: "", encouragement: "", references: references)
    }
}
