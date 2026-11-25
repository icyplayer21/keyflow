import Foundation
import Testing
@testable import KeyflowCore

@Suite struct ModifierDecodingTests {
    @Test func rawFlagsDecodeSidesShiftAndCapsLock() {
        let left = ModifierSnapshot(rawFlags: ModifierSnapshot.shiftMask | ModifierSnapshot.leftShiftMask)
        #expect(left.leftShift && !left.rightShift && left.shift && !left.capsLock)
        #expect(left.shiftSide == .left)

        let right = ModifierSnapshot(rawFlags: ModifierSnapshot.shiftMask | ModifierSnapshot.rightShiftMask)
        #expect(right.shiftSide == .right)

        let both = ModifierSnapshot(rawFlags: ModifierSnapshot.shiftMask | 0x6)
        #expect(both.shiftSide == .both)

        let unsided = ModifierSnapshot(rawFlags: ModifierSnapshot.shiftMask)
        #expect(unsided.shift && unsided.shiftSide == nil)

        let caps = ModifierSnapshot(rawFlags: ModifierSnapshot.capsLockMask | 0x100)
        #expect(caps.capsLock && !caps.shift)
        #expect(ModifierSnapshot(rawFlags: 0x100) == ModifierSnapshot())
    }

    @Test func flagsChangedEventsMapToModifierChanges() {
        let down = ModifierSnapshot.shiftMask | ModifierSnapshot.leftShiftMask
        #expect(ModifierEvent.from(flagsChangedKeyCode: 56, rawFlags: down, at: 1) == .shiftDown(.left, at: 1))
        #expect(ModifierEvent.from(flagsChangedKeyCode: 56, rawFlags: 0x100, at: 2) == .shiftUp(.left, at: 2))
        // Right Shift released while left is still held: the right bit is gone.
        #expect(ModifierEvent.from(flagsChangedKeyCode: 60, rawFlags: down, at: 3) == .shiftUp(.right, at: 3))
        #expect(ModifierEvent.from(flagsChangedKeyCode: 57, rawFlags: ModifierSnapshot.capsLockMask, at: 4) == .capsLock(on: true, at: 4))
        #expect(ModifierEvent.from(flagsChangedKeyCode: 57, rawFlags: 0, at: 5) == .capsLock(on: false, at: 5))
        // Command, Option, Control are not tracked.
        #expect(ModifierEvent.from(flagsChangedKeyCode: 55, rawFlags: 1 << 20, at: 6) == nil)
    }

    @Test func requirementsFollowUSQwerty() {
        #expect(CaseRequirement.of("A") == .uppercaseLetter)
        #expect(CaseRequirement.of("a") == .plain)
        #expect(CaseRequirement.of("1") == .plain)
        #expect(CaseRequirement.of(";") == .plain)
        #expect(CaseRequirement.of(" ") == .plain)
        for symbol in "~!@#$%^&*()_+{}|:\"<>?" {
            #expect(CaseRequirement.of(symbol) == .shiftedSymbol, "\(symbol)")
        }
        #expect(CaseRequirement.of("é") == .unsupported)
        #expect(CaseRequirement.of("…") == .unsupported)
    }
}

@Suite struct ModifierTrackerTests {
    private let left = ModifierSnapshot(leftShift: true)
    private let right = ModifierSnapshot(rightShift: true)
    private let caps = ModifierSnapshot(capsLock: true)
    private let none = ModifierSnapshot()

    @Test func shiftCapitalsRecordSideAndActivationTime() {
        var tracker = ModifierTracker()
        tracker.apply(.shiftDown(.right, at: 1.00))
        let a = tracker.keystroke("A", at: 1.14, modifiers: right)
        tracker.apply(.shiftUp(.right, at: 1.20))
        tracker.apply(.shiftDown(.left, at: 2.00))
        let p = tracker.keystroke("P", at: 2.09, modifiers: left)

        #expect(a.technique == .rightShift && p.technique == .leftShift)
        #expect(a.requirement == .uppercaseLetter)
        #expect(abs((a.shiftLead ?? 0) - 0.14) < 1e-9)
        #expect(abs((p.shiftLead ?? 0) - 0.09) < 1e-9)
        #expect(!a.reconciled && !p.reconciled)
    }

    @Test func capsLockSegmentsRecordWhenItWasSwitchedOn() {
        var tracker = ModifierTracker()
        tracker.apply(.sync(none, at: 0))
        tracker.keystroke("h", at: 0.5, modifiers: none)
        tracker.apply(.capsLock(on: true, at: 1.0))
        let strokes = "NASA".enumerated().map { index, c in
            tracker.keystroke(c, at: 1.2 + Double(index) * 0.1, modifiers: caps)
        }
        tracker.apply(.capsLock(on: false, at: 1.8))
        let after = tracker.keystroke("i", at: 2.0, modifiers: none)

        #expect(strokes.allSatisfy { $0.technique == .capsLock && $0.capsLockOnAt == 1.0 && $0.shiftLead == nil })
        #expect(after.technique == .unmodified)
        #expect(tracker.capsLock == false)
        #expect(tracker.capsLockChangedAt == 1.8)
        #expect(tracker.modifierEvents.count == 3)
    }

    @Test func capsLockAndShiftTogetherAreTheirOwnTechnique() {
        var tracker = ModifierTracker()
        let stroke = tracker.keystroke("A", at: 1, modifiers: ModifierSnapshot(leftShift: true, capsLock: true))
        #expect(stroke.technique == .capsLockWithShift)
        #expect(stroke.technique.usesShift && stroke.technique.usesCapsLock)
    }

    @Test func techniqueIsNeverInferredFromTheCharacterAlone() {
        var tracker = ModifierTracker()
        // An upper-case letter with no modifier observed: an input method or remap produced it.
        #expect(tracker.keystroke("A", at: 1, modifiers: none).technique == .unknown)
        // A shifted symbol without Shift: the layout differs from US QWERTY.
        #expect(tracker.keystroke("@", at: 2, modifiers: none).technique == .unknown)
        // Lower case while upper case was active.
        #expect(tracker.keystroke("a", at: 3, modifiers: caps).technique == .unknown)
        #expect(tracker.keystroke("é", at: 4, modifiers: none).technique == .unknown)
        // Plain characters are unmodified.
        #expect(tracker.keystroke("7", at: 5, modifiers: none).technique == .unmodified)
    }

    @Test func shiftedSymbolsUseShiftAndIgnoreCapsLock() {
        var tracker = ModifierTracker()
        tracker.apply(.shiftDown(.left, at: 1))
        #expect(tracker.keystroke("!", at: 1.2, modifiers: left).technique == .leftShift)
        // Caps Lock does not make "1" into "!", so only Shift counts.
        #expect(tracker.keystroke("@", at: 2, modifiers: ModifierSnapshot(leftShift: true, capsLock: true)).technique == .leftShift)
    }

    @Test func aMissedShiftPressIsCorrectedButNotTimed() {
        var tracker = ModifierTracker()
        // Shift went down before typing began: no flagsChanged was seen.
        let stroke = tracker.keystroke("Q", at: 3, modifiers: right)
        #expect(stroke.technique == .rightShift)
        #expect(stroke.shiftLead == nil)
        #expect(stroke.reconciled)
        #expect(tracker.rightShift == ModifierTracker.Held(since: nil))
        // A missed release is corrected too.
        let next = tracker.keystroke("q", at: 4, modifiers: none)
        #expect(next.technique == .unmodified && next.reconciled)
        #expect(!tracker.isShiftHeld)
    }

    @Test func focusLossReleasesShiftAndForgetsCapsLock() {
        var tracker = ModifierTracker()
        tracker.apply(.sync(caps, at: 0))
        tracker.apply(.shiftDown(.left, at: 1))
        tracker.apply(.focusLost(at: 2))
        #expect(!tracker.isShiftHeld)
        #expect(tracker.capsLock == nil)
        // Back in focus: the sync says Caps Lock is on, but not when it was switched.
        tracker.apply(.sync(caps, at: 5))
        #expect(tracker.capsLock == true)
        #expect(tracker.capsLockChangedAt == nil)
        let stroke = tracker.keystroke("N", at: 5.5, modifiers: caps)
        #expect(stroke.technique == .capsLock)
        #expect(stroke.capsLockOnAt == nil, "the switch happened while Keyflow could not see it")
        #expect(!stroke.reconciled)
    }

    @Test func capsLockLeftOnIsDetectedFromTheKeyPress() {
        var tracker = ModifierTracker()
        tracker.apply(.sync(none, at: 0))
        let stroke = tracker.keystroke("H", at: 1, modifiers: caps)
        #expect(stroke.technique == .capsLock)
        #expect(stroke.reconciled, "Caps Lock changed without a flagsChanged event")
        #expect(tracker.capsLock == true)
    }

    @Test func keyRepeatKeepsTheTechniqueButIsNotTimed() {
        var tracker = ModifierTracker()
        tracker.apply(.shiftDown(.left, at: 1))
        let first = tracker.keystroke("L", at: 1.1, modifiers: left)
        let repeated = tracker.keystroke("L", at: 1.6, isRepeat: true, modifiers: left)
        #expect(first.shiftLead != nil)
        #expect(repeated.isRepeat && repeated.technique == .leftShift && repeated.shiftLead == nil)
    }

    @Test func rapidShiftTransitionsUseTheLatestPress() {
        var tracker = ModifierTracker()
        tracker.apply(.shiftDown(.left, at: 1.00))
        tracker.apply(.shiftUp(.left, at: 1.05))
        tracker.apply(.shiftDown(.left, at: 1.10))
        let stroke = tracker.keystroke("T", at: 1.15, modifiers: left)
        #expect(abs((stroke.shiftLead ?? 0) - 0.05) < 1e-9)

        // Both Shifts held: the technique is Shift, timed from the later press.
        tracker.apply(.shiftDown(.right, at: 1.30))
        let both = tracker.keystroke("H", at: 1.40, modifiers: ModifierSnapshot(leftShift: true, rightShift: true))
        #expect(both.technique == .shift)
        #expect(abs((both.shiftLead ?? 0) - 0.10) < 1e-9)
    }

    @Test func shiftWithoutASideIsStillShift() {
        var tracker = ModifierTracker()
        let stroke = tracker.keystroke("M", at: 1, modifiers: ModifierSnapshot(shift: true))
        #expect(stroke.technique == .shift)
        #expect(tracker.unsidedShift != nil)
        tracker.apply(.shiftUp(.left, at: 2))
        #expect(!tracker.isShiftHeld)
    }

    @Test func withoutKeyFlagsTheTrackedStateIsUsed() {
        var tracker = ModifierTracker()
        tracker.apply(.capsLock(on: true, at: 1))
        #expect(tracker.keystroke("B", at: 1.3, modifiers: nil).technique == .capsLock)
        tracker.apply(.capsLock(on: false, at: 2))
        tracker.apply(.shiftDown(.right, at: 3))
        let stroke = tracker.keystroke("C", at: 3.2, modifiers: nil)
        #expect(stroke.technique == .rightShift)
        #expect(abs((stroke.shiftLead ?? 0) - 0.2) < 1e-9)
    }

    @Test func outOfOrderTimestampsAreNotTimed() {
        var tracker = ModifierTracker()
        tracker.apply(.shiftDown(.left, at: 2.0))
        // A key press stamped before the Shift press (events reordered): technique kept, no negative lead.
        let stroke = tracker.keystroke("A", at: 1.9, modifiers: left)
        #expect(stroke.technique == .leftShift)
        #expect(stroke.shiftLead == nil)
    }
}
