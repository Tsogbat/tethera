#!/usr/bin/env swift
// Renders the Tethera app icon: a flat graphite tile, an off-white mark, amber only for the cursor.
//
//   swift scripts/generate_icon.swift icon [a|b|c]       write the icon set + Brand/AppIcon.png
//   swift scripts/generate_icon.swift preview <file.png>  render all variants side by side

import AppKit
import CoreGraphics

let canvas: CGFloat = 1024
let iconSet = "Tethera/Assets.xcassets/AppIcon.appiconset"
let brandIcon = "Tethera/Resources/Brand/AppIcon.png"

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

let tile: UInt32 = 0x141416
let rim: UInt32 = 0x2A2A2E
let ink: UInt32 = 0xECEAE6
let amber: UInt32 = 0xF5A524

/// Apple-style continuous-corner rounded rect.
func squircle(_ rect: CGRect, radius r: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let c = r * 1.18
    let (minX, minY, maxX, maxY) = (rect.minX, rect.minY, rect.maxX, rect.maxY)
    path.move(to: CGPoint(x: minX + c, y: minY))
    path.addLine(to: CGPoint(x: maxX - c, y: minY))
    path.addCurve(to: CGPoint(x: maxX, y: minY + c), control1: CGPoint(x: maxX - c * 0.36, y: minY), control2: CGPoint(x: maxX, y: minY + c * 0.36))
    path.addLine(to: CGPoint(x: maxX, y: maxY - c))
    path.addCurve(to: CGPoint(x: maxX - c, y: maxY), control1: CGPoint(x: maxX, y: maxY - c * 0.36), control2: CGPoint(x: maxX - c * 0.36, y: maxY))
    path.addLine(to: CGPoint(x: minX + c, y: maxY))
    path.addCurve(to: CGPoint(x: minX, y: maxY - c), control1: CGPoint(x: minX + c * 0.36, y: maxY), control2: CGPoint(x: minX, y: maxY - c * 0.36))
    path.addLine(to: CGPoint(x: minX, y: minY + c))
    path.addCurve(to: CGPoint(x: minX + c, y: minY), control1: CGPoint(x: minX, y: minY + c * 0.36), control2: CGPoint(x: minX + c * 0.36, y: minY))
    path.closeSubpath()
    return path
}

func stroke(_ ctx: CGContext, _ color: UInt32, width: CGFloat, cap: CGLineCap = .round, _ build: (CGContext) -> Void) {
    ctx.saveGState()
    ctx.setStrokeColor(rgb(color))
    ctx.setLineWidth(width)
    ctx.setLineCap(cap)
    ctx.setLineJoin(.round)
    build(ctx)
    ctx.strokePath()
    ctx.restoreGState()
}

func fillRounded(_ ctx: CGContext, _ rect: CGRect, radius: CGFloat, _ color: UInt32) {
    ctx.saveGState()
    ctx.setFillColor(rgb(color))
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.fillPath()
    ctx.restoreGState()
}

/// A: lowercase t; the crossbar ends in a cursor.
func markA(_ ctx: CGContext) {
    stroke(ctx, ink, width: 96) { c in
        c.move(to: CGPoint(x: 432, y: 268))
        c.addLine(to: CGPoint(x: 432, y: 650))
        c.addCurve(to: CGPoint(x: 572, y: 772), control1: CGPoint(x: 432, y: 740), control2: CGPoint(x: 490, y: 772))
        c.addLine(to: CGPoint(x: 628, y: 772))
    }
    stroke(ctx, ink, width: 96) { c in
        c.move(to: CGPoint(x: 318, y: 430))
        c.addLine(to: CGPoint(x: 548, y: 430))
    }
    fillRounded(ctx, CGRect(x: 600, y: 382, width: 118, height: 96), radius: 10, amber)
}

/// B: a prompt, tethered to its cursor.
func markB(_ ctx: CGContext) {
    stroke(ctx, ink, width: 92) { c in
        c.move(to: CGPoint(x: 300, y: 362))
        c.addLine(to: CGPoint(x: 452, y: 512))
        c.addLine(to: CGPoint(x: 300, y: 662))
    }
    stroke(ctx, ink, width: 26, cap: .butt) { c in
        c.move(to: CGPoint(x: 470, y: 618))
        c.addLine(to: CGPoint(x: 600, y: 618))
    }
    fillRounded(ctx, CGRect(x: 610, y: 560, width: 120, height: 116), radius: 10, amber)
}

/// C: a solid cursor with a t cut out of it.
func markC(_ ctx: CGContext) {
    let block = CGRect(x: 330, y: 250, width: 364, height: 524)
    fillRounded(ctx, block, radius: 26, amber)
    stroke(ctx, tile, width: 70) { c in
        c.move(to: CGPoint(x: 478, y: 340))
        c.addLine(to: CGPoint(x: 478, y: 590))
        c.addCurve(to: CGPoint(x: 570, y: 676), control1: CGPoint(x: 478, y: 650), control2: CGPoint(x: 520, y: 676))
        c.addLine(to: CGPoint(x: 606, y: 676))
    }
    stroke(ctx, tile, width: 70) { c in
        c.move(to: CGPoint(x: 404, y: 452))
        c.addLine(to: CGPoint(x: 600, y: 452))
    }
}

func renderIcon(size: Int, variant: String) -> CGImage {
    let px = CGFloat(size)
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: px / canvas, y: px / canvas)
    ctx.translateBy(x: 0, y: canvas)
    ctx.scaleBy(x: 1, y: -1)

    // macOS icon grid: an 824pt tile with a soft drop shadow, flat fill and a hairline rim.
    let rect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = squircle(rect, radius: 185)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 28, color: rgb(0x000000, 0.35))
    ctx.addPath(shape)
    ctx.setFillColor(rgb(tile))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.setStrokeColor(rgb(rim))
    ctx.setLineWidth(4)
    ctx.strokePath()
    ctx.restoreGState()

    switch variant {
    case "b": markB(ctx)
    case "c": markC(ctx)
    default: markA(ctx)
    }
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to path: String) {
    guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { fatalError("PNG encode failed") }
    try! data.write(to: URL(fileURLWithPath: path))
}

let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first {
case "preview":
    // Each variant at 512 px, plus 64/32/16 px, on dark and light backgrounds.
    let out = arguments.count > 1 ? arguments[1] : "icon-preview.png"
    let width = 3 * 620, height = 820
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(rgb(0xF2F1EE))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: 410))
    ctx.setFillColor(rgb(0x1C1C1F))
    ctx.fill(CGRect(x: 0, y: 410, width: width, height: 410))
    for (index, variant) in ["a", "b", "c"].enumerated() {
        let x = CGFloat(index * 620 + 40)
        ctx.draw(renderIcon(size: 512, variant: variant), in: CGRect(x: x, y: 300, width: 400, height: 400))
        for (offset, size) in [(450, 64), (530, 32), (580, 16)] {
            let image = renderIcon(size: size, variant: variant)
            ctx.draw(image, in: CGRect(x: x + CGFloat(offset), y: 560, width: CGFloat(size), height: CGFloat(size)))
            ctx.draw(image, in: CGRect(x: x + CGFloat(offset), y: 140, width: CGFloat(size), height: CGFloat(size)))
        }
    }
    writePNG(ctx.makeImage()!, to: out)
    print("Wrote \(out)")

default:
    let variant = arguments.count > 1 ? arguments[1] : "a"
    let sizes: [(String, Int)] = [
        ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
        ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
        ("icon_512x512", 512), ("icon_512x512@2x", 1024),
    ]
    for (name, size) in sizes { writePNG(renderIcon(size: size, variant: variant), to: "\(iconSet)/\(name).png") }
    writePNG(renderIcon(size: 1024, variant: variant), to: brandIcon)
    print("Wrote variant \(variant) to \(iconSet) and \(brandIcon)")
}
