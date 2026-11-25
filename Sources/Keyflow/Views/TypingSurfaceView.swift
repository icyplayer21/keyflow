import AppKit
import KeyflowCore
import SwiftUI

/// The default number of visible lines.
enum TypingFont {
    static let visibleLines = 3
    static let caretWidth: CGFloat = 2
}

/// The text being typed: a fixed number of visible lines, per-character
/// feedback, and a caret that glides between positions.
///
/// - Untyped text is secondary, correct text primary, mistakes red. A
///   mistyped space, which has no glyph to colour, gets a red underline.
/// - The rest of the word you're on is a little brighter than the text after
///   it, so the eye can read ahead.
/// - Lines scroll up one at a time once the caret reaches the last visible
///   line, so the passage never jumps while typing within a line. A line
///   you've finished fades back as it moves up.
/// - A finished passage gets a soft accent sweep (about 0.4 s).
/// - Under Reduce Motion the caret and lines move without animation, the
///   caret does not blink and there is no sweep. With decorative animations
///   off there is no sweep either.
struct TypingSurfaceView: View {
    let target: [Character]
    let typed: [Character]
    var visibleLines = TypingFont.visibleLines
    /// While idle the caret blinks to invite typing.
    var isIdle = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.decorativeAnimations) private var decorative
    /// Font, size, caret and mistake emphasis from Settings ▸ Appearance and Feedback.
    @Environment(\.typingStyle) private var style
    @State private var caretDimmed = false
    /// 0 to 1 while the end-of-passage sweep crosses the text.
    @State private var sweep: CGFloat?

    /// Typed lines step back to this.
    static let finishedLineOpacity = 0.4
    private var isComplete: Bool { !target.isEmpty && typed.count >= target.count }

    var body: some View {
        let characterWidth = style.characterWidth
        let lineHeight = style.lineHeight
        let font = style.swiftUIFont
        let instantCaret = reduceMotion || style.caretAnimation == .instant

        GeometryReader { geometry in
            let columns = max(8, Int(geometry.size.width / characterWidth))
            let lines = LineLayout.wrap(target, columns: columns)
            let position = typed.count
            let cursorLine = LineLayout.lineIndex(of: position, in: lines)
            let firstVisible = max(0, cursorLine - 1)
            let cursorColumn = lines.isEmpty ? 0 : position - lines[cursorLine].lowerBound
            let wordEnd = Self.currentWordEnd(in: target, at: position)

            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(lines.indices, id: \.self) { index in
                        // Only lines near the viewport carry text.
                        if abs(index - firstVisible) <= visibleLines {
                            Text(attributed(lines[index], wordEnd: wordEnd))
                                .font(font)
                                .lineLimit(1)
                                .fixedSize()
                                .frame(height: lineHeight, alignment: .leading)
                                .opacity(index < cursorLine && !isComplete ? Self.finishedLineOpacity : 1)
                        } else {
                            Color.clear.frame(width: 1, height: lineHeight)
                        }
                    }
                }
                .animation(reduceMotion ? nil : DS.Motion.scroll, value: cursorLine)

                if let sweep {
                    sweepLayer(lines: lines, firstVisible: firstVisible, progress: sweep, width: geometry.size.width)
                        .transition(.opacity)
                        .accessibilityHidden(true)
                }

                caret
                    .opacity(isIdle && caretDimmed ? 0.12 : 1)
                    .offset(caretOffset(column: cursorColumn, line: cursorLine))
                    .animation(instantCaret ? nil : DS.Motion.caret, value: position)
                    .accessibilityHidden(true)
            }
            .offset(y: -CGFloat(firstVisible) * lineHeight)
            .animation(reduceMotion ? nil : DS.Motion.scroll, value: firstVisible)
        }
        .frame(height: lineHeight * CGFloat(visibleLines))
        // Clip slightly outside the text column so the caret is whole at column 0.
        .padding(.horizontal, 4)
        .clipped()
        .padding(.horizontal, -4)
        .task(id: isIdle && !reduceMotion) { await blink() }
        .task(id: isComplete) { await playSweep() }
        .accessibilityElement()
        .accessibilityLabel("Typing passage")
        .accessibilityValue("\(typed.count) of \(target.count) characters typed")
    }

    /// Line: a thin bar before the next character. Block: a soft cell over
    /// it, so the character stays readable. Underline: a bar beneath it.
    @ViewBuilder
    private var caret: some View {
        switch style.caret {
        case .line:
            RoundedRectangle(cornerRadius: TypingFont.caretWidth / 2)
                .fill(Color.accentColor)
                .frame(width: TypingFont.caretWidth, height: style.caretHeight)
        case .block:
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.accentColor.opacity(0.28))
                .frame(width: style.characterWidth, height: style.caretHeight)
        case .underline:
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.accentColor)
                .frame(width: style.characterWidth, height: 2.5)
        }
    }

    private func caretOffset(column: Int, line: Int) -> CGSize {
        let x = CGFloat(column) * style.characterWidth
        let top = CGFloat(line) * style.lineHeight
        switch style.caret {
        case .line:
            return CGSize(width: x - TypingFont.caretWidth / 2, height: top + (style.lineHeight - style.caretHeight) / 2)
        case .block:
            return CGSize(width: x, height: top + (style.lineHeight - style.caretHeight) / 2)
        case .underline:
            return CGSize(width: x, height: top + (style.lineHeight + style.caretHeight) / 2 - 2)
        }
    }

    /// Blinks the caret while idle; stops, fully visible, once typing starts.
    private func blink() async {
        caretDimmed = false
        guard isIdle, !reduceMotion else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(530))
            guard !Task.isCancelled else { break }
            withAnimation(.easeInOut(duration: 0.16)) { caretDimmed.toggle() }
        }
        caretDimmed = false
    }

    /// The visible lines again, in the accent colour, seen through a soft
    /// band that crosses from left to right.
    private func sweepLayer(lines: [Range<Int>], firstVisible: Int, progress: CGFloat, width: CGFloat) -> some View {
        let band = max(120, width * 0.35)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(lines.indices, id: \.self) { index in
                if abs(index - firstVisible) <= visibleLines {
                    Text(String(target[lines[index]]))
                        .font(style.swiftUIFont)
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                        .fixedSize()
                        .frame(height: style.lineHeight, alignment: .leading)
                } else {
                    Color.clear.frame(width: 1, height: style.lineHeight)
                }
            }
        }
        .frame(width: width, alignment: .leading)
        .mask(alignment: .leading) {
            LinearGradient(colors: [.clear, .black, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: band)
                .offset(x: -band + progress * (width + band))
        }
    }

    /// Runs the sweep once when the passage is finished.
    private func playSweep() async {
        guard isComplete else {
            sweep = nil
            return
        }
        guard !reduceMotion, decorative else { return }
        sweep = 0
        withAnimation(.easeInOut(duration: Self.sweepDuration)) { sweep = 1 }
        try? await Task.sleep(for: .seconds(Self.sweepDuration))
        guard !Task.isCancelled else { return }
        withAnimation(DS.Motion.standard) { sweep = nil }
    }

    static let sweepDuration = 0.4

    /// Where the word at `position` ends. On a space, the word after it
    /// counts, since that is the one you're about to type.
    static func currentWordEnd(in target: [Character], at position: Int) -> Int {
        var end = position
        if end < target.count, target[end] == " " { end += 1 }
        while end < target.count, target[end] != " " { end += 1 }
        return end
    }

    private enum CharacterState { case upcoming, pending, correct, incorrect }

    private func state(at index: Int, wordEnd: Int) -> CharacterState {
        guard index < typed.count else { return index < wordEnd ? .upcoming : .pending }
        return typed[index] == target[index] ? .correct : .incorrect
    }

    /// One line as styled text, built from runs of equal state.
    private func attributed(_ range: Range<Int>, wordEnd: Int) -> AttributedString {
        var result = AttributedString()
        var start = range.lowerBound
        while start < range.upperBound {
            let runState = state(at: start, wordEnd: wordEnd)
            var end = start + 1
            while end < range.upperBound, state(at: end, wordEnd: wordEnd) == runState { end += 1 }

            var run = AttributedString(String(target[start..<end]))
            switch runState {
            case .upcoming:
                run.foregroundColor = DS.Palette.upcoming
            case .pending:
                run.foregroundColor = DS.Palette.pending
            case .correct:
                run.foregroundColor = Color.primary
            case .incorrect:
                // Always red; Strong emphasis adds a tint behind the mistake.
                run.foregroundColor = DS.Palette.error
                if style.errorEmphasis == .strong { run.backgroundColor = DS.Palette.error.opacity(0.16) }
                if target[start..<end].contains(" ") {
                    run.underlineStyle = Text.LineStyle(pattern: .solid, color: DS.Palette.error)
                }
            }
            result += run
            start = end
        }
        return result
    }
}

extension View {
    /// Keeps a finished passage on screen while its sweep plays, then sets
    /// `shown` so the results come in. Results that are already there when
    /// the screen appears show at once, and so does everything under Reduce
    /// Motion or with decorative animations off. Only the timing of the
    /// view changes: the round is finished and saved as before.
    func holdingResultsForSweep(_ finished: Bool, shown: Binding<Bool>) -> some View {
        modifier(SweepHold(finished: finished, shown: shown))
    }
}

private struct SweepHold: ViewModifier {
    let finished: Bool
    @Binding var shown: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.decorativeAnimations) private var decorative

    func body(content: Content) -> some View {
        content
            .onAppear { shown = finished }
            .task(id: finished) {
                guard finished else {
                    shown = false
                    return
                }
                guard !shown else { return }
                if reduceMotion || !decorative {
                    shown = true
                    return
                }
                try? await Task.sleep(for: .seconds(TypingSurfaceView.sweepDuration + 0.05))
                guard !Task.isCancelled else { return }
                withAnimation(DS.Motion.standard) { shown = true }
            }
    }
}
