import SwiftUI

/// A view for editing markdown files with live preview
struct MarkdownEditView: View {
    let filePath: String
    let onClose: () -> Void
    
    @State private var content: String = ""
    @State private var originalContent: String = ""
    @State private var isSaving: Bool = false
    @State private var hasChanges: Bool = false
    @State private var showSaveError: Bool = false
    @State private var showLoadError: Bool = false
    @State private var saveErrorMessage: String = ""
    @State private var loadErrorMessage: String = ""
    @EnvironmentObject private var userSettings: UserSettings
    
    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                // File name
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .foregroundColor(.purple)
                    Text((filePath as NSString).lastPathComponent)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    
                    if hasChanges {
                        Circle()
                            .fill(.orange)
                            .frame(width: 8, height: 8)
                            .help("Unsaved changes")
                    }
                }
                
                Spacer()
                
                // Buttons
                HStack(spacing: 12) {
                    Button(action: { onClose() }) {
                        Text("Cancel")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Button(action: saveFile) {
                        HStack(spacing: 4) {
                            if isSaving {
                                ProgressView()
                                    .scaleEffect(0.6)
                            } else {
                                Image(systemName: "square.and.arrow.down")
                            }
                            Text("Save")
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(hasChanges ? SwiftUI.Color.green : SwiftUI.Color.secondary)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(!hasChanges || isSaving)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            
            Divider()
            
            // Split view: Editor | Preview
            HStack(spacing: 0) {
                // Editor pane
                VStack(alignment: .leading, spacing: 4) {
                    Text("MARKDOWN")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                    
                    TextEditor(text: $content)
                        .font(.system(size: CGFloat(userSettings.themeConfiguration.fontSize - 1), design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .background(SwiftUI.Color.clear)
                        .onChange(of: content) { _, newValue in
                            hasChanges = newValue != originalContent
                        }
                }
                .frame(maxWidth: .infinity)
                .background(userSettings.themeConfiguration.backgroundColor.color.opacity(0.3))
                
                Divider()
                
                // Preview pane
                VStack(alignment: .leading, spacing: 4) {
                    Text("PREVIEW")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                    
                    ScrollView {
                        MarkdownOutputView(content: content)
                            .environmentObject(userSettings)
                            .padding(12)
                    }
                }
                .frame(maxWidth: .infinity)
                .background(userSettings.themeConfiguration.backgroundColor.color.opacity(0.5))
            }
        }
        .frame(minWidth: 800, minHeight: 500)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        .onAppear {
            loadFile()
        }
        .alert("Save Error", isPresented: $showSaveError) {
            Button("OK") {}
        } message: {
            Text(saveErrorMessage.isEmpty ? "Failed to save the file. Check permissions." : saveErrorMessage)
        }
        .alert("Load Error", isPresented: $showLoadError) {
            Button("OK") {}
        } message: {
            Text(loadErrorMessage.isEmpty ? "Failed to load the file." : loadErrorMessage)
        }
    }
    
    private func loadFile() {
        do {
            content = try String(contentsOfFile: filePath, encoding: .utf8)
            originalContent = content
        } catch {
            content = ""
            loadErrorMessage = "Failed to load \(filePath): \(error.localizedDescription)"
            showLoadError = true
        }
    }
    
    private func saveFile() {
        isSaving = true
        
        Task {
            do {
                try content.write(toFile: filePath, atomically: true, encoding: .utf8)
                await MainActor.run {
                    originalContent = content
                    hasChanges = false
                    isSaving = false
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    saveErrorMessage = "Failed to save \(filePath): \(error.localizedDescription)"
                    showSaveError = true
                }
            }
        }
    }
}
