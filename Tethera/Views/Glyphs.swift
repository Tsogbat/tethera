import SwiftUI
import TetheraKit

/// A session's mark: the agent it runs, or a plain prompt for a shell. One color, tinted by
/// state rather than brand, so a list of agents stays calm.
struct SessionGlyph: View {
    let agent: AgentKind?
    var size: CGFloat = 14
    var color: Color

    var body: some View {
        Canvas { context, canvas in
            context.scaleBy(x: canvas.width, y: canvas.height)
            GlyphPainter.draw(agent, in: &context, color: color)
        }
        .frame(width: size, height: size)
        .accessibilityLabel(agent?.displayName ?? "Shell")
    }
}

private enum GlyphPainter {
    static func draw(_ agent: AgentKind?, in context: inout GraphicsContext, color: Color) {
        let ink = GraphicsContext.Shading.color(color)
        let line = StrokeStyle(lineWidth: 0.1, lineCap: .round, lineJoin: .round)
        switch agent {
        case nil:
            // A terminal window with a prompt.
            context.stroke(Path(roundedRect: CGRect(x: 0.08, y: 0.16, width: 0.84, height: 0.68), cornerRadius: 0.14), with: ink, style: StrokeStyle(lineWidth: 0.09))
            var prompt = Path()
            prompt.move(to: CGPoint(x: 0.27, y: 0.38))
            prompt.addLine(to: CGPoint(x: 0.42, y: 0.5))
            prompt.addLine(to: CGPoint(x: 0.27, y: 0.62))
            prompt.move(to: CGPoint(x: 0.5, y: 0.63))
            prompt.addLine(to: CGPoint(x: 0.7, y: 0.63))
            context.stroke(prompt, with: ink, style: StrokeStyle(lineWidth: 0.085, lineCap: .round, lineJoin: .round))

        case .claude:
            // Uneven rays around a hub.
            let lengths: [CGFloat] = [0.46, 0.38, 0.48, 0.4, 0.45, 0.37, 0.47, 0.39, 0.46, 0.38, 0.44, 0.41]
            var rays = Path()
            for (index, length) in lengths.enumerated() {
                let angle = CGFloat(index) / CGFloat(lengths.count) * 2 * .pi + 0.14
                let dx = Foundation.cos(angle), dy = Foundation.sin(angle)
                rays.move(to: CGPoint(x: 0.5 + dx * 0.08, y: 0.5 + dy * 0.08))
                rays.addLine(to: CGPoint(x: 0.5 + dx * length, y: 0.5 + dy * length))
            }
            context.stroke(rays, with: ink, style: StrokeStyle(lineWidth: 0.095, lineCap: .round))

        case .codex:
            var path = Path()
            path.move(to: CGPoint(x: 0.14, y: 0.26))
            path.addLine(to: CGPoint(x: 0.4, y: 0.5))
            path.addLine(to: CGPoint(x: 0.14, y: 0.74))
            path.move(to: CGPoint(x: 0.52, y: 0.76))
            path.addLine(to: CGPoint(x: 0.86, y: 0.76))
            context.stroke(path, with: ink, style: StrokeStyle(lineWidth: 0.12, lineCap: .round, lineJoin: .round))

        case .opencode:
            // A frame around a pane.
            context.stroke(Path(CGRect(x: 0.2, y: 0.1, width: 0.6, height: 0.8)), with: ink, style: StrokeStyle(lineWidth: 0.13))
            context.fill(Path(CGRect(x: 0.38, y: 0.32, width: 0.24, height: 0.4)), with: .color(color.opacity(0.45)))

        case .gemini:
            let points = [CGPoint(x: 0.5, y: 0.02), CGPoint(x: 0.98, y: 0.5), CGPoint(x: 0.5, y: 0.98), CGPoint(x: 0.02, y: 0.5)]
            var star = Path()
            star.move(to: points[0])
            for index in 1...points.count { star.addQuadCurve(to: points[index % 4], control: CGPoint(x: 0.5, y: 0.5)) }
            context.fill(star, with: ink)

        case .hermes:
            var wing = context
            wing.translateBy(x: 0.5, y: 0.5)
            wing.rotate(by: .degrees(-18))
            wing.translateBy(x: -0.5, y: -0.5)
            for (y, length) in [(0.22, 0.66), (0.4, 0.54), (0.58, 0.42), (0.76, 0.28)] as [(CGFloat, CGFloat)] {
                var feather = Path()
                feather.move(to: CGPoint(x: 0.86, y: y))
                feather.addLine(to: CGPoint(x: 0.86 - length, y: y))
                wing.stroke(feather, with: ink, style: StrokeStyle(lineWidth: 0.11, lineCap: .round))
            }

        case .antigravity:
            // An arch lifting off its baseline.
            var arch = Path()
            arch.move(to: CGPoint(x: 0.12, y: 0.86))
            arch.addCurve(to: CGPoint(x: 0.88, y: 0.86), control1: CGPoint(x: 0.3, y: -0.12), control2: CGPoint(x: 0.7, y: -0.12))
            context.stroke(arch, with: ink, style: line)
            context.fill(Path(ellipseIn: CGRect(x: 0.42, y: 0.52, width: 0.16, height: 0.16)), with: ink)

        case .ollama:
            var head = Path()
            head.move(to: CGPoint(x: 0.22, y: 0.95))
            head.addLine(to: CGPoint(x: 0.22, y: 0.5))
            head.addQuadCurve(to: CGPoint(x: 0.3, y: 0.36), control: CGPoint(x: 0.22, y: 0.4))
            head.addLine(to: CGPoint(x: 0.28, y: 0.12))
            head.addQuadCurve(to: CGPoint(x: 0.4, y: 0.12), control: CGPoint(x: 0.34, y: 0.02))
            head.addLine(to: CGPoint(x: 0.42, y: 0.3))
            head.addLine(to: CGPoint(x: 0.58, y: 0.3))
            head.addLine(to: CGPoint(x: 0.6, y: 0.12))
            head.addQuadCurve(to: CGPoint(x: 0.72, y: 0.12), control: CGPoint(x: 0.66, y: 0.02))
            head.addLine(to: CGPoint(x: 0.7, y: 0.36))
            head.addQuadCurve(to: CGPoint(x: 0.78, y: 0.5), control: CGPoint(x: 0.78, y: 0.4))
            head.addLine(to: CGPoint(x: 0.78, y: 0.95))
            context.stroke(head, with: ink, style: StrokeStyle(lineWidth: 0.08, lineCap: .round, lineJoin: .round))

        default:
            // Other agents: a diamond.
            var diamond = Path()
            diamond.move(to: CGPoint(x: 0.5, y: 0.08))
            diamond.addLine(to: CGPoint(x: 0.92, y: 0.5))
            diamond.addLine(to: CGPoint(x: 0.5, y: 0.92))
            diamond.addLine(to: CGPoint(x: 0.08, y: 0.5))
            diamond.closeSubpath()
            context.stroke(diamond, with: ink, style: line)
        }
    }
}

/// Braille spinner for "working": a terminal-native motion, not a glow.
struct WorkingSpinner: View {
    var color: Color
    private static let frames = Array("⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏")
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: reduceMotion ? 1 : 0.08)) { context in
            let index = reduceMotion ? 0 : Int(context.date.timeIntervalSinceReferenceDate / 0.08) % Self.frames.count
            Text(String(Self.frames[index]))
                .font(TypeScale.mono(11))
                .foregroundStyle(color)
        }
    }
}
