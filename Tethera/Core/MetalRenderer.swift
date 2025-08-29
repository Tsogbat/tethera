import Metal
import MetalKit
import Foundation

class MetalRenderer: NSObject {
    private var device: MTLDevice!
    private var commandQueue: MTLCommandQueue!
    private var pipelineState: MTLRenderPipelineState!
    private var vertexBuffer: MTLBuffer!
    private var indexBuffer: MTLBuffer!
    private var fontAtlas: MTLTexture!
    private var fontAtlasData: [Character: FontGlyph] = [:]
    
    private var cellSize = CGSize(width: 8, height: 16)
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
        // Create a simple monospace font atlas
        let atlasSize = 512
        let glyphSize = 16
        
        let bytesPerPixel = 4
        let dataSize = atlasSize * atlasSize * bytesPerPixel
        var atlasData = [UInt8](repeating: 0, count: dataSize)
        
        // For now, create a simple pattern - in a real implementation,
        // you'd render actual font glyphs here
        for y in 0..<atlasSize {
            for x in 0..<atlasSize {
                let index = (y * atlasSize + x) * bytesPerPixel
                let glyphX = x / glyphSize
                let glyphY = y / glyphSize
                
                // Create a simple pattern for demonstration
                let value: UInt8 = (glyphX + glyphY) % 2 == 0 ? 255 : 0
                atlasData[index] = value     // R
                atlasData[index + 1] = value // G
                atlasData[index + 2] = value // B
                atlasData[index + 3] = 255   // A
            }
        }
        
        // Create Metal texture
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: atlasSize,
            height: atlasSize,
            mipmapped: false
        )
        
        fontAtlas = device.makeTexture(descriptor: textureDescriptor)
        fontAtlas.replace(
            region: MTLRegionMake2D(0, 0, atlasSize, atlasSize),
            mipmapLevel: 0,
            withBytes: atlasData,
            bytesPerRow: atlasSize * bytesPerPixel
        )
        
        // Create glyph mapping
        let glyphsPerRow = atlasSize / glyphSize
        for i in 0..<256 {
            let x = Float((i % glyphsPerRow) * glyphSize) / Float(atlasSize)
            let y = Float((i / glyphsPerRow) * glyphSize) / Float(atlasSize)
            let width = Float(glyphSize) / Float(atlasSize)
            let height = Float(glyphSize) / Float(atlasSize)
            
            if let scalar = UnicodeScalar(i) {
                let char = Character(scalar)
                fontAtlasData[char] = FontGlyph(x: x, y: y, width: width, height: height)
            }
        }
    }
    
    func resize(columns: Int, rows: Int) {
        self.columns = columns
        self.rows = rows
        needsVertexUpdate = true
        createBuffers()
    }
    
    func updateVertices(for buffer: TerminalBuffer) {
        guard needsVertexUpdate else { return }
        
        var vertices: [Vertex] = []
        
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
                
                // Create quad vertices
                let positions: [SIMD2<Float>] = [
                    SIMD2<Float>(x, y),
                    SIMD2<Float>(x + width, y),
                    SIMD2<Float>(x + width, y + height),
                    SIMD2<Float>(x, y + height)
                ]
                
                let texCoords: [SIMD2<Float>] = [
                    SIMD2<Float>(glyph.x, glyph.y),
                    SIMD2<Float>(glyph.x + glyph.width, glyph.y),
                    SIMD2<Float>(glyph.x + glyph.width, glyph.y + glyph.height),
                    SIMD2<Float>(glyph.x, glyph.y + glyph.height)
                ]
                
                for i in 0..<4 {
                    let vertex = Vertex(
                        position: positions[i],
                        texCoord: texCoords[i],
                        color: color
                    )
                    vertices.append(vertex)
                }
            }
        }
        
        // Update vertex buffer
        let vertexData = vertices.withUnsafeBytes { Data($0) }
        vertexBuffer.contents().copyMemory(from: vertexData.withUnsafeBytes { $0.baseAddress! }, byteCount: vertexData.count)
        
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
}
