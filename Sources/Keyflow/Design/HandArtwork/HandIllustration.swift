import KeyflowCore
import SwiftUI

/// One hand of the finger heatmap, drawn natively from its SVG geometry.
///
/// The artwork's layers are drawn in order: silhouette fill, finger tints
/// clipped to the silhouette, anatomical details, the outline, then hover
/// and selection contours inside the finger and a small status symbol.
/// Hit testing uses the exact finger regions (intersected with the
/// silhouette), so neighbouring fingers never steal a click.
struct HandIllustration: View {
    let artwork: HandArtwork
    let statuses: [HandFinger: FingerStatus]
    let selection: HandFinger?
    let select: (HandFinger) -> Void
    /// Accessibility value for each finger ("Estimated Strong, high confidence").
    var describe: (HandFinger) -> String = { _ in "" }
    @Binding var hovered: HandFinger?

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geometry in
            let fit = Fit(viewBox: artwork.viewBox, size: geometry.size)

            Canvas { context, _ in
                draw(in: &context, fit: fit)
            } symbols: {
                ForEach(FingerStatus.allCases, id: \.self) { status in
                    Image(systemName: status.symbol)
                        .font(.system(size: status == .insufficientData ? 8 : 8.5, weight: .bold))
                        .foregroundStyle(status.heatTint.opacity(status == .insufficientData ? 0.55 : 0.95))
                        .tag(status)
                }
            }
            .contentShape(Path(fit.transformed(artwork.silhouette)))
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let location): hovered = artwork.finger(at: fit.toArtwork(location))
                case .ended: hovered = nil
                }
            }
            .onTapGesture(coordinateSpace: .local) { location in
                if let finger = artwork.finger(at: fit.toArtwork(location)) { select(finger) }
            }
            .pointerStyle(hovered != nil ? .link : nil)
            .accessibilityElement(children: .contain)
            .accessibilityChildren {
                ForEach(fingers, id: \.self) { finger in
                    let frame = fit.transformed(artwork.hitRegions[finger]!).boundingBoxOfPath
                    Rectangle()
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                        .accessibilityLabel(finger.title)
                        .accessibilityValue(describe(finger))
                        .accessibilityAddTraits(finger == selection ? [.isButton, .isSelected] : .isButton)
                        .accessibilityAction { select(finger) }
                }
            }
        }
        .aspectRatio(artwork.viewBox.size, contentMode: .fit)
        // The arm fades out below the wrist, as in the SVG.
        .mask(LinearGradient(stops: [.init(color: .black, location: 0.86), .init(color: .black.opacity(0), location: 1)],
                             startPoint: .top, endPoint: .bottom))
    }

    /// Pinky to thumb on the left hand, thumb to pinky on the right.
    private var fingers: [HandFinger] {
        HandFinger.keyboardOrder.filter { $0.hand == artwork.hand }
    }

    // MARK: Drawing

    private func draw(in context: inout GraphicsContext, fit: Fit) {
        let dark = scheme == .dark
        let silhouette = Path(fit.transformed(artwork.silhouette))
        let ink = Color.primary

        // A. Silhouette
        context.fill(silhouette, with: .color(dark ? Color.white.opacity(0.06) : Color.black.opacity(0.035)))

        // B. Finger tints, inside the silhouette only.
        var inside = context
        inside.clip(to: silhouette)
        for finger in fingers {
            guard let region = artwork.regions[finger] else { continue }
            let status = statuses[finger] ?? .insufficientData
            inside.fill(Path(fit.transformed(region)), with: .color(status.heatTint.opacity(opacity(for: finger, status: status, dark: dark))))
        }

        // C. Anatomy
        for detail in artwork.details {
            let path = Path(fit.transformed(detail.path))
            switch detail.style {
            case .faint:
                context.stroke(path, with: .color(ink.opacity(dark ? 0.10 : 0.08)), style: StrokeStyle(lineWidth: 0.8, lineCap: .round))
            case .detail:
                context.stroke(path, with: .color(ink.opacity(dark ? 0.26 : 0.22)), style: StrokeStyle(lineWidth: 0.75, lineCap: .round))
            case .nail:
                context.fill(path, with: .color(dark ? Color.white.opacity(0.07) : Color.white.opacity(0.7)))
                context.stroke(path, with: .color(ink.opacity(0.16)), lineWidth: 0.6)
            }
        }

        // Outline, open at the wrist.
        context.stroke(Path(fit.transformed(artwork.outline)), with: .color(ink.opacity(dark ? 0.5 : 0.42)),
                       style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))

        // Hover and selection: a fine contour just inside the finger.
        for finger in fingers where finger == hovered || finger == selection {
            guard let hit = artwork.hitRegions[finger] else { continue }
            let region = Path(fit.transformed(hit))
            var within = context
            within.clip(to: region)
            if finger == selection {
                within.stroke(region, with: .color(Color.accentColor.opacity(0.85)), lineWidth: 2.4)
            } else {
                within.stroke(region, with: .color(ink.opacity(0.28)), lineWidth: 2)
            }
        }

        // Status symbols, so colour is never the only signal.
        for finger in fingers {
            guard let anchor = artwork.markers[finger],
                  let symbol = context.resolveSymbol(id: statuses[finger] ?? .insufficientData) else { continue }
            context.draw(symbol, at: fit.toView(anchor))
        }
    }

    private func opacity(for finger: HandFinger, status: FingerStatus, dark: Bool) -> Double {
        let boost = finger == selection ? 0.10 : (finger == hovered ? 0.06 : 0)
        if status == .insufficientData { return (dark ? 0.05 : 0.04) + boost * 0.5 }
        return (dark ? 0.26 : 0.2) + boost
    }

    /// Aspect-fit mapping between the artwork's viewBox and the view.
    struct Fit {
        let viewBox: CGRect
        let scale: CGFloat
        let origin: CGPoint

        init(viewBox: CGRect, size: CGSize) {
            self.viewBox = viewBox
            scale = min(size.width / viewBox.width, size.height / viewBox.height)
            origin = CGPoint(x: (size.width - viewBox.width * scale) / 2, y: (size.height - viewBox.height * scale) / 2)
        }

        var transform: CGAffineTransform {
            CGAffineTransform(translationX: origin.x, y: origin.y)
                .scaledBy(x: scale, y: scale)
                .translatedBy(x: -viewBox.minX, y: -viewBox.minY)
        }

        func transformed(_ path: CGPath) -> CGPath {
            var transform = transform
            return path.copy(using: &transform) ?? path
        }

        func toView(_ point: CGPoint) -> CGPoint { point.applying(transform) }
        func toArtwork(_ point: CGPoint) -> CGPoint { point.applying(transform.inverted()) }
    }
}

extension FingerStatus {
    /// Restrained heatmap hues: muted green, soft blue, warm amber, neutral gray.
    var heatTint: Color {
        switch self {
        case .strong: Color(red: 0.32, green: 0.63, blue: 0.45)
        case .developing: Color(red: 0.36, green: 0.56, blue: 0.84)
        case .needsPractice: Color(red: 0.90, green: 0.60, blue: 0.22)
        case .insufficientData: Color(red: 0.55, green: 0.55, blue: 0.58)
        }
    }
}
