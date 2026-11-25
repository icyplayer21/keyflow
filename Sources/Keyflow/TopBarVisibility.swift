import AppKit
import Observation

/// Decides when the top navigation steps aside. It fades once you type in a
/// running exercise and returns when you pause typing, move the mouse, click,
/// scroll, or the exercise stops. It only changes what is drawn: the layout
/// stays put, so the text never jumps.
///
/// With VoiceOver, Switch Control or Full Keyboard Access on it never fades,
/// so it can't disappear from under someone who isn't looking at it.
@MainActor
@Observable
final class TopBarVisibility {
    static let defaultIdleDelay: Duration = .seconds(2.5)
    /// A resting hand can nudge a trackpad, so tiny movements don't count.
    static let mouseThreshold: CGFloat = 6

    private(set) var isFaded = false

    @ObservationIgnored private let idleDelay: Duration
    @ObservationIgnored private let keepsVisible: @MainActor () -> Bool
    @ObservationIgnored private var revealTask: Task<Void, Never>?
    @ObservationIgnored private var mouseAnchor: CGPoint?
    @ObservationIgnored private var monitor: Any?

    init(idleDelay: Duration = TopBarVisibility.defaultIdleDelay,
         keepsVisible: @escaping @MainActor () -> Bool = TopBarVisibility.assistiveTechnologyIsOn) {
        self.idleDelay = idleDelay
        self.keepsVisible = keepsVisible
    }

    /// VoiceOver, Switch Control or Full Keyboard Access, read each time so
    /// turning one on mid-session takes effect at the next key.
    static func assistiveTechnologyIsOn() -> Bool {
        let workspace = NSWorkspace.shared
        return workspace.isVoiceOverEnabled || workspace.isSwitchControlEnabled
            || (NSApp?.isFullKeyboardAccessEnabled ?? false)
    }

    /// A printable key was used on a typing screen.
    func noteTyping(exerciseRunning: Bool) {
        guard exerciseRunning, !keepsVisible() else { reveal(); return }
        if !isFaded { isFaded = true }
        revealTask?.cancel()
        let delay = idleDelay
        revealTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.reveal()
        }
    }

    func noteMouse(at point: CGPoint) {
        guard let anchor = mouseAnchor else { mouseAnchor = point; return }
        guard hypot(point.x - anchor.x, point.y - anchor.y) >= Self.mouseThreshold else { return }
        mouseAnchor = point
        reveal()
    }

    func reveal() {
        revealTask?.cancel()
        revealTask = nil
        if isFaded { isFaded = false }
    }

    /// Watches the mouse in Keyflow's own windows only. Events pass through untouched.
    func startWatchingMouse() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .scrollWheel]) { [weak self] event in
            let isMove = event.type == .mouseMoved
            let point = event.locationInWindow
            MainActor.assumeIsolated {
                if isMove { self?.noteMouse(at: point) } else { self?.reveal() }
            }
            return event
        }
    }
}
