import SwiftUI

/// A straightforward chromatic tuner so the player can cross-check the app's
/// pitch detection against a standalone tuner. It shows the **concert** pitch
/// (what any standard tuner displays) alongside the instrument's **written**
/// note, a cents needle, and the A=440 equal-tempered reference. Drives its own
/// `AudioEngine` in live capture.
struct TunerView: View {
    let instrument: InstrumentKind
    @Environment(\.dismiss) private var dismiss

    @State private var audio = AudioEngine()
    /// Smoothed concert MIDI (fractional); nil while there's no steady tone.
    @State private var smoothedMidi: Double?

    private var concertMidi: Double? {
        audio.latestLevel > 0.05 ? smoothedMidi : nil
    }

    // Nearest note + cents from the smoothed concert pitch.
    private var reading: (concert: SpelledPitch, written: SpelledPitch, cents: Int, hz: Double)? {
        guard let midi = concertMidi else { return nil }
        let rounded = Int(midi.rounded())
        let cents = Int(((midi - Double(rounded)) * 100).rounded())
        let sharp = (midi - Double(rounded)) > 0
        let concert = SpelledPitch.nearestSpelling(forMidi: rounded, preferSharps: sharp)
        let written = SpelledPitch.nearestSpelling(forMidi: rounded + instrument.transposition, preferSharps: sharp)
        return (concert, written, cents, Pitch.frequency(forMidi: midi))
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Tuner").font(.title2.bold())
            meter
            readouts
            staff
            Text(instrument == .clarinet
                 ? "Shown as written for B♭ clarinet. Reference A = 440 Hz; compare the concert line to your tuner."
                 : "Reference A = 440 Hz, equal temperament. Compare to your tuner.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding(24)
        .frame(width: 520, height: 660)
        .task { await start() }
        .onDisappear { audio.stop(); audio.onSample = nil }
    }

    /// A mini staff showing the (written) note so the player can read it in
    /// context rather than decode a scientific-pitch name.
    private var staff: some View {
        let notes = reading.map { [ScoredNote(index: 0, target: $0.written)] } ?? []
        return StaffView(notes: notes, keySignature: KeySignature(elements: [], kind: .none),
                         noteValue: .quarter, height: 170)
    }

    // MARK: Meter

    private var meter: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let cents = Double(reading?.cents ?? 0)
            let inTune = abs(cents) <= 5
            let x = w / 2 + CGFloat(min(max(cents, -50), 50) / 50) * (w / 2 - 20)

            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(inTune && reading != nil ? Color.green.opacity(0.18) : Color(white: 0.5).opacity(0.12))
                    .animation(.easeOut(duration: 0.15), value: inTune)

                // Tick marks at -50, -25, 0, +25, +50.
                ForEach([-50, -25, 0, 25, 50], id: \.self) { tick in
                    let tx = w / 2 + CGFloat(Double(tick) / 50) * (w / 2 - 20)
                    Rectangle()
                        .fill(tick == 0 ? Color.primary.opacity(0.6) : Color.secondary.opacity(0.4))
                        .frame(width: tick == 0 ? 2 : 1, height: tick == 0 ? 90 : 60)
                        .position(x: tx, y: 52)
                }

                // Needle.
                if reading != nil {
                    Capsule()
                        .fill(inTune ? Color.green : (cents < 0 ? Color.blue : Color.orange))
                        .frame(width: 5, height: 100)
                        .position(x: x, y: 57)
                        .animation(.easeOut(duration: 0.12), value: x)
                }

                HStack {
                    Text("♭ flat").font(.caption2).foregroundStyle(.blue)
                    Spacer()
                    Text("in tune").font(.caption2).foregroundStyle(.green)
                    Spacer()
                    Text("sharp ♯").font(.caption2).foregroundStyle(.orange)
                }
                .padding(.horizontal, 14)
                .padding(.top, 112)
            }
        }
        .frame(height: 135)
    }

    // MARK: Readouts

    @ViewBuilder
    private var readouts: some View {
        if let r = reading {
            // The player reads the written note, so that's the headline; concert
            // is shown underneath for cross-checking against a standard tuner.
            VStack(spacing: 4) {
                Text("\(r.written.letter.name)\(r.written.accidental.symbol)\(r.written.octave)")
                    .font(.system(size: 56, weight: .bold).monospaced())
                    .foregroundStyle(abs(r.cents) <= 5 ? .green : .primary)
                Text(r.cents >= 0 ? "+\(r.cents)¢" : "\(r.cents)¢")
                    .font(.title3.monospaced())
                    .foregroundStyle(abs(r.cents) <= 5 ? .green : abs(r.cents) <= 20 ? .orange : .red)
                Text(instrument == .clarinet
                     ? "written · concert \(r.concert.letter.name)\(r.concert.accidental.symbol)\(r.concert.octave) · \(String(format: "%.1f Hz", r.hz))"
                     : "concert · \(String(format: "%.1f Hz", r.hz))")
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(spacing: 6) {
                Text("—").font(.system(size: 56, weight: .bold))
                Text("play or sing a steady note…").foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Audio

    private func start() async {
        guard await audio.requestPermission() else { return }
        audio.pitchFrequencyRange = (instrument.pitchMinFrequency, instrument.pitchMaxFrequency)
        audio.onSample = { sample in ingest(sample) }
        try? audio.start()
    }

    private func ingest(_ sample: PitchSample) {
        guard let frequency = sample.frequency, sample.clarity > 0.85, sample.rms > 0.02 else { return }
        let midi = Pitch.midi(forFrequency: frequency)
        smoothedMidi = smoothedMidi.map { $0 * 0.6 + midi * 0.4 } ?? midi
    }
}

#Preview {
    TunerView(instrument: .clarinet)
}
