import Foundation
import AppKit
import OSLog

struct PreviewParseResult: Equatable {
    let urls: [URL]
    let errors: [String]
}

/// Service for detecting and handling media files (images, etc.)
class MediaService {
    static let shared = MediaService()
    
    /// Supported image extensions
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "bmp", "tiff", "heic", "svg"]
    
    /// Supported video extensions
    static let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "webm", "avi"]
    
    /// PDF support
    static let documentExtensions: Set<String> = ["pdf"]
    
    private let logger = Logger(subsystem: "com.tethera.app", category: "MediaService")

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
        return parsePreviewCommandDetailed(command, workingDirectory: workingDirectory)?.urls
    }

    /// Parse preview command arguments with error reporting
    func parsePreviewCommandDetailed(_ command: String, workingDirectory: String) -> PreviewParseResult? {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check for preview or show command
        guard trimmed.hasPrefix("preview ") || trimmed.hasPrefix("show ") else {
            return nil
        }
        
        // Extract file arguments
        let args = trimmed.split(separator: " ").dropFirst().map(String.init)
        guard !args.isEmpty else { return nil }
        
        var validPaths: [URL] = []
        var errors: [String] = []
        let fm = FileManager.default
        
        for arg in args {
            let fullPath = resolvePath(arg, workingDirectory: workingDirectory)
            
            // Handle glob patterns (*.png)
            if arg.contains("*") {
                let dir = (fullPath as NSString).deletingLastPathComponent
                let glob = (fullPath as NSString).lastPathComponent.replacingOccurrences(of: "*", with: ".*")
                let regex: NSRegularExpression?
                do {
                    regex = try NSRegularExpression(pattern: "^\(glob)$", options: .caseInsensitive)
                } catch {
                    let message = "Invalid glob pattern: \(arg)"
                    errors.append(message)
                    logger.error("\(message)")
                    continue
                }
                
                let matches: [String]
                do {
                    matches = try fm.contentsOfDirectory(atPath: dir)
                } catch {
                    let message = "Failed to list directory: \(dir)"
                    errors.append(message)
                    logger.error("\(message)")
                    continue
                }
                
                var matchedFiles: [URL] = []
                for file in matches {
                    let range = NSRange(file.startIndex..., in: file)
                    if regex?.firstMatch(in: file, range: range) != nil {
                        let filePath = (dir as NSString).appendingPathComponent(file)
                        if isPreviewable(at: filePath) {
                            matchedFiles.append(URL(fileURLWithPath: filePath))
                        }
                    }
                }
                
                if matchedFiles.isEmpty {
                    errors.append("No previewable files found for: \(arg)")
                } else {
                    validPaths.append(contentsOf: matchedFiles)
                }
            } else {
                // Single file
                if !fm.fileExists(atPath: fullPath) {
                    errors.append("File not found: \(arg)")
                } else if !isPreviewable(at: fullPath) {
                    errors.append("Unsupported file type: \(arg)")
                } else {
                    validPaths.append(URL(fileURLWithPath: fullPath))
                }
            }
        }
        
        if validPaths.isEmpty && errors.isEmpty {
            return nil
        }
        return PreviewParseResult(urls: validPaths, errors: errors)
    }
    
    /// Load image from file path
    func loadImage(from url: URL) -> NSImage? {
        return NSImage(contentsOf: url)
    }
}
