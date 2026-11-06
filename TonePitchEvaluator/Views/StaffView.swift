import SwiftUI

/// Renders a scale as treble-clef sheet music with live per-note feedback:
/// tempo-based notehead coloring (rainbow / green / yellow / gray), translucent
/// "shadow" notes for wrong pitches, and sub-semitone intonation nudges.
struct StaffView: View {
    let notes: [ScoredNote]
    /// Index of the note currently being played, for the playback cursor.
    var currentIndex: Int? = nil
    /// Drawn once after the clef; notes rely on it instead of inline accidentals.
    var keySignature = KeySignature(elements: [], kind: .none)
    /// Rhythmic value, which decides the notehead (hollow vs. filled) and the
    /// number of flags drawn on each stem.
    var noteValue: NoteValue = .quarter
    /// When true, a one-bar rest is drawn before the notes as a tempo lead-in.
    var leadInRestMeasure: Bool = false
    /// Current beat (0..<4) of the lead-in, highlighted by the cursor; nil otherwise.
    var leadInBeat: Int? = nil

    private let beatsPerMeasure = 4

    /// Hollow noteheads for whole/half notes.
    private var filledHead: Bool { noteValue.beats < 2 }
    /// Whole notes carry no stem.
    private var hasStem: Bool { noteValue != .whole }
    /// Flags for note values shorter than a quarter.
    private var flagCount: Int {
        switch noteValue {
        case .eighth: return 1
        case .sixteenth: return 2
        case .thirtySecond: return 3
        default: return 0
        }
    }

    // Layout constants.
    private let space: CGFloat = 15          // vertical gap between staff lines
    private let noteSpacing: CGFloat = 56
    private let clefCenterX: CGFloat = 48
    private let keySigStartX: CGFloat = 74
    private let trailingPad: CGFloat = 44
    var height: CGFloat = 320

    // Staff line positions as diatonic steps (E4 G4 B4 D5 F5). B4 (34) is center.
    private let lineSteps = [30, 32, 34, 36, 38]
    private let centerStep = 34

    private var accidentalSpacing: CGFloat { space * 1.25 }
    private var keySigWidth: CGFloat { CGFloat(keySignature.elements.count) * accidentalSpacing }
    private let timeSigWidth: CGFloat = 26
    private var timeSigCenterX: CGFloat { keySigStartX + keySigWidth + 8 + timeSigWidth / 2 }
    /// X where the staff content begins, after the clef, key signature, and meter.
    private var notesLeft: CGFloat { keySigStartX + keySigWidth + 8 + timeSigWidth + 16 }
    /// Width reserved for the one-bar rest lead-in (zero when not shown).
    private var leadInWidth: CGFloat { leadInRestMeasure ? CGFloat(notesPerMeasure) * noteSpacing : 0 }
    /// X where the first *note* sits, after any lead-in bar.
    private var notesOriginX: CGFloat { notesLeft + leadInWidth }

    private var contentWidth: CGFloat {
        notesOriginX + CGFloat(max(notes.count, 1)) * noteSpacing + trailingPad
    }

    private var needsAnimation: Bool {
        currentIndex != nil || notes.contains { $0.highlight == .rainbow }
    }

    // Scroll state, for showing/driving the edge arrows when the scale is wider
    // than the viewport.
    @State private var scrollPosition = ScrollPosition(edge: .leading)
    @State private var metrics = ScrollMetrics()

    private struct ScrollMetrics: Equatable {
        var offsetX: CGFloat = 0
        var content: CGFloat = 0
        var container: CGFloat = 0
    }

    private var canScrollLeft: Bool { metrics.offsetX > 1 }
    private var canScrollRight: Bool { metrics.content - (metrics.offsetX + metrics.container) > 1 }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !needsAnimation)) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                Canvas { context, size in
                    draw(&context, size: size, time: time)
                }
                .frame(width: contentWidth, height: height)
            }
        }
        .scrollPosition($scrollPosition)
        .onScrollGeometryChange(for: ScrollMetrics.self) { geo in
            ScrollMetrics(offsetX: geo.contentOffset.x,
                          content: geo.contentSize.width,
                          container: geo.containerSize.width)
        } action: { _, newValue in
            metrics = newValue
        }
        .onChange(of: currentIndex) { _, new in
            followCursor(new)
        }
        .frame(height: height)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(alignment: .leading) {
            if canScrollLeft { scrollArrow(.leading) }
        }
        .overlay(alignment: .trailing) {
            if canScrollRight { scrollArrow(.trailing) }
        }
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.black.opacity(0.08)))
    }

    /// Keep the current note on screen as playback advances left → right,
    /// holding the cursor ~40% from the left so upcoming notes stay visible.
    private func followCursor(_ index: Int?) {
        guard metrics.container > 0 else { return }
        guard let index else {
            withAnimation(.easeInOut(duration: 0.3)) { scrollPosition.scrollTo(x: 0) }
            return
        }
        let maxOffset = max(metrics.content - metrics.container, 0)
        let target = min(max(xPos(forIndex: index) - metrics.container * 0.4, 0), maxOffset)
        withAnimation(.easeInOut(duration: 0.25)) { scrollPosition.scrollTo(x: target) }
    }

    /// A tappable edge arrow that pages the staff left or right.
    private func scrollArrow(_ edge: HorizontalEdge) -> some View {
        let isTrailing = edge == .trailing
        return Button {
            let page = max(metrics.container * 0.8, noteSpacing)
            let target = isTrailing
                ? min(metrics.offsetX + page, metrics.content - metrics.container)
                : max(metrics.offsetX - page, 0)
            withAnimation(.easeInOut(duration: 0.25)) {
                scrollPosition.scrollTo(x: target)
            }
        } label: {
            Image(systemName: isTrailing ? "chevron.right" : "chevron.left")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.black.opacity(0.8))
                .frame(width: 32, height: 50)
                .glassEffect(.regular.interactive(), in: .capsule)
                .padding(isTrailing ? .trailing : .leading, 8)
        }
        .buttonStyle(.plain)
        .help(isTrailing ? "Scroll to see more notes" : "Scroll back")
    }

    // MARK: Geometry

    private func yPos(forStep step: Double, in size: CGSize) -> CGFloat {
        size.height / 2 - CGFloat(step - Double(centerStep)) * (space / 2)
    }

    private func xPos(forIndex index: Int) -> CGFloat {
        notesOriginX + CGFloat(index) * noteSpacing + noteSpacing / 2
    }

    // MARK: Drawing

    private func draw(_ context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        drawStaffLines(&context, size: size)
        drawBarlines(&context, size: size)
        drawClef(&context, size: size)
        drawKeySignature(&context, size: size)
        drawTimeSignature(&context, size: size)
        drawLeadIn(&context, size: size)

        if let current = currentIndex, notes.indices.contains(current) {
            drawCursor(atX: xPos(forIndex: current), in: &context, size: size)
        }

        for note in notes {
            drawNote(note, in: &context, size: size, time: time)
        }
        drawStemsAndBeams(in: &context, size: size)
    }

    /// The translucent playback cursor highlight at a given x.
    private func drawCursor(atX x: CGFloat, in context: inout GraphicsContext, size: CGSize) {
        let top = yPos(forStep: 44, in: size)
        let bottom = yPos(forStep: 20, in: size)
        let bar = Path(roundedRect: CGRect(x: x - 16, y: top, width: 32, height: bottom - top), cornerRadius: 8)
        context.fill(bar, with: .color(.accentColor.opacity(0.14)))
    }

    /// Draw the one-bar rest lead-in: a whole-measure rest, and the cursor
    /// stepping across it beat by beat during the lead-in.
    private func drawLeadIn(_ context: inout GraphicsContext, size: CGSize) {
        guard leadInRestMeasure else { return }

        if let beat = leadInBeat {
            let fraction = (CGFloat(beat) + 0.5) / CGFloat(beatsPerMeasure)
            drawCursor(atX: notesLeft + fraction * leadInWidth, in: &context, size: size)
        }

        // Whole-measure rest: a filled block hanging under the 4th staff line (D5).
        let restW = space * 1.5, restH = space * 0.55
        let cx = notesLeft + leadInWidth / 2
        let lineY = yPos(forStep: 36, in: size)
        context.fill(Path(CGRect(x: cx - restW / 2, y: lineY, width: restW, height: restH)),
                     with: .color(.black.opacity(0.75)))
    }

    /// Notes that fill one 4/4 measure at the current note value.
    private var notesPerMeasure: Int {
        max(1, Int((4.0 / noteValue.beats).rounded()))
    }

    /// Vertical barlines at each measure boundary, plus a heavier final barline.
    private func drawBarlines(_ context: inout GraphicsContext, size: CGSize) {
        let topY = yPos(forStep: Double(lineSteps.last!), in: size)      // top line (F5)
        let bottomY = yPos(forStep: Double(lineSteps.first!), in: size)  // bottom line (E4)

        func bar(atX x: CGFloat, heavy: Bool) {
            var path = Path()
            path.move(to: CGPoint(x: x, y: topY))
            path.addLine(to: CGPoint(x: x, y: bottomY))
            context.stroke(path, with: .color(.black.opacity(0.55)), lineWidth: heavy ? 2.6 : 1)
        }

        // Barline closing the lead-in rest bar.
        if leadInRestMeasure { bar(atX: notesOriginX, heavy: false) }

        var i = notesPerMeasure
        while i < notes.count {
            bar(atX: notesOriginX + CGFloat(i) * noteSpacing, heavy: false)
            i += notesPerMeasure
        }
        bar(atX: notesOriginX + CGFloat(notes.count) * noteSpacing, heavy: true)
    }

    private func drawStaffLines(_ context: inout GraphicsContext, size: CGSize) {
        for step in lineSteps {
            let y = yPos(forStep: Double(step), in: size)
            var path = Path()
            path.move(to: CGPoint(x: 18, y: y))
            path.addLine(to: CGPoint(x: contentWidth - 18, y: y))
            context.stroke(path, with: .color(.black.opacity(0.55)), lineWidth: 1)
        }
    }

    private func drawClef(_ context: inout GraphicsContext, size: CGSize) {
        let clef = Text("\u{1D11E}")   // 𝄞 treble clef
            .font(.custom("Palatino", size: space * 7.2))
            .foregroundStyle(.black)
        context.draw(clef, at: CGPoint(x: clefCenterX, y: yPos(forStep: 33.5, in: size)), anchor: .center)
    }

    private func drawTimeSignature(_ context: inout GraphicsContext, size: CGSize) {
        func numeral(_ s: String, atStep step: Double) {
            let text = Text(s)
                .font(.custom("Palatino", size: space * 2.7).weight(.bold))
                .foregroundStyle(.black)
            context.draw(text, at: CGPoint(x: timeSigCenterX, y: yPos(forStep: step, in: size)), anchor: .center)
        }
        numeral("4", atStep: 36)   // beats per bar, upper half
        numeral("4", atStep: 32)   // beat unit, lower half
    }

    private func drawKeySignature(_ context: inout GraphicsContext, size: CGSize) {
        for (i, element) in keySignature.elements.enumerated() {
            let x = keySigStartX + CGFloat(i) * accidentalSpacing + accidentalSpacing / 2
            let y = yPos(forStep: Double(keySignature.diatonicStep(for: element)), in: size)
            drawAccidental(element.accidental.symbol, at: CGPoint(x: x, y: y), color: .black, in: &context)
        }
    }

    private func drawNote(_ note: ScoredNote, in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let x = xPos(forIndex: note.index)
        let baseStep = Double(note.target.diatonicStep)
        let y = yPos(forStep: baseStep + note.microShiftSteps, in: size)

        drawLedgerLines(forStep: note.target.diatonicStep, x: x, in: &context, size: size)

        // Target notehead, colored by tempo accuracy.
        let pulsing = note.highlight == .rainbow
        let scale = pulsing ? 1.0 + 0.09 * sin(time * 6) : 1.0
        drawNotehead(at: CGPoint(x: x, y: y), highlight: note.highlight, time: time, scale: scale, filled: filledHead, in: &context)

        // Accidental only when it differs from what the key signature implies for
        // this letter (e.g. a raised 7th in harmonic/melodic minor, or a natural
        // that cancels a signature sharp/flat).
        if note.target.accidental != keySignature.effectiveAccidental(for: note.target.letter) {
            drawAccidental(note.target.accidental.explicitSymbol, at: CGPoint(x: x - space * 1.5, y: y), color: .black, in: &context)
        }

        // Intonation arrow for small (sub-semitone) errors.
        if note.shadowPitch == nil, let cents = note.centsOff, abs(cents) > Scoring.onPitchCents {
            let up = cents > 0
            let arrow = Text(up ? "\u{25B2}" : "\u{25BC}")
                .font(.system(size: space * 0.8))
                .foregroundStyle(up ? Color.orange : Color.blue)
            context.draw(arrow, at: CGPoint(x: x + space * 1.4, y: y), anchor: .center)
        }

        // Shadow note: the pitch the player actually produced, when it's clearly
        // a different note than written.
        if let shadow = note.shadowPitch {
            drawShadowNote(shadow, column: x, targetY: y, in: &context, size: size)
        }
    }

    private func drawLedgerLines(forStep step: Int, x: CGFloat, in context: inout GraphicsContext, size: CGSize) {
        let halfWidth = space * 1.25
        func line(atStep s: Int) {
            let y = yPos(forStep: Double(s), in: size)
            var path = Path()
            path.move(to: CGPoint(x: x - halfWidth, y: y))
            path.addLine(to: CGPoint(x: x + halfWidth, y: y))
            context.stroke(path, with: .color(.black.opacity(0.55)), lineWidth: 1)
        }
        if step <= 28 {
            for s in stride(from: 28, through: step, by: -2) { line(atStep: s) }
        } else if step >= 40 {
            for s in stride(from: 40, through: step, by: 2) { line(atStep: s) }
        }
    }

    private func drawNotehead(at point: CGPoint, highlight: NoteHighlight, time: TimeInterval, scale: CGFloat, filled: Bool, in context: inout GraphicsContext) {
        let w = space * 1.32 * scale
        let h = space * 0.98 * scale
        let rect = CGRect(x: point.x - w / 2, y: point.y - h / 2, width: w, height: h)
        let path = Path(ellipseIn: rect)

        defer {
            // Hollow it out for whole/half notes by punching a white center,
            // leaving a colored ring that still carries the feedback color.
            if !filled {
                let inner = rect.insetBy(dx: w * 0.24, dy: h * 0.30)
                context.fill(Path(ellipseIn: inner), with: .color(.white))
            }
        }

        switch highlight {
        case .rainbow:
            // Flashy animated rainbow: rotate the hue wheel over time, with a
            // soft translucent glow behind the head. No context-wide filters —
            // those would bleed into every subsequent draw call.
            let base = time.truncatingRemainder(dividingBy: 1.0)
            let colors = (0...6).map { i -> Color in
                Color(hue: (base + Double(i) / 7.0).truncatingRemainder(dividingBy: 1.0), saturation: 0.9, brightness: 1.0)
            }
            let glow = Path(ellipseIn: rect.insetBy(dx: -6, dy: -6))
            context.fill(glow, with: .radialGradient(Gradient(colors: [colors[0].opacity(0.5), .clear]),
                                                      center: point, startRadius: 0, endRadius: w))
            context.fill(path, with: .linearGradient(Gradient(colors: colors + [colors[0]]),
                                                      startPoint: CGPoint(x: rect.minX, y: rect.minY),
                                                      endPoint: CGPoint(x: rect.maxX, y: rect.maxY)))
        case .green:
            context.fill(path, with: .color(Color(red: 0.16, green: 0.72, blue: 0.35)))
        case .yellow:
            context.fill(path, with: .color(Color(red: 0.98, green: 0.80, blue: 0.10)))
        case .gray:
            context.fill(path, with: .color(Color(white: 0.80)))
        case .neutral:
            context.fill(path, with: .color(.black))
        }
    }

    // Stem/beam layout constants.
    private var headHalf: CGFloat { space * 0.66 }
    private var stemLength: CGFloat { space * 3.3 }
    private let stemColor = Color.black.opacity(0.7)

    /// Draw every note's stem, beaming runs of eighths and shorter together the
    /// way they'd be engraved (one group per beat), and flagging any leftover
    /// single short note. Whole notes get nothing; half/quarter get plain stems.
    private func drawStemsAndBeams(in context: inout GraphicsContext, size: CGSize) {
        guard hasStem else { return }
        guard flagCount > 0 else {
            for note in notes { drawSingleStem(note, flags: 0, in: &context, size: size) }
            return
        }
        // One beam group per beat: 2 eighths, 4 sixteenths, 8 thirty-seconds.
        let groupSize = max(2, Int((1.0 / noteValue.beats).rounded()))
        var i = 0
        while i < notes.count {
            let group = Array(notes[i..<min(i + groupSize, notes.count)])
            if group.count == 1 {
                drawSingleStem(group[0], flags: flagCount, in: &context, size: size)
            } else {
                drawBeamedGroup(group, in: &context, size: size)
            }
            i += groupSize
        }
    }

    private func noteY(_ note: ScoredNote, in size: CGSize) -> CGFloat {
        yPos(forStep: Double(note.target.diatonicStep) + note.microShiftSteps, in: size)
    }

    private func drawSingleStem(_ note: ScoredNote, flags: Int, in context: inout GraphicsContext, size: CGSize) {
        let x = xPos(forIndex: note.index)
        let y = noteY(note, in: size)
        let up = Double(note.target.diatonicStep) < Double(centerStep)
        let stemX = up ? x + headHalf : x - headHalf
        let endY = up ? y - stemLength : y + stemLength

        var path = Path()
        path.move(to: CGPoint(x: stemX, y: y))
        path.addLine(to: CGPoint(x: stemX, y: endY))
        context.stroke(path, with: .color(stemColor), lineWidth: 1.6)

        // Flags only for an isolated short note (runs are beamed instead).
        let dir: CGFloat = up ? 1 : -1
        for i in 0..<flags {
            let fy = endY + CGFloat(i) * space * 0.9 * dir
            var flag = Path()
            flag.move(to: CGPoint(x: stemX, y: fy))
            flag.addQuadCurve(
                to: CGPoint(x: stemX + space * 1.1 * dir, y: fy + space * 1.7 * dir),
                control: CGPoint(x: stemX + space * 1.3 * dir, y: fy + space * 0.4 * dir)
            )
            context.stroke(flag, with: .color(stemColor), lineWidth: 2.2)
        }
    }

    private func drawBeamedGroup(_ group: [ScoredNote], in context: inout GraphicsContext, size: CGSize) {
        let center = Double(centerStep)
        let steps = group.map { Double($0.target.diatonicStep) }
        // Single direction for the whole group, toward the note farthest from
        // the middle line (low notes → stems up, high notes → stems down).
        let maxAbove = steps.map { $0 - center }.max() ?? 0
        let maxBelow = steps.map { center - $0 }.max() ?? 0
        let up = maxBelow >= maxAbove

        let xs = group.map { xPos(forIndex: $0.index) + (up ? headHalf : -headHalf) }
        let ys = group.map { noteY($0, in: size) }
        let beamY = up ? (ys.min()! - stemLength) : (ys.max()! + stemLength)

        for (stemX, y) in zip(xs, ys) {
            var path = Path()
            path.move(to: CGPoint(x: stemX, y: y))
            path.addLine(to: CGPoint(x: stemX, y: beamY))
            context.stroke(path, with: .color(stemColor), lineWidth: 1.6)
        }

        // One beam bar per flag level, stacked from the outer edge inward.
        let beamThickness = space * 0.5
        let beamGap = space * 0.34
        let left = xs.min()!, right = xs.max()!
        for b in 0..<flagCount {
            let step = CGFloat(b) * (beamThickness + beamGap)
            let topY = up ? (beamY + step) : (beamY - step - beamThickness)
            let rect = CGRect(x: left, y: topY, width: right - left, height: beamThickness)
            context.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(stemColor))
        }
    }

    private func drawAccidental(_ symbol: String, at point: CGPoint, color: Color, in context: inout GraphicsContext) {
        guard !symbol.isEmpty else { return }
        let text = Text(symbol).font(.custom("Palatino", size: space * 2.1)).foregroundStyle(color)
        context.draw(text, at: point, anchor: .center)
    }

    private func drawShadowNote(_ pitch: SpelledPitch, column x: CGFloat, targetY: CGFloat, in context: inout GraphicsContext, size: CGSize) {
        let y = yPos(forStep: Double(pitch.diatonicStep), in: size)
        drawLedgerLines(forStep: pitch.diatonicStep, x: x, in: &context, size: size)

        // Dotted connector between written and played pitch.
        var connector = Path()
        connector.move(to: CGPoint(x: x, y: targetY))
        connector.addLine(to: CGPoint(x: x, y: y))
        context.stroke(connector, with: .color(.purple.opacity(0.35)),
                       style: StrokeStyle(lineWidth: 1, dash: [2, 3]))

        let w = space * 1.3, h = space * 0.96
        let rect = CGRect(x: x - w / 2, y: y - h / 2, width: w, height: h)
        context.fill(Path(ellipseIn: rect), with: .color(.purple.opacity(0.32)))
        context.stroke(Path(ellipseIn: rect), with: .color(.purple.opacity(0.5)), lineWidth: 1)

        drawAccidental(pitch.accidental.explicitSymbol,
                       at: CGPoint(x: x - space * 1.5, y: y), color: .purple.opacity(0.6), in: &context)
    }
}

#Preview("Staff") {
    // A D major scale (two sharps) with assorted feedback states.
    let scale = Scale(tonic: Tonic(letter: .d, accidental: .natural), quality: .major)
    var notes = scale.notes.enumerated().map { ScoredNote(index: $0.offset, target: $0.element) }
    notes[0].tempo = .perfect; notes[0].centsOff = 4; notes[0].playedWrittenMidi = Double(notes[0].target.midi)
    notes[1].tempo = .slight; notes[1].centsOff = 10; notes[1].playedWrittenMidi = Double(notes[1].target.midi)
    notes[2].tempo = .moderate; notes[2].centsOff = 35; notes[2].playedWrittenMidi = Double(notes[2].target.midi) + 0.35
    notes[3].tempo = .off; notes[3].centsOff = -60; notes[3].playedWrittenMidi = Double(notes[3].target.midi) - 0.6
    notes[4].tempo = .perfect; notes[4].centsOff = 140
    notes[4].playedWrittenMidi = Double(notes[4].target.midi) + 1.4   // shadow note a semitone up
    return StaffView(notes: notes, currentIndex: 6, keySignature: scale.keySignature)
        .padding()
        .frame(width: 900)
}
