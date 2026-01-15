import Metal
import MetalKit
import Foundation
import CoreText

class MetalRenderer: NSObject {
    private var device: MTLDevice!
    private var commandQueue: MTLCommandQueue!
    private var pipelineState: MTLRenderPipelineState!
    private var vertexBuffer: MTLBuffer!
    private var indexBuffer: MTLBuffer!
    private var fontAtlas: MTLTexture!
    private var fontAtlasData: [Character: FontGlyph] = [:]
    private var atlasSize = CGSize(width: 512, height: 512)
    private var font: CTFont?
    
    private(set) var cellSize = CGSize(width: 8, height: 16)
    private var columns = 80
    private var rows = 24
    
    private var vertexData: [Float] = []
    private var needsVertexUpdate = true
    
    struct FontGlyph {
        let x: Float
        let y: Float
        let width: Float
        let height: Float
    }
    
    struct Vertex {
        let position: SIMD2<Float>
        let texCoord: SIMD2<Float>
        let color: SIMD4<Float>
    }
    
    override init() {
        super.init()
        setupMetal()
        createFontAtlas()
    }
    
    private func setupMetal() {
        device = MTLCreateSystemDefaultDevice()
        guard device != nil else {
            fatalError("Metal is not supported on this device")
        }
        
        commandQueue = device.makeCommandQueue()
        createPipelineState()
        createBuffers()
    }
    
    private func createPipelineState() {
        let library = device.makeDefaultLibrary()
        let vertexFunction = library?.makeFunction(name: "vertex_main")
        let fragmentFunction = library?.makeFunction(name: "fragment_main")
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        
        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            fatalError("Failed to create pipeline state: \(error)")
        }
    }
    
    private func createBuffers() {
        // Create vertex buffer (will be updated dynamically)
        let vertexBufferSize = columns * rows * 4 * MemoryLayout<Vertex>.size
        vertexBuffer = device.makeBuffer(length: vertexBufferSize, options: [])
        
        // Create index buffer for quads
        var indices: [UInt16] = []
        for i in 0..<(columns * rows) {
            let base = UInt16(i * 4)
            indices.append(contentsOf: [base, base + 1, base + 2, base, base + 2, base + 3])
        }
        indexBuffer = device.makeBuffer(bytes: indices, length: indices.count * MemoryLayout<UInt16>.size, options: [])
    }
    
    private func createFontAtlas() {
        // Build a basic ASCII glyph atlas using CoreText (32-126)
        let fontName = "Menlo"
        let fontSize: CGFloat = 14
        let ctFont = CTFontCreateWithName(fontName as CFString, fontSize, nil)
        font = ctFont
        
        let ascent = CTFontGetAscent(ctFont)
        let descent = CTFontGetDescent(ctFont)
        let leading = CTFontGetLeading(ctFont)
        var glyph = CTFontGetGlyphWithName(ctFont, "M" as CFString)
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(ctFont, .horizontal, &glyph, &advance, 1)
        
        let cellWidth = max(1, ceil(advance.width))
        let cellHeight = max(1, ceil(ascent + descent + leading))
        cellSize = CGSize(width: cellWidth, height: cellHeight)
        
        let glyphs: [UInt32] = Array(32...126)
        let columns = 16
        let rows = Int(ceil(Double(glyphs.count) / Double(columns)))
        let atlasWidth = Int(cellWidth) * columns
        let atlasHeight = Int(cellHeight) * rows
        atlasSize = CGSize(width: CGFloat(atlasWidth), height: CGFloat(atlasHeight))
        
        let bytesPerPixel = 4
        let bytesPerRow = atlasWidth * bytesPerPixel
        let dataSize = atlasHeight * bytesPerRow
        var atlasData = [UInt8](repeating: 0, count: dataSize)
        
        atlasData.withUnsafeMutableBytes { ptr in
            guard let context = CGContext(
                data: ptr.baseAddress,
                width: atlasWidth,
                height: atlasHeight,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return
            }
            
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.setAllowsAntialiasing(true)
            context.setShouldAntialias(true)
            context.setTextDrawingMode(.fill)
            
            // Flip for top-left origin
            context.translateBy(x: 0, y: CGFloat(atlasHeight))
            context.scaleBy(x: 1, y: -1)
            
            for (index, codepoint) in glyphs.enumerated() {
                let col = index % columns
                let row = index / columns
                let x = CGFloat(col) * cellWidth
                let y = CGFloat(row) * cellHeight + ascent
                
                let uni = UniChar(codepoint)
                var glyph = CGGlyph()
                var chars = [uni]
                if CTFontGetGlyphsForCharacters(ctFont, &chars, &glyph, 1) {
                    let position = CGPoint(x: x, y: y)
                    let glyphsToDraw = [glyph]
                    let positions = [position]
                    glyphsToDraw.withUnsafeBufferPointer { glyphPtr in
                        positions.withUnsafeBufferPointer { posPtr in
                            if let g = glyphPtr.baseAddress, let p = posPtr.baseAddress {
                                CTFontDrawGlyphs(ctFont, g, p, 1, context)
                            }
                        }
                    }
                    
                    let u = Float(x / CGFloat(atlasWidth))
                    let v = Float((CGFloat(row) * cellHeight) / CGFloat(atlasHeight))
                    let w = Float(cellWidth / CGFloat(atlasWidth))
                    let h = Float(cellHeight / CGFloat(atlasHeight))
                    
                    if let scalar = UnicodeScalar(codepoint) {
                        let char = Character(scalar)
                        fontAtlasData[char] = FontGlyph(x: u, y: v, width: w, height: h)
                    }
                }
            }
        }
        
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: atlasWidth,
            height: atlasHeight,
            mipmapped: false
        )
        
        fontAtlas = device.makeTexture(descriptor: textureDescriptor)
        fontAtlas.replace(
            region: MTLRegionMake2D(0, 0, atlasWidth, atlasHeight),
            mipmapLevel: 0,
            withBytes: atlasData,
            bytesPerRow: bytesPerRow
        )
    }
    
    func resize(columns: Int, rows: Int) {
        self.columns = columns
        self.rows = rows
        needsVertexUpdate = true
        createBuffers()
    }
    
    // Pre-allocated vertex array to avoid per-frame allocations
    private var vertexArray: [Vertex] = []
    private var lastVertexCount = 0
    
    func updateVertices(for buffer: TerminalBuffer) {
        guard needsVertexUpdate else { return }
        
        let totalVertices = columns * rows * 4
        let totalWidth = Float(columns) * Float(cellSize.width)
        let totalHeight = Float(rows) * Float(cellSize.height)
        
        // Resize array only if needed (terminal resized)
        if vertexArray.count != totalVertices {
            let defaultVertex = Vertex(
                position: SIMD2<Float>(0, 0),
                texCoord: SIMD2<Float>(0, 0),
                color: SIMD4<Float>(1, 1, 1, 1)
            )
            vertexArray = [Vertex](repeating: defaultVertex, count: totalVertices)
        }
        
        var index = 0
        for row in 0..<rows {
            for col in 0..<columns {
                let cell = buffer.getCell(at: Position(x: col, y: row))
                let attributes = cell?.attributes ?? CharacterAttributes()
                
                let x = Float(col) * Float(cellSize.width)
                let y = Float(row) * Float(cellSize.height)
                let width = Float(cellSize.width)
                let height = Float(cellSize.height)
                
                let color = colorToVector(attributes.foregroundColor)
                
                // Get glyph coordinates from atlas
                let glyph = fontAtlasData[cell?.character ?? " "] ?? FontGlyph(x: 0, y: 0, width: 1, height: 1)
                
                let x0 = (x / totalWidth) * 2.0 - 1.0
                let y0 = 1.0 - (y / totalHeight) * 2.0
                let x1 = ((x + width) / totalWidth) * 2.0 - 1.0
                let y1 = 1.0 - ((y + height) / totalHeight) * 2.0
                
                // Update quad vertices in-place
                vertexArray[index] = Vertex(
                    position: SIMD2<Float>(x0, y0),
                    texCoord: SIMD2<Float>(glyph.x, glyph.y),
                    color: color
                )
                vertexArray[index + 1] = Vertex(
                    position: SIMD2<Float>(x1, y0),
                    texCoord: SIMD2<Float>(glyph.x + glyph.width, glyph.y),
                    color: color
                )
                vertexArray[index + 2] = Vertex(
                    position: SIMD2<Float>(x1, y1),
                    texCoord: SIMD2<Float>(glyph.x + glyph.width, glyph.y + glyph.height),
                    color: color
                )
                vertexArray[index + 3] = Vertex(
                    position: SIMD2<Float>(x0, y1),
                    texCoord: SIMD2<Float>(glyph.x, glyph.y + glyph.height),
                    color: color
                )
                index += 4
            }
        }
        
        // Update vertex buffer
        vertexArray.withUnsafeBytes { ptr in
            vertexBuffer.contents().copyMemory(from: ptr.baseAddress!, byteCount: ptr.count)
        }
        
        needsVertexUpdate = false
    }
    
    private func colorToVector(_ color: Color) -> SIMD4<Float> {
        switch color {
        case .black:
            return SIMD4<Float>(0, 0, 0, 1)
        case .red:
            return SIMD4<Float>(1, 0, 0, 1)
        case .green:
            return SIMD4<Float>(0, 1, 0, 1)
        case .yellow:
            return SIMD4<Float>(1, 1, 0, 1)
        case .blue:
            return SIMD4<Float>(0, 0, 1, 1)
        case .magenta:
            return SIMD4<Float>(1, 0, 1, 1)
        case .cyan:
            return SIMD4<Float>(0, 1, 1, 1)
        case .white:
            return SIMD4<Float>(1, 1, 1, 1)
        case .brightBlack:
            return SIMD4<Float>(0.5, 0.5, 0.5, 1)
        case .brightRed:
            return SIMD4<Float>(1, 0.5, 0.5, 1)
        case .brightGreen:
            return SIMD4<Float>(0.5, 1, 0.5, 1)
        case .brightYellow:
            return SIMD4<Float>(1, 1, 0.5, 1)
        case .brightBlue:
            return SIMD4<Float>(0.5, 0.5, 1, 1)
        case .brightMagenta:
            return SIMD4<Float>(1, 0.5, 1, 1)
        case .brightCyan:
            return SIMD4<Float>(0.5, 1, 1, 1)
        case .brightWhite:
            return SIMD4<Float>(1, 1, 1, 1)
        case .custom(let r, let g, let b):
            return SIMD4<Float>(Float(r) / 255, Float(g) / 255, Float(b) / 255, 1)
        }
    }
    
    func render(in view: MTKView, buffer: TerminalBuffer) {
        updateVertices(for: buffer)
        
        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor else { return }
        
        let commandBuffer = commandQueue.makeCommandBuffer()
        let renderEncoder = commandBuffer?.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
        
        renderEncoder?.setRenderPipelineState(pipelineState)
        renderEncoder?.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        renderEncoder?.setFragmentTexture(fontAtlas, index: 0)
        
        renderEncoder?.drawIndexedPrimitives(
            type: .triangle,
            indexCount: columns * rows * 6,
            indexType: .uint16,
            indexBuffer: indexBuffer,
            indexBufferOffset: 0
        )
        
        renderEncoder?.endEncoding()
        commandBuffer?.present(drawable)
        commandBuffer?.commit()
    }
    
    // Store the current buffer for rendering
    var currentBuffer: TerminalBuffer?
    
    func setBuffer(_ buffer: TerminalBuffer) {
        currentBuffer = buffer
    }

    func setNeedsVertexUpdate() {
        needsVertexUpdate = true
    }
}
