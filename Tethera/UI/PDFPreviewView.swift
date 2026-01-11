import SwiftUI
import PDFKit

/// PDF preview component with multi-page navigation
struct PDFPreviewView: View {
    let url: URL
    @EnvironmentObject private var userSettings: UserSettings
    @State private var pdfDocument: PDFDocument?
    @State private var currentPage: Int = 0
    @State private var isLoading = true
    @State private var loadError: String?
    
    private var pageCount: Int {
        pdfDocument?.pageCount ?? 0
    }
    
    var body: some View {
        VStack(spacing: 8) {
            if let error = loadError {
                // Error state
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 24))
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundColor(userSettings.themeConfiguration.textColor.color.opacity(0.6))
                }
                .frame(width: 450, height: 350)
                .background(userSettings.themeConfiguration.backgroundColor.color.opacity(0.5))
                .cornerRadius(8)
            } else if let pdfDoc = pdfDocument {
                // PDF page display
                if let page = pdfDoc.page(at: currentPage) {
                    PDFPageView(page: page)
                        .frame(width: 450, height: 580)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(userSettings.themeConfiguration.textColor.color.opacity(0.1), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                }
                
                // Page navigation
                if pageCount > 1 {
                    HStack(spacing: 16) {
                        Button(action: { 
                            if currentPage > 0 { currentPage -= 1 }
                        }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .disabled(currentPage == 0)
                        .buttonStyle(.plain)
                        .foregroundColor(currentPage == 0 ? .secondary.opacity(0.4) : userSettings.themeConfiguration.accentColor.color)
                        
                        Text("Page \(currentPage + 1) of \(pageCount)")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(userSettings.themeConfiguration.textColor.color.opacity(0.7))
                        
                        Button(action: {
                            if currentPage < pageCount - 1 { currentPage += 1 }
                        }) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .disabled(currentPage >= pageCount - 1)
                        .buttonStyle(.plain)
                        .foregroundColor(currentPage >= pageCount - 1 ? .secondary.opacity(0.4) : userSettings.themeConfiguration.accentColor.color)
                        
                        Spacer()
                        
                        // Open in Preview button
                        Button(action: {
                            NSWorkspace.shared.open(url)
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up.right.square")
                                Text("Open")
                            }
                            .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(userSettings.themeConfiguration.accentColor.color)
                    }
                    .padding(.horizontal, 8)
                }
            } else if isLoading {
                // Loading state
                VStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading PDF...")
                        .font(.system(size: 11))
                        .foregroundColor(userSettings.themeConfiguration.textColor.color.opacity(0.5))
                }
                .frame(width: 450, height: 350)
                .background(userSettings.themeConfiguration.backgroundColor.color.opacity(0.5))
                .cornerRadius(8)
            }
        }
        .onAppear {
            loadPDF()
        }
    }
    
    private func loadPDF() {
        guard FileManager.default.fileExists(atPath: url.path) else {
            loadError = "PDF file not found"
            isLoading = false
            return
        }
        
        if let doc = PDFDocument(url: url) {
            self.pdfDocument = doc
        } else {
            loadError = "Failed to load PDF"
        }
        isLoading = false
    }
}

/// Renders a single PDF page as an NSImage
struct PDFPageView: NSViewRepresentable {
    let page: PDFPage
    
    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.displayMode = .singlePage
        pdfView.autoScales = true
        pdfView.backgroundColor = .clear
        return pdfView
    }
    
    func updateNSView(_ pdfView: PDFView, context: Context) {
        if let document = page.document {
            pdfView.document = document
            pdfView.go(to: page)
        }
    }
}

#Preview {
    PDFPreviewView(url: URL(fileURLWithPath: "/tmp/test.pdf"))
        .environmentObject(UserSettings())
        .padding()
        .background(.black)
}
