import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The main screen: pick a scale and tempo, play along with the metronome while
/// the staff lights up in real time, then listen back, save, and ask Claude for
/// coaching.
struct PracticeView: View {
    private static let defaultTonic = Tonic(letter: .c, accidental: .natural)
    @State private var session = PracticeSession(scale: Scale(tonic: defaultTonic, quality: .major))
    @State private var tonic: Tonic = defaultTonic
    @State private var quality: ScaleQuality = .major
    @State private var instrument: InstrumentKind = .clarinet

    private var tonicOptions: [Tonic] { Tonic.options(forMinor: quality != .major) }

    @AppStorage("anthropicAPIKey") private var apiKey = ""
    @AppStorage(VoiceProfile.Keys.region) private var regionCode = VoiceProfile.defaultRegionCode
    @AppStorage(VoiceProfile.Keys.low) private var voiceLow = 0
    @AppStorage(VoiceProfile.Keys.high) private var voiceHigh = 0
    @State private var showingSettings = false
    @State private var showingRangeFinder = false
    @State private var showingCalibration = false
    @State private var showingTuner = false

    /// The singer's measured range, when known, used to place voice scales so
    /// they sit where the singer can actually sing.
    private var voiceRange: ClosedRange<Int>? {
        guard instrument == .voice, voiceLow > 0, voiceHigh > voiceLow else { return nil }
        return voiceLow...voiceHigh
    }

    @State private var coaching: CoachingFeedback?
    @State private var coachingError: String?
    @State private var isCoaching = false
    @State private var copied = false

    private var report: ToneReport? {
        session.phase == .finished ? ToneAnalyzer.analyze(session: session) : nil
    }

    var body: some View {
        VStack(spacing: 18) {
            header
            controlBar

            VStack(spacing: 6) {
                Text(session.scale.name)
                    .font(.custom("Palatino", size: 20).weight(.semibold))
                StaffView(notes: session.notes,
                          currentIndex: session.currentIndex,
                          keySignature: session.scale.keySignature,
                          noteValue: session.noteValue,
                          leadInRestMeasure: true,
                          leadInBeat: session.leadInBeat)
                    .overlay {
                        if session.phase == .countIn, let n = session.countdownNumber {
                            FilmLeaderView(number: n, beatDuration: session.secondsPerBeat)
                                .frame(width: 190, height: 190)
                                .id(n)
                                .transition(.scale(scale: 0.6).combined(with: .opacity))
                        }
                    }
                    .animation(.easeOut(duration: 0.15), value: session.countdownNumber)
            }

            statusLine

            if session.phase == .finished {
                ScrollView {
                    VStack(spacing: 16) {
                        if session.audio.recordingURL != nil { playbackBar }
                        if let report {
                            HStack {
                                Spacer()
                                Button {
                                    copyAnalysis(report: report)
                                } label: {
                                    Label(copied ? "Copied!" : "Copy analysis", systemImage: copied ? "checkmark" : "doc.on.doc")
                                }
                                .buttonStyle(.glass)
                                Button {
                                    saveAnalysis(report: report)
                                } label: {
                                    Label("Save…", systemImage: "square.and.arrow.down")
                                }
                                .buttonStyle(.glass)
                            }
                            ResultsPanel(report: report,
                                         onReplay: session.audio.recordingURL != nil ? { replay($0) } : nil)
                            coachingSection(report: report)
                        } else {
                            noAnalysisCard
                        }
                    }
                    .padding(.bottom, 8)
                }
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(22)
        .frame(minWidth: 1040, minHeight: 780)
        .sheet(isPresented: $showingSettings) { SettingsSheet(apiKey: $apiKey, regionCode: $regionCode) }
        .sheet(isPresented: $showingRangeFinder) { VocalRangeView() }
        .sheet(isPresented: $showingCalibration) { PitchCalibrationView() }
        .sheet(isPresented: $showingTuner) { TunerView(instrument: instrument) }
        .onChange(of: tonic) { _, _ in rebuildScale() }
        .onChange(of: instrument) { _, _ in rebuildScale() }
        .onChange(of: voiceLow) { _, _ in rebuildScale() }
        .onChange(of: voiceHigh) { _, _ in rebuildScale() }
        .onChange(of: quality) { old, new in
            if (old == .major) != (new == .major) {
                tonic = tonic.mapped(into: tonicOptions)
            }
            rebuildScale()
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Tone/Pitch")
                    .font(.custom("Palatino", size: 30).weight(.bold))
                Text(instrument == .voice ? "Voice tone & intonation trainer" : "Clarinet tone & intonation trainer")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if instrument == .voice {
                voiceToolButtons
            }
            Button { showingTuner = true } label: {
                Label("Tuner", systemImage: "tuningfork")
            }
            .buttonStyle(.glass)
            .disabled(isRunning)
            .help("Chromatic tuner — cross-check against a standalone tuner")
            Button { showingSettings = true } label: {
                Image(systemName: "gearshape").font(.title3).padding(6)
            }
            .buttonStyle(.glass)
            .help("Settings — Anthropic API key")
        }
    }

    private var voiceToolButtons: some View {
        HStack(spacing: 10) {
            Button { showingRangeFinder = true } label: {
                Label("Find my range", systemImage: "arrow.up.and.down")
            }
            .buttonStyle(.glass)
            Button { showingCalibration = true } label: {
                Label("Tune-up", systemImage: "target")
            }
            .buttonStyle(.glass)
        }
        .disabled(isRunning)
    }

    // MARK: Controls

    private var controlBar: some View {
        HStack(spacing: 16) {
            HStack(alignment: .top, spacing: 22) {
                labeled("Instrument") {
                    Picker("", selection: $instrument) {
                        ForEach(InstrumentKind.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 110)
                }
                .disabled(isRunning)

                labeled("Scale") {
                    HStack(spacing: 6) {
                        Picker("", selection: $tonic) {
                            ForEach(tonicOptions) { Text($0.name).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 70)
                        Picker("", selection: $quality) {
                            ForEach(ScaleQuality.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 150)
                    }
                }

                labeled("Tempo — \(Int(session.tempo)) bpm") {
                    Slider(value: bindTempo, in: 40...200, step: 1).frame(width: 160)
                }
                .disabled(isRunning)

                labeled("Note value") {
                    Picker("", selection: bindNoteValue) {
                        ForEach(NoteValue.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 110)
                }
                .disabled(isRunning)

                labeled("Metronome") {
                    HStack(spacing: 10) {
                        Toggle("", isOn: bindMetronome)
                            .labelsHidden()
                            .toggleStyle(.switch)
                        Toggle("Silent", isOn: bindMetronomeSilent)
                            .toggleStyle(.checkbox)
                            .disabled(!session.metronomeOn)
                            .help("Flash the beat on screen instead of clicking, so it doesn't bleed into your recording")
                    }
                }
                .disabled(isRunning)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .glassEffect(in: .rect(cornerRadius: 20))

            Spacer()

            recordButton
        }
    }

    private var recordButton: some View {
        Button(action: record) {
            Label(isRunning ? "Stop" : "Record", systemImage: isRunning ? "stop.fill" : "mic.fill")
                .font(.headline)
                .frame(minWidth: 118)
                .padding(.vertical, 4)
                .contentTransition(.opacity)
        }
        .buttonStyle(.glassProminent)
        .tint(isRunning ? .red : .accentColor)
        .controlSize(.large)
        .animation(.easeInOut(duration: 0.35), value: isRunning)
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .kerning(0.4)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            content()
        }
    }

    // MARK: Status line

    private var statusLine: some View {
        HStack(spacing: 14) {
            switch session.phase {
            case .idle:
                Text(idleStatus).foregroundStyle(.secondary)
            case .countIn:
                Text("Count-in…")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.orange)
            case .leadIn:
                Text("Lead-in — feel the tempo…")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.orange)
            case .playing:
                Text("Playing — note \((session.currentIndex ?? 0) + 1) of \(session.notes.count)")
                    .font(.headline)
                LiveTuner(frequency: session.audio.latestFrequency, level: session.audio.latestLevel, instrument: instrument)
            case .finished:
                Text("Done! Listen back below, then get your analysis.")
                    .font(.headline)
                    .foregroundStyle(Color(red: 0.16, green: 0.6, blue: 0.33))
            }
            if isRunning && session.metronomeOn {
                BeatIndicator(tick: session.beatTick, silent: session.metronomeSilent)
            }
            Spacer()
        }
        .frame(height: 26)
    }

    /// Idle instruction, with a headphones tip when the audible metronome could
    /// bleed into the recording.
    private var idleStatus: String {
        let base = "Press record, watch the film-leader count-in, then play the scale along with the moving cursor."
        if session.metronomeOn && !session.metronomeSilent {
            return base + "  Tip: wear headphones (or tick “Silent”) so the metronome doesn't bleed into your take."
        }
        return base
    }

    // MARK: Playback + save

    private var playbackBar: some View {
        HStack(spacing: 12) {
            Button {
                if session.audio.isPlayingRecording { session.audio.stopPlayback() }
                else { session.audio.playRecording() }
            } label: {
                Label(session.audio.isPlayingRecording ? "Stop" : "Play my take",
                      systemImage: session.audio.isPlayingRecording ? "stop.fill" : "play.fill")
            }
            .buttonStyle(.glass)

            Button { saveRecording() } label: {
                Label("Save to disk…", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.glass)

            Spacer()
            Text("Recorded this take — listen back, then save if you like it.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .glassEffect(in: .rect(cornerRadius: 16))
    }

    /// Shown when the run finished but too few sustained notes were tracked to
    /// score (e.g. the scale sat outside the singer's range, or notes were too
    /// short/quiet). Keeps the take available to listen back.
    private var noAnalysisCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Not enough to analyze yet", systemImage: "waveform.badge.exclamationmark")
                .font(.headline)
            Text(instrument == .voice
                 ? "I couldn't track enough sustained notes. Try singing a bit louder and holding each note, and pick a key that sits inside your range (use “Find my range”). Then record again."
                 : "I couldn't track enough sustained notes. Try playing a bit louder and holding each note steady, then record again.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.black.opacity(0.08)))
        .environment(\.colorScheme, .light)
    }

    private func saveRecording() {
        guard let source = session.audio.recordingURL else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "caf") ?? .audio]
        panel.nameFieldStringValue = "\(session.scale.name) take.caf"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        try? FileManager.default.removeItem(at: dest)
        try? FileManager.default.copyItem(at: source, to: dest)
    }

    // MARK: Coaching

    @ViewBuilder
    private func coachingSection(report: ToneReport) -> some View {
        VStack(spacing: 12) {
            if let coaching {
                CoachingCard(feedback: coaching)
            } else {
                Button {
                    requestCoaching(report: report)
                } label: {
                    HStack {
                        if isCoaching { ProgressView().controlSize(.small) }
                        Image(systemName: "sparkles")
                        Text(isCoaching ? "Claude is listening…" : "Get AI coaching from Claude")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(isCoaching)

                if let coachingError {
                    Text(coachingError)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                    if apiKey.trimmingCharacters(in: .whitespaces).isEmpty {
                        Button("Add API key") { showingSettings = true }
                    }
                }
            }
        }
    }

    // MARK: Actions

    private var isRunning: Bool { session.phase == .countIn || session.phase == .leadIn || session.phase == .playing }

    private func record() {
        coaching = nil
        coachingError = nil
        session.startStop()
    }

    private func rebuildScale() {
        session.setScale(Scale(tonic: tonic, quality: quality, instrument: instrument, range: voiceRange))
        coaching = nil
        coachingError = nil
    }

    /// Replay the recorded section for a flagged note: find its first slot in
    /// the run and play that slice of the take.
    private func replay(_ problem: ProblemNote) {
        guard let origin = session.transportOrigin,
              let index = session.notes.firstIndex(where: { $0.target.name == problem.noteName }) else { return }
        let spn = session.secondsPerNote
        let start = max(0, origin + Double(index) * spn - 0.05)
        let duration = max(0.6, spn + 0.1)
        session.audio.playRecording(from: start, duration: duration)
    }

    private func copyAnalysis(report: ToneReport) {
        let text = AnalysisText.make(report: report, coaching: coaching)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }

    private func saveAnalysis(report: ToneReport) {
        let text = AnalysisText.make(report: report, coaching: coaching)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(report.scaleName) analysis.txt"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? text.data(using: .utf8)?.write(to: url)
    }

    private func requestCoaching(report: ToneReport) {
        coachingError = nil
        isCoaching = true
        let coach = ClaudeCoach(apiKey: apiKey)
        Task {
            do {
                coaching = try await coach.coach(on: report)
            } catch {
                coachingError = (error as? CoachError)?.errorDescription ?? error.localizedDescription
            }
            isCoaching = false
        }
    }

    // MARK: Bindings into the observable session

    private var bindTempo: Binding<Double> {
        Binding(get: { session.tempo }, set: { session.tempo = $0 })
    }
    private var bindNoteValue: Binding<NoteValue> {
        Binding(get: { session.noteValue }, set: { session.noteValue = $0 })
    }
    private var bindMetronome: Binding<Bool> {
        Binding(get: { session.metronomeOn }, set: { session.metronomeOn = $0 })
    }
    private var bindMetronomeSilent: Binding<Bool> {
        Binding(get: { session.metronomeSilent }, set: { session.metronomeSilent = $0 })
    }
}

// MARK: - Beat indicator

/// A dot that flashes on each metronome beat, so a silent (visual) metronome
/// still conveys the tempo.
private struct BeatIndicator: View {
    let tick: Int
    let silent: Bool
    @State private var flash = false

    var body: some View {
        Circle()
            .fill(silent ? Color.orange : Color.accentColor)
            .frame(width: 14, height: 14)
            .scaleEffect(flash ? 1.4 : 0.9)
            .opacity(flash ? 1 : 0.4)
            .animation(.easeOut(duration: 0.18), value: flash)
            .onChange(of: tick) { _, _ in
                flash = true
                Task { try? await Task.sleep(for: .milliseconds(120)); flash = false }
            }
            .help(silent ? "Silent metronome — watch the beat" : "Metronome beat")
    }
}

// MARK: - Live tuner

private struct LiveTuner: View {
    let frequency: Double?
    let level: Double
    let instrument: InstrumentKind

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform")
                .foregroundStyle(level > 0.08 ? .green : .secondary)
            if level > 0.08, let frequency, frequency > 0 {
                let written = instrument.writtenMidi(forSoundingFrequency: frequency)
                let rounded = Int(written.rounded())
                let cents = Int(((written - Double(rounded)) * 100).rounded())
                let pitch = SpelledPitch.nearestSpelling(forMidi: rounded, preferSharps: true)
                Text("\(pitch.letter.name)\(pitch.accidental.symbol)\(pitch.octave)")
                    .font(.headline.monospaced())
                Text(cents >= 0 ? "+\(cents)¢" : "\(cents)¢")
                    .font(.subheadline.monospaced())
                    .foregroundStyle(abs(cents) <= 15 ? .green : abs(cents) <= 35 ? .orange : .red)
            } else {
                Text("listening…").foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Settings

private struct SettingsSheet: View {
    @Binding var apiKey: String
    @Binding var regionCode: String
    @Environment(\.dismiss) private var dismiss
    @State private var showingCalibration = false

    /// Leaf (country) regions with localized names, sorted for the picker.
    private var regions: [(code: String, name: String)] {
        Locale.Region.isoRegions
            .filter { $0.subRegions.isEmpty }
            .compactMap { region in
                guard let name = Locale.current.localizedString(forRegionCode: region.identifier) else { return nil }
                return (region.identifier, name)
            }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings").font(.title2.bold())
            Text("Paste an Anthropic API key to enable AI coaching. It's stored locally on this Mac.")
                .font(.callout)
                .foregroundStyle(.secondary)
            SecureField("sk-ant-…", text: $apiKey)
                .textFieldStyle(.roundedBorder)
            Text("Get a key at console.anthropic.com. Coaching uses the Claude Messages API (model \(ClaudeCoach.model)).")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Region").font(.headline)
                Text("Used to match your voice to a well-known singer from your area.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("", selection: $regionCode) {
                    ForEach(regions, id: \.code) { Text($0.name).tag($0.code) }
                }
                .labelsHidden()
                .frame(maxWidth: 260)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Diagnostics").font(.headline)
                Text("Plays a clarinet scale through the built-in sampler and checks the pitch detector reads every note correctly.")
                    .font(.caption).foregroundStyle(.secondary)
                Button {
                    showingCalibration = true
                } label: {
                    Label("Run detector calibration", systemImage: "waveform.badge.magnifyingglass")
                }
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440)
        .sheet(isPresented: $showingCalibration) { DetectorCalibrationView() }
    }
}

#Preview {
    PracticeView()
}
