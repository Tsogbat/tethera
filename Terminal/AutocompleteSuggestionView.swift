import SwiftUI

struct AutocompleteSuggestionView: View {
    let suggestions: [AutocompleteSuggestion]
    let onSuggestionSelected: (AutocompleteSuggestion) -> Void
    let onArrowNavigation: (Int) -> Void
    @Binding var selectedIndex: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                suggestionRow(index: index, suggestion: suggestion)
            }
        }
        .padding(.vertical, 8)
        .background(suggestionBackground)
        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("AutocompleteKeyDown"))) { notification in
            if let keyCode = notification.object as? UInt16 {
                handleKeyDown(keyCode: keyCode)
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
                .font(getFont(size: 13))
                .foregroundColor(.white)
                .lineLimit(1)
            
            Spacer()
            
            // Type description
            Text(suggestion.description)
                .font(getFont(size: 11))
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(index == selectedIndex ? SwiftUI.Color.white.opacity(0.1) : SwiftUI.Color.clear)
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
            .fill(SwiftUI.Color(red: 0.08, green: 0.09, blue: 0.12))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(SwiftUI.Color.white.opacity(0.1), lineWidth: 1)
            )
    }
    
    private func colorForType(_ type: AutocompleteSuggestion.SuggestionType) -> SwiftUI.Color {
        switch type {
        case .command: return .green
        case .file: return .blue
        case .directory: return SwiftUI.Color.orange
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
    
    private func getFont(size: CGFloat) -> Font {
        if FontLoader.shared.isFontAvailable("JetBrainsMono-Medium") {
            return .custom("JetBrainsMono-Medium", size: size)
        } else if FontLoader.shared.isFontAvailable("JetBrainsMono-Regular") {
            return .custom("JetBrainsMono-Regular", size: size)
        } else {
            return .system(size: size, design: .monospaced)
        }
    }
}
