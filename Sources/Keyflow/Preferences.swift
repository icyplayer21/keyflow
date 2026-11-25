import AppKit
import KeyflowCore
import Observation
import SwiftUI

/// Every preference shown in Settings that is not already owned by a
/// feature model. Each property is stored in `UserDefaults` under a stable
/// key, has one documented default, and is the only copy of that setting.
///
/// Settings that already existed stay where they were and are shown in
/// Settings by binding to their owners, so nothing is stored twice:
/// - Default test duration → `TypingSessionModel.durationSeconds` (`test.duration`)
/// - Show virtual keyboard → each Learn model's `showsKeyboard`
///   (`muscleMemory.showsKeyboard`, `fingerFocus.showsKeyboard`, `mechanics.showsKeyboard`)
@MainActor
@Observable
final class Preferences {
    // MARK: General

    /// Default: Practice.
    var startupSection: AppSection { didSet { save(startupSection.rawValue, Key.startupSection) } }
    /// Default: off. When on, it takes precedence over `startupSection`.
    var restoresLastSection: Bool { didSet { save(restoresLastSection, Key.restoresLastSection) } }
    /// The section open when Keyflow last quit. Not a setting itself.
    var lastSection: AppSection { didSet { save(lastSection.rawValue, Key.lastSection) } }

    // MARK: Appearance

    /// Default: System.
    var theme: Theme { didSet { save(theme.rawValue, Key.theme); applyTheme() } }
    /// Default: Top bar. Where Learn, Practice, Test, Focus and Progress live.
    var navigation: NavigationStyle { didSet { save(navigation.rawValue, Key.navigation) } }
    /// In Sidebar mode, whether you hid the sidebar (⌃⌘S or the toolbar
    /// button). Not a setting: it is how you left the window.
    var sidebarHidden: Bool { didSet { save(sidebarHidden, Key.sidebarHidden) } }
    /// Default: SF Mono.
    var typingFont: TypingFontChoice { didSet { save(typingFont.rawValue, Key.typingFont) } }
    /// Default: 24 pt. Settings offers 18...36; a stored value outside that is clamped on load.
    var typingFontSize: Double { didSet { save(typingFontSize, Key.typingFontSize) } }
    /// Default: Line.
    var caretStyle: CaretStyle { didSet { save(caretStyle.rawValue, Key.caretStyle) } }
    /// Default: Smooth. Reduce Motion always makes it instant.
    var caretAnimation: CaretAnimation { didSet { save(caretAnimation.rawValue, Key.caretAnimation) } }
    /// Default: Comfortable (the previous fixed width).
    var typingWidth: TypingWidth { didSet { save(typingWidth.rawValue, Key.typingWidth) } }

    // MARK: Typing

    /// Default: on. Visual Shift and Caps Lock hints in Typing Mechanics.
    /// Technique is still checked when they are off.
    var modifierGuidance: Bool { didSet { save(modifierGuidance, Key.modifierGuidance) } }

    // MARK: Training

    /// Default: on. Typing Mechanics suggestions and finger suggestions after tests.
    var adaptiveRecommendations: Bool { didSet { save(adaptiveRecommendations, Key.adaptiveRecommendations) } }
    /// Default: Balanced. Orders Typing Mechanics suggestions.
    var trainingPriority: TrainingPriority { didSet { save(trainingPriority.rawValue, Key.trainingPriority) } }

    // MARK: Feedback

    /// Default: Off.
    var soundFeedback: SoundFeedback { didSet { save(soundFeedback.rawValue, Key.soundFeedback) } }
    /// Default: Standard.
    var errorEmphasis: ErrorEmphasis { didSet { save(errorEmphasis.rawValue, Key.errorEmphasis) } }
    /// Default: on. Off removes decorative transitions; Reduce Motion always wins.
    var decorativeAnimations: Bool { didSet { save(decorativeAnimations, Key.decorativeAnimations) } }

    /// The keyboard layout exercises are written for. Only US QWERTY exists
    /// today; stored so more layouts can be added without a migration.
    var keyboardLayout: TypingLayout { didSet { save(keyboardLayout.rawValue, Key.keyboardLayout) } }

    // MARK: Welcome Journey

    /// Nil until Keyflow has decided at a launch (see `OnboardingStatus`).
    /// Not a setting: Reset Settings leaves it alone, so it never brings the
    /// journey back uninvited.
    var onboardingStatus: OnboardingStatus? { didSet { save(onboardingStatus?.rawValue, Key.onboardingStatus) } }

    static let fontSizes: ClosedRange<Double> = 18...36

    enum Key {
        static let startupSection = "settings.general.startupSection"
        static let restoresLastSection = "settings.general.restoresLastSection"
        static let lastSection = "settings.general.lastSection"
        static let theme = "settings.appearance.theme"
        static let navigation = "settings.appearance.navigation"
        /// Not in `all`: it is not a setting. The key the sidebar always used.
        static let sidebarHidden = "sidebar.hidden"
        static let typingFont = "settings.appearance.typingFont"
        static let typingFontSize = "settings.appearance.typingFontSize"
        static let caretStyle = "settings.appearance.caretStyle"
        static let caretAnimation = "settings.appearance.caretAnimation"
        static let typingWidth = "settings.appearance.typingWidth"
        static let modifierGuidance = "settings.typing.modifierGuidance"
        static let keyboardLayout = "settings.typing.keyboardLayout"
        static let adaptiveRecommendations = "settings.training.adaptiveRecommendations"
        static let trainingPriority = "settings.training.priority"
        static let soundFeedback = "settings.feedback.sound"
        static let errorEmphasis = "settings.feedback.errorEmphasis"
        static let decorativeAnimations = "settings.feedback.decorativeAnimations"
        /// Not in `all`: it is not a setting.
        static let onboardingStatus = "onboarding.status"

        /// Everything "Reset Settings" clears from this class.
        static let all = [startupSection, restoresLastSection, theme, navigation, typingFont, typingFontSize, caretStyle,
                          caretAnimation, typingWidth, modifierGuidance, keyboardLayout, adaptiveRecommendations,
                          trainingPriority, soundFeedback, errorEmphasis, decorativeAnimations]
    }

    @ObservationIgnored private let defaults: UserDefaults?

    /// The app's preferences. Tests make their own with a scratch suite or `nil`.
    static let shared = Preferences(defaults: .standard)

    init(defaults: UserDefaults?) {
        self.defaults = defaults
        func value<T: RawRepresentable>(_ key: String, _ fallback: T) -> T where T.RawValue == String {
            defaults?.string(forKey: key).flatMap(T.init(rawValue:)) ?? fallback
        }
        func bool(_ key: String, _ fallback: Bool) -> Bool { defaults?.object(forKey: key) as? Bool ?? fallback }

        startupSection = value(Key.startupSection, AppSection.practice)
        restoresLastSection = bool(Key.restoresLastSection, false)
        lastSection = value(Key.lastSection, AppSection.practice)
        theme = value(Key.theme, Theme.system)
        navigation = value(Key.navigation, NavigationStyle.topBar)
        sidebarHidden = bool(Key.sidebarHidden, false)
        typingFont = value(Key.typingFont, TypingFontChoice.sfMono)
        let size = defaults?.object(forKey: Key.typingFontSize) as? Double ?? 24
        typingFontSize = min(Self.fontSizes.upperBound, max(Self.fontSizes.lowerBound, size))
        caretStyle = value(Key.caretStyle, CaretStyle.line)
        caretAnimation = value(Key.caretAnimation, CaretAnimation.smooth)
        typingWidth = value(Key.typingWidth, TypingWidth.comfortable)
        modifierGuidance = bool(Key.modifierGuidance, true)
        keyboardLayout = value(Key.keyboardLayout, TypingLayout.usQWERTY)
        adaptiveRecommendations = bool(Key.adaptiveRecommendations, true)
        trainingPriority = value(Key.trainingPriority, TrainingPriority.balanced)
        soundFeedback = value(Key.soundFeedback, SoundFeedback.off)
        errorEmphasis = value(Key.errorEmphasis, ErrorEmphasis.standard)
        decorativeAnimations = bool(Key.decorativeAnimations, true)
        onboardingStatus = defaults?.string(forKey: Key.onboardingStatus).flatMap(OnboardingStatus.init(rawValue:))
    }

    /// The section to open at launch: the last one when restoring, else the chosen one.
    var launchSection: AppSection { restoresLastSection ? lastSection : startupSection }

    /// Back to every default above. Training data is never touched.
    func resetToDefaults() {
        for key in Key.all { defaults?.removeObject(forKey: key) }
        let fresh = Preferences(defaults: nil)
        startupSection = fresh.startupSection
        restoresLastSection = fresh.restoresLastSection
        theme = fresh.theme
        navigation = fresh.navigation
        typingFont = fresh.typingFont
        typingFontSize = fresh.typingFontSize
        caretStyle = fresh.caretStyle
        caretAnimation = fresh.caretAnimation
        typingWidth = fresh.typingWidth
        modifierGuidance = fresh.modifierGuidance
        keyboardLayout = fresh.keyboardLayout
        adaptiveRecommendations = fresh.adaptiveRecommendations
        trainingPriority = fresh.trainingPriority
        soundFeedback = fresh.soundFeedback
        errorEmphasis = fresh.errorEmphasis
        decorativeAnimations = fresh.decorativeAnimations
        // The didSets above re-saved the defaults; remove them again so nothing is pinned.
        for key in Key.all { defaults?.removeObject(forKey: key) }
    }

    /// Applies the theme to every window, including Settings.
    func applyTheme() {
        guard let app = NSApp else { return }
        app.appearance = theme.appearance
    }

    /// The typing presentation these preferences describe.
    var typingStyle: TypingStyle {
        TypingStyle(font: typingFont, size: typingFontSize, caret: caretStyle, caretAnimation: caretAnimation,
                    errorEmphasis: errorEmphasis)
    }

    private func save(_ value: Any?, _ key: String) { defaults?.set(value, forKey: key) }
}

// MARK: - Choices

enum Theme: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: Self { self }
    var title: String { rawValue.capitalized }
    var appearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// How you move between the five sections.
enum NavigationStyle: String, CaseIterable, Identifiable {
    /// A glass bar across the top that steps aside while you type.
    case topBar
    /// A list down the left side that stays put.
    case sidebar
    var id: Self { self }
    var title: String { self == .topBar ? "Top Bar" : "Sidebar" }
    var symbol: String { self == .topBar ? "rectangle.topthird.inset.filled" : "sidebar.left" }
    var other: NavigationStyle { self == .topBar ? .sidebar : .topBar }
    /// Words for the tour: "in the top bar", "in the sidebar".
    var place: String { self == .topBar ? "in the top bar" : "in the sidebar" }
}

enum TypingFontChoice: String, CaseIterable, Identifiable {
    case sfMono, menlo
    var id: Self { self }
    var title: String { self == .sfMono ? "SF Mono" : "Menlo" }

    /// Both ship with macOS. Menlo falls back to SF Mono if ever missing.
    func nsFont(size: CGFloat) -> NSFont {
        switch self {
        case .sfMono: .monospacedSystemFont(ofSize: size, weight: .regular)
        case .menlo: NSFont(name: "Menlo-Regular", size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular)
        }
    }
}

enum CaretStyle: String, CaseIterable, Identifiable {
    case line, block, underline
    var id: Self { self }
    var title: String { rawValue.capitalized }
}

enum CaretAnimation: String, CaseIterable, Identifiable {
    case smooth, instant
    var id: Self { self }
    var title: String { rawValue.capitalized }
}

enum TypingWidth: String, CaseIterable, Identifiable {
    case compact, comfortable, wide
    var id: Self { self }
    var title: String { rawValue.capitalized }
    /// The widest the typing column gets.
    var points: CGFloat {
        switch self {
        case .compact: 680
        case .comfortable: 860
        case .wide: 1080
        }
    }
}

enum TypingLayout: String, CaseIterable, Identifiable {
    case usQWERTY
    var id: Self { self }
    var title: String { "US QWERTY" }
}

enum TrainingPriority: String, CaseIterable, Identifiable {
    case balanced, accuracyFirst, speedFirst
    var id: Self { self }
    var title: String {
        switch self {
        case .balanced: "Balanced"
        case .accuracyFirst: "Accuracy First"
        case .speedFirst: "Speed First"
        }
    }
    var core: MechanicsRecommender.Priority {
        switch self {
        case .balanced: .balanced
        case .accuracyFirst: .accuracy
        case .speedFirst: .speed
        }
    }
}

enum SoundFeedback: String, CaseIterable, Identifiable {
    case off, mistakes
    var id: Self { self }
    var title: String { self == .off ? "Off" : "On mistakes" }
}

enum ErrorEmphasis: String, CaseIterable, Identifiable {
    case standard, strong
    var id: Self { self }
    var title: String { self == .standard ? "Standard" : "Strong" }
}

// MARK: - Typing style

/// How the typing passage is drawn. Every glyph of a monospaced font has the
/// same advance, so line breaks and the caret position stay plain arithmetic.
struct TypingStyle: Equatable {
    var font: TypingFontChoice = .sfMono
    var size: Double = 24
    var caret: CaretStyle = .line
    var caretAnimation: CaretAnimation = .smooth
    var errorEmphasis: ErrorEmphasis = .standard

    var nsFont: NSFont { font.nsFont(size: size) }
    var swiftUIFont: Font { Font(nsFont as CTFont) }
    /// 44 pt at the original 24 pt: the same proportions at every size.
    var lineHeight: CGFloat { (size * 44 / 24).rounded() }
    var caretHeight: CGFloat { (size * 29 / 24).rounded() }
    var characterWidth: CGFloat { ("0" as NSString).size(withAttributes: [.font: nsFont]).width }

    static let standard = TypingStyle()
}

private struct TypingStyleKey: EnvironmentKey {
    static let defaultValue = TypingStyle.standard
}

private struct TypingWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = DS.Layout.readingWidth
}

private struct DecorativeAnimationsKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var typingStyle: TypingStyle {
        get { self[TypingStyleKey.self] }
        set { self[TypingStyleKey.self] = newValue }
    }

    /// The widest the typing column gets.
    var typingWidth: CGFloat {
        get { self[TypingWidthKey.self] }
        set { self[TypingWidthKey.self] = newValue }
    }

    /// Off when the user turned decorative animations off.
    var decorativeAnimations: Bool {
        get { self[DecorativeAnimationsKey.self] }
        set { self[DecorativeAnimationsKey.self] = newValue }
    }
}

extension View {
    /// Passes the appearance preferences down to every view.
    func applying(_ preferences: Preferences) -> some View {
        environment(\.typingStyle, preferences.typingStyle)
            .environment(\.typingWidth, preferences.typingWidth.points)
            .environment(\.decorativeAnimations, preferences.decorativeAnimations)
    }
}
