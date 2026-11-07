// Renders Tethera's icon and brand images from the 3D model in Tethera/Views/Retro/RetroComputer.swift.
//
//   scripts/render_icon.sh icon             write the app icon set, Brand/AppIcon.png and docs/assets/icon*.png
//   scripts/render_icon.sh preview <out>    a contact sheet: the icon at 512/128/64/32/16 on dark and light
//   scripts/render_icon.sh shot <out>       the whole rig with its keyboard, for checking the model

import AppKit
import CoreText
import Metal
import SceneKit

@main
struct RenderIcon {
    static let iconSet = "Tethera/Assets.xcassets/AppIcon.appiconset"
    static let brandIcon = "Tethera/Resources/Brand/AppIcon.png"
    static let tile = NSColor(retroHex: 0x1A1A1C)

    static func main() {
        for url in (try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: "Tethera/Fonts"), includingPropertiesForKeys: nil)) ?? []
        where url.pathExtension == "ttf" {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        let arguments = Array(CommandLine.arguments.dropFirst())
        switch arguments.first {
        case "preview":
            writePNG(contactSheet(), to: arguments.count > 1 ? arguments[1] : "icon-preview.png")
        case "shot":
            let model = RetroComputer(keyboard: true)
            model.addStudio(dark: false)
            model.addCamera(at: SCNVector3(5.6, 5.2, 10.5), lookingAt: SCNVector3(0, 1.1, 1.4), fov: 30)
            writePNG(render(model, size: CGSize(width: 1600, height: 1200), background: NSColor(retroHex: 0xE7E4DE)),
                     to: arguments.count > 1 ? arguments[1] : "rig.png")
        default:
            let master = icon(size: 1024)
            let sizes: [(String, Int)] = [
                ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
                ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
                ("icon_512x512", 512), ("icon_512x512@2x", 1024),
            ]
            for (name, size) in sizes { writePNG(resize(master, to: size), to: "\(iconSet)/\(name).png") }
            writePNG(master, to: brandIcon)
            writePNG(master, to: "docs/assets/icon.png")
            writePNG(resize(master, to: 256), to: "docs/assets/icon-256.png")
            writePNG(resize(master, to: 64), to: "docs/assets/icon-64.png")
            print("Wrote \(iconSet), \(brandIcon) and docs/assets/icon*.png")
        }
    }

    /// Renders the model with a transparent background (the floor still catches its shadow).
    static func render(_ model: RetroComputer, size: CGSize, background: NSColor = .clear) -> CGImage {
        model.scene.background.contents = background
        let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        renderer.scene = model.scene
        renderer.pointOfView = model.scene.rootNode.childNodes.first { $0.camera != nil }
        let image = renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
        var rect = CGRect(origin: .zero, size: size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)!
    }

    /// The icon: a graphite tile on the macOS grid, the computer standing on it in ¾ view.
    static func icon(size: Int) -> CGImage {
        let model = RetroComputer(keyboard: false)
        model.addStudio(dark: true)
        model.addCamera(at: SCNVector3(3.4, 3.0, 8.6), lookingAt: SCNVector3(0.12, 1.36, 0.2), fov: 26.5)
        let picture = render(model, size: CGSize(width: 2048, height: 2048))

        let px = CGFloat(size), canvas: CGFloat = 1024
        let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = .high
        ctx.scaleBy(x: px / canvas, y: px / canvas)

        let rect = CGRect(x: 100, y: 100, width: 824, height: 824)
        let shape = squircle(rect, radius: 185)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: NSColor(white: 0, alpha: 0.35).cgColor)
        ctx.addPath(shape)
        ctx.setFillColor(tile.cgColor)
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(shape)
        ctx.clip()
        ctx.draw(picture, in: rect.insetBy(dx: -40, dy: -40).offsetBy(dx: 0, dy: 6))
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(shape)
        ctx.setStrokeColor(NSColor(white: 1, alpha: 0.07).cgColor)
        ctx.setLineWidth(3)
        ctx.strokePath()
        ctx.restoreGState()
        return ctx.makeImage()!
    }

    static func contactSheet() -> CGImage {
        let master = icon(size: 1024)
        let width = 1240, height = 1100
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(NSColor(retroHex: 0xE7E4DE).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: 550))
        ctx.setFillColor(NSColor(retroHex: 0x1C1C1F).cgColor)
        ctx.fill(CGRect(x: 0, y: 550, width: width, height: 550))
        for base in [0, 550] {
            ctx.draw(master, in: CGRect(x: 30, y: base + 25, width: 500, height: 500))
            var x = 580
            for size in [128, 64, 32, 16] {
                ctx.draw(resize(master, to: size), in: CGRect(x: x, y: base + 275 - size / 2, width: size, height: size))
                x += size + 60
            }
        }
        return ctx.makeImage()!
    }

    static func resize(_ image: CGImage, to size: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        return ctx.makeImage()!
    }

    /// Apple-style continuous-corner rounded rect.
    static func squircle(_ rect: CGRect, radius r: CGFloat) -> CGPath {
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

    static func writePNG(_ image: CGImage, to path: String) {
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { fatalError("PNG encode failed") }
        try! data.write(to: URL(fileURLWithPath: path))
        print("Wrote \(path)")
    }
}
