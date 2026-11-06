import SwiftUI
import AVFoundation

// MARK: - Calibration run

struct CalibrationResult: Identifiable {
    let id = UUID()
    let writtenMidi: Int
    let detectedWrittenMidi: Int?
    let cents: Int?

    var expectedName: String { SpelledPitch.nearestSpelling(forMidi: writtenMidi, preferSharps: true).name }
    var detectedName: String? { detectedWrittenMidi.map { SpelledPitch.nearestSpelling(forMidi: $0, preferSharps: true).name } }
    /// Correct note within a quarter-tone — the detector read what was played.
    var ok: Bool { detectedWrittenMidi == writtenMidi && (cents.map { abs($0) <= 35 } ?? false) }
}

/// Plays a clarinet scale through the built-in sampler and runs the same YIN
/// detector on the rendered audio, so detection can be verified end-to-end
/// (including the B♭ transposition) without a microphone.
@MainActor
@Observable
final class DetectorCalibration {
    private(set) var results: [CalibrationResult] = []
    private(set) var isRunning = false
    private(set) var currentWrittenMidi: Int?

    /// Lowest written E3 (52) up to high F above the staff (written F6, 89).
    let lowestWritten = 52
    let highestWritten = 89

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var connected = false

    func run() async {
        guard !isRunning else { return }
        isRunning = true
        results = []

        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        let sampleRate = format.sampleRate > 0 ? format.sampleRate : 48_000
        if !connected {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            connected = true
        }
        let audible = (try? engine.start()) != nil
        if audible { player.play() }

        let detector = PitchDetector(sampleRate: sampleRate)

        for written in lowestWritten...highestWritten {
            if Task.isCancelled { break }
            currentWrittenMidi = written
            // A real clarinet sounds a major second below the written note.
            let soundingFreq = Pitch.frequency(forMidi: Double(written - Clarinet.transposition))
            let buffer = Self.clarinetBuffer(soundingFreq: soundingFreq, format: format, seconds: 0.5)

            // Detect directly on the generated audio (deterministic, no mic).
            let detected = detector.detect(Self.midWindow(of: buffer))
            if let freq = detected.frequency, detected.clarity > 0.6 {
                let detectedWritten = Pitch.midi(forFrequency: freq) + Double(Clarinet.transposition)
                let rounded = Int(detectedWritten.rounded())
                let cents = Int(((detectedWritten - Double(written)) * 100).rounded())
                results.append(CalibrationResult(writtenMidi: written, detectedWrittenMidi: rounded, cents: cents))
            } else {
                results.append(CalibrationResult(writtenMidi: written, detectedWrittenMidi: nil, cents: nil))
            }

            if audible { player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil) }
            try? await Task.sleep(for: .milliseconds(audible ? 420 : 40))
        }

        player.stop()
        engine.stop()
        currentWrittenMidi = nil
        isRunning = false
    }

    var passCount: Int { results.filter(\.ok).count }

    /// A short clarinet-like tone (strong odd harmonics) with a soft envelope.
    private static func clarinetBuffer(soundingFreq: Double, format: AVAudioFormat, seconds: Double) -> AVAudioPCMBuffer {
        let sr = format.sampleRate
        let frames = AVAudioFrameCount(sr * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let partials: [(Double, Double)] = [(1, 0.5), (3, 1.0), (5, 0.6), (7, 0.35), (9, 0.2), (11, 0.12)]
        guard let channels = buffer.floatChannelData else { return buffer }
        for i in 0..<Int(frames) {
            let t = Double(i) / sr
            var s = 0.0
            for (h, a) in partials where h * soundingFreq < sr / 2 { s += a * sin(2 * .pi * soundingFreq * h * t) }
            let env = min(1, t / 0.03) * min(1, max(0, (seconds - t)) / 0.05)
            let v = Float(s * 0.12 * env)
            for c in 0..<Int(format.channelCount) { channels[c][i] = v }
        }
        return buffer
    }

    /// A 2048-sample window from the middle of a buffer for detection.
    private static func midWindow(of buffer: AVAudioPCMBuffer) -> [Float] {
        let mono = buffer.monoSamples()
        guard mono.count >= 2048 else { return mono }
        let mid = mono.count / 2
        return Array(mono[(mid - 1024)..<(mid + 1024)])
    }
}

// MARK: - View

struct DetectorCalibrationView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var calibration = DetectorCalibration()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Detector calibration").font(.title2.bold())
            Text("Plays a clarinet scale (lowest E3 up to high F) through the built-in sampler and checks that the detector reads each written note back correctly, including the B♭ transposition.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !calibration.results.isEmpty {
                Text("\(calibration.passCount) of \(calibration.results.count) read correctly")
                    .font(.headline)
                    .foregroundStyle(calibration.passCount == calibration.results.count ? .green : .orange)
            }

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(calibration.results) { row in
                        HStack {
                            Image(systemName: row.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(row.ok ? .green : .red)
                            Text(row.expectedName)
                                .frame(width: 60, alignment: .leading)
                                .font(.callout.monospaced())
                            Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                            Text(row.detectedName ?? "no read")
                                .frame(width: 70, alignment: .leading)
                                .font(.callout.monospaced())
                                .foregroundStyle(row.detectedName == nil ? .red : .primary)
                            if let cents = row.cents {
                                Text(cents >= 0 ? "+\(cents)¢" : "\(cents)¢")
                                    .font(.caption.monospaced()).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 1)
                    }
                }
            }
            .frame(minHeight: 240)

            HStack {
                if calibration.isRunning { ProgressView().controlSize(.small) }
                Button(calibration.isRunning ? "Running…" : "Run again") {
                    Task { await calibration.run() }
                }
                .disabled(calibration.isRunning)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460, height: 560)
        .task { await calibration.run() }
    }
}
