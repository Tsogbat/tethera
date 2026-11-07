import SwiftUI

struct PaletteAction: Identifiable {
    let id = UUID()
    let title: String
    var subtitle: String? = nil
    var icon: String? = nil
    var agent: AgentCLI? = nil
    var shortcut: String? = nil
    var isChecked = false
    let perform: () -> Void

    /// Subsequence match with a bonus for word starts and contiguous runs.
    func score(_ query: String) -> Int? {
        guard !query.isEmpty else { return 0 }
        let haystack = Array(title.lowercased())
        let needle = Array(query.lowercased())
        var score = 0
        var index = 0
        var previousMatch = -2
        for character in needle {
            guard let found = haystack[index...].firstIndex(of: character) else { return nil }
            score += 1
            if found == previousMatch + 1 { score += 3 }
            if found == 0 || haystack[found - 1] == " " || haystack[found - 1] == ":" { score += 5 }
            previousMatch = found
            index = found + 1
        }
        return score - haystack.count / 8
    }
}

struct CommandPaletteView: View {
    @EnvironmentObject private var settings: UserSettings
    let actions: [PaletteAction]
    let onDismiss: () -> Void

    @State private var query = ""
    @State private var selected = 0
    @FocusState private var fieldFocused: Bool
    @State private var appeared = false
    @Namespace private var selection

    private var results: [PaletteAction] {
        guard !query.isEmpty else { return actions }
        return actions
            .compactMap { action in action.score(query).map { (action, $0) } }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(settings.theme.isDark ? 0.28 : 0.12)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "command")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(settings.theme.accent)
                    TextField("Type a command…", text: $query)
                        .textFieldStyle(.plain)
                        .font(Typography.ui(15))
                        .foregroundStyle(settings.theme.textPrimary)
                        .focused($fieldFocused)
                        .onSubmit(runSelected)
                    KeyHint(keys: "esc", label: "")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)

                Rectangle().fill(settings.theme.hairline).frame(height: 0.5)

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 1) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, action in
                                row(action, isSelected: index == selected)
                                    .id(index)
                                    .onTapGesture {
                                        selected = index
                                        runSelected()
                                    }
                                    .onHover { inside in if inside { selected = index } }
                            }
                            if results.isEmpty {
                                Text("No matching commands")
                                    .font(Typography.ui(12.5))
                                    .foregroundStyle(settings.theme.textTertiary)
                                    .padding(.vertical, 24)
                            }
                        }
                        .padding(6)
                        .animation(Motion.snappy, value: selected)
                    }
                    .frame(maxHeight: 380)
                    .onChange(of: selected) { _, index in
                        withAnimation(Motion.quick) { proxy.scrollTo(index, anchor: .center) }
                    }
                }
            }
            .frame(width: 560)
            .glassSurface(RoundedRectangle(cornerRadius: 18, style: .continuous), elevated: true)
            .padding(.top, 90)
            .scaleEffect(appeared ? 1 : 0.97)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            fieldFocused = true
            withAnimation(Motion.snappy) { appeared = true }
        }
        .onChange(of: query) { _, _ in selected = 0 }
        .onKeyPress(.downArrow) {
            selected = min(selected + 1, max(results.count - 1, 0))
            return .handled
        }
        .onKeyPress(.upArrow) {
            selected = max(selected - 1, 0)
            return .handled
        }
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
    }

    private func row(_ action: PaletteAction, isSelected: Bool) -> some View {
        HStack(spacing: 11) {
            Group {
                if let agent = action.agent {
                    AgentBadge(agent: agent, size: 18)
                } else {
                    Image(systemName: action.icon ?? "circle")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isSelected ? settings.theme.accent : settings.theme.textSecondary)
                }
            }
            .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(action.title)
                    .font(Typography.ui(13, weight: .medium))
                    .foregroundStyle(settings.theme.textPrimary)
                if let subtitle = action.subtitle {
                    Text(subtitle)
                        .font(Typography.ui(11))
                        .foregroundStyle(settings.theme.textTertiary)
                }
            }
            Spacer()
            if action.isChecked {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(settings.theme.accent)
            }
            if let shortcut = action.shortcut {
                Text(shortcut)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(settings.theme.textTertiary)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(settings.theme.accentSoft)
                    .matchedGeometryEffect(id: "selection", in: selection)
            }
        }
        .contentShape(Rectangle())
    }

    private func runSelected() {
        let current = results
        guard current.indices.contains(selected) else { return }
        let action = current[selected]
        onDismiss()
        DispatchQueue.main.async { action.perform() }
    }
}
