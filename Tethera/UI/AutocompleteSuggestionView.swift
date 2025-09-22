import SwiftUI

struct AutocompleteSuggestionView: View {
    let suggestions: [AutocompleteSuggestion]
    let onSuggestionSelected: (AutocompleteSuggestion) -> Void
    let onArrowNavigation: (Int) -> Void
    @Binding var selectedIndex: Int
    @EnvironmentObject private var userSettings: UserSettings
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                        suggestionRow(index: index, suggestion: suggestion)
                            .id(index)
                    }
                }
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: 200) // Limit height to make it scrollable
            .background(suggestionBackground)
            .shadow(color: (userSettings.themeConfiguration.isDarkMode ? SwiftUI.Color.black : SwiftUI.Color.gray).opacity(0.25), radius: 8, x: 0, y: 4)
            .onChange(of: selectedIndex) { _, newIndex in
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("AutocompleteKeyDown"))) { notification in
                if let keyCode = notification.object as? UInt16 {
                    handleKeyDown(keyCode: keyCode)
                }
            }
        }
    }
    
    private func suggestionRow(index: Int, suggestion: AutocompleteSuggestion) -> some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: suggestion.type.icon)
                .foregroundColor(colorForType(suggestion.type))
                .font(.system(size: 12, weight: .medium))
                .frame(width: 16)
            
            // Suggestion text
            Text(suggestion.text)
                .font(themeFont(size: 13))
                .foregroundColor(userSettings.themeConfiguration.textColor.color)
                .lineLimit(1)
            
            Spacer()
            
            // Type description
            Text(suggestion.description)
                .font(themeFont(size: 11))
                .foregroundColor(userSettings.themeConfiguration.textColor.color.opacity(0.65))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
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
                SwiftUI.Color.white.opacity(0.06) : SwiftUI.Color.black.opacity(0.04)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        (userSettings.themeConfiguration.isDarkMode ? SwiftUI.Color.white.opacity(0.12) : SwiftUI.Color.black.opacity(0.08)),
                        lineWidth: 1
                    )
            )
    }
    
    private func colorForType(_ type: AutocompleteSuggestion.SuggestionType) -> SwiftUI.Color {
        switch type {
        case .command: return userSettings.themeConfiguration.accentColor.color
        case .file: return userSettings.themeConfiguration.accentColor.color
        case .directory: return userSettings.themeConfiguration.accentColor.color
        }
    }
    
    private func handleKeyDown(keyCode: UInt16) {
        switch keyCode {
        case 125: // Down Arrow
            let newIndex = min(selectedIndex + 1, suggestions.count - 1)
            selectedIndex = newIndex
            onArrowNavigation(newIndex)
        case 126: // Up Arrow
            let newIndex = max(selectedIndex - 1, 0)
            selectedIndex = newIndex
            onArrowNavigation(newIndex)
        case 36: // Return
            if selectedIndex < suggestions.count {
                onSuggestionSelected(suggestions[selectedIndex])
            }
        case 48: // Tab
            if selectedIndex < suggestions.count {
                onSuggestionSelected(suggestions[selectedIndex])
            }
        default:
            break
        }
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

