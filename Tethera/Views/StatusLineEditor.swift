import SwiftUI
import TetheraKit

/// Settings → Agents → Status line: pick what Claude Code's status line shows, see it, apply
/// it (shown as a diff first, like every config change).
struct StatusLineEditor: View {
    let apply: (AgentIntegrations.Plan) -> Void
    let cancel: () -> Void
    @State private var chosen: [String]
    @State private var separator: String

    static let separators = [" · ", "  │  ", "  ", " / "]

    init(apply: @escaping (AgentIntegrations.Plan) -> Void, cancel: @escaping () -> Void) {
        self.apply = apply
        self.cancel = cancel
        let current = AgentIntegrations.currentStatusLineFormat() ?? StatusLineFormat.defaultFormat
        let keys = StatusLineFormat.segments.map(\.key).filter { current.contains("{\($0)}") }
        _chosen = State(initialValue: keys.isEmpty ? ["model", "context", "cost", "branch"] : keys)
        _separator = State(initialValue: Self.separators.first { current.contains($0) } ?? " · ")
    }

    private var format: String {
        chosen.map { "{\($0)}" }.joined(separator: separator)
    }

    private var preview: String {
        StatusLineFormat.render(format, values: Dictionary(uniqueKeysWithValues: StatusLineFormat.segments.map { ($0.key, $0.sample) }))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Claude Code status line").font(.headline)
            Text(preview.isEmpty ? " " : preview)
                .font(.system(size: 12, design: .monospaced))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.85)))
                .foregroundStyle(Color.white.opacity(0.85))
            VStack(alignment: .leading, spacing: 6) {
                ForEach(StatusLineFormat.segments) { segment in
                    Toggle(isOn: Binding(
                        get: { chosen.contains(segment.key) },
                        set: { on in
                            if on {
                                // Keep the order of the list, whatever order they're ticked in.
                                chosen = StatusLineFormat.segments.map(\.key).filter { chosen.contains($0) || $0 == segment.key }
                            } else {
                                chosen.removeAll { $0 == segment.key }
                            }
                        })) {
                        HStack {
                            Text(segment.label)
                            Spacer()
                            Text(segment.sample).foregroundStyle(.secondary).font(.system(.caption, design: .monospaced))
                        }
                    }
                }
            }
            Picker("Separator", selection: $separator) {
                ForEach(Self.separators, id: \.self) { Text("“\($0)”").tag($0) }
            }
            Text("Tethera renders this from the data Claude Code already sends its status line; your own status line command is kept and comes back if you disconnect.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Button("Review Change…") { apply(AgentIntegrations.statusLinePlan(format: format)) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(chosen.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}
