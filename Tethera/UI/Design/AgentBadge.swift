import SwiftUI

/// An agent's mark on a rounded tile, drawn as vectors so it stays crisp at every size.
struct AgentBadge: View {
    let agent: AgentCLI
    var size: CGFloat = 18

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
        Canvas { context, canvas in
            AgentMarkPainter.draw(agent, in: &context, size: canvas.width)
        }
        .frame(width: size, height: size)
        .background(shape.fill(agent.tileFill))
        .overlay(shape.strokeBorder(.white.opacity(agent.tileIsLight ? 0 : 0.14), lineWidth: 0.5))
        .overlay(shape.strokeBorder(.black.opacity(agent.tileIsLight ? 0.12 : 0), lineWidth: 0.5))
        .clipShape(shape)
        .accessibilityLabel(agent.displayName)
    }
}

extension AgentCLI {
    fileprivate var tileFill: LinearGradient {
        let colors: [Color]
        switch self {
        case .claude: colors = [Color(red: 0.87, green: 0.49, blue: 0.36), Color(red: 0.80, green: 0.40, blue: 0.29)]
        case .opencode: colors = [Color(white: 0.20), Color(white: 0.08)]
        case .codex: colors = [Color(white: 0.17), Color(white: 0.04)]
        case .gemini: colors = [Color(red: 0.13, green: 0.14, blue: 0.20), Color(red: 0.07, green: 0.08, blue: 0.12)]
        case .hermes: colors = [Color(red: 0.55, green: 0.42, blue: 1.0), Color(red: 0.36, green: 0.24, blue: 0.86)]
        case .ollama: colors = [.white, Color(white: 0.92)]
        }
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }

    fileprivate var tileIsLight: Bool { self == .ollama }
}

/// Marks are laid out on a unit square, then scaled to the badge.
private enum AgentMarkPainter {
    static func draw(_ agent: AgentCLI, in context: inout GraphicsContext, size: CGFloat) {
        context.scaleBy(x: size, y: size)
        switch agent {
        case .claude: claude(&context)
        case .opencode: opencode(&context)
        case .codex: codex(&context)
        case .gemini: gemini(&context)
        case .hermes: hermes(&context)
        case .ollama: ollama(&context)
        }
    }

    private static let ink = Color(red: 0.99, green: 0.97, blue: 0.94)

    /// A hand-drawn-feeling starburst: uneven rays around a small hub.
    private static func claude(_ context: inout GraphicsContext) {
        let lengths: [CGFloat] = [0.35, 0.29, 0.37, 0.31, 0.34, 0.28, 0.36, 0.30, 0.35, 0.29, 0.33, 0.31]
        var rays = Path()
        for (index, length) in lengths.enumerated() {
            let angle = CGFloat(index) / CGFloat(lengths.count) * 2 * .pi + 0.14
            let direction = CGVector(dx: Foundation.cos(angle), dy: Foundation.sin(angle))
            let inner = CGPoint(x: 0.5 + direction.dx * 0.05, y: 0.5 + direction.dy * 0.05)
            let outer = CGPoint(x: 0.5 + direction.dx * length, y: 0.5 + direction.dy * length)
            rays.move(to: inner)
            rays.addLine(to: outer)
        }
        context.stroke(rays, with: .color(ink), style: StrokeStyle(lineWidth: 0.075, lineCap: .round))
        context.fill(Path(ellipseIn: CGRect(x: 0.41, y: 0.41, width: 0.18, height: 0.18)), with: .color(ink))
    }

    /// A bright frame around a dark pane, like the OpenCode app icon.
    private static func opencode(_ context: inout GraphicsContext) {
        let frame = Path(roundedRect: CGRect(x: 0.29, y: 0.22, width: 0.42, height: 0.56), cornerRadius: 0.02)
        context.fill(frame, with: .linearGradient(Gradient(colors: [.white, Color(white: 0.78)]),
                                                  startPoint: CGPoint(x: 0.3, y: 0.2), endPoint: CGPoint(x: 0.7, y: 0.8)))
        let pane = Path(CGRect(x: 0.39, y: 0.33, width: 0.22, height: 0.34))
        context.fill(pane, with: .linearGradient(Gradient(colors: [Color(white: 0.10), Color(white: 0.30)]),
                                                 startPoint: CGPoint(x: 0.5, y: 0.33), endPoint: CGPoint(x: 0.5, y: 0.67)))
    }

    /// A shell prompt: chevron and cursor.
    private static func codex(_ context: inout GraphicsContext) {
        var chevron = Path()
        chevron.move(to: CGPoint(x: 0.27, y: 0.34))
        chevron.addLine(to: CGPoint(x: 0.43, y: 0.50))
        chevron.addLine(to: CGPoint(x: 0.27, y: 0.66))
        let style = StrokeStyle(lineWidth: 0.085, lineCap: .round, lineJoin: .round)
        context.stroke(chevron, with: .color(.white), style: style)
        var cursor = Path()
        cursor.move(to: CGPoint(x: 0.52, y: 0.66))
        cursor.addLine(to: CGPoint(x: 0.73, y: 0.66))
        context.stroke(cursor, with: .color(.white.opacity(0.85)), style: style)
    }

    /// A four-point sparkle with concave sides.
    private static func gemini(_ context: inout GraphicsContext) {
        let center = CGPoint(x: 0.5, y: 0.5)
        let points = [CGPoint(x: 0.5, y: 0.1), CGPoint(x: 0.9, y: 0.5), CGPoint(x: 0.5, y: 0.9), CGPoint(x: 0.1, y: 0.5)]
        var star = Path()
        star.move(to: points[0])
        for index in 1...points.count {
            star.addQuadCurve(to: points[index % points.count], control: center)
        }
        star.closeSubpath()
        let gradient = Gradient(colors: [Color(red: 0.28, green: 0.59, blue: 0.89),
                                         Color(red: 0.57, green: 0.47, blue: 0.78),
                                         Color(red: 0.79, green: 0.40, blue: 0.45)])
        context.fill(star, with: .linearGradient(gradient, startPoint: CGPoint(x: 0.2, y: 0.2), endPoint: CGPoint(x: 0.85, y: 0.85)))
    }

    /// A swept wing: feathers shortening from the leading edge.
    private static func hermes(_ context: inout GraphicsContext) {
        var wing = context
        wing.translateBy(x: 0.5, y: 0.5)
        wing.rotate(by: .degrees(-18))
        wing.translateBy(x: -0.5, y: -0.5)
        let feathers: [(y: CGFloat, length: CGFloat, opacity: Double)] = [
            (0.33, 0.48, 1), (0.45, 0.40, 0.92), (0.57, 0.31, 0.84), (0.69, 0.21, 0.76),
        ]
        for feather in feathers {
            var line = Path()
            line.move(to: CGPoint(x: 0.74, y: feather.y))
            line.addLine(to: CGPoint(x: 0.74 - feather.length, y: feather.y))
            wing.stroke(line, with: .color(.white.opacity(feather.opacity)), style: StrokeStyle(lineWidth: 0.085, lineCap: .round))
        }
    }

    /// A llama face in outline.
    private static func ollama(_ context: inout GraphicsContext) {
        let ink = Color(white: 0.08)
        let line = StrokeStyle(lineWidth: 0.055, lineCap: .round, lineJoin: .round)
        var head = Path()
        head.move(to: CGPoint(x: 0.31, y: 0.86))
        head.addLine(to: CGPoint(x: 0.31, y: 0.50))
        head.addQuadCurve(to: CGPoint(x: 0.37, y: 0.38), control: CGPoint(x: 0.31, y: 0.41))
        head.addLine(to: CGPoint(x: 0.36, y: 0.20))
        head.addQuadCurve(to: CGPoint(x: 0.44, y: 0.20), control: CGPoint(x: 0.40, y: 0.12))
        head.addLine(to: CGPoint(x: 0.45, y: 0.34))
        head.addLine(to: CGPoint(x: 0.55, y: 0.34))
        head.addLine(to: CGPoint(x: 0.56, y: 0.20))
        head.addQuadCurve(to: CGPoint(x: 0.64, y: 0.20), control: CGPoint(x: 0.60, y: 0.12))
        head.addLine(to: CGPoint(x: 0.63, y: 0.38))
        head.addQuadCurve(to: CGPoint(x: 0.69, y: 0.50), control: CGPoint(x: 0.69, y: 0.41))
        head.addLine(to: CGPoint(x: 0.69, y: 0.86))
        context.stroke(head, with: .color(ink), style: line)
        context.stroke(Path(ellipseIn: CGRect(x: 0.415, y: 0.57, width: 0.17, height: 0.13)), with: .color(ink), style: line)
        for x in [0.40, 0.60] {
            context.fill(Path(ellipseIn: CGRect(x: x - 0.03, y: 0.47, width: 0.06, height: 0.06)), with: .color(ink))
        }
    }
}
