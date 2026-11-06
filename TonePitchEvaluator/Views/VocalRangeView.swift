import SwiftUI

/// A guided range finder: the singer holds their lowest comfortable note, then
/// their highest, and the app captures the two extremes to compute a vocal
/// range and a rough voice type. Optionally asks Claude for a locale-matched
/// singer. Drives its own `AudioEngine` in a live (non-drill) capture mode.
struct VocalRangeView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("anthropicAPIKey") private var apiKey = ""
    @AppStorage(VoiceProfile.Keys.low) private var savedLow = 0
    @AppStorage(VoiceProfile.Keys.high) private var savedHigh = 0
    @AppStorage(VoiceProfile.Keys.region) private var regionCode = VoiceProfile.defaultRegionCode

    private enum Step { case lowest, highest, done }

    @State private var audio = AudioEngine()
    /// How long a steady note must be held before it's captured.
    private static let holdDuration = 1.3

    @State private var step: Step = .lowest
    @State private var recent: [(time: TimeInterval, midi: Double)] = []
    /// The current stable concert MIDI, or nil while the pitch is unsettled.
    @State private var stableMidi: Double?
    /// Anchor for the hold-to-capture timer: the note and when the hold began.
    @State private var holdMidi: Double?
    @State private var holdStart: Date?
    @State private var holdProgress: Double = 0
    @State private var lowMidi: Int?
    @State private var highMidi: Int?
    @State private var listening = false

    @State private var singerMatch: SingerMatch?
    @State private var matchError: String?
    @State private var isMatching = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Find your vocal range")
                .font(.title2.bold())

            switch step {
            case .lowest, .highest:
                captureStep
            case .done:
                resultStep
            }

            HStack {
                Spacer()
                Button(step == .done ? "Done" : "Cancel") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 500)
        .task { await startListening() }
        .onDisappear { audio.stop(); audio.onSample = nil }
    }

    // MARK: Capture

    private var captureStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(step == .lowest
                 ? "Slide down to the **lowest** note you can sing comfortably and hold it steady."
                 : "Now slide up to the **highest** note you can sing comfortably and hold it steady.")
                .fixedSize(horizontal: false, vertical: true)

            liveReadout

            Text("Keep holding until the ring fills, or tap to set it now.")
                .font(.caption).foregroundStyle(.secondary)

            Button {
                capture()
            } label: {
                Label(step == .lowest ? "Set as my lowest" : "Set as my highest",
                      systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(stableMidi == nil)

            if let lowMidi, step == .highest {
                Text("Lowest captured: \(SpelledPitch.nearestSpelling(forMidi: lowMidi, preferSharps: false).name)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var liveReadout: some View {
        HStack(spacing: 14) {
            // Hold-to-capture ring fills while a steady note is sustained.
            ZStack {
                Circle().stroke(.quaternary, lineWidth: 5)
                Circle()
                    .trim(from: 0, to: holdProgress)
                    .stroke(Color.green, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.1), value: holdProgress)
                Image(systemName: "waveform")
                    .font(.title3)
                    .foregroundStyle(audio.latestLevel > 0.08 ? .green : .secondary)
            }
            .frame(width: 54, height: 54)

            if let midi = stableMidi {
                let name = SpelledPitch.nearestSpelling(forMidi: Int(midi.rounded()), preferSharps: false).name
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.system(size: 34, weight: .semibold).monospaced())
                    Text("holding steady — \(Int(holdProgress * 100))%")
                        .font(.caption).foregroundStyle(.green)
                }
            } else if audio.latestLevel > 0.08 {
                Text("hold the note steady…").font(.title3).foregroundStyle(.orange)
            } else {
                Text(listening ? "sing a note…" : "starting mic…").foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
    }

    private func capture() {
        guard let midi = stableMidi else { return }
        let rounded = Int(midi.rounded())
        switch step {
        case .lowest:
            lowMidi = rounded
            step = .highest
            resetHold()
        case .highest:
            // Guard against the "highest" landing below the lowest.
            highMidi = max(rounded, (lowMidi ?? rounded) + 1)
            finish()
        case .done:
            break
        }
    }

    private func resetHold() {
        recent.removeAll()
        stableMidi = nil
        holdMidi = nil
        holdStart = nil
        holdProgress = 0
    }

    private func finish() {
        guard let low = lowMidi, let high = highMidi else { return }
        savedLow = low
        savedHigh = high
        if regionCode.isEmpty { regionCode = VoiceProfile.defaultRegionCode }
        audio.stop()
        audio.onSample = nil
        step = .done
    }

    // MARK: Result

    @ViewBuilder
    private var resultStep: some View {
        if let low = lowMidi, let high = highMidi {
            let profile = VoiceProfile(lowMidi: low, highMidi: high, regionCode: regionCode)
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your range: \(profile.lowName) – \(profile.highName)")
                        .font(.title3.weight(.semibold))
                    Text("\(profile.rangeSemitones) semitones · likely **\(profile.voiceType.rawValue)**")
                        .foregroundStyle(.secondary)
                }

                Divider()

                if let match = singerMatch {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("🌟 \(match.singer)").font(.headline)
                        Text(match.reason).fixedSize(horizontal: false, vertical: true)
                        Text(match.voiceTypeNote)
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("A playful, best-effort match — verify before relying on it.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                } else {
                    Button {
                        matchSinger(profile: profile)
                    } label: {
                        HStack {
                            if isMatching { ProgressView().controlSize(.small) }
                            Image(systemName: "person.wave.2")
                            Text(isMatching ? "Finding a match…" : "Match me to a singer in \(profile.regionName)")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.glass)
                    .disabled(isMatching)

                    if let matchError {
                        Text(matchError).font(.callout).foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: Audio + matching

    private func startListening() async {
        guard await audio.requestPermission() else { return }
        audio.pitchFrequencyRange = (InstrumentKind.voice.pitchMinFrequency, InstrumentKind.voice.pitchMaxFrequency)
        audio.onSample = { sample in ingest(sample) }
        try? audio.start()
        listening = true
    }

    /// Track a short rolling window of confident pitches; report a stable MIDI
    /// when they agree, and advance the hold-to-capture timer while the singer
    /// sustains that note. Unvoiced/quiet windows reset the hold.
    private func ingest(_ sample: PitchSample) {
        guard let frequency = sample.frequency, sample.clarity > 0.82, sample.rms > 0.015 else {
            // Silence or a breath: drop the hold so it restarts cleanly.
            recent.removeAll()
            stableMidi = nil
            holdMidi = nil
            holdStart = nil
            holdProgress = 0
            return
        }
        let midi = Pitch.midi(forFrequency: frequency)   // concert pitch for voice
        recent.append((sample.time, midi))
        recent = recent.suffix(12)

        let window = recent.map(\.midi)
        guard window.count >= 6,
              let lo = window.min(), let hi = window.max(), hi - lo < 0.7 else {
            stableMidi = nil
            holdProgress = 0
            holdStart = nil
            return
        }
        let median = window.sorted()[window.count / 2]
        stableMidi = median

        // Advance the hold timer while the held note stays put (~within a
        // semitone); auto-capture once it has been held long enough.
        if let anchor = holdMidi, let start = holdStart, abs(anchor - median) < 0.8 {
            holdProgress = min(1, Date().timeIntervalSince(start) / Self.holdDuration)
            if holdProgress >= 1 { capture() }
        } else {
            holdMidi = median
            holdStart = Date()
            holdProgress = 0
        }
    }

    private func matchSinger(profile: VoiceProfile) {
        matchError = nil
        isMatching = true
        let coach = ClaudeCoach(apiKey: apiKey)
        Task {
            do {
                singerMatch = try await coach.matchSinger(profile: profile)
            } catch {
                matchError = (error as? CoachError)?.errorDescription ?? error.localizedDescription
            }
            isMatching = false
        }
    }
}

#Preview {
    VocalRangeView()
}
