import SwiftUI

/// Completion menu anchored above the input bar.
struct AutocompleteSuggestionView: View {
    @EnvironmentObject private var settings: UserSettings
    let suggestions: [AutocompleteSuggestion]
    @Binding var selectedIndex: Int
    let onSelect: (AutocompleteSuggestion) -> Void
    @Namespace private var selection

    private let rowHeight: CGFloat = 30
    private let visibleRows = 7

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                        row(suggestion, index: index)
                            .id(index)
                    }
                }
                .padding(5)
            }
            .scrollIndicators(suggestions.count > visibleRows ? .automatic : .never)
            .frame(height: CGFloat(min(suggestions.count, visibleRows)) * (rowHeight + 1) + 10)
            .onChange(of: selectedIndex) { _, index in
                withAnimation(Motion.quick) { proxy.scrollTo(index, anchor: .center) }
            }
        }
        .glassSurface(RoundedRectangle(cornerRadius: 13, style: .continuous), elevated: true)
    }

    private func row(_ suggestion: AutocompleteSuggestion, index: Int) -> some View {
        let isSelected = index == selectedIndex
        return HStack(spacing: 9) {
            Image(systemName: suggestion.type.icon)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(isSelected ? settings.theme.accent : settings.theme.textTertiary)
                .frame(width: 14)
            Text(suggestion.text)
                .font(Typography.mono(settings.themeConfiguration.fontFamily, size: 12.5, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(settings.theme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 10)
            if !suggestion.description.isEmpty {
                Text(suggestion.description)
                    .font(Typography.ui(11))
                    .foregroundStyle(settings.theme.textTertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: rowHeight)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(settings.theme.accentSoft)
                    .matchedGeometryEffect(id: "selection", in: selection)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onSelect(suggestion) }
        .onHover { inside in
            if inside {
                withAnimation(Motion.quick) { selectedIndex = index }
            }
        }
        .animation(Motion.snappy, value: selectedIndex)
    }
}
