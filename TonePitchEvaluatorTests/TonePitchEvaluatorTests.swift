import Testing
import Foundation
@testable import TonePitchEvaluator

/// Behavior tests for the YIN pitch detector, driven by synthesized signals so
/// detection accuracy is verified without a microphone.
@MainActor
struct PitchDetectorTests {

    private func sine(_ frequency: Double, sampleRate: Double, count: Int, amplitude: Float = 0.5) -> [Float] {
        (0..<count).map { amplitude * Float(sin(2 * .pi * frequency * Double($0) / sampleRate)) }
    }

    @Test func detectsPureToneWithinAFewCents() {
        let sr = 48_000.0
        let detector = PitchDetector(sampleRate: sr)
        for target in [147.0, 220.0, 440.0, 880.0] {       // D3, A3, A4, A5
            let estimate = detector.detect(sine(target, sampleRate: sr, count: 2048))
            let frequency = try? #require(estimate.frequency)
            if let frequency {
                let cents = abs(1200 * log2(frequency / target))
                #expect(cents < 15)                        // within ~15 cents
            }
            #expect(estimate.clarity > 0.8)
        }
    }

    @Test func silenceIsUnvoiced() {
        let detector = PitchDetector(sampleRate: 48_000)
        let estimate = detector.detect([Float](repeating: 0, count: 2048))
        #expect(estimate.frequency == nil)
    }

    @Test func quietNoiseIsRejected() {
        let detector = PitchDetector(sampleRate: 48_000)
        var generator = SystemRandomNumberGenerator()
        let noise = (0..<2048).map { _ in Float.random(in: -0.005...0.005, using: &generator) }
        let estimate = detector.detect(noise)
        #expect(estimate.frequency == nil)                 // below the silence floor
    }

    @Test func detectedPitchIsStableAcrossWindows() {
        let sr = 48_000.0
        let detector = PitchDetector(sampleRate: sr)
        let a = detector.detect(sine(440, sampleRate: sr, count: 2048))
        let b = detector.detect(sine(440, sampleRate: sr, count: 2048, amplitude: 0.3))
        if let fa = a.frequency, let fb = b.frequency {
            #expect(abs(fa - fb) < 1)                      // amplitude shouldn't shift pitch
        }
    }

    /// Clarinet-like tone: strong odd harmonics, weak fundamental & evens.
    private func clarinetTone(_ f0: Double, sampleRate: Double, count: Int) -> [Float] {
        let partials: [(Int, Double)] = [(1, 0.5), (3, 1.0), (5, 0.6), (7, 0.35), (9, 0.2), (11, 0.12)]
        return (0..<count).map { i in
            let t = Double(i) / sampleRate
            var s = 0.0
            for (h, a) in partials where Double(h) * f0 < sampleRate / 2 {
                s += a * sin(2 * .pi * f0 * Double(h) * t)
            }
            return Float(s * 0.25)
        }
    }

    /// The whole clarinet written range (E3→high F) must read back to the right
    /// written note — no octave errors — once the B♭ transposition is applied.
    @Test func clarinetWrittenRangeReadsBackCorrectly() {
        let sr = 48_000.0
        let detector = PitchDetector(sampleRate: sr)
        for written in stride(from: 52, through: 89, by: 1) {
            let soundingFreq = Pitch.frequency(forMidi: Double(written - Clarinet.transposition))
            let estimate = detector.detect(clarinetTone(soundingFreq, sampleRate: sr, count: 2048))
            let frequency = try? #require(estimate.frequency)
            if let frequency {
                let readWritten = Pitch.midi(forFrequency: frequency) + Double(Clarinet.transposition)
                #expect(Int(readWritten.rounded()) == written)          // correct note, no octave slip
                #expect(abs(readWritten - Double(written)) < 0.25)       // within a quarter-tone
            }
        }
    }
}
