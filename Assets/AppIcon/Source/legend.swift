// Draws the keycap legends as textures for keycap.py.
// Usage: swift legend.swift <output-dir>
//
// The texture covers the keycap footprint, model x and y from -1 to 1, so a
// point (x, y) on the key is pixel ((x + 1) / 2, (y + 1) / 2) of the image.
// The ⌘ is built from its geometry (a square whose sides run on into four
// loops), not taken from a font, so its strokes are even and as heavy as
// small sizes need.
import AppKit
import CoreText

let size = 4096
let scale = CGFloat(size) / 2   // pixels per model unit

/// The ⌘ centre line: sides at ±s, loops of radius r centred at ±(s + r).
func commandPath(center: CGPoint, extent: CGFloat, stroke: CGFloat) -> CGPath {
    let s: CGFloat = 1, r: CGFloat = 0.74
    let half = s + 2 * r
    let k = (extent / 2 - stroke / 2) / half   // fit the outer edge of the stroke to the extent
    var points: [CGPoint] = []
    func p(_ x: CGFloat, _ y: CGFloat) { points.append(CGPoint(x: center.x + x * k, y: center.y + y * k)) }
    func arc(_ cx: CGFloat, _ cy: CGFloat, from a0: CGFloat, to a1: CGFloat) {
        let steps = 180
        for i in 0...steps {
            let a = (a0 + (a1 - a0) * CGFloat(i) / CGFloat(steps)) * .pi / 180
            p(cx + r * cos(a), cy + r * sin(a))
        }
    }
    let c = s + r
    arc(c, c, from: 180, to: -90)        // top right: from the right side's top to the top side's right end
    arc(-c, c, from: 270, to: 0)         // top left
    arc(-c, -c, from: 0, to: -270)       // bottom left
    arc(c, -c, from: 90, to: -180)       // bottom right
    let path = CGMutablePath()
    path.addLines(between: points)
    path.closeSubpath()
    return path.copy(strokingWithWidth: stroke, lineCap: .round, lineJoin: .round, miterLimit: 1)
}

func render(_ name: String, symbolCenterY: CGFloat, symbolExtent: CGFloat, stroke: CGFloat,
            word: (size: CGFloat, baseline: CGFloat)?, to directory: URL) throws {
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setShouldAntialias(true)
    context.interpolationQuality = .high
    // Model units → pixels.
    context.translateBy(x: scale, y: scale)
    context.scaleBy(x: scale, y: scale)
    context.setFillColor(CGColor(gray: 1, alpha: 1))

    context.addPath(commandPath(center: CGPoint(x: 0, y: symbolCenterY), extent: symbolExtent, stroke: stroke))
    context.fillPath()

    if let word {
        let font = NSFont.systemFont(ofSize: word.size * scale, weight: .medium)
        let text = NSAttributedString(string: "command", attributes: [.font: font, .foregroundColor: NSColor.white])
        let line = CTLineCreateWithAttributedString(text)
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        context.saveGState()
        context.scaleBy(x: 1 / scale, y: 1 / scale)   // CoreText in pixels
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: -bounds.midX, y: word.baseline * scale)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    let image = context.makeImage()!
    let rep = NSBitmapImageRep(cgImage: image)
    try rep.representation(using: .png, properties: [:])!.write(to: directory.appending(path: "\(name).png"))
}

let directory = URL(fileURLWithPath: CommandLine.arguments[1])
// Full legend: ⌘ above, "command" below, both inside the flat of the top.
try render("legend-full", symbolCenterY: 0.13, symbolExtent: 0.66, stroke: 0.072,
           word: (size: 0.165, baseline: -0.47), to: directory)
// Small sizes: the ⌘ alone, larger and heavier, so the word cannot turn into noise.
try render("legend-symbol", symbolCenterY: 0, symbolExtent: 0.92, stroke: 0.12, word: nil, to: directory)
print("legends written")
