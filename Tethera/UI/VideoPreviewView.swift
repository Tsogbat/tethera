import SwiftUI
import AVKit

/// Video preview component for the preview command
struct VideoPreviewView: View {
    let url: URL
    @State private var player: AVPlayer?
    @State private var isLoading = true
    @State private var loadError: String?
    @EnvironmentObject private var userSettings: UserSettings
    
    var body: some View {
        Group {
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
                .frame(width: 400, height: 225)
                .background(userSettings.themeConfiguration.backgroundColor.color.opacity(0.5))
                .cornerRadius(8)
            } else if let player = player {
                // Video player
                VideoPlayer(player: player)
                    .frame(width: 400, height: 225)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(userSettings.themeConfiguration.textColor.color.opacity(0.1), lineWidth: 1)
                    )
                    .onAppear {
                        // Don't autoplay - let user control
                    }
                    .onDisappear {
                        player.pause()
                    }
            } else if isLoading {
                // Loading state
                VStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading video...")
                        .font(.system(size: 11))
                        .foregroundColor(userSettings.themeConfiguration.textColor.color.opacity(0.5))
                }
                .frame(width: 400, height: 225)
                .background(userSettings.themeConfiguration.backgroundColor.color.opacity(0.5))
                .cornerRadius(8)
            }
        }
        .onAppear {
            loadVideo()
        }
    }
    
    private func loadVideo() {
        // Verify file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            loadError = "Video file not found"
            isLoading = false
            return
        }
        
        // Create player
        let avPlayer = AVPlayer(url: url)
        self.player = avPlayer
        isLoading = false
    }
}

#Preview {
    VideoPreviewView(url: URL(fileURLWithPath: "/tmp/test.mp4"))
        .environmentObject(UserSettings())
        .padding()
        .background(.black)
}
