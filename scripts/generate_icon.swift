#!/usr/bin/env swift
// Renders the Tethera app icon (1024×1024) and the icon set sizes.
// Usage: swift scripts/generate_icon.swift [output-dir]

import AppKit
import CoreGraphics

let canvas: CGFloat = 1024
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Tethera/Assets.xcassets/AppIcon.appiconset"

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: a)
}

func gradient(_ stops: [(UInt32, CGFloat, CGFloat)]) -> CGGradient {
    let colors = stops.map { rgb($0.0, $0.1) } as CFArray
    let locations = stops.map { $0.2 }
    return CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: locations)!
}

/// Apple-style continuous-corner rounded rect (squircle approximation).
func squircle(_ rect: CGRect, radius: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let r = min(radius, min(rect.width, rect.height) / 2)
    let k: CGFloat = 1.18 // extend the curve for a smoother, continuous corner
    let c = r * k
    let (minX, minY, maxX, maxY) = (rect.minX, rect.minY, rect.maxX, rect.maxY)
    path.move(to: CGPoint(x: minX + c, y: minY))
    path.addLine(to: CGPoint(x: maxX - c, y: minY))
    path.addCurve(to: CGPoint(x: maxX, y: minY + c),
                  control1: CGPoint(x: maxX - c * 0.36, y: minY),
                  control2: CGPoint(x: maxX, y: minY + c * 0.36))
    path.addLine(to: CGPoint(x: maxX, y: maxY - c))
    path.addCurve(to: CGPoint(x: maxX - c, y: maxY),
                  control1: CGPoint(x: maxX, y: maxY - c * 0.36),
                  control2: CGPoint(x: maxX - c * 0.36, y: maxY))
    path.addLine(to: CGPoint(x: minX + c, y: maxY))
    path.addCurve(to: CGPoint(x: minX, y: maxY - c),
                  control1: CGPoint(x: minX + c * 0.36, y: maxY),
                  control2: CGPoint(x: minX, y: maxY - c * 0.36))
    path.addLine(to: CGPoint(x: minX, y: minY + c))
    path.addCurve(to: CGPoint(x: minX + c, y: minY),
                  control1: CGPoint(x: minX, y: minY + c * 0.36),
                  control2: CGPoint(x: minX + c * 0.36, y: minY))
    path.closeSubpath()
    return path
}

func renderIcon(size: Int) -> CGImage {
    let px = CGFloat(size)
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: px / canvas, y: px / canvas)
    // Flip to a top-left origin so the numbers below read naturally.
    ctx.translateBy(x: 0, y: canvas)
    ctx.scaleBy(x: 1, y: -1)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = squircle(body, radius: 186)

    // Drop shadow under the tile.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 14), blur: 34, color: rgb(0x000000, 0.42))
    ctx.addPath(bodyPath)
    ctx.setFillColor(rgb(0x0B0D16))
    ctx.fillPath()
    ctx.restoreGState()

    // Body: deep ink gradient.
    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()
    ctx.drawLinearGradient(gradient([(0x232A45, 1, 0), (0x121628, 1, 0.55), (0x07080F, 1, 1)]),
                           start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
    // Liquid light: violet bloom low-right, cyan bloom high-left.
    ctx.drawRadialGradient(gradient([(0x7B5CFF, 0.55, 0), (0x7B5CFF, 0, 1)]),
                           startCenter: CGPoint(x: 700, y: 860), startRadius: 0,
                           endCenter: CGPoint(x: 700, y: 860), endRadius: 520, options: [])
    ctx.drawRadialGradient(gradient([(0x39D5FF, 0.22, 0), (0x39D5FF, 0, 1)]),
                           startCenter: CGPoint(x: 230, y: 180), startRadius: 0,
                           endCenter: CGPoint(x: 230, y: 180), endRadius: 470, options: [])
    // Glass sheen across the top half.
    ctx.drawRadialGradient(gradient([(0xFFFFFF, 0.11, 0), (0xFFFFFF, 0.04, 0.55), (0xFFFFFF, 0, 1)]),
                           startCenter: CGPoint(x: 512, y: -260), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: -260), endRadius: 760, options: [])
    ctx.restoreGState()

    // Specular rim.
    ctx.saveGState()
    ctx.addPath(squircle(body.insetBy(dx: 2, dy: 2), radius: 184))
    ctx.setLineWidth(3)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    ctx.drawLinearGradient(gradient([(0xFFFFFF, 0.38, 0), (0xFFFFFF, 0.06, 0.45), (0xFFFFFF, 0.14, 1)]),
                           start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
    ctx.restoreGState()

    // ── Mark: a prompt bar (the block) held by a tether ───────────────
    let accentTop: UInt32 = 0x6FE6FF
    let accentBottom: UInt32 = 0x7B5CFF
    let stemX: CGFloat = 512
    let barRect = CGRect(x: 262, y: 300, width: 500, height: 138)
    let nodeCenter = CGPoint(x: stemX, y: 730)
    let nodeRadius: CGFloat = 46

    // Tether glow.
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 60, color: rgb(accentBottom, 0.75))
    ctx.setStrokeColor(rgb(accentBottom, 0.9))
    ctx.setLineWidth(40)
    ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: stemX, y: barRect.maxY - 10))
    ctx.addLine(to: CGPoint(x: stemX, y: nodeCenter.y))
    ctx.strokePath()
    ctx.restoreGState()

    // Tether stem.
    ctx.saveGState()
    let stem = CGMutablePath()
    stem.move(to: CGPoint(x: stemX, y: barRect.maxY - 10))
    stem.addLine(to: CGPoint(x: stemX, y: nodeCenter.y))
    ctx.addPath(stem.copy(strokingWithWidth: 40, lineCap: .round, lineJoin: .round, miterLimit: 1))
    ctx.clip()
    ctx.drawLinearGradient(gradient([(accentTop, 1, 0), (accentBottom, 1, 1)]),
                           start: CGPoint(x: stemX, y: barRect.maxY), end: CGPoint(x: stemX, y: nodeCenter.y + nodeRadius), options: [])
    ctx.restoreGState()

    // Anchor node with a glassy core.
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 48, color: rgb(accentBottom, 0.9))
    ctx.addEllipse(in: CGRect(x: nodeCenter.x - nodeRadius, y: nodeCenter.y - nodeRadius, width: nodeRadius * 2, height: nodeRadius * 2))
    ctx.setFillColor(rgb(accentBottom))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: nodeCenter.x - nodeRadius, y: nodeCenter.y - nodeRadius, width: nodeRadius * 2, height: nodeRadius * 2))
    ctx.clip()
    ctx.drawLinearGradient(gradient([(0x9DF0FF, 1, 0), (accentBottom, 1, 0.7), (0x5A3BE0, 1, 1)]),
                           start: CGPoint(x: nodeCenter.x - 30, y: nodeCenter.y - nodeRadius),
                           end: CGPoint(x: nodeCenter.x + 20, y: nodeCenter.y + nodeRadius), options: [])
    ctx.addEllipse(in: CGRect(x: nodeCenter.x - 24, y: nodeCenter.y - 34, width: 30, height: 20))
    ctx.setFillColor(rgb(0xFFFFFF, 0.55))
    ctx.fillPath()
    ctx.restoreGState()

    // Prompt bar: frosted glass slab.
    let barPath = squircle(barRect, radius: 52)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 18), blur: 36, color: rgb(0x000000, 0.45))
    ctx.addPath(barPath)
    ctx.setFillColor(rgb(0xE9EDFB))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(barPath)
    ctx.clip()
    ctx.drawLinearGradient(gradient([(0xFFFFFF, 1, 0), (0xE3E8F8, 1, 0.55), (0xC4CCEA, 1, 1)]),
                           start: CGPoint(x: 512, y: barRect.minY), end: CGPoint(x: 512, y: barRect.maxY), options: [])
    ctx.restoreGState()
    // Bar rim.
    ctx.saveGState()
    ctx.addPath(barPath)
    ctx.setLineWidth(2)
    ctx.setStrokeColor(rgb(0xFFFFFF, 0.9))
    ctx.strokePath()
    ctx.restoreGState()

    // Chevron.
    let chevronX: CGFloat = barRect.minX + 92
    let midY = barRect.midY
    ctx.saveGState()
    ctx.setStrokeColor(rgb(0x161A2C))
    ctx.setLineWidth(24)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.move(to: CGPoint(x: chevronX, y: midY - 36))
    ctx.addLine(to: CGPoint(x: chevronX + 40, y: midY))
    ctx.addLine(to: CGPoint(x: chevronX, y: midY + 36))
    ctx.strokePath()
    ctx.restoreGState()

    // Cursor: accent capsule.
    let cursor = CGRect(x: chevronX + 82, y: midY + 14, width: 112, height: 24)
    ctx.saveGState()
    let cursorPath = CGPath(roundedRect: cursor, cornerWidth: 12, cornerHeight: 12, transform: nil)
    ctx.addPath(cursorPath)
    ctx.clip()
    ctx.drawLinearGradient(gradient([(accentTop, 1, 0), (accentBottom, 1, 1)]),
                           start: CGPoint(x: cursor.minX, y: cursor.midY), end: CGPoint(x: cursor.maxX, y: cursor.midY), options: [])
    ctx.restoreGState()

    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to path: String) {
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("PNG encode failed") }
    try! data.write(to: URL(fileURLWithPath: path))
}

try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let sizes: [(name: String, px: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for entry in sizes {
    writePNG(renderIcon(size: entry.px), to: "\(outDir)/\(entry.name).png")
}
print("Wrote icon set to \(outDir)")
