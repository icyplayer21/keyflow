import AppKit
import KeyflowCore
import SwiftUI

/// How the Key Repetition letter grows. Pure numbers, so the curve is tested.
/// Everything is driven by progress toward the goal, so a goal of 25 and a
/// goal of 200 both end at the same size and color.
enum KeyRepetitionGrowth {
    /// Letter height as a share of the screen area, at the start and the goal.
    static let startHeight: CGFloat = 0.12
    static let endHeight: CGFloat = 0.85
    /// Above 1, growth starts gentle and gets steeper toward the goal.
    static let curve = 1.5
    /// A wide letter (W, M) never takes more than this share of the width.
    static let maximumWidth: CGFloat = 0.9
    /// The last stretch, where the glow and tremble build.
    static let finalStretch = 0.9
    static let maximumTremble: CGFloat = 6

    struct Metrics: Equatable {
        /// Capital height per point of font size.
        var capHeight: CGFloat
        /// This letter's width per point of font size.
        var width: CGFloat

        static func of(_ letter: String) -> Metrics {
            let base = NSFont.systemFont(ofSize: 100, weight: .semibold)
            let font = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: 100) } ?? base
            let width = (letter as NSString).size(withAttributes: [.font: font]).width
            return Metrics(capHeight: max(0.1, font.capHeight / 100), width: max(0.1, width / 100))
        }
    }

    static func clamp(_ progress: Double) -> Double { min(1, max(0, progress)) }

    /// Letter height as a share of the area, before any width limit.
    static func heightShare(_ progress: Double) -> CGFloat {
        startHeight + (endHeight - startHeight) * CGFloat(pow(clamp(progress), curve))
    }

    /// The font size at the goal: as tall as planned, or as wide as fits.
    static func endFontSize(area: CGSize, metrics: Metrics) -> CGFloat {
        max(1, min(area.height * endHeight / metrics.capHeight, area.width * maximumWidth / metrics.width))
    }

    static func fontSize(progress: Double, area: CGSize, metrics: Metrics) -> CGFloat {
        let end = endFontSize(area: area, metrics: metrics)
        let start = min(end, area.height * startHeight / metrics.capHeight)
        let shape = (heightShare(progress) - startHeight) / (endHeight - startHeight)
        return start + (end - start) * shape
    }

    /// How far past its size a correct press pops the letter.
    static func punch(_ progress: Double) -> CGFloat { 0.12 + 0.05 * CGFloat(clamp(progress)) }

    /// 0 until the final stretch, then up to 1 at the goal.
    static func intensity(_ progress: Double) -> Double {
        max(0, (clamp(progress) - finalStretch) / (1 - finalStretch))
    }

    // MARK: Color

    struct RGB: Equatable {
        var red: Double, green: Double, blue: Double
        var color: Color { Color(red: red, green: green, blue: blue) }

        func mixed(with other: RGB, _ amount: Double) -> RGB {
            RGB(red: red + (other.red - red) * amount, green: green + (other.green - green) * amount,
                blue: blue + (other.blue - blue) * amount)
        }
    }

    private static let darkTop = [RGB(red: 1, green: 1, blue: 1), RGB(red: 1, green: 1, blue: 1),
                                  RGB(red: 1, green: 0.95, blue: 0.82), RGB(red: 1, green: 0.78, blue: 0.36)]
    private static let darkBottom = [RGB(red: 0.93, green: 0.93, blue: 0.93), RGB(red: 1, green: 0.93, blue: 0.78),
                                     RGB(red: 1, green: 0.75, blue: 0.35), RGB(red: 1, green: 0.52, blue: 0.12)]
    // White would vanish on a light background, so light mode starts from ink.
    private static let lightTop = [RGB(red: 0.12, green: 0.12, blue: 0.13), RGB(red: 0.2, green: 0.17, blue: 0.14),
                                   RGB(red: 0.55, green: 0.33, blue: 0.1), RGB(red: 0.85, green: 0.5, blue: 0.05)]
    private static let lightBottom = [RGB(red: 0.25, green: 0.25, blue: 0.27), RGB(red: 0.45, green: 0.33, blue: 0.2),
                                      RGB(red: 0.85, green: 0.5, blue: 0.1), RGB(red: 0.95, green: 0.42, blue: 0.05)]

    private static func blend(_ stops: [RGB], _ progress: Double) -> RGB {
        let position = clamp(progress) * Double(stops.count - 1)
        let index = min(stops.count - 2, Int(position))
        return stops[index].mixed(with: stops[index + 1], position - Double(index))
    }

    static func topColor(_ progress: Double, dark: Bool) -> RGB { blend(dark ? darkTop : lightTop, progress) }
    static func bottomColor(_ progress: Double, dark: Bool) -> RGB { blend(dark ? darkBottom : lightBottom, progress) }
}

/// One triangular piece of the shattered letter. Pure geometry, so it is tested.
/// Points are relative to the letter's center.
struct KeyRepetitionShard: Equatable {
    let points: [CGPoint]
    let centroid: CGPoint
    /// Unit vector, away from the letter's center.
    let direction: CGVector
    /// Share of the blast radius it travels. Pieces near the center fly fastest.
    let reach: Double
    let spin: Double

    /// A jittered grid cut into triangles. `keep` says whether a point (in
    /// 0...1 of the box) lies on the letter; empty pieces are dropped.
    static func make(columns: Int, rows: Int, size: CGSize, seed: UInt64,
                     keep: (CGPoint) -> Bool) -> [KeyRepetitionShard] {
        var random = SeededGenerator(seed: seed)
        var lattice: [[CGPoint]] = []
        for row in 0...rows {
            var line: [CGPoint] = []
            for column in 0...columns {
                let inner = row > 0 && row < rows && column > 0 && column < columns
                let dx = inner ? Double.random(in: -0.32...0.32, using: &random) : 0
                let dy = inner ? Double.random(in: -0.32...0.32, using: &random) : 0
                line.append(CGPoint(x: (Double(column) + dx) / Double(columns), y: (Double(row) + dy) / Double(rows)))
            }
            lattice.append(line)
        }

        var shards: [KeyRepetitionShard] = []
        let longest = max(1, hypot(size.width, size.height) / 2)
        func add(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, using random: inout SeededGenerator) {
            let middle = CGPoint(x: (a.x + b.x + c.x) / 3, y: (a.y + b.y + c.y) / 3)
            guard keep(middle) || keep(a) || keep(b) || keep(c) else { return }
            let place = { (p: CGPoint) in CGPoint(x: (p.x - 0.5) * size.width, y: (p.y - 0.5) * size.height) }
            let centroid = place(middle)
            let distance = hypot(centroid.x, centroid.y)
            let base = distance > 1 ? atan2(centroid.y, centroid.x) : Double.random(in: 0..<(2 * .pi), using: &random)
            let angle = base + Double.random(in: -0.35...0.35, using: &random)
            let nearness = 1 - min(1, distance / longest)
            shards.append(KeyRepetitionShard(points: [place(a), place(b), place(c)], centroid: centroid,
                                             direction: CGVector(dx: cos(angle), dy: sin(angle)),
                                             reach: (0.35 + 0.65 * nearness) * Double.random(in: 0.7...1.2, using: &random),
                                             spin: Double.random(in: -9...9, using: &random)))
        }
        for row in 0..<rows {
            for column in 0..<columns {
                let a = lattice[row][column], b = lattice[row][column + 1]
                let c = lattice[row + 1][column + 1], d = lattice[row + 1][column]
                if Bool.random(using: &random) {
                    add(a, b, c, using: &random)
                    add(a, c, d, using: &random)
                } else {
                    add(a, b, d, using: &random)
                    add(b, c, d, using: &random)
                }
            }
        }
        return shards
    }

    /// Fast at first, then slowing.
    func travel(at progress: Double, radius: CGFloat) -> CGSize {
        let u = min(1, max(0, progress))
        let distance = (1 - pow(1 - u, 3)) * reach * Double(radius)
        return CGSize(width: direction.dx * distance, height: direction.dy * distance + u * u * 36)
    }

    func opacity(at progress: Double) -> Double {
        min(1, max(0, (1 - progress) / 0.4))
    }

    func scale(at progress: Double) -> Double {
        1 - 0.55 * min(1, max(0, progress))
    }
}

/// A small spark trailing out of the blast.
struct KeyRepetitionParticle: Equatable {
    let angle: Double
    /// Share of the blast radius it travels.
    let reach: Double
    let tintIndex: Int
    let delay: Double

    static func make(count: Int, seed: UInt64) -> [KeyRepetitionParticle] {
        var random = SeededGenerator(seed: seed)
        return (0..<count).map { index in
            // Evenly around the circle with some jitter, so no side is empty.
            let angle = Double(index) / Double(count) * 2 * .pi + Double.random(in: -0.2...0.2, using: &random)
            return KeyRepetitionParticle(angle: angle, reach: Double.random(in: 0.45...1.1, using: &random),
                                         tintIndex: Int.random(in: 0..<3, using: &random),
                                         delay: Double.random(in: 0...0.06, using: &random))
        }
    }

    func offset(at progress: Double, radius: CGFloat) -> CGSize {
        let u = min(1, max(0, progress))
        let travel = (1 - pow(1 - u, 3)) * reach * Double(radius)
        return CGSize(width: cos(angle) * travel, height: sin(angle) * travel + u * u * 50)
    }

    func opacity(at progress: Double) -> Double {
        min(1, max(0, (1 - progress) / 0.5))
    }
}

/// The letter drawn once, then cut into its shards.
struct KeyRepetitionLetterArt {
    struct Piece {
        let shard: KeyRepetitionShard
        let image: CGImage
        /// Where `image` sits, in points relative to the letter's center.
        let rect: CGRect
        let outline: Path
    }

    let pieces: [Piece]

    @MainActor
    static func make(letter: String, fontSize: CGFloat, dark: Bool, scale: CGFloat, seed: UInt64,
                     power: Double = 1) -> KeyRepetitionLetterArt? {
        let view = Text(letter)
            .font(.system(size: fontSize, weight: .semibold, design: .rounded))
            .foregroundStyle(LinearGradient(colors: [KeyRepetitionGrowth.topColor(power, dark: dark).color,
                                                     KeyRepetitionGrowth.bottomColor(power, dark: dark).color],
                                            startPoint: .top, endPoint: .bottom))
            .fixedSize()
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        guard let image = renderer.cgImage, let mask = AlphaMask(image) else { return nil }

        let size = CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        let shards = KeyRepetitionShard.make(columns: 12, rows: 16, size: size, seed: seed) { mask.isOpaque(at: $0) }
        let pieces: [Piece] = shards.compactMap { shard in
            let xs = shard.points.map(\.x), ys = shard.points.map(\.y)
            guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return nil }
            let rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).insetBy(dx: -1, dy: -1)
            let pixels = CGRect(x: (rect.minX + size.width / 2) * scale, y: (rect.minY + size.height / 2) * scale,
                                width: rect.width * scale, height: rect.height * scale).integral
            guard let crop = image.cropping(to: pixels) else { return nil }
            let placed = CGRect(x: pixels.minX / scale - size.width / 2, y: pixels.minY / scale - size.height / 2,
                                width: CGFloat(crop.width) / scale, height: CGFloat(crop.height) / scale)
            var outline = Path()
            outline.addLines(shard.points.map { CGPoint(x: $0.x - shard.centroid.x, y: $0.y - shard.centroid.y) })
            outline.closeSubpath()
            return Piece(shard: shard, image: crop, rect: placed, outline: outline)
        }
        return KeyRepetitionLetterArt(pieces: pieces)
    }

    /// A small copy of the image's transparency.
    private struct AlphaMask {
        static let side = 96
        let alpha: [UInt8]

        init?(_ image: CGImage) {
            var bytes = [UInt8](repeating: 0, count: Self.side * Self.side * 4)
            let drew: Bool = bytes.withUnsafeMutableBytes { buffer in
                guard let context = CGContext(data: buffer.baseAddress, width: Self.side, height: Self.side,
                                              bitsPerComponent: 8, bytesPerRow: Self.side * 4,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                context.draw(image, in: CGRect(x: 0, y: 0, width: Self.side, height: Self.side))
                return true
            }
            guard drew else { return nil }
            alpha = stride(from: 3, to: bytes.count, by: 4).map { bytes[$0] }
        }

        func isOpaque(at point: CGPoint) -> Bool {
            let x = min(Self.side - 1, max(0, Int(point.x * CGFloat(Self.side))))
            let y = min(Self.side - 1, max(0, Int(point.y * CGFloat(Self.side))))
            return alpha[y * Self.side + x] > 40
        }
    }
}

/// The ending: the letter squeezes, snaps white-hot and shatters.
/// The session is already saved by the time this plays.
struct KeyRepetitionBurstView: View {
    static let duration = KeyRepetitionBurstFrame.breakTime + KeyRepetitionBurstFrame.shardLife

    let letter: String
    let area: CGSize
    /// How full the letter was on the final press. Fuller means a bigger blast.
    var power: Double = 1
    let seed: UInt64
    let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.decorativeAnimations) private var decorative
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @State private var start = Date.now
    @State private var art: KeyRepetitionLetterArt?
    @State private var sparks: [KeyRepetitionParticle] = []
    @State private var faded = false

    private var isAnimated: Bool { !reduceMotion && decorative }

    var body: some View {
        Group {
            if isAnimated {
                TimelineView(.animation) { timeline in
                    KeyRepetitionBurstFrame(letter: letter, area: area, art: art, sparks: sparks,
                                            time: timeline.date.timeIntervalSince(start), power: power)
                }
            } else {
                // Reduce Motion: no burst, just a quiet fade into the results.
                Text(letter)
                    .font(.system(size: KeyRepetitionGrowth.fontSize(progress: power, area: area, metrics: .of(letter)),
                                  weight: .semibold, design: .rounded))
                    .foregroundStyle(KeyRepetitionGrowth.bottomColor(power, dark: colorScheme == .dark).color)
                    .fixedSize()
                    .opacity(faded ? 0 : 1)
                    .frame(width: area.width, height: area.height)
                    .clipped()
            }
        }
        .frame(width: area.width, height: area.height)
        .accessibilityHidden(true)
        .onAppear {
            if isAnimated {
                art = KeyRepetitionLetterArt.make(letter: letter,
                                                  fontSize: KeyRepetitionGrowth.fontSize(progress: power, area: area, metrics: .of(letter)),
                                                  dark: colorScheme == .dark, scale: displayScale, seed: seed, power: power)
                sparks = KeyRepetitionParticle.make(count: 12 + Int(34 * min(1, max(0, power))), seed: seed)
            } else {
                withAnimation(.linear(duration: 0.35)) { faded = true }
            }
            start = .now
        }
        .task {
            try? await Task.sleep(for: .seconds(isAnimated ? Self.duration : 0.4))
            guard !Task.isCancelled else { return }
            onDone()
        }
    }
}

/// One moment of the ending.
struct KeyRepetitionBurstFrame: View {
    static let squeezeEnd = 0.10
    static let breakTime = 0.16
    static let shardLife = 0.94

    let letter: String
    let area: CGSize
    let art: KeyRepetitionLetterArt?
    let sparks: [KeyRepetitionParticle]
    let time: TimeInterval
    var power: Double = 1
    @Environment(\.colorScheme) private var colorScheme

    /// How far the blast reaches, from a small pop to the full shatter.
    static func blastScale(_ power: Double) -> Double { 0.4 + 0.6 * min(1, max(0, power)) }
    private var blast: Double { Self.blastScale(power) }

    /// The letter's size just before it breaks.
    static func squeezeScale(at time: TimeInterval) -> Double {
        if time <= 0 { return 1 }
        if time < squeezeEnd {
            let u = time / squeezeEnd
            return 1 - 0.08 * (1 - (1 - u) * (1 - u))
        }
        let u = min(1, (time - squeezeEnd) / (breakTime - squeezeEnd))
        return 0.92 + 0.18 * u * u
    }

    /// 0...1: how white-hot the letter is while it snaps outward.
    static func heat(at time: TimeInterval) -> Double {
        guard time > squeezeEnd else { return 0 }
        return min(1, (time - squeezeEnd) / (breakTime - squeezeEnd))
    }

    var body: some View {
        Canvas { context, size in
            draw(in: &context, size: size)
        }
        .frame(width: area.width, height: area.height)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let dark = colorScheme == .dark
        if time < Self.breakTime {
            drawWhole(in: context, center: center, dark: dark)
        } else {
            let elapsed = time - Self.breakTime
            // A tiny kick on impact that dies away at once.
            let kick = 7 * power * exp(-elapsed * 22) * sin(elapsed * 70)
            var blast = context
            blast.translateBy(x: kick, y: -kick * 0.6)
            drawCore(in: blast, center: center, size: size, elapsed: elapsed)
            drawRing(in: blast, center: center, size: size, elapsed: elapsed, dark: dark)
            drawSparks(in: blast, center: center, size: size, elapsed: elapsed, dark: dark)
            drawShards(in: blast, center: center, size: size, elapsed: elapsed)
        }
    }

    /// Exactly what the growing letter showed, so there is no visible swap.
    private func drawWhole(in context: GraphicsContext, center: CGPoint, dark: Bool) {
        let glow = KeyRepetitionGrowth.bottomColor(power, dark: dark).color
        let glowStrength = 0.32 * KeyRepetitionGrowth.intensity(power)
        let reach = min(area.width, area.height) * 0.62
        context.fill(Path(ellipseIn: CGRect(x: center.x - reach, y: center.y - reach, width: reach * 2, height: reach * 2)),
                     with: .radialGradient(Gradient(colors: [glow.opacity(glowStrength), .clear]),
                                           center: center, startRadius: 0, endRadius: reach))
        var letterContext = context
        letterContext.translateBy(x: center.x, y: center.y)
        let scale = Self.squeezeScale(at: time)
        letterContext.scaleBy(x: scale, y: scale)
        let font = KeyRepetitionGrowth.fontSize(progress: power, area: area, metrics: .of(letter))
        // A Canvas needs the gradient set on the resolved text to keep it.
        var text = letterContext.resolve(Text(letter).font(.system(size: font, weight: .semibold, design: .rounded)))
        let height = text.measure(in: CGSize(width: CGFloat.infinity, height: .infinity)).height
        let heat = Self.heat(at: time)
        let white = KeyRepetitionGrowth.RGB(red: 1, green: 1, blue: 0.96)
        text.shading = .linearGradient(Gradient(colors: [KeyRepetitionGrowth.topColor(power, dark: dark).mixed(with: white, heat).color,
                                                         KeyRepetitionGrowth.bottomColor(power, dark: dark).mixed(with: white, heat).color]),
                                       startPoint: CGPoint(x: 0, y: -height / 2), endPoint: CGPoint(x: 0, y: height / 2))
        letterContext.draw(text, at: .zero)
    }

    private func drawCore(in context: GraphicsContext, center: CGPoint, size: CGSize, elapsed: TimeInterval) {
        let strength = max(0, 1 - elapsed / 0.2)
        guard strength > 0 else { return }
        let reach = min(size.width, size.height) * (0.28 + 0.2 * (1 - strength)) * blast
        context.fill(Path(ellipseIn: CGRect(x: center.x - reach, y: center.y - reach, width: reach * 2, height: reach * 2)),
                     with: .radialGradient(Gradient(colors: [Color.white.opacity(0.95 * strength),
                                                             Color(red: 1, green: 0.8, blue: 0.45).opacity(0.4 * strength), .clear]),
                                           center: center, startRadius: 0, endRadius: reach))
    }

    private func drawRing(in context: GraphicsContext, center: CGPoint, size: CGSize, elapsed: TimeInterval, dark: Bool) {
        let u = elapsed / 0.55
        guard u < 1 else { return }
        let radius = hypot(size.width, size.height) * 0.52 * blast * (1 - pow(1 - u, 3)) + 20
        let ring = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        context.stroke(ring, with: .color(KeyRepetitionGrowth.topColor(power, dark: dark).color.opacity(0.7 * (1 - u))),
                       lineWidth: 3.5 * (1 - u) + 0.5)
    }

    private func drawSparks(in context: GraphicsContext, center: CGPoint, size: CGSize, elapsed: TimeInterval, dark: Bool) {
        let tints = [KeyRepetitionGrowth.RGB(red: 1, green: 0.97, blue: 0.85).color,
                     KeyRepetitionGrowth.topColor(power, dark: dark).color, KeyRepetitionGrowth.bottomColor(power, dark: dark).color]
        let radius = hypot(size.width, size.height) * 0.5 * blast
        for spark in sparks {
            let u = (elapsed - spark.delay) / (Self.shardLife * 0.8)
            guard u > 0, u < 1 else { continue }
            let head = spark.offset(at: u, radius: radius), tail = spark.offset(at: max(0, u - 0.05), radius: radius)
            var line = Path()
            line.move(to: CGPoint(x: center.x + tail.width, y: center.y + tail.height))
            line.addLine(to: CGPoint(x: center.x + head.width, y: center.y + head.height))
            context.stroke(line, with: .color(tints[spark.tintIndex].opacity(spark.opacity(at: u))),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
    }

    private func drawShards(in context: GraphicsContext, center: CGPoint, size: CGSize, elapsed: TimeInterval) {
        guard let art else { return }
        let progress = elapsed / Self.shardLife
        guard progress < 1 else { return }
        let radius = hypot(size.width, size.height) * 0.6 * blast
        // Pieces start at the snapped-out size, then shrink as they fly.
        let startScale = Self.squeezeScale(at: Self.breakTime)
        let hot = max(0, 1 - elapsed / 0.09)
        for piece in art.pieces {
            let shard = piece.shard
            let travel = shard.travel(at: progress, radius: radius)
            var copy = context
            copy.opacity = shard.opacity(at: progress)
            copy.translateBy(x: center.x + shard.centroid.x * startScale + travel.width,
                             y: center.y + shard.centroid.y * startScale + travel.height)
            copy.rotate(by: .radians(shard.spin * progress))
            let scale = startScale * shard.scale(at: progress)
            copy.scaleBy(x: scale, y: scale)
            copy.clip(to: piece.outline)
            let image = Image(decorative: piece.image, scale: piece.image.width > 0 ? CGFloat(piece.image.width) / piece.rect.width : 1)
            let place = piece.rect.offsetBy(dx: -shard.centroid.x, dy: -shard.centroid.y)
            if hot > 0 {
                // The flash stays on the letter's ink, not the whole triangle.
                copy.drawLayer { layer in
                    layer.draw(image, in: place)
                    layer.blendMode = .sourceAtop
                    layer.fill(piece.outline, with: .color(.white.opacity(0.75 * hot)))
                }
            } else {
                copy.draw(image, in: place)
            }
        }
    }
}
