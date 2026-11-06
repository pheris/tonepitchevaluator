import Foundation

/// A single fundamental-frequency estimate for a window of audio, plus a few
/// cheap timbre descriptors derived from its harmonic structure.
struct PitchEstimate: Sendable {
    /// Detected frequency in Hz, or nil when the window is unvoiced/too noisy.
    let frequency: Double?
    /// 0...1 periodicity confidence (1 = perfectly periodic).
    let clarity: Double
    /// Root-mean-square level of the window (rough loudness).
    let rms: Double
    /// Spectral centroid expressed in harmonic number (1 = energy all in the
    /// fundamental, higher = brighter). nil when unvoiced.
    let brightness: Double?
    /// Energy in odd harmonics divided by energy in even harmonics. The B♭
    /// clarinet's cylindrical bore favors odd harmonics, especially low down.
    let oddEvenRatio: Double?

    static let unvoiced = PitchEstimate(frequency: nil, clarity: 0, rms: 0, brightness: nil, oddEvenRatio: nil)
}

/// Monophonic pitch tracker using the YIN algorithm
/// (de Cheveigné & Kawahara, 2002). Pure value type with no shared state, so a
/// window can be analyzed directly on the audio thread.
struct PitchDetector {
    var sampleRate: Double
    /// YIN absolute threshold; lower is stricter about periodicity.
    var threshold: Double = 0.12
    /// Frequency search bounds. Clarinet concert pitch spans ~147 Hz (D3) to
    /// ~1865 Hz (B♭6); the margins give the tracker room around those.
    var minFrequency: Double = 110
    var maxFrequency: Double = 2600
    /// Reject windows quieter than this RMS (breaths, room noise, faint
    /// metronome bleed). A clarinet into the mic sits well above this.
    var silenceFloor: Double = 0.02

    nonisolated func detect(_ samples: [Float]) -> PitchEstimate {
        let n = samples.count
        var sumSquares = 0.0
        for s in samples { sumSquares += Double(s) * Double(s) }
        let rms = (sumSquares / Double(max(n, 1))).squareRoot()

        guard rms >= silenceFloor else {
            return PitchEstimate(frequency: nil, clarity: 0, rms: rms, brightness: nil, oddEvenRatio: nil)
        }

        let tauMax = min(n / 2, Int(sampleRate / minFrequency))
        let tauMin = max(2, Int(sampleRate / maxFrequency))
        guard tauMax > tauMin + 2 else {
            return PitchEstimate(frequency: nil, clarity: 0, rms: rms, brightness: nil, oddEvenRatio: nil)
        }

        // Difference function d(tau).
        var d = [Double](repeating: 0, count: tauMax)
        for tau in 1..<tauMax {
            var sum = 0.0
            let limit = n - tau
            var i = 0
            while i < limit {
                let delta = Double(samples[i]) - Double(samples[i + tau])
                sum += delta * delta
                i += 1
            }
            d[tau] = sum
        }

        // Cumulative mean normalized difference d'(tau).
        var dPrime = [Double](repeating: 1, count: tauMax)
        var runningSum = 0.0
        for tau in 1..<tauMax {
            runningSum += d[tau]
            dPrime[tau] = runningSum > 0 ? d[tau] * Double(tau) / runningSum : 1
        }

        // Absolute threshold: first dip below threshold, descended to its local min.
        var tauEstimate = -1
        var tau = tauMin
        while tau < tauMax {
            if dPrime[tau] < threshold {
                while tau + 1 < tauMax && dPrime[tau + 1] < dPrime[tau] { tau += 1 }
                tauEstimate = tau
                break
            }
            tau += 1
        }

        if tauEstimate == -1 {
            // No clear period: take the global minimum but demand some periodicity.
            var best = tauMin
            var bestValue = dPrime[tauMin]
            for t in (tauMin + 1)..<tauMax where dPrime[t] < bestValue {
                bestValue = dPrime[t]
                best = t
            }
            if bestValue > 0.55 {
                return PitchEstimate(frequency: nil, clarity: max(0, 1 - bestValue), rms: rms, brightness: nil, oddEvenRatio: nil)
            }
            tauEstimate = best
        }

        let refined = parabolicRefine(dPrime, around: tauEstimate)
        let frequency = sampleRate / refined
        let clarity = max(0, 1 - dPrime[tauEstimate])
        guard frequency >= minFrequency, frequency <= maxFrequency else {
            return PitchEstimate(frequency: nil, clarity: clarity, rms: rms, brightness: nil, oddEvenRatio: nil)
        }

        let timbre = harmonicTimbre(samples, fundamental: frequency)
        return PitchEstimate(frequency: frequency, clarity: clarity, rms: rms,
                             brightness: timbre.brightness, oddEvenRatio: timbre.oddEvenRatio)
    }

    /// Measure the amplitude of the first several harmonics with the Goertzel
    /// algorithm (cheap, and we already know the fundamental), then summarize as
    /// a brightness (harmonic-number centroid) and an odd/even energy ratio.
    nonisolated private func harmonicTimbre(_ samples: [Float], fundamental f0: Double) -> (brightness: Double?, oddEvenRatio: Double?) {
        let nyquist = sampleRate / 2
        let maxHarmonic = min(12, Int(nyquist / f0))
        guard maxHarmonic >= 2 else { return (nil, nil) }

        var amplitudes = [Double](repeating: 0, count: maxHarmonic + 1)
        for h in 1...maxHarmonic {
            amplitudes[h] = goertzelMagnitude(samples, frequency: f0 * Double(h))
        }

        let total = amplitudes.reduce(0, +)
        guard total > 0 else { return (nil, nil) }

        var centroid = 0.0
        var oddEnergy = 0.0
        var evenEnergy = 0.0
        for h in 1...maxHarmonic {
            centroid += Double(h) * amplitudes[h]
            if h.isMultiple(of: 2) { evenEnergy += amplitudes[h] } else { oddEnergy += amplitudes[h] }
        }
        let brightness = centroid / total
        let oddEven = oddEnergy / max(evenEnergy, total * 0.001)
        return (brightness, oddEven)
    }

    /// Goertzel magnitude of one frequency bin over the window.
    nonisolated private func goertzelMagnitude(_ samples: [Float], frequency: Double) -> Double {
        let omega = 2 * Double.pi * frequency / sampleRate
        let coeff = 2 * cos(omega)
        var s1 = 0.0
        var s2 = 0.0
        for sample in samples {
            let s0 = Double(sample) + coeff * s1 - s2
            s2 = s1
            s1 = s0
        }
        let power = s1 * s1 + s2 * s2 - coeff * s1 * s2
        return power > 0 ? power.squareRoot() : 0
    }

    /// Sub-sample refinement of the period via parabolic interpolation.
    nonisolated private func parabolicRefine(_ d: [Double], around tau: Int) -> Double {
        guard tau > 0, tau < d.count - 1 else { return Double(tau) }
        let x0 = d[tau - 1], x1 = d[tau], x2 = d[tau + 1]
        let denom = 2 * (x0 - 2 * x1 + x2)
        guard denom != 0 else { return Double(tau) }
        return Double(tau) + (x0 - x2) / denom
    }
}
