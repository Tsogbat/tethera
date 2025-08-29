import SwiftUI

struct CommandPaletteView: View {
    @Binding var isPresented: Bool
    var actions: [String]
    @State private var filter: String = ""
    var body: some View {
        if isPresented {
            VStack {
                TextField("Type a command...", text: $filter)
                    .font(.custom("JetBrainsMono-Regular", size: 16))
                    .padding()
                    .background(SwiftUI.Color.white)
                    .cornerRadius(8)
                List(filteredActions, id: \ .self) { action in
                    Text(action)
                        .font(.custom("JetBrainsMono-Regular", size: 15))
                        .onTapGesture {
                            // TODO: Handle action
                            isPresented = false
                        }
                }
                .frame(maxHeight: 200)
            }
            .padding()
            .background(SwiftUI.Color.white.opacity(0.95))
            .cornerRadius(12)
            .shadow(radius: 20)
            .padding(40)
        }
    }
    var filteredActions: [String] {
        if filter.isEmpty { return actions }
        return actions.filter { $0.localizedCaseInsensitiveContains(filter) }
    }
}
