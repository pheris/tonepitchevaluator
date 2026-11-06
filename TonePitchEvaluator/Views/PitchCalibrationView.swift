import SwiftUI

/// A sing-in-tune trainer that shows the feedback on real sheet music: the
/// target note sits on a staff, and the pitch you're actually singing is drawn
/// as a ghost note above/below it (with a direction arrow for small errors), so
/// you can see at a glance whether to go higher or lower. The surrounding frame
/// greens as you lock on. Drives its own `AudioEngine` in live capture (concert
/// pitch).
struct PitchCalibrationView: View {
    @Environment(\.dismiss) private var dismiss

    /// Half the width of the "inside the note" band, in cents.
    private static let noteBand = 50.0

    @State private var audio = AudioEngine()
    @State private var targetMidi = 60          // C4
    @State private var smoothedCents: Double?

    var body: some View {
        VStack(spacing: 20) {
            header
            targetSelector
            staffVisual
            statusChip
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 600, height: 560)
        .task { await startListening() }
        .onDisappear { audio.stop(); audio.onSample = nil }
    }

    // MARK: Derived state

    private var targetName: String {
        SpelledPitch.nearestSpelling(forMidi: targetMidi, preferSharps: false).name
    }

    /// Current smoothed cents relative to the target, only while there's a voice.
    private var cents: Double? {
        audio.latestLevel > 0.06 ? smoothedCents : nil
    }

    /// The staff note: the target, plus the sung pitch as its "played" value so
    /// `StaffView` draws a ghost note / direction arrow for the deviation.
    private var calibrationNote: ScoredNote {
        let target = SpelledPitch.nearestSpelling(forMidi: targetMidi, preferSharps: false)
        var note = ScoredNote(index: 0, target: target)
        if let cents {
            note.tempo = .perfect   // in-tune head celebrates; off-pitch shows ghost
            note.centsOff = cents
            note.playedWrittenMidi = Double(targetMidi) + cents / 100.0
        }
        return note
    }

    /// 0…1 alignment; 1 = perfectly centered in the note.
    private var alignment: Double {
        guard let cents else { return 0 }
        return max(0, 1 - abs(cents) / Self.noteBand)
    }

    // MARK: Sections

    private var header: some View {
        VStack(spacing: 2) {
            Text("Tune-up").font(.title2.bold())
            Text("Match the target note — your pitch shows as a ghost note on the staff.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private var targetSelector: some View {
        HStack(spacing: 16) {
            Button { targetMidi = max(InstrumentKind.voice.lowestWrittenMidi, targetMidi - 1) } label: {
                Image(systemName: "minus.circle.fill").font(.title2)
            }
            .buttonStyle(.plain)

            VStack(spacing: 0) {
                Text("Target").font(.caption).foregroundStyle(.secondary)
                Text(targetName).font(.system(size: 30, weight: .bold).monospaced())
            }
            .frame(width: 120)

            Button { targetMidi = min(InstrumentKind.voice.highestWrittenMidi, targetMidi + 1) } label: {
                Image(systemName: "plus.circle.fill").font(.title2)
            }
            .buttonStyle(.plain)
        }
    }

    /// Sheet-music feedback: the target note and the sung ghost note on a staff,
    /// inside a frame that greens as the pitch locks on.
    private var staffVisual: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.green.opacity(0.10 + 0.55 * alignment))
                .animation(.easeOut(duration: 0.15), value: alignment)
            StaffView(notes: [calibrationNote], noteValue: .quarter)
                .padding(12)
        }
    }

    @ViewBuilder
    private var statusChip: some View {
        if let cents {
            if abs(cents) <= 12 {
                Label("In tune — hold it", systemImage: "checkmark.seal.fill")
                    .font(.headline).foregroundStyle(.green)
            } else if cents < 0 {
                Label("Sing higher", systemImage: "arrow.up")
                    .font(.headline).foregroundStyle(.blue)
            } else {
                Label("Sing lower", systemImage: "arrow.down")
                    .font(.headline).foregroundStyle(.orange)
            }
        } else {
            Text("Sing the target note…").foregroundStyle(.secondary)
        }
    }

    // MARK: Audio

    private func startListening() async {
        guard await audio.requestPermission() else { return }
        audio.pitchFrequencyRange = (InstrumentKind.voice.pitchMinFrequency, InstrumentKind.voice.pitchMaxFrequency)
        audio.onSample = { sample in ingest(sample) }
        try? audio.start()
    }

    private func ingest(_ sample: PitchSample) {
        guard let frequency = sample.frequency, sample.clarity > 0.88, sample.rms > 0.02 else { return }
        let newCents = Pitch.cents(ofFrequency: frequency, relativeToMidi: Double(targetMidi))
        // Exponential smoothing to settle the pointer without lagging badly.
        smoothedCents = smoothedCents.map { $0 * 0.6 + newCents * 0.4 } ?? newCents
    }
}

#Preview {
    PitchCalibrationView()
}
