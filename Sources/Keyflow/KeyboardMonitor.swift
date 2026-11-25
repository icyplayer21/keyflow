import AppKit
import KeyflowCore

/// The parts of a key-down event the typing surface cares about.
struct KeyPress: Sendable {
    static let `return`: UInt16 = 36
    static let tab: UInt16 = 48
    static let delete: UInt16 = 51
    static let escape: UInt16 = 53
    static let enter: UInt16 = 76

    let keyCode: UInt16
    let characters: String?
    let hasCommandOrControl: Bool
    let hasOption: Bool
    /// System uptime at the moment the key went down (monotonic).
    let timestamp: TimeInterval
    /// Shift (with side) and Caps Lock as macOS reported them with this key
    /// press. `nil` where unknown, such as in tests that do not set it.
    var modifiers: ModifierSnapshot? = nil
    /// An auto-repeat from a held key.
    var isRepeat = false

    /// The single typed character, if this key produces visible text
    /// (excludes control codes and the function-key range used by arrows etc.).
    /// Full-width and CJK punctuation from input methods such as Pinyin is
    /// mapped back to the character on the key ("；" → ";").
    var printableCharacter: Character? {
        guard let characters, characters.count == 1, let character = characters.first,
              character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first,
              scalar.value >= 0x20, scalar.value != 0x7F,
              !(0xF700...0xF8FF).contains(scalar.value)
        else { return nil }
        return TypedCharacter.normalize(character)
    }

    init(keyCode: UInt16, characters: String?, hasCommandOrControl: Bool, hasOption: Bool,
         timestamp: TimeInterval, modifiers: ModifierSnapshot? = nil, isRepeat: Bool = false) {
        self.keyCode = keyCode
        self.characters = characters
        self.hasCommandOrControl = hasCommandOrControl
        self.hasOption = hasOption
        self.timestamp = timestamp
        self.modifiers = modifiers
        self.isRepeat = isRepeat
    }

    /// Reads a key-down event.
    init(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        self.init(keyCode: event.keyCode,
                  characters: event.characters,
                  hasCommandOrControl: flags.contains(.command) || flags.contains(.control),
                  hasOption: flags.contains(.option),
                  timestamp: event.timestamp,
                  modifiers: ModifierSnapshot(rawFlags: event.modifierFlags.rawValue),
                  isRepeat: event.isARepeat)
    }
}

/// Captures key-downs for the typing surface without needing first-responder
/// focus, so typing works no matter what was clicked last. Keys are left alone
/// while a text field or editor is being edited.
///
/// Only events sent to Keyflow's own windows are seen (a local monitor): no
/// global monitoring, no Accessibility or Input Monitoring permission.
///
/// Screens that study technique (Typing Mechanics) also pass `onModifier`, and
/// then receive Shift and Caps Lock changes from `flagsChanged`, a sync of the
/// full state when listening starts and when the app becomes active again,
/// and `focusLost` when it resigns, since key-ups can go missing then.
///
/// Each monitor serves one window: the main window's typing screens never
/// see keys pressed in Settings, and the Settings preview sees only those.
@MainActor
final class KeyboardMonitor {
    /// `onboarding` is the Welcome Journey's typing exercise, in the main window.
    enum Scope { case main, settings, onboarding }

    /// The identifier the Settings window is given, to tell it apart.
    static let settingsWindowID = NSUserInterfaceItemIdentifier("keyflow.settings")

    /// True while the Welcome Journey is showing: the typing screens behind
    /// it see no keys, so nothing typed during the tour starts or changes a
    /// session. Their monitors stay installed and resume when it closes.
    static var journeyIsShowing = false
    /// A typing screen used a printable key. Lets the top bar step aside.
    static var onTypingKey: (@MainActor () -> Void)?

    private var token: Any?
    private var observers: [NSObjectProtocol] = []
    private let scope: Scope

    init(scope: Scope = .main) { self.scope = scope }

    /// Whether an event belongs to this monitor's window.
    nonisolated static func accepts(_ window: NSWindow?, scope: Scope) -> Bool {
        let (isSettings, journey) = MainActor.assumeIsolated { (window?.identifier == settingsWindowID, journeyIsShowing) }
        switch scope {
        case .settings: return isSettings
        case .main: return !isSettings && !journey
        case .onboarding: return !isSettings && journey
        }
    }

    func start(_ handler: @escaping @MainActor (KeyPress) -> Bool,
               onModifier: (@MainActor (ModifierEvent) -> Void)? = nil) {
        stop()
        let mask: NSEvent.EventTypeMask = onModifier == nil ? .keyDown : [.keyDown, .flagsChanged]
        let scope = scope
        token = NSEvent.addLocalMonitorForEvents(matching: mask) { event in
            guard Self.accepts(event.window, scope: scope) else { return event }
            if event.type == .flagsChanged {
                if let change = ModifierEvent.from(flagsChangedKeyCode: event.keyCode,
                                                   rawFlags: event.modifierFlags.rawValue, at: event.timestamp) {
                    MainActor.assumeIsolated { onModifier?(change) }
                }
                return event
            }
            let press = KeyPress(event)
            let consumed = MainActor.assumeIsolated {
                if NSApp.keyWindow?.firstResponder is NSTextView { return false }
                let used = handler(press)
                if used, scope == .main, press.printableCharacter != nil { Self.onTypingKey?() }
                return used
            }
            return consumed ? nil : event
        }

        guard let onModifier else { return }
        onModifier(Self.currentState())
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { onModifier(.focusLost(at: ProcessInfo.processInfo.systemUptime)) }
            },
            center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { onModifier(Self.currentState()) }
            },
        ]
    }

    func stop() {
        if let token { NSEvent.removeMonitor(token) }
        token = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
    }

    /// The modifier state right now, as macOS reports it to this app.
    static func currentState() -> ModifierEvent {
        .sync(ModifierSnapshot(rawFlags: NSEvent.modifierFlags.rawValue), at: ProcessInfo.processInfo.systemUptime)
    }
}
