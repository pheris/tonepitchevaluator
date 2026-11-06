import SwiftUI

/// An old-timey SMPTE film-leader countdown: a black disc with crosshairs, an
/// outer and inner ring, a radial hand that sweeps a full turn each beat, and a
/// big number in the center. Shown during the count-in, one number per beat.
struct FilmLeaderView: View {
    /// The number to display (counts down 4, 3, 2, 1).
    let number: Int
    /// Seconds per beat — the sweep completes one rotation over this time.
    let beatDuration: Double

    @State private var start = Date()

    var body: some View {
        TimelineView(.animation) { timeline in
            let elapsed = timeline.date.timeIntervalSince(start)
            let progress = beatDuration > 0 ? min(max(elapsed / beatDuration, 0), 1) : 0
            Canvas { context, size in draw(&context, size: size, progress: progress) }
        }
        .onAppear { start = Date() }
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize, progress: Double) {
        let side = min(size.width, size.height)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let r = side / 2 - 6

        func circle(_ radius: CGFloat) -> Path {
            Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        }

        // Film-grain dark disc.
        context.fill(circle(r), with: .color(.black.opacity(0.92)))

        // Swept "wipe" sector that fills as the beat progresses.
        var wedge = Path()
        wedge.move(to: center)
        wedge.addArc(center: center, radius: r, startAngle: .degrees(-90),
                     endAngle: .degrees(-90 + 360 * progress), clockwise: false)
        wedge.closeSubpath()
        context.fill(wedge, with: .color(.white.opacity(0.16)))

        // Rings.
        context.stroke(circle(r), with: .color(.white.opacity(0.75)), lineWidth: 3)
        context.stroke(circle(r * 0.7), with: .color(.white.opacity(0.35)), lineWidth: 1.5)

        // Crosshair, clipped to the disc.
        var cross = Path()
        cross.move(to: CGPoint(x: center.x, y: center.y - r)); cross.addLine(to: CGPoint(x: center.x, y: center.y + r))
        cross.move(to: CGPoint(x: center.x - r, y: center.y)); cross.addLine(to: CGPoint(x: center.x + r, y: center.y))
        context.stroke(cross, with: .color(.white.opacity(0.5)), lineWidth: 1.5)

        // Sweeping hand.
        let angle = CGFloat(-90 + 360 * progress) * .pi / 180
        var hand = Path()
        hand.move(to: center)
        hand.addLine(to: CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r))
        context.stroke(hand, with: .color(.white.opacity(0.9)), lineWidth: 2.5)

        // The big number.
        let label = Text("\(number)")
            .font(.custom("Palatino", size: side * 0.42).weight(.bold))
            .foregroundStyle(.white)
        context.draw(label, at: center)
    }
}

#Preview {
    FilmLeaderView(number: 3, beatDuration: 0.75)
        .frame(width: 200, height: 200)
        .padding()
        .background(.white)
}
