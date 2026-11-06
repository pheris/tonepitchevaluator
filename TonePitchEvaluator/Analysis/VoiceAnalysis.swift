import Foundation

// MARK: - Voice analysis

/// Voice-specific tone characterization, the singing counterpart to the
/// clarinet's `GearGuess`. All values are measured from the captured pitch
/// track and timbre descriptors; the range/voice-type come from a previously
/// measured `VoiceProfile` when available.
struct VoiceAnalysis: Codable, Sendable {
    /// Classified voice type (nil until a range has been measured).
    let voiceType: String?
    let rangeLowName: String?
    let rangeHighName: String?
    let rangeSemitones: Int?

    /// Vibrato rate in Hz (0 when none is detected) and its extent in cents.
    let vibratoRateHz: Double
    let vibratoExtentCents: Double

    /// 0…1 breathiness (airy vs. pressed), from tonal clarity.
    let breathiness: Double
    /// Harmonic-number centroid (brightness) and its warm inverse (0…1).
    let brightness: Double
    let warmth: Double
    /// 0…1 dynamic steadiness and mean tonal clarity, reused from the shared pass.
    let dynamicSteadiness: Double
    let meanClarity: Double
}

// MARK: - Analyzer

enum VoiceAnalyzer {
    /// Build a `VoiceAnalysis` from the voiced samples of a run plus any stored
    /// vocal-range profile. `meanClarity`, `brightness`, and `dynamicSteadiness`
    /// are passed in from `ToneAnalyzer`'s shared pass to avoid recomputing them.
    static func analyze(voiced: [CapturedSample],
                        profile: VoiceProfile?,
                        meanClarity: Double,
                        meanBrightness: Double,
                        dynamicSteadiness: Double) -> VoiceAnalysis {
        let (rate, extent) = vibrato(from: voiced)

        let breathiness = max(0, min(1, (0.97 - meanClarity) / 0.3))
        let warmth = max(0, min(1, 1 - (meanBrightness - 1) / 6))

        return VoiceAnalysis(
            voiceType: profile?.voiceType.rawValue,
            rangeLowName: profile?.lowName,
            rangeHighName: profile?.highName,
            rangeSemitones: profile?.rangeSemitones,
            vibratoRateHz: rate.rounded(to: 1),
            vibratoExtentCents: extent.rounded(to: 0),
            breathiness: breathiness.rounded(to: 2),
            brightness: meanBrightness.rounded(to: 2),
            warmth: warmth.rounded(to: 2),
            dynamicSteadiness: dynamicSteadiness.rounded(to: 2),
            meanClarity: meanClarity.rounded(to: 2)
        )
    }

    /// Estimate vibrato by detrending the pitch track (in cents) against a short
    /// moving average, then measuring the oscillation rate from zero crossings
    /// and the extent from its spread. Returns (rateHz, extentCents).
    private static func vibrato(from voiced: [CapturedSample]) -> (Double, Double) {
        let samples = voiced.sorted { $0.audioTime < $1.audioTime }
        guard samples.count >= 12 else { return (0, 0) }

        // Cents series relative to the first note, then detrended by a moving
        // average (~0.4 s) so slow drift between scale notes isn't mistaken for
        // vibrato.
        let cents = samples.map { $0.writtenMidi * 100 }
        let dt = medianDelta(samples.map(\.audioTime))
        guard dt > 0 else { return (0, 0) }
        let windowCount = max(3, Int((0.4 / dt).rounded()))

        var detrended = [Double](repeating: 0, count: cents.count)
        for i in cents.indices {
            let lo = max(0, i - windowCount / 2)
            let hi = min(cents.count - 1, i + windowCount / 2)
            let avg = cents[lo...hi].reduce(0, +) / Double(hi - lo + 1)
            detrended[i] = cents[i] - avg
        }

        // Spread: standard deviation → peak extent ≈ 2·σ·√2.
        let meanD = detrended.reduce(0, +) / Double(detrended.count)
        let variance = detrended.reduce(0) { $0 + ($1 - meanD) * ($1 - meanD) } / Double(detrended.count)
        let sigma = variance.squareRoot()
        let extent = sigma * 2 * 2.0.squareRoot()

        // Rate: half the zero-crossing count over the total duration.
        var crossings = 0
        for i in 1..<detrended.count where (detrended[i - 1] <= 0) != (detrended[i] <= 0) {
            crossings += 1
        }
        let duration = samples.last!.audioTime - samples.first!.audioTime
        let rate = duration > 0 ? (Double(crossings) / 2.0) / duration : 0

        // Only report a plausible singing vibrato (3–9 Hz, at least ~20 cents).
        guard extent >= 20, rate >= 3, rate <= 9 else { return (0, 0) }
        return (rate, extent)
    }

    private static func medianDelta(_ times: [TimeInterval]) -> TimeInterval {
        guard times.count >= 2 else { return 0 }
        var deltas: [TimeInterval] = []
        for i in 1..<times.count { deltas.append(times[i] - times[i - 1]) }
        deltas.sort()
        return deltas[deltas.count / 2]
    }
}

private extension Double {
    func rounded(to places: Int) -> Double {
        let factor = pow(10.0, Double(places))
        return (self * factor).rounded() / factor
    }
}
