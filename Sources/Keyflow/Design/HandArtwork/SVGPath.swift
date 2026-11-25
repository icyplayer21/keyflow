import CoreGraphics
import Foundation

/// Parses SVG path data (`d` attributes) into Core Graphics paths.
///
/// Supports every path command except elliptical arcs: M L H V C S Q T Z,
/// absolute and relative, with implicit repeats. Keyflow's artwork uses no
/// arcs; an `A` command makes parsing fail rather than draw something wrong.
enum SVGPath {
    enum ParseError: Error, Equatable {
        case unsupportedCommand(Character)
        case malformed(String)
    }

    static func parse(_ data: String) throws -> CGPath {
        var scanner = Scanner(data)
        let path = CGMutablePath()
        var current = CGPoint.zero
        var start = CGPoint.zero
        var lastControl: CGPoint?        // for S and T reflections
        var lastCommand: Character = " "
        var command: Character?

        while true {
            scanner.skipSeparators()
            guard !scanner.isAtEnd else { break }
            if let letter = scanner.letter() {
                command = letter
            } else if command == nil {
                throw ParseError.malformed("Path data must start with a command")
            }
            guard let cmd = command else { break }
            let relative = cmd.isLowercase
            let base = relative ? current : .zero
            func point() throws -> CGPoint {
                let x = try scanner.number(), y = try scanner.number()
                return CGPoint(x: base.x + x, y: base.y + y)
            }

            switch cmd.uppercased().first! {
            case "M":
                current = try point()
                start = current
                path.move(to: current)
                // Further pairs after a moveto are implicit linetos.
                command = relative ? "l" : "L"
                lastControl = nil
            case "L":
                current = try point()
                path.addLine(to: current)
                lastControl = nil
            case "H":
                let x = try scanner.number()
                current = CGPoint(x: (relative ? current.x : 0) + x, y: current.y)
                path.addLine(to: current)
                lastControl = nil
            case "V":
                let y = try scanner.number()
                current = CGPoint(x: current.x, y: (relative ? current.y : 0) + y)
                path.addLine(to: current)
                lastControl = nil
            case "C":
                let c1 = try point(), c2 = try point(), end = try point()
                path.addCurve(to: end, control1: c1, control2: c2)
                lastControl = c2
                current = end
            case "S":
                let c1 = reflect(lastControl, about: current, if: "CS".contains(lastCommand.uppercased().first!))
                let c2 = try point(), end = try point()
                path.addCurve(to: end, control1: c1, control2: c2)
                lastControl = c2
                current = end
            case "Q":
                let c = try point(), end = try point()
                path.addQuadCurve(to: end, control: c)
                lastControl = c
                current = end
            case "T":
                let c = reflect(lastControl, about: current, if: "QT".contains(lastCommand.uppercased().first!))
                let end = try point()
                path.addQuadCurve(to: end, control: c)
                lastControl = c
                current = end
            case "Z":
                path.closeSubpath()
                current = start
                lastControl = nil
                command = nil   // a number straight after Z is malformed
            default:
                throw ParseError.unsupportedCommand(cmd)
            }
            lastCommand = cmd
        }
        return path
    }

    private static func reflect(_ control: CGPoint?, about point: CGPoint, if applicable: Bool) -> CGPoint {
        guard applicable, let control else { return point }
        return CGPoint(x: 2 * point.x - control.x, y: 2 * point.y - control.y)
    }

    /// A minimal tokenizer for path data.
    private struct Scanner {
        let characters: [Character]
        var index = 0

        init(_ string: String) { characters = Array(string) }

        var isAtEnd: Bool { index >= characters.count }

        mutating func skipSeparators() {
            while index < characters.count, characters[index].isWhitespace || characters[index] == "," { index += 1 }
        }

        mutating func letter() -> Character? {
            guard index < characters.count, characters[index].isLetter, characters[index] != "e", characters[index] != "E"
            else { return nil }
            defer { index += 1 }
            return characters[index]
        }

        mutating func number() throws -> CGFloat {
            skipSeparators()
            let begin = index
            if index < characters.count, "+-".contains(characters[index]) { index += 1 }
            var seenDot = false
            while index < characters.count {
                let c = characters[index]
                if c.isNumber { index += 1 }
                else if c == ".", !seenDot { seenDot = true; index += 1 }
                else if c == "e" || c == "E" {
                    index += 1
                    if index < characters.count, "+-".contains(characters[index]) { index += 1 }
                } else { break }
            }
            guard index > begin, let value = Double(String(characters[begin..<index])) else {
                throw ParseError.malformed("Expected a number at \(begin)")
            }
            return CGFloat(value)
        }
    }
}
