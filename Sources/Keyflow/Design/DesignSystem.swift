import AppKit
import SwiftUI

/// Keyflow's design tokens. Screens take spacing, type, colour, radii and
/// motion from here instead of inventing their own values.
///
/// - Interface text is SF Pro (the system font); typing passages and numbers
///   are SF Mono.
/// - Colours are semantic, so light, dark and increased-contrast appearances
///   follow the system. The accent colour is reserved for the caret, the
///   next key, the primary action and live time — nothing decorative.
/// - Surfaces are separated by whitespace and hairlines, not cards or shadows.
enum DS {
    /// A 4-point scale.
    enum Space {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let s: CGFloat = 12
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    enum Radius {
        /// Buttons, option bars, key caps in hints.
        static let control: CGFloat = 6
        /// Keys of the on-screen keyboard.
        static let key: CGFloat = 6
        /// Text editors and the rare framed surface.
        static let panel: CGFloat = 8
    }

    enum Layout {
        /// The widest a typing passage or reading column gets.
        static let readingWidth: CGFloat = 860
        /// The widest an analytical page gets.
        static let pageWidth: CGFloat = 960
        static let pagePadding: CGFloat = 40
    }

    enum Typography {
        static let pageTitle = Font.system(size: 20, weight: .semibold)
        static let sectionTitle = Font.system(size: 15, weight: .semibold)
        static let body = Font.system(size: 13)
        static let bodyEmphasis = Font.system(size: 13, weight: .medium)
        static let caption = Font.system(size: 11)
        /// Small upper-case labels above or below values.
        static let eyebrow = Font.system(size: 10.5, weight: .semibold)

        /// Numbers are always SF Mono so digits line up and never jitter.
        static func metric(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
            .system(size: size, weight: weight, design: .monospaced)
        }

        /// For keys, letter pairs and words shown as data.
        static let code = Font.system(size: 13, weight: .medium, design: .monospaced)
    }

    enum Palette {
        /// Text not yet typed: clearly readable, clearly not done.
        static let pending = Color.primary.opacity(0.45)
        /// The rest of the word being typed: between pending and typed.
        static let upcoming = Color.primary.opacity(0.7)
        static let error = Color(nsColor: .systemRed)
        static let success = Color(nsColor: .systemGreen)
        static let caution = Color(nsColor: .systemOrange)
        /// Resting fill for interactive surfaces.
        static let fill = Color.primary.opacity(0.045)
        static let hover = Color.primary.opacity(0.07)
        static let selected = Color.primary.opacity(0.1)
        static let hairline = Color.primary.opacity(0.1)
    }

    enum Motion {
        static let quick = Animation.easeOut(duration: 0.12)
        static let standard = Animation.easeOut(duration: 0.2)
        /// Short enough that the caret never trails fast typing.
        static let caret = Animation.easeOut(duration: 0.07)
        static let scroll = Animation.easeOut(duration: 0.18)
        /// The Welcome Journey's spotlight, arrow and panels moving between steps.
        static let tour = Animation.spring(duration: 0.34, bounce: 0.1)
        /// The highlight sliding between options on a glass bar.
        static let selection = Animation.spring(duration: 0.28, bounce: 0.18)
    }
}

extension View {
    /// `.animation(_:value:)` that switches itself off under Reduce Motion.
    func motion<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(MotionModifier(animation: animation, value: value))
    }
}

private struct MotionModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Settings ▸ Feedback ▸ Decorative animations.
    @Environment(\.decorativeAnimations) private var decorative
    let animation: Animation
    let value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion || !decorative ? nil : animation, value: value)
    }
}

/// `withAnimation` that switches itself off under Reduce Motion.
@MainActor
func withMotion(_ animation: Animation, _ body: () -> Void) {
    if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || !Preferences.shared.decorativeAnimations {
        body()
    } else {
        withAnimation(animation, body)
    }
}
