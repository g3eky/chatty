// Draws the 1024x1024 app icon ("Double chevron" design) to the PNG path given as the first argument.
// Coordinates and colors are the CSS/SVG values from the design mockup; the context is flipped to match.
import AppKit

let size = 1024
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.translateBy(x: 0, y: CGFloat(size))
ctx.scaleBy(x: 1, y: -1)

func rgba(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}
func roundedRect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> CGPath {
    CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: r, cornerHeight: r, transform: nil)
}
func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: nil, colors: colors as CFArray, locations: locations)!
}
// CSS box-shadow offsets point down; shadow offsets are in unflipped device space.
func shadow(_ y: CGFloat, blur: CGFloat, _ color: CGColor) {
    ctx.setShadow(offset: CGSize(width: 0, height: -y), blur: blur, color: color)
}
/// Strokes `points` as a round polyline filled with a diagonal gradient across its bounding box.
func chevron(_ points: [CGPoint], alpha: CGFloat) {
    ctx.saveGState()
    ctx.setAlpha(alpha)
    ctx.addLines(between: points)
    ctx.setLineWidth(28)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    let xs = points.map(\.x), ys = points.map(\.y)
    ctx.drawLinearGradient(gradient([rgba(0xCDD6F4), rgba(0xB4BEFE)], [0, 1]),
                           start: CGPoint(x: xs.min()!, y: ys.min()!),
                           end: CGPoint(x: xs.max()!, y: ys.max()!),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}

let accent = rgba(0xCBA6F7)

// Icon body: 824px squircle at (100, 100), radius 185, with drop shadow.
// Everything after this is drawn in the body's own coordinates (0...824).
ctx.translateBy(x: 100, y: 100)
let body = roundedRect(0, 0, 824, 824, 185)
ctx.saveGState()
shadow(28, blur: 56, rgba(0x11111B, 0.5))
ctx.addPath(body)
ctx.setFillColor(rgba(0x1E1E2E))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(body)
ctx.clip()

// linear-gradient(155deg, #45375F, #1E1E2E 50%, #11111B): CSS angle is clockwise from "to top".
let angle = 155 * CGFloat.pi / 180
let dir = CGPoint(x: sin(angle), y: -cos(angle))
let half = 824 * (abs(sin(angle)) + abs(cos(angle))) / 2
ctx.drawLinearGradient(gradient([rgba(0x45375F), rgba(0x1E1E2E), rgba(0x11111B)], [0, 0.5, 1]),
                       start: CGPoint(x: 412 - dir.x * half, y: 412 - dir.y * half),
                       end: CGPoint(x: 412 + dir.x * half, y: 412 + dir.y * half), options: [])

// Inset shadows: a 3px white ring, then a 3px top highlight (the body not covered by itself moved down).
ctx.addPath(body)
ctx.setStrokeColor(rgba(0xFFFFFF, 0.08))
ctx.setLineWidth(6)
ctx.strokePath()
ctx.addPath(body)
ctx.addPath(roundedRect(0, 3, 824, 824, 185))
ctx.setFillColor(rgba(0xFFFFFF, 0.22))
ctx.fillPath(using: .evenOdd)

// Glow: radial-gradient(circle at 50% 45%, accent 50% alpha, transparent at 58% of the farthest corner).
let glowCenter = CGPoint(x: 412, y: 824 * 0.45)
let farthest = hypot(412, 824 - glowCenter.y)
ctx.drawRadialGradient(gradient([rgba(0xCBA6F7, 0x80 / 255), rgba(0xCBA6F7, 0)], [0, 1]),
                       startCenter: glowCenter, startRadius: 0,
                       endCenter: glowCenter, endRadius: farthest * 0.58, options: [])

// Scanlines: 2px of white 0.025 every 8px, counted up from the bottom edge.
ctx.setFillColor(rgba(0xFFFFFF, 0.025))
for y in stride(from: CGFloat(824), to: 0, by: -8) {
    ctx.fill(CGRect(x: 0, y: y - 2, width: 824, height: 2))
}

// Speech bubble: 560x400 at (132, 170) with 90px corners and a tail down to (236, 664).
let bubble = CGMutablePath()
bubble.move(to: CGPoint(x: 222, y: 170))
bubble.addArc(tangent1End: CGPoint(x: 692, y: 170), tangent2End: CGPoint(x: 692, y: 260), radius: 90)
bubble.addArc(tangent1End: CGPoint(x: 692, y: 570), tangent2End: CGPoint(x: 602, y: 570), radius: 90)
bubble.addLine(to: CGPoint(x: 340, y: 570))
bubble.addLine(to: CGPoint(x: 236, y: 664))
bubble.addLine(to: CGPoint(x: 256, y: 570))
bubble.addArc(tangent1End: CGPoint(x: 132, y: 570), tangent2End: CGPoint(x: 132, y: 480), radius: 90)
bubble.addArc(tangent1End: CGPoint(x: 132, y: 170), tangent2End: CGPoint(x: 222, y: 170), radius: 90)
bubble.closeSubpath()
ctx.addPath(bubble)
ctx.setFillColor(rgba(0xCBA6F7, 0.12))
ctx.fillPath()
ctx.addPath(bubble)
ctx.setStrokeColor(rgba(0xCBA6F7, 0.5))
ctx.setLineWidth(5)
ctx.setLineJoin(.round)
ctx.strokePath()

// Bubble content is a centered flex row: 170x180 chevrons, 22px gap, 100x32 cursor 108px lower.
// That puts the chevron SVG at (266, 280) and the cursor at (458, 408).
let cx: CGFloat = 266, cy: CGFloat = 280
chevron([CGPoint(x: cx + 28, y: cy + 34), CGPoint(x: cx + 82, y: cy + 90), CGPoint(x: cx + 28, y: cy + 146)],
        alpha: 0.55)
chevron([CGPoint(x: cx + 88, y: cy + 34), CGPoint(x: cx + 142, y: cy + 90), CGPoint(x: cx + 88, y: cy + 146)],
        alpha: 1)

// Cursor: accent→#F5C2E7 gradient with 36px and 90px accent glows.
let cursor = roundedRect(458, 408, 100, 32, 16)
for blur: CGFloat in [90, 36] {
    ctx.saveGState()
    shadow(0, blur: blur, accent)
    ctx.addPath(cursor)
    ctx.setFillColor(accent)
    ctx.fillPath()
    ctx.restoreGState()
}
ctx.saveGState()
ctx.addPath(cursor)
ctx.clip()
ctx.drawLinearGradient(gradient([accent, rgba(0xF5C2E7)], [0, 1]),
                       start: CGPoint(x: 458, y: 0), end: CGPoint(x: 558, y: 0), options: [])
ctx.restoreGState()

// Gloss: white 0.13 at the top fading to clear at 42%.
ctx.drawLinearGradient(gradient([rgba(0xFFFFFF, 0.13), rgba(0xFFFFFF, 0)], [0, 1]),
                       start: .zero, end: CGPoint(x: 0, y: 824 * 0.42), options: [])

ctx.restoreGState()

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
