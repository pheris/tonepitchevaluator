import SwiftUI

/// The objective, on-device analysis of a finished scale run.
struct ResultsPanel: View {
    let report: ToneReport
    /// Optional hook to replay the recorded section for a problem note.
    var onReplay: ((ProblemNote) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Analysis — \(report.scaleName)")
                    .font(.title3.bold())
                Spacer()
                Text("\(report.evaluatedNoteCount) of \(report.playedNoteCount + report.missedNoteCount) notes scored")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Headline scores.
            HStack(spacing: 12) {
                StatChip(title: "Like a pro", value: "\(Int((report.professionalCloseness * 100).rounded()))%",
                         tint: closenessTint)
                StatChip(title: "Avg error", value: "\(Int(report.meanAbsCents.rounded()))¢",
                         tint: centsTint(report.meanAbsCents))
                StatChip(title: "Tendency", value: tendency, tint: .secondary)
                StatChip(title: "On tempo", value: "\(Int(report.onTempoPercent))%", tint: .blue)
                StatChip(title: "Perfect", value: "\(Int(report.perfectNotePercent))%", tint: .purple)
            }

            // Tone descriptors.
            VStack(alignment: .leading, spacing: 6) {
                Text("Tone").font(.headline)
                HStack(spacing: 18) {
                    descriptor("Focus", report.meanClarity, of: 1.0, suffix: "")
                    descriptor("Steadiness", report.dynamicSteadiness, of: 1.0, suffix: "")
                    plain("Brightness", String(format: "%.1f", report.meanBrightness))
                    plain("Odd/even", String(format: "%.1f", report.meanOddEvenRatio))
                }
            }

            if !report.registerIntonation.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Intonation by register").font(.headline)
                    ForEach(report.registerIntonation, id: \.registerName) { stat in
                        HStack {
                            Text(stat.registerName).frame(width: 120, alignment: .leading)
                            Text(signed(stat.meanSignedCents))
                                .font(.callout.monospaced())
                                .foregroundStyle(centsTint(abs(stat.meanSignedCents)))
                            Text("(\(stat.noteCount) notes)").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                        }
                    }
                }
            }

            if !report.problemNotes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Notes to watch").font(.headline)
                    ForEach(report.problemNotes, id: \.noteName) { note in
                        HStack(spacing: 8) {
                            if let onReplay {
                                Button {
                                    onReplay(note)
                                } label: {
                                    Image(systemName: "play.circle")
                                }
                                .buttonStyle(.plain)
                                .help("Replay \(note.noteName) from your take")
                            }
                            Text("• \(note.noteName): consistently \(note.meanSignedCents > 0 ? "sharp" : "flat") by \(Int(abs(note.meanSignedCents)))¢ (×\(note.occurrences))")
                                .font(.callout)
                        }
                    }
                }
            }

            // Baseline gear inference (the fun part Claude expands on).
            if let gear = report.gearGuess {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tone-color impression (just for fun)").font(.headline)
                    Text("Your sound is **\(gear.instrumentCharacter)** — a bit like a \(gear.closestInstrument).")
                        .font(.callout)
                    Text("Reed hunch: \(gear.reedStrengthGuess).")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("A playful read of your tone color — it can't actually tell a French (Buffet) bore from a German (Oehler) one.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // Voice characterization (the singing counterpart to the gear guess).
            if let voice = report.voice {
                voiceSection(voice)
            }
        }
        .padding(18)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.black.opacity(0.08)))
        // The card is always white, so render its text in light appearance to
        // avoid white-on-white in dark mode.
        .environment(\.colorScheme, .light)
    }

    private var tendency: String {
        let c = report.meanSignedCents
        if abs(c) < 4 { return "centered" }
        return c > 0 ? "sharp" : "flat"
    }

    private var closenessTint: Color {
        switch report.professionalCloseness {
        case 0.8...: return .green
        case 0.55..<0.8: return .blue
        case 0.3..<0.55: return .orange
        default: return .red
        }
    }

    private func centsTint(_ cents: Double) -> Color {
        switch cents {
        case ..<10: return .green
        case 10..<25: return .orange
        default: return .red
        }
    }

    private func signed(_ cents: Double) -> String {
        cents >= 0 ? "+\(Int(cents.rounded()))¢" : "\(Int(cents.rounded()))¢"
    }

    private func descriptor(_ title: String, _ value: Double, of max: Double, suffix: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            ProgressView(value: min(value, max), total: max).frame(width: 90)
            Text(String(format: "%.0f%%", (value / max) * 100)).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func plain(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout.monospaced())
        }
    }

    @ViewBuilder
    private func voiceSection(_ voice: VoiceAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Voice character").font(.headline)
            if let type = voice.voiceType, let low = voice.rangeLowName, let high = voice.rangeHighName {
                Text("Classified as **\(type)** — range \(low)–\(high) (\(voice.rangeSemitones ?? 0) semitones).")
                    .font(.callout)
            } else {
                Text("Run the range finder to classify your voice type and range.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if voice.vibratoRateHz > 0 {
                Text("Vibrato: \(String(format: "%.1f", voice.vibratoRateHz)) Hz, ±\(Int(voice.vibratoExtentCents))¢.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Text("Vibrato: little or none detected (fairly straight tone).")
                    .font(.callout).foregroundStyle(.secondary)
            }
            HStack(spacing: 18) {
                descriptor("Breathiness", voice.breathiness, of: 1.0, suffix: "")
                descriptor("Warmth", voice.warmth, of: 1.0, suffix: "")
            }
        }
    }
}

private struct StatChip: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.bold().monospacedDigit()).foregroundStyle(tint)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Claude's qualitative coaching, rendered as a friendly card.
struct CoachingCard: View {
    let feedback: CoachingFeedback

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(.purple)
                Text("Coaching from Claude").font(.headline)
            }

            Text(feedback.headline)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            // Top-level TL;DR so the player gets the gist without reading it all.
            if !feedback.summary.isEmpty {
                Text(feedback.summary)
                    .font(.callout)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !feedback.positives.isEmpty {
                section("What's working") {
                    ForEach(feedback.positives, id: \.self) { item in
                        Label(item, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.primary)
                            .labelStyle(TopAlignedLabel(tint: Color(red: 0.16, green: 0.6, blue: 0.33)))
                    }
                }
            }

            if !feedback.issues.isEmpty {
                section("Things to work on") {
                    ForEach(feedback.issues, id: \.tip) { issue in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(issue.area).font(.subheadline.bold())
                            Text(issue.tip).fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.bottom, 2)
                    }
                }
            }

            if !feedback.problemNoteComment.isEmpty {
                section("Specific notes") {
                    Text(feedback.problemNoteComment).fixedSize(horizontal: false, vertical: true)
                }
            }

            section("Just for fun") {
                if let clarinetGuess = feedback.clarinetGuess {
                    Text("🎺 Clarinet guess: \(clarinetGuess)").fixedSize(horizontal: false, vertical: true)
                }
                if let reedGuess = feedback.reedGuess {
                    Text("🎋 Reed guess: \(reedGuess)").fixedSize(horizontal: false, vertical: true)
                }
                if let voiceType = feedback.voiceType {
                    Text("🎤 Voice type: \(voiceType)").fixedSize(horizontal: false, vertical: true)
                }
                if let rangeComment = feedback.rangeComment, !rangeComment.isEmpty {
                    Text("📈 Range: \(rangeComment)").fixedSize(horizontal: false, vertical: true)
                }
                if let singerMatch = feedback.singerMatch, !singerMatch.isEmpty {
                    Text("🌟 Reminds me of: \(singerMatch)").fixedSize(horizontal: false, vertical: true)
                }
                if !feedback.styleComparison.isEmpty {
                    Text("🎧 Style: \(feedback.styleComparison)").fixedSize(horizontal: false, vertical: true)
                }
            }

            if !feedback.safeReferences.isEmpty {
                section("References") {
                    ForEach(feedback.safeReferences, id: \.url) { ref in
                        if let url = URL(string: ref.url) {
                            Link(destination: url) {
                                Label(ref.title, systemImage: "link")
                                    .font(.callout)
                            }
                        } else {
                            Text("• \(ref.title)").font(.callout)
                        }
                    }
                    Text("AI-suggested references — verify before relying on them.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Text(feedback.encouragement)
                .font(.callout.italic())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        // A faint tint over an OPAQUE white fill — without the white, the 6%
        // gradient would let the dark window show through and the (light-mode)
        // dark text would be unreadable.
        .background(
            LinearGradient(colors: [Color.purple.opacity(0.06), Color.blue.opacity(0.06)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 16)
        )
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.purple.opacity(0.18)))
        .environment(\.colorScheme, .light)
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.subheadline.bold()).foregroundStyle(.secondary)
            content()
        }
    }
}

private struct TopAlignedLabel: LabelStyle {
    let tint: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            configuration.icon.foregroundStyle(tint)
            configuration.title.fixedSize(horizontal: false, vertical: true)
        }
    }
}

#if DEBUG
#Preview("Results — Voice") {
    ScrollView {
        VStack(spacing: 16) {
            ResultsPanel(report: .sampleVoice)
            CoachingCard(feedback: .sampleVoice)
        }
        .padding()
    }
    .frame(width: 700, height: 920)
}

#Preview("Results — Clarinet") {
    ScrollView {
        VStack(spacing: 16) {
            ResultsPanel(report: .sampleClarinet)
            CoachingCard(feedback: .sampleClarinet)
        }
        .padding()
    }
    .frame(width: 700, height: 920)
}
#endif
