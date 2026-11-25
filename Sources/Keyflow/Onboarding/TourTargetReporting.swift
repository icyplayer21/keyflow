import AppKit
import SwiftUI

extension View {
    /// Marks a real control the Welcome Journey can point at. Its frame in
    /// window coordinates is kept up to date while the journey is showing,
    /// and removed when the control leaves the screen, so the tour never
    /// points at where something used to be. `when` is false for a copy
    /// that is not in use, such as the sidebar while the top bar is showing.
    func tourTarget(_ target: TourTarget, in journey: WelcomeJourney, when isInUse: Bool = true) -> some View {
        background {
            if journey.isActive && isInUse {
                WindowFrameReader { frame in
                    if journey.targetFrames[target] != frame { journey.targetFrames[target] = frame }
                }
            }
        }
    }
}

/// Reports its own frame in window coordinates (AppKit: origin bottom-left),
/// or nil once it leaves the window.
///
/// AppKit coordinates are used rather than SwiftUI's because a control can
/// live in its own hosting view, where SwiftUI's coordinate spaces do not
/// reach the rest of the window. Converting each
/// view to the window gives one coordinate system for every target and for
/// the overlay.
struct WindowFrameReader: NSViewRepresentable {
    let report: @MainActor (CGRect?) -> Void

    func makeNSView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.report = report
        return view
    }

    func updateNSView(_ view: ReaderView, context: Context) {
        view.report = report
        view.measureSoon()
    }

    static func dismantleNSView(_ view: ReaderView, coordinator: ()) {
        view.stopObserving()
        view.report(nil)
    }

    final class ReaderView: NSView {
        var report: @MainActor (CGRect?) -> Void = { _ in }
        private var last: CGRect?
        private var observers: [NSObjectProtocol] = []
        private var pending = false

        /// Never takes clicks: it sits behind real controls.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopObserving()
            guard let window else { send(nil); return }
            // A resize can move a target without changing its frame inside its
            // own hosting view, so measure again
            // whenever the window resizes or anything asks for it.
            let center = NotificationCenter.default
            observers = [
                center.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.measureSoon() }
                },
                center.addObserver(forName: Self.measureAll, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.measureSoon() }
                },
            ]
            measureSoon()
        }

        override func setFrameOrigin(_ newOrigin: NSPoint) { super.setFrameOrigin(newOrigin); measureSoon() }
        override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); measureSoon() }
        override func layout() { super.layout(); measureSoon() }

        func stopObserving() {
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
        }

        /// After the current layout pass, never during it: reporting changes
        /// observed state, which must not happen while SwiftUI is updating.
        func measureSoon() {
            guard !pending else { return }
            pending = true
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.pending = false
                    self.send(self.window == nil || self.isHiddenOrHasHiddenAncestor ? nil : self.convert(self.bounds, to: nil))
                }
            }
        }

        private func send(_ frame: CGRect?) {
            guard frame != last else { return }
            last = frame
            report(frame)
        }

        /// Posted to make every reader measure again (after a step changes).
        static let measureAll = Notification.Name("keyflow.tour.measureAll")
    }
}
