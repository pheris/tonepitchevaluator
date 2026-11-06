import Foundation

/// The key signature for a scale: the ordered sharps or flats drawn once after
/// the clef, so individual notes don't each carry an accidental. Degrees that
/// fall outside the signature (e.g. the raised 7th of a harmonic minor) are
/// still drawn with an explicit accidental by the renderer.
struct KeySignature: Sendable, Equatable {
    enum Kind: Sendable { case sharps, flats, none }

    struct Element: Sendable, Equatable {
        let letter: NoteLetter
        let accidental: Accidental
    }

    /// Accidentals in conventional engraving order (left to right).
    let elements: [Element]
    let kind: Kind

    /// The accidental this signature applies to a given letter, if any.
    func accidental(for letter: NoteLetter) -> Accidental? {
        elements.first { $0.letter == letter }?.accidental
    }

    /// What this signature makes a bare letter sound like (natural if unlisted).
    func effectiveAccidental(for letter: NoteLetter) -> Accidental {
        accidental(for: letter) ?? .natural
    }

    // Canonical orders for sharps and flats.
    private static let sharpOrder: [NoteLetter] = [.f, .c, .g, .d, .a, .e, .b]
    private static let flatOrder: [NoteLetter] = [.b, .e, .a, .d, .g, .f, .c]

    // Conventional treble-clef octave for each accidental's glyph position.
    private static let sharpOctave: [NoteLetter: Int] = [.f: 5, .c: 5, .g: 5, .d: 5, .a: 4, .e: 5, .b: 4]
    private static let flatOctave: [NoteLetter: Int] = [.b: 4, .e: 5, .a: 4, .d: 5, .g: 4, .c: 5, .f: 4]

    /// Diatonic staff step where an element's glyph sits on the treble staff.
    func diatonicStep(for element: Element) -> Int {
        let table = kind == .sharps ? Self.sharpOctave : Self.flatOctave
        let octave = table[element.letter] ?? 4
        return octave * 7 + element.letter.rawValue
    }

    /// Derive the signature from a tonic and mode. Minor modes use the natural
    /// (relative-major) signature; harmonic/melodic alterations are rendered as
    /// accidentals on the notes themselves.
    static func forTonic(_ tonic: Tonic, isMinor: Bool) -> KeySignature {
        let pattern = (isMinor ? ScaleQuality.naturalMinor : ScaleQuality.major).ascendingSemitones
        let baseOctave = 4
        let tonicMidi = (baseOctave + 1) * 12 + tonic.letter.semitone + tonic.accidental.rawValue

        var byLetter: [NoteLetter: Accidental] = [:]
        for degree in 0..<7 {
            let letterRaw = tonic.letter.rawValue + degree
            let letter = NoteLetter(rawValue: letterRaw % 7)!
            let octave = baseOctave + letterRaw / 7
            let naturalMidi = (octave + 1) * 12 + letter.semitone
            if let accidental = Accidental(rawValue: tonicMidi + pattern[degree] - naturalMidi),
               accidental != .natural {
                byLetter[letter] = accidental
            }
        }

        guard !byLetter.isEmpty else { return KeySignature(elements: [], kind: .none) }
        let usesSharps = byLetter.values.contains { $0.rawValue > 0 }
        let order = usesSharps ? sharpOrder : flatOrder
        let elements = order.compactMap { letter in
            byLetter[letter].map { Element(letter: letter, accidental: $0) }
        }
        return KeySignature(elements: elements, kind: usesSharps ? .sharps : .flats)
    }
}

extension Scale {
    var keySignature: KeySignature {
        KeySignature.forTonic(tonic, isMinor: quality != .major)
    }
}
