import Foundation

/// Word-wraps text for a fixed-width (monospaced) typing surface.
/// Kept out of the view layer so cursor placement is plain arithmetic.
public enum LineLayout {
    /// Splits `text` into lines of at most `columns` characters, breaking
    /// between words. A word's trailing spaces stay on its line, so the cursor
    /// never sits past the right edge. Words longer than a line are hard-split.
    /// The returned ranges are contiguous and cover the whole text.
    public static func wrap(_ text: [Character], columns: Int) -> [Range<Int>] {
        guard !text.isEmpty else { return [] }
        guard columns > 0 else { return [0..<text.count] }

        var lines: [Range<Int>] = []
        var lineStart = 0
        var index = 0

        while index < text.count {
            // A token is a word plus the spaces that follow it.
            var end = index
            while end < text.count, text[end] != " " { end += 1 }
            while end < text.count, text[end] == " " { end += 1 }

            if end - lineStart > columns {
                if index > lineStart {
                    lines.append(lineStart..<index)
                    lineStart = index
                }
                while end - lineStart > columns {
                    lines.append(lineStart..<(lineStart + columns))
                    lineStart += columns
                }
            }
            index = end
        }
        if lineStart < text.count {
            lines.append(lineStart..<text.count)
        }
        return lines
    }

    /// The line containing `position`. A position at the very end of the text
    /// belongs to the last line.
    public static func lineIndex(of position: Int, in lines: [Range<Int>]) -> Int {
        lines.firstIndex { $0.contains(position) } ?? max(0, lines.count - 1)
    }
}
