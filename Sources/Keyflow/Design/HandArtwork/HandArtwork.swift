import CoreGraphics
import Foundation
import KeyflowCore

/// The vector geometry of one hand, read from its SVG source
/// (`Assets/Hands/left-hand.svg`, `right-hand.svg`, embedded at build time
/// in `HandArtworkSources.swift`). Everything shares the SVG's viewBox.
struct HandArtwork: @unchecked Sendable {
    enum DetailStyle: Equatable {
        /// Knuckles and joint creases.
        case detail
        /// Tendons and other barely-there structure.
        case faint
        case nail
    }

    let hand: Hand
    let viewBox: CGRect
    /// The whole hand, closed: fills, clipping and hit testing.
    let silhouette: CGPath
    /// The contour line, left open at the wrist.
    let outline: CGPath
    /// Finger regions as drawn (to be clipped to the silhouette).
    let regions: [HandFinger: CGPath]
    /// Finger regions intersected with the silhouette: exact hit areas.
    let hitRegions: [HandFinger: CGPath]
    let details: [(path: CGPath, style: DetailStyle)]
    /// Where each finger's status symbol sits.
    let markers: [HandFinger: CGPoint]

    enum LoadError: Error, Equatable {
        case missing(String)
        case badViewBox
    }

    init(svg: String, hand: Hand) throws {
        let document = try SVGDocument(svg)
        guard document.viewBox.width > 0, document.viewBox.height > 0 else { throw LoadError.badViewBox }

        func path(_ id: String) throws -> CGPath {
            guard let element = document.paths.first(where: { $0.id == id }) else { throw LoadError.missing(id) }
            return try SVGPath.parse(element.d)
        }

        self.hand = hand
        viewBox = document.viewBox
        silhouette = try path("silhouette")
        outline = try path("silhouette-outline")

        var regions: [HandFinger: CGPath] = [:]
        var hits: [HandFinger: CGPath] = [:]
        var markers: [HandFinger: CGPoint] = [:]
        for finger in HandFinger.allCases where finger.hand == hand {
            let id = Self.regionID(finger)
            regions[finger] = try path(id)
            hits[finger] = try path("\(id)-hit").intersection(silhouette)
            guard let marker = document.points["\(id)-marker"] else { throw LoadError.missing("\(id)-marker") }
            markers[finger] = marker
        }
        self.regions = regions
        hitRegions = hits
        self.markers = markers

        details = try document.paths.compactMap { element in
            let style: DetailStyle? = switch element.className {
            case "detail": .detail
            case "faint": .faint
            case "nail": .nail
            default: nil
            }
            guard let style else { return nil }
            return (try SVGPath.parse(element.d), style)
        }
    }

    /// "thumb", "index", "middle", "ring", "pinky": the SVG region ids.
    static func regionID(_ finger: HandFinger) -> String {
        finger.isThumb ? "thumb" : finger.shortName.lowercased()
    }

    /// The finger whose region contains `point` (in viewBox coordinates).
    func finger(at point: CGPoint) -> HandFinger? {
        hitRegions.first { $0.value.contains(point) }?.key
    }

    static let left: HandArtwork? = try? HandArtwork(svg: HandArtworkSources.left, hand: .left)
    static let right: HandArtwork? = try? HandArtwork(svg: HandArtworkSources.right, hand: .right)

    static func artwork(for hand: Hand) -> HandArtwork? { hand == .left ? left : right }
}

/// Just enough of an SVG document: the viewBox, every `<path>` with its
/// id and class, and every `<circle>` centre by id.
struct SVGDocument {
    struct PathElement {
        let id: String?
        let className: String?
        let d: String
    }

    private(set) var viewBox: CGRect = .zero
    private(set) var paths: [PathElement] = []
    private(set) var points: [String: CGPoint] = [:]

    enum ParseError: Error { case invalidXML(String) }

    init(_ svg: String) throws {
        let delegate = Delegate()
        let parser = XMLParser(data: Data(svg.utf8))
        parser.delegate = delegate
        guard parser.parse() else {
            throw ParseError.invalidXML(parser.parserError?.localizedDescription ?? "unknown error")
        }
        viewBox = delegate.viewBox
        paths = delegate.paths
        points = delegate.points
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var viewBox: CGRect = .zero
        var paths: [PathElement] = []
        var points: [String: CGPoint] = [:]
        /// Depth inside <defs>, whose paths (the clip path) are not artwork.
        var defsDepth = 0

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            switch name {
            case "svg":
                let values = (attributes["viewBox"] ?? "").split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { Double($0) }
                if values.count == 4 { viewBox = CGRect(x: values[0], y: values[1], width: values[2], height: values[3]) }
            case "defs":
                defsDepth += 1
            case "path" where defsDepth == 0:
                if let d = attributes["d"] {
                    paths.append(PathElement(id: attributes["id"], className: attributes["class"], d: d))
                }
            case "circle":
                if let id = attributes["id"], let x = attributes["cx"].flatMap(Double.init), let y = attributes["cy"].flatMap(Double.init) {
                    points[id] = CGPoint(x: x, y: y)
                }
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            if name == "defs" { defsDepth -= 1 }
        }
    }
}
