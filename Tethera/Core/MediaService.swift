import Foundation
import AppKit

/// Service for detecting and handling media files (images, etc.)
class MediaService {
    static let shared = MediaService()
    
    /// Supported image extensions
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "bmp", "tiff", "heic", "svg"]
    
    /// Supported video extensions
    static let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "webm", "avi"]
    
    /// PDF support
    static let documentExtensions: Set<String> = ["pdf"]
    
    private init() {}
    
    // MARK: - File Detection
    
    /// Check if file is a previewable image
    func isImage(at path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return Self.imageExtensions.contains(ext)
    }
    
    /// Check if file is a previewable media
    func isPreviewable(at path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return Self.imageExtensions.contains(ext) || 
               Self.documentExtensions.contains(ext)
    }
    
    /// Get full path from potentially relative path
    func resolvePath(_ path: String, workingDirectory: String) -> String {
        if path.hasPrefix("/") {
            return path
        } else if path.hasPrefix("~") {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            return path.replacingOccurrences(of: "~", with: home)
        } else {
            return (workingDirectory as NSString).appendingPathComponent(path)
        }
    }
    
    /// Parse preview command arguments and return valid image paths
    func parsePreviewCommand(_ command: String, workingDirectory: String) -> [URL]? {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check for preview or show command
        guard trimmed.hasPrefix("preview ") || trimmed.hasPrefix("show ") else {
            return nil
        }
        
        // Extract file arguments
        let args = trimmed.split(separator: " ").dropFirst().map(String.init)
        guard !args.isEmpty else { return nil }
        
        var validPaths: [URL] = []
        let fm = FileManager.default
        
        for arg in args {
            let fullPath = resolvePath(arg, workingDirectory: workingDirectory)
            
            // Handle glob patterns (*.png)
            if arg.contains("*") {
                let pattern = fullPath
                if let matches = try? fm.contentsOfDirectory(atPath: (pattern as NSString).deletingLastPathComponent) {
                    let dir = (fullPath as NSString).deletingLastPathComponent
                    let glob = (fullPath as NSString).lastPathComponent.replacingOccurrences(of: "*", with: ".*")
                    
                    for file in matches {
                        let filePath = (dir as NSString).appendingPathComponent(file)
                        if isPreviewable(at: filePath) {
                            // Simple glob match
                            if let regex = try? NSRegularExpression(pattern: "^\(glob)$", options: .caseInsensitive) {
                                let range = NSRange(file.startIndex..., in: file)
                                if regex.firstMatch(in: file, range: range) != nil {
                                    validPaths.append(URL(fileURLWithPath: filePath))
                                }
                            }
                        }
                    }
                }
            } else {
                // Single file
                if fm.fileExists(atPath: fullPath) && isPreviewable(at: fullPath) {
                    validPaths.append(URL(fileURLWithPath: fullPath))
                }
            }
        }
        
        return validPaths.isEmpty ? nil : validPaths
    }
    
    /// Load image from file path
    func loadImage(from url: URL) -> NSImage? {
        return NSImage(contentsOf: url)
    }
}
