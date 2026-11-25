// Image steps for the app icon, with CoreGraphics only.
//
//   swift icontool.swift crop <in.png> <out.png> <size> <dx> <dy>
//       Box-filters a square render down to <size>, shifting it by (dx, dy)
//       pixels of the output first (used to centre the key on the canvas),
//       and clears the last 1% of alpha the shadow catcher leaves behind.
//   swift icontool.swift squircle <in.png> <out.png> <shape.png>
//       Box-filters a full-frame render to 1024 and clips it to the macOS
//       icon shape in <shape.png> (an 824 px body on the standard grid).
//   swift icontool.swift iconset <large.png> <small.png> <dir.iconset>
//       Writes every macOS icon size. Images 64 px and under come from
//       <small.png> (the ⌘ alone); the rest from <large.png>.
//   swift icontool.swift preview <large.png> <small.png> <out.png>
//       A review sheet: the icon at 512, 256, 128, 64, 32 and 16 px (actual
//       pixels, then enlarged ×4 for 32 and 16), on light and dark.
//   swift icontool.swift bounds <in.png> [alpha]
//       Prints the box of pixels with alpha above the threshold (default 2%).
//
// Downscaling halves repeatedly with an exact 2 × 2 average of premultiplied
// pixels, then (for sizes that are not a power-of-two fraction) one final
// high-quality resample. That is a true area average: no ringing, no lost
// thin edges, and transparency stays clean.
import AppKit

struct Pixels {
    var width: Int, height: Int
    var data: [Double]   // premultiplied RGBA, 0...1

    init(width: Int, height: Int) {
        self.width = width; self.height = height
        data = Array(repeating: 0, count: width * height * 4)
    }

    init(contentsOf url: URL) {
        let rep = NSBitmapImageRep(data: try! Data(contentsOf: url))!
        let image = rep.cgImage!
        self.init(cgImage: image)
    }

    init(cgImage image: CGImage) {
        width = image.width; height = image.height
        var raw = [UInt16](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &raw, width: width, height: height, bitsPerComponent: 16, bytesPerRow: width * 8,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder16Little.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        data = raw.map { Double($0) / 65535 }
    }

    func halved() -> Pixels {
        var out = Pixels(width: width / 2, height: height / 2)
        for y in 0..<out.height {
            for x in 0..<out.width {
                for c in 0..<4 {
                    let a = data[((2 * y) * width + 2 * x) * 4 + c] + data[((2 * y) * width + 2 * x + 1) * 4 + c]
                    let b = data[((2 * y + 1) * width + 2 * x) * 4 + c] + data[((2 * y + 1) * width + 2 * x + 1) * 4 + c]
                    out.data[(y * out.width + x) * 4 + c] = (a + b) / 4
                }
            }
        }
        return out
    }

    func shifted(dx: Int, dy: Int) -> Pixels {
        var out = Pixels(width: width, height: height)
        for y in 0..<height {
            for x in 0..<width {
                let sx = x - dx, sy = y - dy
                guard sx >= 0, sy >= 0, sx < width, sy < height else { continue }
                for c in 0..<4 { out.data[(y * width + x) * 4 + c] = data[(sy * width + sx) * 4 + c] }
            }
        }
        return out
    }

    func cropped(x: Int, y: Int, width w: Int, height h: Int) -> Pixels {
        var out = Pixels(width: w, height: h)
        for row in 0..<h {
            for col in 0..<w {
                for c in 0..<4 { out.data[(row * w + col) * 4 + c] = data[((y + row) * width + x + col) * 4 + c] }
            }
        }
        return out
    }

    var cgImage: CGImage {
        var raw = data.map { UInt16(max(0, min(1, $0)) * 65535 + 0.5) }
        let context = CGContext(data: &raw, width: width, height: height, bitsPerComponent: 16, bytesPerRow: width * 8,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder16Little.rawValue)!
        return context.makeImage()!
    }

    /// Area-averaged to `size` × `size`.
    func scaled(to size: Int) -> Pixels {
        var image = self
        while image.width / 2 >= size, image.width % 2 == 0 { image = image.halved() }
        guard image.width != size else { return image }
        let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 16, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder16Little.rawValue)!
        context.interpolationQuality = .high
        context.draw(image.cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))
        return Pixels(cgImage: context.makeImage()!)
    }
}

/// 8-bit sRGB PNG with alpha, as icon files are.
func writePNG(_ image: CGImage, _ url: URL) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: image.width, pixelsHigh: image.height,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let srgb = rep.retagging(with: .sRGB)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: srgb)
    NSGraphicsContext.current!.cgContext.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    NSGraphicsContext.restoreGraphicsState()
    try! srgb.representation(using: .png, properties: [:])!.write(to: url)
}

let args = CommandLine.arguments
let url = { (i: Int) in URL(fileURLWithPath: args[i]) }

switch args[1] {
case "crop":
    let size = Int(args[4])!, dx = Int(args[5])!, dy = Int(args[6])!
    let source = Pixels(contentsOf: url(2))
    let factor = source.width / size
    var image = source.shifted(dx: dx * factor, dy: dy * factor).scaled(to: size)
    // The shadow catcher leaves a trace of alpha (under 1%) out to the
    // edges; remove it so the canvas around the key is truly clear.
    for i in stride(from: 0, to: image.data.count, by: 4) {
        let a = image.data[i + 3]
        let kept = max(0, (a - 0.01) / 0.99)
        let k = a > 0 ? kept / a : 0
        for c in 0..<4 { image.data[i + c] *= k }
    }
    writePNG(image.cgImage, url(3))

case "bounds":
    let image = Pixels(contentsOf: url(2))
    let threshold = args.count > 3 ? Double(args[3])! : 0.02
    var minX = image.width, minY = image.height, maxX = 0, maxY = 0
    for y in 0..<image.height {
        for x in 0..<image.width where image.data[(y * image.width + x) * 4 + 3] > threshold {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        }
    }
    // Bitmap rows run from the top of the image.
    print("x \(minX)...\(maxX)  y-from-top \(minY)...\(maxY)  of \(image.width)")

case "squircle":
    // The outline is read from icon-shape-1024.png: the shape macOS 26 and
    // later use for app icons, taken from the system's own rendering (the
    // tile it puts free-form icons on). An icon whose outline differs from it
    // at large sizes is shrunk onto that tile, so the body matches it exactly.
    // Its faint system shadow halo (about 11%) is removed; macOS draws icon
    // shadows itself.
    let size = 1024
    let body = Pixels(contentsOf: url(2)).scaled(to: size)
    let shape = Pixels(contentsOf: url(4))
    precondition(shape.width == size, "the shape image must be 1024 px")
    var icon = Pixels(width: size, height: size)
    for i in 0..<(size * size) {
        let a = shape.data[i * 4 + 3]
        let m = max(0, min(1, (a - 0.12) / 0.88))
        for c in 0..<3 { icon.data[i * 4 + c] = body.data[i * 4 + c] / max(body.data[i * 4 + 3], 1e-9) * m }
        icon.data[i * 4 + 3] = m
    }
    writePNG(icon.cgImage, url(3))

case "iconset":
    let large = Pixels(contentsOf: url(2)), small = Pixels(contentsOf: url(3))
    let directory = url(4)
    try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
        let pixels = points * scale
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        writePNG((pixels <= 64 ? small : large).scaled(to: pixels).cgImage, directory.appending(path: name))
    }

case "preview":
    let large = Pixels(contentsOf: url(2)), small = Pixels(contentsOf: url(3))
    let sizes = [512, 256, 128, 64, 32, 16]
    let width = 1800, height = 1240
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    for (row, background) in [(0, CGColor(srgbRed: 0.93, green: 0.93, blue: 0.94, alpha: 1)),
                              (1, CGColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1))] {
        let top = CGFloat(height) - CGFloat(row + 1) * CGFloat(height / 2)
        context.setFillColor(background)
        context.fill(CGRect(x: 0, y: top, width: CGFloat(width), height: CGFloat(height / 2)))
        var x: CGFloat = 40
        for size in sizes {
            let icon = (size <= 64 ? small : large).scaled(to: size).cgImage
            context.interpolationQuality = .none
            context.draw(icon, in: CGRect(x: x, y: top + 60, width: CGFloat(size), height: CGFloat(size)))
            if size <= 32 {   // the same pixels, enlarged ×4, to inspect
                context.draw(icon, in: CGRect(x: x, y: top + 60 + CGFloat(size) + 30, width: CGFloat(size * 4), height: CGFloat(size * 4)))
                x += CGFloat(size * 4)
            }
            x += CGFloat(size) + 40
        }
    }
    writePNG(context.makeImage()!, url(4))

default:
    fatalError("unknown command")
}
