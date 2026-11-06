import AVFoundation
import Foundation

/// A timestamped pitch measurement delivered from the capture stream.
struct PitchSample: Sendable {
    /// Seconds since capture started.
    let time: TimeInterval
    /// Detected sounding frequency in Hz, or nil when unvoiced.
    let frequency: Double?
    let clarity: Double
    let rms: Double
    /// Harmonic-number centroid (timbre brightness), nil when unvoiced.
    let brightness: Double?
    /// Odd/even harmonic energy ratio, nil when unvoiced.
    let oddEvenRatio: Double?
}

/// Owns streaming state across audio-thread callbacks. Marked `nonisolated` so
/// it can be driven from the real-time tap thread (this project defaults types
/// to the main actor); access is single-threaded through the serial tap.
nonisolated final class StreamingPitchProcessor: @unchecked Sendable {
    private let detector: PitchDetector
    private let sampleRate: Double
    private let windowSize: Int
    private let hopSize: Int
    private let emit: @Sendable (PitchSample) -> Void

    private var accumulator: [Float] = []
    private var processed: Int = 0

    init(detector: PitchDetector, sampleRate: Double, windowSize: Int, hopSize: Int,
         emit: @escaping @Sendable (PitchSample) -> Void) {
        self.detector = detector
        self.sampleRate = sampleRate
        self.windowSize = windowSize
        self.hopSize = hopSize
        self.emit = emit
    }

    func append(_ samples: [Float]) {
        accumulator.append(contentsOf: samples)
        while accumulator.count >= windowSize {
            let window = Array(accumulator[0..<windowSize])
            let estimate = detector.detect(window)
            let centerSample = processed + windowSize / 2
            emit(PitchSample(time: Double(centerSample) / sampleRate,
                             frequency: estimate.frequency,
                             clarity: estimate.clarity,
                             rms: estimate.rms,
                             brightness: estimate.brightness,
                             oddEvenRatio: estimate.oddEvenRatio))
            accumulator.removeFirst(hopSize)
            processed += hopSize
        }
    }
}

/// Wraps the record-to-disk file so the real-time tap can write to it off the
/// main actor. Single-threaded through the serial tap, like the processor.
nonisolated final class RecordingWriter: @unchecked Sendable {
    private let file: AVAudioFile
    init(file: AVAudioFile) { self.file = file }
    func write(_ buffer: AVAudioPCMBuffer) { try? file.write(from: buffer) }
}

/// Resets a published flag when audio playback finishes.
private final class PlaybackObserver: NSObject, AVAudioPlayerDelegate {
    let onFinish: @MainActor () -> Void
    init(onFinish: @escaping @MainActor () -> Void) { self.onFinish = onFinish }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in onFinish() }
    }
}

/// Captures microphone audio, runs YIN pitch detection on a sliding window,
/// records the take to a file for playback/export, and synthesizes metronome
/// clicks. Observable so SwiftUI can show a live meter and the detected note.
@MainActor
@Observable
final class AudioEngine {
    private(set) var isRunning = false
    private(set) var permissionDenied = false

    /// Live values for UI feedback (a simple tuner/meter).
    var latestLevel: Double = 0
    var latestFrequency: Double?

    /// The file written during the last take (for playback / save).
    private(set) var recordingURL: URL?
    private(set) var isPlayingRecording = false

    /// Called on the main actor for every analyzed window during capture.
    var onSample: ((PitchSample) -> Void)?

    /// Fundamental-frequency search bounds for the pitch tracker, set from the
    /// active instrument before `start()`. Defaults to the clarinet's range.
    var pitchFrequencyRange: (min: Double, max: Double) = (110, 2600)

    private let engine = AVAudioEngine()
    private let clickPlayer = AVAudioPlayerNode()
    private var processor: StreamingPitchProcessor?
    private var recordingWriter: RecordingWriter?
    private var clickAccent: AVAudioPCMBuffer?
    private var clickNormal: AVAudioPCMBuffer?
    private var clickConnected = false

    private var filePlayer: AVAudioPlayer?
    private var playbackObserver: PlaybackObserver?
    private var sectionStopTask: Task<Void, Never>?

    private let windowSize = 2048
    private let hopSize = 1024

    // MARK: Permission

    func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            permissionDenied = !granted
            return granted
        default:
            permissionDenied = true
            return false
        }
    }

    // MARK: Capture lifecycle

    func start() throws {
        guard !isRunning else { return }
        stopPlayback()

        let input = engine.inputNode
        let inputFormat = input.inputFormat(forBus: 0)
        let sampleRate = inputFormat.sampleRate > 0 ? inputFormat.sampleRate : 48000

        setUpClickPlayerIfNeeded()

        var detector = PitchDetector(sampleRate: sampleRate)
        detector.minFrequency = pitchFrequencyRange.min
        detector.maxFrequency = pitchFrequencyRange.max
        let processor = StreamingPitchProcessor(
            detector: detector, sampleRate: sampleRate,
            windowSize: windowSize, hopSize: hopSize
        ) { [weak self] sample in
            DispatchQueue.main.async { self?.deliver(sample) }
        }
        self.processor = processor

        // Record the take to a temp file for later playback / export.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tonika-take-\(UUID().uuidString).caf")
        let writer = (try? AVAudioFile(forWriting: url, settings: inputFormat.settings))
            .map(RecordingWriter.init)
        self.recordingWriter = writer
        self.recordingURL = writer == nil ? nil : url

        input.installTap(onBus: 0, bufferSize: AVAudioFrameCount(windowSize), format: inputFormat) { buffer, _ in
            writer?.write(buffer)
            processor.append(buffer.monoSamples())
        }

        engine.prepare()
        try engine.start()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        clickPlayer.stop()
        engine.stop()
        processor = nil
        recordingWriter = nil   // closes the file
        isRunning = false
        latestLevel = 0
        latestFrequency = nil
    }

    // MARK: Playback of the recorded take

    func playRecording() {
        guard let url = recordingURL else { return }
        stopPlayback()
        let observer = PlaybackObserver { [weak self] in self?.isPlayingRecording = false }
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.delegate = observer
        playbackObserver = observer
        filePlayer = player
        player.play()
        isPlayingRecording = true
    }

    /// Play just a slice of the recorded take — used to replay the section a
    /// coaching point refers to. Stops automatically after `duration`.
    func playRecording(from startTime: TimeInterval, duration: TimeInterval) {
        guard let url = recordingURL else { return }
        stopPlayback()
        let observer = PlaybackObserver { [weak self] in self?.isPlayingRecording = false }
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.delegate = observer
        playbackObserver = observer
        filePlayer = player
        player.currentTime = max(0, min(startTime, player.duration))
        player.play()
        isPlayingRecording = true

        sectionStopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            if self?.filePlayer === player { self?.stopPlayback() }
        }
    }

    func stopPlayback() {
        sectionStopTask?.cancel()
        sectionStopTask = nil
        filePlayer?.stop()
        filePlayer = nil
        isPlayingRecording = false
    }

    // MARK: Metronome

    /// Play a single click. `accent` marks the downbeat with a brighter tone.
    func playClick(accent: Bool) {
        guard let buffer = accent ? clickAccent : clickNormal, isRunning else { return }
        clickPlayer.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        if !clickPlayer.isPlaying { clickPlayer.play() }
    }

    // MARK: Internals

    private func deliver(_ sample: PitchSample) {
        latestLevel = min(1, sample.rms * 12)
        latestFrequency = sample.frequency
        onSample?(sample)
    }

    private func setUpClickPlayerIfNeeded() {
        guard !clickConnected else { return }
        engine.attach(clickPlayer)
        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        engine.connect(clickPlayer, to: engine.mainMixerNode, format: format)
        clickAccent = Self.makeClick(frequency: 1500, format: format)
        clickNormal = Self.makeClick(frequency: 1000, format: format)
        clickConnected = true
    }

    /// Build a short percussive click: a sine burst with a fast exponential decay.
    private static func makeClick(frequency: Double, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let frames = AVAudioFrameCount(sampleRate * 0.04)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let channels = buffer.floatChannelData else { return nil }
        buffer.frameLength = frames
        let channelCount = Int(format.channelCount)
        for frame in 0..<Int(frames) {
            let t = Double(frame) / sampleRate
            let envelope = exp(-t * 55)
            let value = Float(sin(2 * .pi * frequency * t) * envelope * 0.3)
            for channel in 0..<channelCount { channels[channel][frame] = value }
        }
        return buffer
    }
}

extension AVAudioPCMBuffer {
    /// First channel of the buffer as a plain Float array.
    nonisolated func monoSamples() -> [Float] {
        guard let channelData = floatChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: channelData[0], count: Int(frameLength)))
    }
}
