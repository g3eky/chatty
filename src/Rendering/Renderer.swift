import Metal
import QuartzCore
import SwiftTerm

/// One instanced quad. Layout matches `Quad` in the shader source below.
struct Quad {
    var pos: SIMD2<Float>
    var size: SIMD2<Float>
    var uv: SIMD4<Float> = .zero
    var color: SIMD4<Float>
    var mode: Float = 0  // 0 solid, 1 glyph mask tinted by color, 2 color glyph (emoji)
}

/// Vertex shader uniforms, in pixels. Layout matches `Uniforms` in the shader source below.
private struct Uniforms {
    var viewport: SIMD2<Float>
    var origin: SIMD2<Float>
}

/// Turns the visible terminal grid into quads and draws them with a single instanced draw call.
final class Renderer {
    let device: MTLDevice
    private(set) var atlas: GlyphAtlas
    private(set) var scale: CGFloat
    private(set) var appearance: Settings.Appearance
    private var fonts: Settings.Fonts
    private var foreground, background, cursor, selection: SIMD4<Float>
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private var palette: [SIMD4<Float>]

    init(fonts: Settings.Fonts, appearance: Settings.Appearance, scale: CGFloat) {
        self.fonts = fonts
        self.appearance = appearance
        (foreground, background, cursor, selection) = Self.colors(appearance)
        palette = Self.makePalette(ansi: Theme.named(appearance.theme)?.ansi)
        self.scale = scale
        device = MTLCreateSystemDefaultDevice()!
        queue = device.makeCommandQueue()!
        let library = try! device.makeLibrary(source: Self.shaderSource, options: nil)
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = library.makeFunction(name: "vertexMain")
        desc.fragmentFunction = library.makeFunction(name: "fragmentMain")
        let color = desc.colorAttachments[0]!
        color.pixelFormat = .bgra8Unorm
        color.isBlendingEnabled = true
        color.sourceRGBBlendFactor = .one
        color.sourceAlphaBlendFactor = .one
        color.destinationRGBBlendFactor = .oneMinusSourceAlpha
        color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        pipeline = try! device.makeRenderPipelineState(descriptor: desc)
        atlas = GlyphAtlas(device: device, fonts: fonts, scale: scale)
    }

    func setScale(_ newScale: CGFloat) {
        guard newScale != scale else { return }
        scale = newScale
        atlas = GlyphAtlas(device: device, fonts: fonts, scale: newScale)
    }

    func setFonts(_ newFonts: Settings.Fonts) {
        guard newFonts != fonts else { return }
        fonts = newFonts
        atlas = GlyphAtlas(device: device, fonts: newFonts, scale: scale)
    }

    func setAppearance(_ newAppearance: Settings.Appearance) {
        appearance = newAppearance
        (foreground, background, cursor, selection) = Self.colors(newAppearance)
        palette = Self.makePalette(ansi: Theme.named(newAppearance.theme)?.ansi)
    }

    private static func colors(_ a: Settings.Appearance) -> (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>) {
        (SIMD4(hex: a.foreground), SIMD4(hex: a.background), SIMD4(hex: a.cursor), SIMD4(hex: a.selection))
    }

    /// Draws rows `top..<top+rows` (scroll-invariant row numbers). `selection` is inclusive and ordered.
    func draw(in layer: CAMetalLayer, terminal: Terminal, top: Int, showCursor: Bool, focused: Bool,
              selection: (start: Position, end: Position)?, markedText: String) {
        guard let drawable = layer.nextDrawable() else { return }
        let cw = Float(atlas.cellWidth), ch = Float(atlas.cellHeight)
        let thickness = max(1, (Float(scale)).rounded())
        var backgrounds: [Quad] = [], glyphs: [Quad] = [], overlays: [Quad] = []

        let buffer = terminal.buffer
        let cursorRow = buffer.totalLinesTrimmed + buffer.yDisp + buffer.y - top
        let cursorCol = min(buffer.x, terminal.cols - 1)
        let drawCursor = showCursor && markedText.isEmpty && (0..<terminal.rows).contains(cursorRow)

        for screenRow in 0..<terminal.rows {
            guard let line = terminal.getScrollInvariantLine(row: top + screenRow) else { continue }
            let row = top + screenRow
            let y = Float(screenRow) * ch
            for col in 0..<min(terminal.cols, line.count) {
                let cell = line[col]
                let width = Int(cell.width)
                if width == 0 { continue }  // right half of a wide character
                let attr = cell.attribute
                var fg = color(attr.fg, foreground: true), bg = color(attr.bg, foreground: false)
                if attr.style.contains(.inverse) { swap(&fg, &bg) }
                if let s = selection, Self.contains(s, col: col, row: row) { bg = self.selection }
                if attr.style.contains(.dim) { fg = bg + (fg - bg) * 0.6 }
                if drawCursor && focused && appearance.cursorStyle == .block
                    && screenRow == cursorRow && col == cursorCol { fg = background }

                let x = Float(col) * cw, w = cw * Float(width)
                if bg != background {
                    backgrounds.append(Quad(pos: [x, y], size: [w, ch], color: bg))
                }
                let text = cell.getText()
                if text != " ", text != "\0", !attr.style.contains(.invisible),
                   let glyph = atlas.glyph(text, bold: attr.style.contains(.bold),
                                           italic: attr.style.contains(.italic), wide: width > 1) {
                    glyphs.append(Quad(pos: [x, y], size: [w, ch], uv: glyph.uv, color: fg,
                                       mode: glyph.isColor ? 2 : 1))
                }
                if attr.style.contains(.underline) || attr.underlineStyle != .none {
                    overlays.append(Quad(pos: [x, y + ch - 2 * thickness], size: [w, thickness], color: fg))
                }
            }
        }

        if drawCursor {
            let x = Float(cursorCol) * cw, y = Float(cursorRow) * ch
            switch (appearance.cursorStyle, focused) {
            case (.block, true):
                backgrounds.append(Quad(pos: [x, y], size: [cw, ch], color: cursor))
            case (.block, false):
                overlays += [
                    Quad(pos: [x, y], size: [cw, thickness], color: cursor),
                    Quad(pos: [x, y + ch - thickness], size: [cw, thickness], color: cursor),
                    Quad(pos: [x, y], size: [thickness, ch], color: cursor),
                    Quad(pos: [x + cw - thickness, y], size: [thickness, ch], color: cursor),
                ]
            case (.underline, _):
                overlays.append(Quad(pos: [x, y + ch - 2 * thickness], size: [cw, 2 * thickness], color: cursor))
            case (.bar, _):
                overlays.append(Quad(pos: [x, y], size: [2 * thickness, ch], color: cursor))
            }
        }

        // IME composition text, drawn over the grid at the cursor.
        var marked: [Quad] = []
        var x = Float(buffer.x) * cw
        let y = Float(buffer.y) * ch
        for character in markedText {
            let wide = character.unicodeScalars.first!.value >= 0x1100
            let w = cw * (wide ? 2 : 1)
            marked.append(Quad(pos: [x, y], size: [w, ch], color: background))
            if let glyph = atlas.glyph(String(character), bold: false, italic: false, wide: wide) {
                marked.append(Quad(pos: [x, y], size: [w, ch], uv: glyph.uv, color: foreground,
                                   mode: glyph.isColor ? 2 : 1))
            }
            marked.append(Quad(pos: [x, y + ch - 2 * thickness], size: [w, thickness], color: foreground))
            x += w
        }

        let quads = backgrounds + glyphs + overlays + marked
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        // The window background is premultiplied by the opacity setting.
        let bg = background * Float(appearance.opacity)
        pass.colorAttachments[0].clearColor = MTLClearColor(red: Double(bg.x), green: Double(bg.y),
                                                            blue: Double(bg.z), alpha: Double(bg.w))
        let commands = queue.makeCommandBuffer()!
        let encoder = commands.makeRenderCommandEncoder(descriptor: pass)!
        if !quads.isEmpty {
            let instances = device.makeBuffer(bytes: quads, length: MemoryLayout<Quad>.stride * quads.count)!
            let padding = Float((appearance.padding * scale).rounded())
            var uniforms = Uniforms(viewport: [Float(drawable.texture.width), Float(drawable.texture.height)],
                                    origin: [padding, padding])
            encoder.setRenderPipelineState(pipeline)
            encoder.setVertexBuffer(instances, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: 1)
            encoder.setFragmentTexture(atlas.texture, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4,
                                   instanceCount: quads.count)
        }
        encoder.endEncoding()
        commands.present(drawable)
        commands.commit()
    }

    private static func contains(_ s: (start: Position, end: Position), col: Int, row: Int) -> Bool {
        row >= s.start.row && row <= s.end.row
            && (row > s.start.row || col >= s.start.col)
            && (row < s.end.row || col <= s.end.col)
    }

    private func color(_ c: Attribute.Color, foreground: Bool) -> SIMD4<Float> {
        switch c {
        case .ansi256(let code):
            return palette[Int(code)]
        case .trueColor(let r, let g, let b):
            return SIMD4(Float(r) / 255, Float(g) / 255, Float(b) / 255, 1)
        case .defaultColor:
            return foreground ? self.foreground : background
        case .defaultInvertedColor:
            return foreground ? background : self.foreground
        }
    }

    /// 16 ANSI colors from the theme (or SwiftTerm's defaults), then the xterm 6x6x6 cube and 24-step gray ramp.
    private static func makePalette(ansi: [String]?) -> [SIMD4<Float>] {
        var palette = ansi?.map { SIMD4<Float>(hex: $0) } ?? Color.defaultInstalledColors.prefix(16).map {
            SIMD4<Float>(Float($0.red) / 65535, Float($0.green) / 65535, Float($0.blue) / 65535, 1)
        }
        let levels: [Float] = [0, 95, 135, 175, 215, 255]
        for r in levels { for g in levels { for b in levels {
            palette.append(SIMD4(r / 255, g / 255, b / 255, 1))
        } } }
        for i in 0..<24 {
            let v = Float(8 + i * 10) / 255
            palette.append(SIMD4(v, v, v, 1))
        }
        return palette
    }

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct Quad { float2 pos; float2 size; float4 uv; float4 color; float mode; };
    struct Uniforms { float2 viewport; float2 origin; };
    struct VertexOut {
        float4 position [[position]];
        float2 uv;
        float4 color;
        float mode [[flat]];
    };

    vertex VertexOut vertexMain(uint vid [[vertex_id]], uint iid [[instance_id]],
                                constant Quad *quads [[buffer(0)]],
                                constant Uniforms &u [[buffer(1)]]) {
        Quad q = quads[iid];
        float2 corner = float2(vid & 1, vid >> 1);
        float2 p = u.origin + q.pos + corner * q.size;
        VertexOut out;
        out.position = float4(p.x / u.viewport.x * 2 - 1, 1 - p.y / u.viewport.y * 2, 0, 1);
        out.uv = mix(q.uv.xy, q.uv.zw, corner);
        out.color = q.color;
        out.mode = q.mode;
        return out;
    }

    fragment float4 fragmentMain(VertexOut in [[stage_in]], texture2d<float> atlas [[texture(0)]]) {
        constexpr sampler s(filter::nearest);
        if (in.mode < 0.5) return float4(in.color.rgb * in.color.a, in.color.a);
        float4 texel = atlas.sample(s, in.uv);
        if (in.mode < 1.5) return float4(in.color.rgb, 1) * texel.a;
        return texel;
    }
    """
}
