import Foundation

/// Renders a `ToneReport` (and optional Claude coaching) as plain text for the
/// "Copy analysis" button, so the player can paste it into notes or a message.
enum AnalysisText {
    static func make(report: ToneReport, coaching: CoachingFeedback?) -> String {
        var lines: [String] = []

        lines.append("Tone/Pitch analysis — \(report.scaleName) (\(report.instrument.rawValue))")
        lines.append("Tempo \(report.tempoBPM) bpm · \(report.noteValue) notes")
        lines.append("")
        lines.append("Notes: \(report.evaluatedNoteCount) scored of \(report.playedNoteCount + report.missedNoteCount)")
        lines.append("Like-a-pro: \(Int((report.professionalCloseness * 100).rounded()))%")
        lines.append("Avg error: \(Int(report.meanAbsCents.rounded()))¢ (tendency \(signed(report.meanSignedCents))¢)")
        lines.append("On tempo: \(Int(report.onTempoPercent))% · Perfect notes: \(Int(report.perfectNotePercent))%")
        lines.append("Tone: focus \(pct(report.meanClarity)), steadiness \(pct(report.dynamicSteadiness))")

        if !report.registerIntonation.isEmpty {
            lines.append("")
            lines.append("Intonation by register:")
            for stat in report.registerIntonation {
                lines.append("  • \(stat.registerName): \(signed(stat.meanSignedCents))¢ (\(stat.noteCount) notes)")
            }
        }

        if !report.problemNotes.isEmpty {
            lines.append("")
            lines.append("Notes to watch:")
            for note in report.problemNotes {
                let dir = note.meanSignedCents > 0 ? "sharp" : "flat"
                lines.append("  • \(note.noteName): \(dir) by \(Int(abs(note.meanSignedCents)))¢ (×\(note.occurrences))")
            }
        }

        if let voice = report.voice {
            lines.append("")
            lines.append("Voice character:")
            if let type = voice.voiceType, let low = voice.rangeLowName, let high = voice.rangeHighName {
                lines.append("  • \(type), range \(low)–\(high) (\(voice.rangeSemitones ?? 0) semitones)")
            }
            if voice.vibratoRateHz > 0 {
                lines.append("  • Vibrato \(String(format: "%.1f", voice.vibratoRateHz)) Hz, ±\(Int(voice.vibratoExtentCents))¢")
            }
            lines.append("  • Breathiness \(pct(voice.breathiness)), warmth \(pct(voice.warmth))")
        }
        if let gear = report.gearGuess {
            lines.append("")
            lines.append("Gear guess: \(gear.closestInstrument) — \(gear.instrumentCharacter); \(gear.reedStrengthGuess)")
        }

        if let c = coaching {
            lines.append("")
            lines.append("— Coaching from Claude —")
            lines.append(c.headline)
            if !c.summary.isEmpty { lines.append("Summary: \(c.summary)") }
            if !c.positives.isEmpty {
                lines.append("What's working:")
                for p in c.positives { lines.append("  • \(p)") }
            }
            if !c.issues.isEmpty {
                lines.append("Things to work on:")
                for i in c.issues { lines.append("  • \(i.area): \(i.tip)") }
            }
            if !c.problemNoteComment.isEmpty { lines.append("Specific notes: \(c.problemNoteComment)") }
            if !c.encouragement.isEmpty { lines.append(c.encouragement) }
            if !c.safeReferences.isEmpty {
                lines.append("References:")
                for r in c.safeReferences { lines.append("  • \(r.title) — \(r.url)") }
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func signed(_ cents: Double) -> String {
        cents >= 0 ? "+\(Int(cents.rounded()))" : "\(Int(cents.rounded()))"
    }
    private static func pct(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }
}
