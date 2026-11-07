import AppKit
import SceneKit

/// Tethera's object: a small retro all-in-one computer and its oversized, few-key keyboard.
///
/// One model, three uses: the app icon (`scripts/render_icon.swift`), Home and About.
/// The website's three.js scene (`docs/js/scene.js`) is built from the same numbers.
/// Units: 1 ≈ 10 cm, y up, the computer faces +z, the origin is on the floor under it.
/// Self-contained (AppKit + SceneKit only) so the icon script can compile it on its own.
final class RetroComputer {
    enum Palette {
        static let cream = NSColor(retroHex: 0xE9E3D3)
        static let creamShade = NSColor(retroHex: 0xDED6C4)
        static let plinth = NSColor(retroHex: 0xDCD4C2)
        static let graphite = NSColor(retroHex: 0x2B2B2E)
        static let bone = NSColor(retroHex: 0xF2F0ED)
        static let ink = NSColor(retroHex: 0x1A1A1A)
        static let screen = NSColor(retroHex: 0x0E0E0F)
        static let slot = NSColor(retroHex: 0x2A2826)
    }

    /// Keys on the keyboard, back row first. `return` is the long bone key.
    static let keyNames = ["esc", "⌘", "K", "D", "t", "return"]

    let scene = SCNScene()
    /// Everything that moves together (idle float, hover tilt).
    let rig = SCNNode()
    let computer = SCNNode()
    private(set) var keyboard: SCNNode?
    private(set) var keys: [String: SCNNode] = [:]
    private let screenMaterial = SCNMaterial()
    private var keyRest: [String: SCNVector3] = [:]

    init(keyboard withKeyboard: Bool = true, screen: NSImage? = nil) {
        scene.rootNode.addChildNode(rig)
        rig.addChildNode(computer)
        buildComputer()
        if withKeyboard { buildKeyboard() }
        setScreen(screen ?? RetroScreen.prompt())
    }

    // MARK: Screen

    /// Shows an image on the CRT. It's lit from within, so it reads in any lighting.
    func setScreen(_ image: NSImage) {
        screenMaterial.diffuse.contents = image
        screenMaterial.emission.contents = image
    }

    // MARK: Keys

    /// Presses a key with a soft spring: down fast, back up past rest, settle.
    func press(_ name: String) {
        guard let key = keys[name], let rest = keyRest[name] else { return }
        key.removeAction(forKey: "press")
        key.position = rest
        let travel: CGFloat = 0.22
        func move(_ dy: CGFloat, _ duration: TimeInterval, _ mode: SCNActionTimingMode) -> SCNAction {
            let action = SCNAction.move(to: SCNVector3(rest.x, rest.y + dy, rest.z), duration: duration)
            action.timingMode = mode
            return action
        }
        let squash = SCNAction.sequence([
            SCNAction.scale(to: 0.96, duration: 0.07),
            SCNAction.scale(to: 1.0, duration: 0.25),
        ])
        let spring = SCNAction.sequence([
            move(-travel, 0.07, .easeOut),
            move(0.05, 0.16, .easeOut),
            move(-0.015, 0.12, .easeInEaseOut),
            move(0, 0.1, .easeInEaseOut),
        ])
        key.runAction(.group([spring, squash]), forKey: "press")
        if let keyboard {
            keyboard.removeAction(forKey: "wobble")
            let tilt = SCNAction.sequence([
                SCNAction.rotateBy(x: 0.012, y: 0, z: 0, duration: 0.08),
                SCNAction.rotateBy(x: -0.018, y: 0, z: 0, duration: 0.18),
                SCNAction.rotateBy(x: 0.006, y: 0, z: 0, duration: 0.16),
            ])
            keyboard.runAction(tilt, forKey: "wobble")
        }
    }

    /// The key a hit-test result belongs to, if any.
    func keyName(for node: SCNNode) -> String? {
        var current: SCNNode? = node
        while let candidate = current {
            if let name = candidate.name, keys[name] === candidate { return name }
            current = candidate.parent
        }
        return nil
    }

    // MARK: Lighting

    /// A soft studio: an environment of two softboxes for reflections, one shadow-casting key
    /// light and a floor that only receives shadows (so any background shows through).
    func addStudio(dark: Bool) {
        scene.lightingEnvironment.contents = RetroScreen.studioEnvironment()
        scene.lightingEnvironment.intensity = dark ? 1.15 : 1.35

        let key = SCNLight()
        key.type = .directional
        key.intensity = dark ? 650 : 800
        key.color = NSColor(white: 1, alpha: 1)
        key.castsShadow = true
        key.shadowMode = .deferred
        key.shadowRadius = 14
        key.shadowSampleCount = 24
        key.shadowColor = NSColor(white: 0, alpha: dark ? 0.55 : 0.28)
        key.orthographicScale = 6
        key.shadowMapSize = CGSize(width: 2048, height: 2048)
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.position = SCNVector3(3, 7, 5)
        keyNode.look(at: SCNVector3(0, 1, 0.8))
        scene.rootNode.addChildNode(keyNode)

        let fill = SCNLight()
        fill.type = .ambient
        fill.intensity = dark ? 140 : 220
        let fillNode = SCNNode()
        fillNode.light = fill
        scene.rootNode.addChildNode(fillNode)

        let floor = SCNFloor()
        floor.reflectivity = 0
        let shadowOnly = SCNMaterial()
        shadowOnly.lightingModel = .shadowOnly
        floor.firstMaterial = shadowOnly
        let floorNode = SCNNode(geometry: floor)
        floorNode.castsShadow = false
        scene.rootNode.addChildNode(floorNode)
    }

    /// A perspective camera looking at the computer from `position`.
    @discardableResult
    func addCamera(at position: SCNVector3, lookingAt target: SCNVector3, fov: CGFloat = 30) -> SCNNode {
        let camera = SCNCamera()
        camera.fieldOfView = fov
        camera.zNear = 0.1
        camera.zFar = 100
        camera.wantsHDR = true
        camera.wantsExposureAdaptation = false
        camera.exposureOffset = 0
        camera.whitePoint = 1.2
        let node = SCNNode()
        node.camera = camera
        node.position = position
        node.look(at: target)
        scene.rootNode.addChildNode(node)
        return node
    }

    // MARK: Model

    private func plastic(_ color: NSColor, roughness: CGFloat = 0.55, clearCoat: CGFloat = 0.25) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = color
        material.roughness.contents = roughness
        material.metalness.contents = 0.0
        material.clearCoat.contents = clearCoat
        material.clearCoatRoughness.contents = 0.6
        return material
    }

    private func box(_ w: CGFloat, _ h: CGFloat, _ d: CGFloat, chamfer: CGFloat, _ material: SCNMaterial) -> SCNNode {
        let geometry = SCNBox(width: w, height: h, length: d, chamferRadius: chamfer)
        geometry.chamferSegmentCount = 8
        geometry.firstMaterial = material
        return SCNNode(geometry: geometry)
    }

    private func panel(_ w: CGFloat, _ h: CGFloat, radius: CGFloat, depth: CGFloat, _ material: SCNMaterial) -> SCNNode {
        let path = NSBezierPath(roundedRect: NSRect(x: -w / 2, y: -h / 2, width: w, height: h), xRadius: radius, yRadius: radius)
        path.flatness = 0.002
        let shape = SCNShape(path: path, extrusionDepth: depth)
        shape.chamferRadius = min(depth / 2, 0.012)
        shape.firstMaterial = material
        return SCNNode(geometry: shape)
    }

    private func buildComputer() {
        let cream = plastic(Palette.cream)
        let plinth = box(2.2, 0.14, 2.0, chamfer: 0.06, plastic(Palette.plinth, roughness: 0.7, clearCoat: 0))
        plinth.position = SCNVector3(0, 0.07, 0)
        computer.addChildNode(plinth)

        let body = box(2.4, 2.8, 2.2, chamfer: 0.26, cream)
        body.position = SCNVector3(0, 1.54, 0)
        computer.addChildNode(body)

        // The front face sits at z = 1.1. The bezel is a slightly darker plate, the screen on it.
        let bezel = panel(1.96, 1.6, radius: 0.2, depth: 0.04, plastic(Palette.creamShade, roughness: 0.6, clearCoat: 0.1))
        bezel.position = SCNVector3(0, 1.98, 1.1)
        computer.addChildNode(bezel)

        let screen = SCNPlane(width: 1.64, height: 1.26)
        screen.cornerRadius = 0.12
        screenMaterial.lightingModel = .physicallyBased
        screenMaterial.roughness.contents = 0.18
        screenMaterial.metalness.contents = 0.0
        screenMaterial.emission.intensity = 0.95
        screenMaterial.diffuse.mipFilter = .linear
        screenMaterial.emission.mipFilter = .linear
        screenMaterial.diffuse.intensity = 0.15
        screen.firstMaterial = screenMaterial
        let screenNode = SCNNode(geometry: screen)
        screenNode.name = "screen"
        screenNode.position = SCNVector3(0, 1.98, 1.125)
        computer.addChildNode(screenNode)

        // A clear glass layer in front of the picture gives the CRT its sheen.
        let glass = SCNPlane(width: 1.64, height: 1.26)
        glass.cornerRadius = 0.12
        let glassMaterial = SCNMaterial()
        glassMaterial.lightingModel = .physicallyBased
        glassMaterial.diffuse.contents = NSColor(white: 0, alpha: 1)
        glassMaterial.roughness.contents = 0.08
        glassMaterial.metalness.contents = 0.0
        glassMaterial.transparency = 0.18
        glassMaterial.blendMode = .add
        glassMaterial.writesToDepthBuffer = false
        glass.firstMaterial = glassMaterial
        let glassNode = SCNNode(geometry: glass)
        glassNode.position = SCNVector3(0, 1.98, 1.135)
        computer.addChildNode(glassNode)

        let dark = plastic(Palette.slot, roughness: 0.8, clearCoat: 0)
        let slot = box(0.72, 0.07, 0.03, chamfer: 0.012, dark)
        slot.position = SCNVector3(0.48, 0.72, 1.1)
        computer.addChildNode(slot)

        let groove = plastic(Palette.creamShade, roughness: 0.8, clearCoat: 0)
        for index in 0..<5 {
            let line = box(0.36, 0.025, 0.02, chamfer: 0.01, groove)
            line.position = SCNVector3(-0.62, 0.6 + CGFloat(index) * 0.06, 1.1)
            computer.addChildNode(line)
        }

        let led = SCNCylinder(radius: 0.03, height: 0.02)
        let ledMaterial = plastic(Palette.bone, roughness: 0.3, clearCoat: 0.5)
        ledMaterial.emission.contents = Palette.bone
        ledMaterial.emission.intensity = 0.35
        led.firstMaterial = ledMaterial
        let ledNode = SCNNode(geometry: led)
        ledNode.eulerAngles.x = .pi / 2
        ledNode.position = SCNVector3(-0.9, 0.72, 1.105)
        computer.addChildNode(ledNode)
    }

    private func buildKeyboard() {
        let slab = box(3.8, 0.34, 2.0, chamfer: 0.14, plastic(Palette.cream))
        slab.position = SCNVector3(0, 0.17, 2.75)
        slab.eulerAngles.x = 4 * .pi / 180
        rig.addChildNode(slab)
        keyboard = slab

        let unit: CGFloat = 0.8, gap: CGFloat = 0.08
        let back: CGFloat = -0.44, front: CGFloat = 0.44
        let layout: [(String, CGFloat, CGFloat, CGFloat)] = [
            ("esc", -1.32, back, unit), ("⌘", -0.44, back, unit), ("K", 0.44, back, unit), ("D", 1.32, back, unit),
            ("t", -1.32, front, unit), ("return", 0.44, front, 4 * unit + 3 * gap - unit - gap),
        ]
        for (name, x, z, width) in layout {
            let isReturn = name == "return"
            let cap = box(width, 0.34, unit, chamfer: 0.14,
                          plastic(isReturn ? Palette.bone : Palette.graphite, roughness: isReturn ? 0.5 : 0.62, clearCoat: 0.15))
            cap.name = name
            cap.position = SCNVector3(x, 0.17 + 0.17, z)
            cap.castsShadow = true

            let legend = SCNPlane(width: width - 0.2, height: unit - 0.2)
            let legendMaterial = SCNMaterial()
            legendMaterial.lightingModel = .constant
            legendMaterial.diffuse.contents = RetroScreen.legend(name, size: CGSize(width: (width - 0.2) * 640, height: (unit - 0.2) * 640),
                                                                 color: isReturn ? Palette.ink : Palette.bone)
            legendMaterial.writesToDepthBuffer = false
            legendMaterial.diffuse.mipFilter = .linear
            legendMaterial.diffuse.minificationFilter = .linear
            legend.firstMaterial = legendMaterial
            let legendNode = SCNNode(geometry: legend)
            legendNode.eulerAngles.x = -.pi / 2
            legendNode.position = SCNVector3(0, 0.171, 0)
            cap.addChildNode(legendNode)

            slab.addChildNode(cap)
            keys[name] = cap
            keyRest[name] = cap.position
        }

        // A coiled cable from the keyboard's back-left corner to the computer's left side.
        let cable = SCNNode(geometry: RetroComputer.coiledCable(
            from: SCNVector3(-1.5, 0.25, 1.75), via: SCNVector3(-1.75, 0.08, 1.05), to: SCNVector3(-1.2, 0.45, 0.3),
            coilRadius: 0.055, turns: 16, wire: 0.03))
        cable.geometry?.firstMaterial = plastic(Palette.graphite, roughness: 0.45, clearCoat: 0.3)
        rig.addChildNode(cable)
    }

    /// A tube swept along a helix that winds around a quadratic Bézier.
    static func coiledCable(from a: SCNVector3, via b: SCNVector3, to c: SCNVector3, coilRadius: CGFloat, turns: CGFloat, wire: CGFloat) -> SCNGeometry {
        func lerp(_ p: SCNVector3, _ q: SCNVector3, _ t: CGFloat) -> SCNVector3 {
            SCNVector3(p.x + (q.x - p.x) * t, p.y + (q.y - p.y) * t, p.z + (q.z - p.z) * t)
        }
        func curve(_ t: CGFloat) -> SCNVector3 { lerp(lerp(a, b, t), lerp(b, c, t), t) }
        let steps = 900, sides = 10
        var centers: [SIMD3<Float>] = []
        // Parallel-transport frame along the base curve, then wind around it.
        var normal = SIMD3<Float>(0, 1, 0)
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let p = curve(t), q = curve(min(1, t + 0.001)), r = curve(max(0, t - 0.001))
            let point = SIMD3<Float>(Float(p.x), Float(p.y), Float(p.z))
            let tangent = simd_normalize(SIMD3<Float>(Float(q.x - r.x), Float(q.y - r.y), Float(q.z - r.z)))
            normal = simd_normalize(normal - simd_dot(normal, tangent) * tangent)
            let binormal = simd_cross(tangent, normal)
            // Straight ends where the cable enters each part.
            let ease = Float(min(1, min(t, 1 - t) * 14))
            let angle = Float(t * turns * 2 * .pi)
            let offset = (cos(angle) * normal + sin(angle) * binormal) * Float(coilRadius) * ease
            centers.append(point + offset)
        }
        var vertices: [SCNVector3] = [], normals: [SCNVector3] = [], indices: [Int32] = []
        var ringNormal = SIMD3<Float>(0, 1, 0)
        for (i, center) in centers.enumerated() {
            let next = centers[min(i + 1, centers.count - 1)], previous = centers[max(i - 1, 0)]
            let tangent = simd_normalize(next - previous)
            ringNormal = simd_normalize(ringNormal - simd_dot(ringNormal, tangent) * tangent)
            let binormal = simd_cross(tangent, ringNormal)
            for s in 0..<sides {
                let angle = Float(s) / Float(sides) * 2 * .pi
                let n = cos(angle) * ringNormal + sin(angle) * binormal
                let v = center + n * Float(wire)
                vertices.append(SCNVector3(CGFloat(v.x), CGFloat(v.y), CGFloat(v.z)))
                normals.append(SCNVector3(CGFloat(n.x), CGFloat(n.y), CGFloat(n.z)))
            }
        }
        for i in 0..<(centers.count - 1) {
            for s in 0..<sides {
                let a = Int32(i * sides + s), b = Int32(i * sides + (s + 1) % sides)
                let c = a + Int32(sides), d = b + Int32(sides)
                indices += [a, c, b, b, c, d]
            }
        }
        return SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals)],
                           elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
    }
}

/// Pictures for the CRT and the keycaps, drawn in the same monochrome as the app.
enum RetroScreen {
    static let size = CGSize(width: 820, height: 630)

    /// A font for the screen: Geist Mono when it's registered, otherwise the system monospace.
    static func mono(_ size: CGFloat, _ weight: NSFont.Weight = .medium) -> NSFont {
        let name = weight == .bold ? "GeistMono-Bold" : (weight == .regular ? "GeistMono-Regular" : "GeistMono-Medium")
        return NSFont(name: name, size: size) ?? .monospacedSystemFont(ofSize: size, weight: weight)
    }

    private static func draw(_ size: CGSize = RetroScreen.size, _ body: @escaping (CGRect) -> Void) -> NSImage {
        let image = NSImage(size: size, flipped: true) { rect in
            Palette.screen.setFill()
            rect.fill()
            body(rect)
            return true
        }
        return image
    }

    private typealias Palette = RetroComputer.Palette

    /// `t_`, the icon's screen and the idle state.
    static func prompt(cursor: Bool = true) -> NSImage {
        draw { rect in
            let font = mono(rect.height * 0.42, .medium)
            let text = NSAttributedString(string: "t", attributes: [.font: font, .foregroundColor: Palette.bone])
            let textSize = text.size()
            let cursorWidth = textSize.width * 0.9
            let total = textSize.width + cursorWidth * 1.08
            let x = (rect.width - total) / 2
            let y = (rect.height - textSize.height) / 2 - rect.height * 0.02
            text.draw(at: CGPoint(x: x, y: y))
            if cursor {
                Palette.bone.setFill()
                NSRect(x: x + textSize.width + cursorWidth * 0.08, y: y + textSize.height * 0.78,
                       width: cursorWidth, height: rect.height * 0.055).fill()
            }
        }
    }

    /// A few lines of text, top-left, like a terminal. The first line is the title.
    static func lines(_ lines: [String], highlight: Int? = nil) -> NSImage {
        draw { rect in
            let font = mono(rect.height * 0.068, .medium)
            var y = rect.height * 0.13
            for (index, line) in lines.enumerated() {
                let color = index == highlight || index == 0 ? Palette.bone : Palette.bone.withAlphaComponent(0.55)
                NSAttributedString(string: line, attributes: [.font: font, .foregroundColor: color])
                    .draw(at: CGPoint(x: rect.width * 0.09, y: y))
                y += font.pointSize * 1.55
            }
        }
    }

    /// A big number with a caption, e.g. how many agents need you.
    static func count(_ value: Int, caption: String) -> NSImage {
        draw { rect in
            let big = NSAttributedString(string: "\(value)", attributes: [.font: mono(rect.height * 0.42, .medium), .foregroundColor: Palette.bone])
            let small = NSAttributedString(string: caption, attributes: [.font: mono(rect.height * 0.075, .medium),
                                                                         .foregroundColor: Palette.bone.withAlphaComponent(0.7)])
            let bigSize = big.size(), smallSize = small.size()
            let top = (rect.height - bigSize.height - smallSize.height) / 2
            big.draw(at: CGPoint(x: (rect.width - bigSize.width) / 2, y: top))
            small.draw(at: CGPoint(x: (rect.width - smallSize.width) / 2, y: top + bigSize.height))
        }
    }

    /// A keycap legend on a transparent background.
    static func legend(_ name: String, size: CGSize, color: NSColor) -> NSImage {
        NSImage(size: size, flipped: true) { rect in
            let label = name == "⌘" ? "⌘" : name
            let font = name == "⌘" ? NSFont.systemFont(ofSize: rect.height * 0.34, weight: .medium) : mono(rect.height * 0.27, .bold)
            let text = NSAttributedString(string: label, attributes: [.font: font, .foregroundColor: color])
            // Legends sit top-left, like real keycaps.
            text.draw(at: CGPoint(x: rect.height * 0.08, y: rect.height * 0.04))
            return true
        }
    }

    /// An equirectangular studio: dim walls, a big softbox overhead-front and a strip on the right.
    static func studioEnvironment() -> NSImage {
        let size = CGSize(width: 1024, height: 512)
        return NSImage(size: size, flipped: true) { rect in
            NSColor(white: 0.32, alpha: 1).setFill()
            rect.fill()
            NSColor(white: 0.18, alpha: 1).setFill()
            NSRect(x: 0, y: rect.height * 0.55, width: rect.width, height: rect.height * 0.45).fill()
            func softbox(_ box: NSRect, _ white: CGFloat) {
                for step in stride(from: 1.0, through: 0.0, by: -0.1) {
                    NSColor(white: white * (1 - step * 0.6), alpha: 0.25).setFill()
                    NSBezierPath(roundedRect: box.insetBy(dx: -step * 40, dy: -step * 30), xRadius: 30, yRadius: 30).fill()
                }
                NSColor(white: white, alpha: 1).setFill()
                NSBezierPath(roundedRect: box, xRadius: 20, yRadius: 20).fill()
            }
            softbox(NSRect(x: rect.width * 0.38, y: rect.height * 0.08, width: rect.width * 0.24, height: rect.height * 0.2), 1.0)
            softbox(NSRect(x: rect.width * 0.7, y: rect.height * 0.25, width: rect.width * 0.06, height: rect.height * 0.3), 0.85)
            softbox(NSRect(x: rect.width * 0.12, y: rect.height * 0.3, width: rect.width * 0.08, height: rect.height * 0.18), 0.5)
            return true
        }
    }
}

extension NSColor {
    convenience init(retroHex hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
