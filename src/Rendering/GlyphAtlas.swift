import AppKit
import CoreText
import Metal

/// Rasterizes glyphs with Core Text into cell-sized slots of a single Metal texture.
final class GlyphAtlas {
    struct Glyph {
        let uv: SIMD4<Float>
        let isColor: Bool
    }

    private struct Key: Hashable {
        let text: String
        let bold: Bool
        let italic: Bool
        let wide: Bool
    }

    let texture: MTLTexture
    let cellWidth: Int
    let cellHeight: Int
    private let size = 2048
    private let scale: CGFloat
    private let fonts: [CTFont]  // regular, bold, italic, bold italic
    private let descent: CGFloat
    private var cache: [Key: Glyph] = [:]
    private var penX = 0, penY = 0

    init(device: MTLDevice, fonts settings: Settings.Fonts, scale: CGFloat) {
        self.scale = scale
        let fontSize = CGFloat(settings.size)
        let regular: CTFont, bold: CTFont
        let manager = NSFontManager.shared
        if let family = settings.family,
           let font = manager.font(withFamily: family, traits: [], weight: 5, size: fontSize) {
            regular = font as CTFont
            bold = (manager.font(withFamily: family, traits: .boldFontMask, weight: 9, size: fontSize) ?? font) as CTFont
        } else {
            regular = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular) as CTFont
            bold = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold) as CTFont
        }
        func italic(_ font: CTFont) -> CTFont {
            CTFontCreateCopyWithSymbolicTraits(font, 0, nil, .traitItalic, .traitItalic) ?? font
        }
        fonts = [regular, bold, italic(regular), italic(bold)]

        var glyph = CGGlyph()
        var m: UniChar = 0x4D  // "M"
        CTFontGetGlyphsForCharacters(regular, &m, &glyph, 1)
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(regular, .horizontal, &glyph, &advance, 1)
        descent = CTFontGetDescent(regular)
        let height = CTFontGetAscent(regular) + descent + CTFontGetLeading(regular)
        cellWidth = Int((advance.width * scale).rounded(.up))
        cellHeight = Int((height * scale).rounded(.up))

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: size, height: size, mipmapped: false)
        desc.usage = .shaderRead
        texture = device.makeTexture(descriptor: desc)!
    }

    /// Returns the glyph for a cell's text, rasterizing it on first use. Nil when the atlas is full.
    func glyph(_ text: String, bold: Bool, italic: Bool, wide: Bool) -> Glyph? {
        let key = Key(text: text, bold: bold, italic: italic, wide: wide)
        if let glyph = cache[key] { return glyph }

        let w = cellWidth * (wide ? 2 : 1), h = cellHeight
        if penX + w > size { penX = 0; penY += h }
        if penY + h > size { return nil }

        let font = fonts[(bold ? 1 : 0) + (italic ? 2 : 0)]
        let attributed = NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: NSColor.white,
        ])
        let line = CTLineCreateWithAttributedString(attributed)

        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        pixels.withUnsafeMutableBytes { buf in
            let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.scaleBy(x: scale, y: scale)
            ctx.textPosition = CGPoint(x: 0, y: descent)
            CTLineDraw(line, ctx)
        }
        texture.replace(region: MTLRegionMake2D(penX, penY, w, h), mipmapLevel: 0,
                        withBytes: pixels, bytesPerRow: w * 4)

        let s = Float(size)
        let glyph = Glyph(
            uv: SIMD4(Float(penX) / s, Float(penY) / s, Float(penX + w) / s, Float(penY + h) / s),
            isColor: Self.hasColorFont(line))
        penX += w
        cache[key] = glyph
        return glyph
    }

    private static func hasColorFont(_ line: CTLine) -> Bool {
        let runs = CTLineGetGlyphRuns(line) as! [CTRun]
        return runs.contains { run in
            let attrs = CTRunGetAttributes(run) as NSDictionary
            guard let font = attrs[kCTFontAttributeName] else { return false }
            return CTFontGetSymbolicTraits(font as! CTFont).contains(.traitColorGlyphs)
        }
    }
}
