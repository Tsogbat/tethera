import SwiftUI

struct AutocompleteSuggestionView: View {
    let suggestions: [AutocompleteSuggestion]
    let onSuggestionSelected: (AutocompleteSuggestion) -> Void
    let onArrowNavigation: (Int) -> Void
    @Binding var selectedIndex: Int
    @EnvironmentObject private var userSettings: UserSettings
    
    // Scale dropdown based on user's font size preference
    private var scaleFactor: CGFloat {
        userSettings.themeConfiguration.fontSize / 14.0
    }
    
    private var rowHeight: CGFloat {
        max(36, 32 * scaleFactor)
    }
    // Ideal height = 5 items, shrink if fewer, scroll if more
    private var idealHeight: CGFloat {
        let itemCount = min(suggestions.count, 5) // Show max 5 items without scroll
        return CGFloat(itemCount) * rowHeight + 8 // 8 for padding
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                        suggestionRow(index: index, suggestion: suggestion)
                            .id(index)
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(suggestions.count > 5 ? .visible : .hidden)
            .frame(height: idealHeight) // Exact height based on items
            .background(suggestionBackground)
            .shadow(color: (userSettings.themeConfiguration.isDarkMode ? SwiftUI.Color.black : SwiftUI.Color.gray).opacity(0.25), radius: 8, x: 0, y: 4)
            .onChange(of: selectedIndex) { _, newIndex in
                withAnimation(.easeInOut(duration: 0.15)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
    }
    
    private func suggestionRow(index: Int, suggestion: AutocompleteSuggestion) -> some View {
        HStack(spacing: 8 * scaleFactor) {
            Image(systemName: suggestion.type.icon)
                .foregroundColor(userSettings.themeConfiguration.accentColor.color)
                .font(.system(size: 11 * scaleFactor, weight: .medium))
                .frame(width: 14 * scaleFactor)
            
            Text(suggestion.text)
                .font(themeFont(size: userSettings.themeConfiguration.fontSize * 0.9))
                .foregroundColor(userSettings.themeConfiguration.textColor.color)
                .lineLimit(1)
            
            Spacer()
            
            if !suggestion.description.isEmpty {
                Text(suggestion.description)
                    .font(themeFont(size: userSettings.themeConfiguration.fontSize * 0.7))
                    .foregroundColor(userSettings.themeConfiguration.textColor.color.opacity(0.5))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6 * scaleFactor)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(index == selectedIndex ? userSettings.themeConfiguration.accentColor.color.opacity(0.18) : SwiftUI.Color.clear)
        )
        .onTapGesture {
            onSuggestionSelected(suggestion)
        }
        .onHover { isHovered in
            if isHovered {
                selectedIndex = index
            }
        }
    }
    
    private var suggestionBackground: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(
                userSettings.themeConfiguration.isDarkMode ?
                SwiftUI.Color(red: 0.10, green: 0.10, blue: 0.12) : SwiftUI.Color(red: 0.96, green: 0.96, blue: 0.98)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        LinearGradient(
                            colors: [
                                userSettings.themeConfiguration.accentColor.color.opacity(0.4),
                                userSettings.themeConfiguration.accentColor.color.opacity(0.15)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
    }
    
    private func themeFont(size: CGFloat) -> Font {
        let family = userSettings.themeConfiguration.fontFamily
        if FontLoader.shared.isFontAvailable("\(family)-Medium") {
            return .custom("\(family)-Medium", size: size)
        }
        if FontLoader.shared.isFontAvailable(family) {
            return .custom(family, size: size)
        }
        return .system(size: size, design: .monospaced)
    }
}
