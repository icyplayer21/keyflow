import CoreGraphics
import Foundation
import Testing
@testable import Keyflow
import KeyflowCore

@Suite struct SVGPathTests {
    private func points(_ d: String) throws -> [CGPoint] {
        var result: [CGPoint] = []
        try SVGPath.parse(d).applyWithBlock { element in
            let e = element.pointee
            let count = switch e.type {
            case .moveToPoint, .addLineToPoint: 1
            case .addQuadCurveToPoint: 2
            case .addCurveToPoint: 3
            default: 0
            }
            if count > 0 { result.append(e.points[count - 1]) }
        }
        return result
    }

    @Test func absoluteAndRelativeCommands() throws {
        #expect(try points("M10,10 L20,10 l0,10 H5 v-5 h2 V0") ==
                [CGPoint(x: 10, y: 10), CGPoint(x: 20, y: 10), CGPoint(x: 20, y: 20), CGPoint(x: 5, y: 20),
                 CGPoint(x: 5, y: 15), CGPoint(x: 7, y: 15), CGPoint(x: 7, y: 0)])
    }

    @Test func implicitLinetoAfterMoveAndCompactNumbers() throws {
        #expect(try points("m1 1 2 2-1.5.5") == [CGPoint(x: 1, y: 1), CGPoint(x: 3, y: 3), CGPoint(x: 1.5, y: 3.5)])
        #expect(try points("M1e1,2E0") == [CGPoint(x: 10, y: 2)])
    }

    @Test func curvesIncludingSmoothShorthands() throws {
        let path = try SVGPath.parse("M0,0 C0,10 10,10 10,0 S20,-10 20,0 Q25,5 30,0 T40,0 Z")
        #expect(path.boundingBoxOfPath.maxX == 40)
        #expect(try points("M0,0 c1,1 2,1 3,0 s2,-1 3,0").last == CGPoint(x: 6, y: 0))
    }

    @Test func arcsAndGarbageAreRejected() {
        #expect(throws: SVGPath.ParseError.unsupportedCommand("A")) { try SVGPath.parse("M0,0 A5,5 0 0 1 10,0") }
        #expect(throws: (any Error).self) { try SVGPath.parse("10,10") }
        #expect(throws: (any Error).self) { try SVGPath.parse("M0,0 L5") }
    }
}

@Suite struct HandArtworkTests {
    private static let assets = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Assets/Hands")

    @Test func embeddedArtworkMatchesTheSVGFiles() throws {
        let left = try String(contentsOf: Self.assets.appending(path: "left-hand.svg"), encoding: .utf8)
        let right = try String(contentsOf: Self.assets.appending(path: "right-hand.svg"), encoding: .utf8)
        #expect(HandArtworkSources.left == left, "Run Scripts/hand-artwork/embed_hands.py after editing the SVGs")
        #expect(HandArtworkSources.right == right, "Run Scripts/hand-artwork/embed_hands.py after editing the SVGs")
    }

    @Test(arguments: [Hand.left, .right])
    func loadsEveryLayer(hand: Hand) throws {
        let artwork = try #require(HandArtwork.artwork(for: hand))
        #expect(artwork.viewBox == CGRect(x: 0, y: 0, width: 320, height: 380))
        #expect(Set(artwork.regions.keys) == Set(HandFinger.allCases.filter { $0.hand == hand }))
        #expect(artwork.hitRegions.count == 5)
        #expect(artwork.markers.count == 5)
        #expect(artwork.details.contains { $0.style == .nail })
        #expect(artwork.details.filter { $0.style == .nail }.count == 5)
        #expect(artwork.details.contains { $0.style == .detail })
        // One continuous silhouette.
        var moves = 0
        artwork.silhouette.applyWithBlock { if $0.pointee.type == .moveToPoint { moves += 1 } }
        #expect(moves == 1)
    }

    @Test(arguments: [Hand.left, .right])
    func everyFingerIsHitAtItsMarkerAndOnlyThere(hand: Hand) throws {
        let artwork = try #require(HandArtwork.artwork(for: hand))
        for (finger, marker) in artwork.markers {
            #expect(artwork.finger(at: marker) == finger, "\(finger) marker")
        }
        // Outside the hand, nothing is selected.
        #expect(artwork.finger(at: CGPoint(x: 2, y: 2)) == nil)
        #expect(artwork.finger(at: CGPoint(x: 160, y: 330)) == nil, "the back of the hand belongs to no finger")
    }

    @Test(arguments: [Hand.left, .right])
    func regionsNeverOverlapAndStayInsideTheHand(hand: Hand) throws {
        let artwork = try #require(HandArtwork.artwork(for: hand))
        var hits: [HandFinger: Int] = [:]
        for x in stride(from: 0.5, to: 320, by: 2) {
            for y in stride(from: 0.5, to: 380, by: 2) {
                let point = CGPoint(x: x, y: y)
                let owners = artwork.hitRegions.filter { $0.value.contains(point) }.map(\.key)
                #expect(owners.count <= 1, "\(point) is in \(owners)")
                if let owner = owners.first {
                    #expect(artwork.silhouette.contains(point), "\(owner) leaks outside the hand at \(point)")
                    hits[owner, default: 0] += 1
                }
            }
        }
        // Every finger has a substantial area; the middle finger is the largest of the four.
        for finger in HandFinger.allCases where finger.hand == hand {
            #expect((hits[finger] ?? 0) > 300, "\(finger): \(hits[finger] ?? 0)")
        }
        let middle = hand == .left ? HandFinger.leftMiddle : .rightMiddle
        let pinky = hand == .left ? HandFinger.leftPinky : .rightPinky
        #expect(hits[middle]! > hits[pinky]!)
    }

    @Test func rightHandMirrorsTheLeft() throws {
        let left = try #require(HandArtwork.left), right = try #require(HandArtwork.right)
        for finger in HandFinger.allCases where finger.hand == .left {
            let mirrored = HandFinger.allCases.first { $0.hand == .right && $0.finger.name == finger.finger.name }!
            let marker = left.markers[finger]!
            let opposite = right.markers[mirrored]!
            #expect(abs(opposite.x - (320 - marker.x)) < 0.01 && abs(opposite.y - marker.y) < 0.01)
            #expect(right.finger(at: CGPoint(x: 320 - marker.x, y: marker.y)) == mirrored)
        }
        // Thumbs point towards the centre: the left thumb is on the right of its hand.
        #expect(left.markers[.leftThumb]!.x > left.markers[.leftIndex]!.x)
        #expect(right.markers[.rightThumb]!.x < right.markers[.rightIndex]!.x)
    }

    @Test func middleFingerReachesHighestAndPinkyIsShortest() throws {
        let left = try #require(HandArtwork.left)
        let tops = left.hitRegions.mapValues { $0.boundingBoxOfPath.minY }
        #expect(tops[.leftMiddle]! < tops[.leftRing]! && tops[.leftMiddle]! < tops[.leftIndex]!)
        #expect(tops[.leftPinky]! > tops[.leftRing]!)
    }

    @Test func fitMapsBetweenViewAndArtwork() {
        let fit = HandIllustration.Fit(viewBox: CGRect(x: 0, y: 0, width: 320, height: 380), size: CGSize(width: 400, height: 380))
        #expect(fit.scale == 1)
        #expect(fit.origin == CGPoint(x: 40, y: 0))
        let point = CGPoint(x: 100, y: 200)
        let back = fit.toArtwork(fit.toView(point))
        #expect(abs(back.x - point.x) < 0.001 && abs(back.y - point.y) < 0.001)
    }
}
