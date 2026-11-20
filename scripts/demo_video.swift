// Makes the demo video from screenshots, with AVFoundation (no ffmpeg):
//
//   swift scripts/demo_video.swift out.mp4 "image.png|Caption" "other.png|Another caption" …
//
// Each shot holds for a few seconds under its caption, with a crossfade between shots.
import AVFoundation
import AppKit
import CoreText

let width = 1600, height = 1040, fps: Int32 = 30
let hold = 3.4, fade = 0.5
let background = CGColor(red: 0.067, green: 0.067, blue: 0.067, alpha: 1)
let ink = NSColor(srgbRed: 0.949, green: 0.941, blue: 0.929, alpha: 1)

let arguments = CommandLine.arguments.dropFirst()
guard let output = arguments.first, arguments.count > 1 else {
    FileHandle.standardError.write(Data("usage: demo_video.swift out.mp4 \"image.png|caption\" …\n".utf8))
    exit(1)
}
let slides: [(CGImage, String)] = arguments.dropFirst().map { entry in
    let parts = entry.split(separator: "|", maxSplits: 1).map(String.init)
    guard let image = NSImage(contentsOfFile: parts[0])?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        FileHandle.standardError.write(Data("can't read \(parts[0])\n".utf8))
        exit(1)
    }
    return (image, parts.count > 1 ? parts[1] : "")
}

/// One slide: the shot fitted above its caption.
func render(_ image: CGImage, _ caption: String) -> CGImage {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)!
    context.setFillColor(background)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let captionHeight: CGFloat = 130
    let box = CGRect(x: 60, y: captionHeight, width: CGFloat(width) - 120, height: CGFloat(height) - captionHeight - 40)
    let scale = min(box.width / CGFloat(image.width), box.height / CGFloat(image.height))
    let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: box.midX - size.width / 2, y: box.midY - size.height / 2, width: size.width, height: size.height))
    let font = NSFont.systemFont(ofSize: 38, weight: .semibold)
    let text = NSAttributedString(string: caption, attributes: [.font: font, .foregroundColor: ink])
    let line = CTLineCreateWithAttributedString(text)
    let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
    context.textPosition = CGPoint(x: (CGFloat(width) - bounds.width) / 2, y: 52)
    CTLineDraw(line, context)
    return context.makeImage()!
}

let frames = slides.map { render($0.0, $0.1) }
let url = URL(fileURLWithPath: output)
try? FileManager.default.removeItem(at: url)
let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
    AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 2_400_000, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel],
])
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
])
writer.add(input)
writer.startWriting()
writer.startSession(atSourceTime: .zero)

func append(_ draw: (CGContext) -> Void, at frame: Int) {
    while !input.isReadyForMoreMediaData { usleep(2_000) }
    var buffer: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
    guard let buffer else { return }
    CVPixelBufferLockBaseAddress(buffer, [])
    let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)!
    draw(context)
    CVPixelBufferUnlockBaseAddress(buffer, [])
    adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps))
}

let rect = CGRect(x: 0, y: 0, width: width, height: height)
var frame = 0
for (index, image) in frames.enumerated() {
    for _ in 0..<Int(hold * Double(fps)) {
        append({ $0.draw(image, in: rect) }, at: frame)
        frame += 1
    }
    guard index + 1 < frames.count else { break }
    let next = frames[index + 1]
    let steps = Int(fade * Double(fps))
    for step in 0..<steps {
        let t = CGFloat(step + 1) / CGFloat(steps)
        append({ context in
            context.draw(image, in: rect)
            context.setAlpha(t)
            context.draw(next, in: rect)
        }, at: frame)
        frame += 1
    }
}
input.markAsFinished()
let done = DispatchSemaphore(value: 0)
writer.finishWriting { done.signal() }
done.wait()
if writer.status != .completed {
    FileHandle.standardError.write(Data("failed: \(writer.error?.localizedDescription ?? "unknown")\n".utf8))
    exit(1)
}
print("wrote \(output): \(frames.count) shots, \(String(format: "%.1f", Double(frame) / Double(fps))) s")
