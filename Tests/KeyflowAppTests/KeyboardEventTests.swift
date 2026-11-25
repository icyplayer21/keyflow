import AppKit
import Carbon.HIToolbox
import Testing
@testable import Keyflow
import KeyflowCore

/// Real `NSEvent` objects built by AppKit, read the way the keyboard monitor reads them.
@MainActor
@Suite struct KeyboardEventTests {
    private func keyDown(_ characters: String, flags: UInt, keyCode: UInt16 = 0, repeat isRepeat: Bool = false) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: NSEvent.ModifierFlags(rawValue: flags),
                                      timestamp: 12.5, windowNumber: 0, context: nil, characters: characters,
                                      charactersIgnoringModifiers: characters.lowercased(), isARepeat: isRepeat,
                                      keyCode: keyCode))
    }

    private func flagsChanged(keyCode: UInt16, flags: UInt, at time: TimeInterval) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: NSEvent.ModifierFlags(rawValue: flags),
                                      timestamp: time, windowNumber: 0, context: nil, characters: "",
                                      charactersIgnoringModifiers: "", isARepeat: false, keyCode: keyCode))
    }

    @Test func keyDownCarriesShiftSideCapsLockAndRepeat() throws {
        let leftShiftA = KeyPress(try keyDown("A", flags: ModifierSnapshot.shiftMask | ModifierSnapshot.leftShiftMask))
        #expect(leftShiftA.modifiers == ModifierSnapshot(leftShift: true))
        #expect(leftShiftA.timestamp == 12.5)
        #expect(leftShiftA.printableCharacter == "A")
        #expect(!leftShiftA.hasCommandOrControl)

        let capsN = KeyPress(try keyDown("N", flags: ModifierSnapshot.capsLockMask, repeat: true))
        #expect(capsN.modifiers == ModifierSnapshot(capsLock: true))
        #expect(capsN.isRepeat)

        // Existing typing is unaffected: Command still marks the key as a shortcut.
        let command = KeyPress(try keyDown("r", flags: NSEvent.ModifierFlags.command.rawValue))
        #expect(command.hasCommandOrControl)
    }

    @Test func appKitFlagMasksMatchTheCoreDecoding() {
        #expect(NSEvent.ModifierFlags.shift.rawValue == ModifierSnapshot.shiftMask)
        #expect(NSEvent.ModifierFlags.capsLock.rawValue == ModifierSnapshot.capsLockMask)
        #expect(UInt16(kVK_Shift) == ModifierEvent.leftShiftKeyCode)
        #expect(UInt16(kVK_RightShift) == ModifierEvent.rightShiftKeyCode)
        #expect(UInt16(kVK_CapsLock) == ModifierEvent.capsLockKeyCode)
    }

    @Test func flagsChangedEventsBecomeModifierEvents() throws {
        let down = try flagsChanged(keyCode: 60, flags: ModifierSnapshot.shiftMask | ModifierSnapshot.rightShiftMask, at: 3)
        #expect(ModifierEvent.from(flagsChangedKeyCode: down.keyCode, rawFlags: down.modifierFlags.rawValue, at: down.timestamp)
                == .shiftDown(.right, at: 3))
        let caps = try flagsChanged(keyCode: 57, flags: ModifierSnapshot.capsLockMask, at: 4)
        #expect(ModifierEvent.from(flagsChangedKeyCode: caps.keyCode, rawFlags: caps.modifierFlags.rawValue, at: caps.timestamp)
                == .capsLock(on: true, at: 4))
    }

    @Test func eventsFlowThroughTheTrackerInOrder() throws {
        var tracker = ModifierTracker()
        let shiftDown = try flagsChanged(keyCode: 56, flags: ModifierSnapshot.shiftMask | ModifierSnapshot.leftShiftMask, at: 12.4)
        tracker.apply(ModifierEvent.from(flagsChangedKeyCode: shiftDown.keyCode, rawFlags: shiftDown.modifierFlags.rawValue,
                                         at: shiftDown.timestamp)!)
        let press = KeyPress(try keyDown("P", flags: ModifierSnapshot.shiftMask | ModifierSnapshot.leftShiftMask))
        let stroke = tracker.keystroke(press.printableCharacter!, keyCode: press.keyCode, at: press.timestamp,
                                       isRepeat: press.isRepeat, modifiers: press.modifiers)
        #expect(stroke.technique == .leftShift)
        #expect(abs((stroke.shiftLead ?? 0) - 0.1) < 1e-9)
    }

    @Test func currentKeyboardLayoutIsReadable() {
        // Environment-dependent: some layout is always active.
        let layout = KeyboardLayoutInfo.current()
        #expect(layout != nil)
        #expect(!(layout?.identifier.isEmpty ?? true))
        #expect(KeyboardLayoutInfo(identifier: "com.apple.keylayout.ABC", name: "ABC").isUSCompatible)
        #expect(KeyboardLayoutInfo(identifier: "com.apple.keylayout.PinyinKeyboard", name: "Pinyin").isUSCompatible)
        #expect(!KeyboardLayoutInfo(identifier: "com.apple.keylayout.German", name: "German").isUSCompatible)
        #expect(!KeyboardLayoutInfo(identifier: "com.apple.keylayout.French", name: "French").isUSCompatible)
    }
}
