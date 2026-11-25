import KeyflowCore
import SwiftUI

/// Tells the two hands apart. Used sparingly: a thin line on keys and a dot
/// beside hand labels, never as a fill.
enum HandStyle {
    static func tint(for hand: Hand?) -> Color {
        switch hand {
        case .left: .teal
        case .right: .indigo
        case nil: .gray
        }
    }
}

/// A QWERTY keyboard (letter rows and space bar) drawn as quiet outlines.
///
/// - Keys the exercise uses are a shade firmer, with a thin hand-coloured
///   line along the bottom.
/// - The next key gets an accent outline and a faint accent wash.
/// - A mistake briefly outlines the key you missed and the key you pressed
///   in red.
/// - F and J carry the home-row bumps.
struct TrainingKeyboardView: View {
    let exerciseKeys: Set<Character>
    let nextKey: Character?
    let miss: MuscleMemoryModel.KeyMiss?
    var keySize: CGFloat = 38
    /// Keys of the finger being trained (Finger Focus): a little firmer
    /// than other exercise keys, with a thicker hand line.
    var targetKeys: Set<Character> = []
    /// Shows Caps Lock and both Shift keys, for Typing Mechanics.
    var modifiers: ModifierGuide?
    /// Shows the number row, and each key's shifted symbol, for Numbers & Symbols.
    var showsNumberRow = false

    /// What the modifier keys show.
    struct ModifierGuide: Equatable {
        /// Caps Lock is on (its light is lit).
        var capsLockOn = false
        /// Shift keys currently held.
        var heldShift: ShiftSide?
        /// The Shift recommended for the next key.
        var recommendedShift: ShiftSide?
        /// Caps Lock should be switched before the next key.
        var capsLockNeedsToggle = false
    }

    @State private var flashingMissID: Int?
    private let gap: CGFloat = 5

    var body: some View {
        let rows = showsNumberRow ? Array(KeyboardLayout.rows.indices) : Array(KeyboardLayout.rows.indices.dropFirst())

        VStack(alignment: .leading, spacing: gap) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: gap) {
                    if let modifiers, row == 2 {
                        modifierKey("caps lock", units: KeyboardLayout.rowOffsets[2], active: modifiers.capsLockOn,
                                    suggested: modifiers.capsLockNeedsToggle, light: modifiers.capsLockOn)
                    }
                    if let modifiers, row == 3 {
                        modifierKey("shift", units: KeyboardLayout.rowOffsets[3],
                                    active: modifiers.heldShift == .left || modifiers.heldShift == .both,
                                    suggested: modifiers.recommendedShift == .left)
                    }
                    ForEach(KeyboardLayout.rows[row], id: \.base) { key in
                        keyView(key)
                    }
                    if let modifiers, row == 3 {
                        modifierKey("shift", units: Self.rightShiftUnits,
                                    active: modifiers.heldShift == .right || modifiers.heldShift == .both,
                                    suggested: modifiers.recommendedShift == .right)
                    }
                }
                .padding(.leading, leadingUnits(row) * (keySize + gap))
            }
        }
        .onChange(of: miss?.id) { _, id in
            guard let id else { return }
            flashingMissID = id
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(450))
                if flashingMissID == id {
                    withMotion(.easeOut(duration: 0.3)) { flashingMissID = nil }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        guard let nextKey, let finger = FingerMap.finger(for: nextKey) else { return "Keyboard" }
        var text = "Next key \(Self.name(of: nextKey)), \(finger.title)"
        if let modifiers {
            if let side = modifiers.recommendedShift { text += ", with the \(side == .left ? "left" : "right") Shift" }
            if modifiers.capsLockNeedsToggle { text += modifiers.capsLockOn ? ", switch Caps Lock off" : ", switch Caps Lock on" }
            if modifiers.capsLockOn { text += ". Caps Lock is on" }
        }
        return text
    }

    /// The right Shift reaches the right edge of the top letter row.
    private static let rightShiftUnits: Double = {
        let top = KeyboardLayout.rowOffsets[1] + Double(KeyboardLayout.rows[1].count)
        let bottom = KeyboardLayout.rowOffsets[3] + Double(KeyboardLayout.rows[3].count)
        return top - bottom
    }()

    /// Indent of a row in key widths. With modifier keys, rows keep their
    /// true offsets so Caps Lock and Shift fill the space on the left.
    private func leadingUnits(_ row: Int) -> Double {
        guard modifiers != nil else {
            return KeyboardLayout.rowOffsets[row] - (showsNumberRow ? 0 : KeyboardLayout.rowOffsets[1])
        }
        switch row {
        case 2, 3: return 0
        default: return KeyboardLayout.rowOffsets[row]
        }
    }

    private func modifierKey(_ title: String, units: Double, active: Bool, suggested: Bool, light: Bool? = nil) -> some View {
        let stroke: Color = suggested ? .accentColor : (active ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.12))
        return ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: DS.Radius.key)
                .fill(active ? Color.accentColor.opacity(0.16) : (suggested ? Color.accentColor.opacity(0.06) : Color.primary.opacity(0.03)))
            RoundedRectangle(cornerRadius: DS.Radius.key)
                .strokeBorder(stroke, lineWidth: suggested || active ? 1.5 : 1)
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(active || suggested ? Color.accentColor : Color.secondary)
                .padding(.leading, 7)
                .padding(.bottom, 6)
            if let light {
                // The key's light, as on Apple keyboards.
                Circle()
                    .fill(light ? DS.Palette.success : Color.primary.opacity(0.15))
                    .frame(width: 5, height: 5)
                    .padding(.leading, 7)
                    .padding(.bottom, keySize - 12)
            }
        }
        .frame(width: units * (keySize + gap) - gap, height: keySize)
        .motion(DS.Motion.quick, value: active)
        .motion(DS.Motion.quick, value: suggested)
    }

    static func name(of key: Character) -> String {
        key == " " ? "space" : String(key).uppercased()
    }

    private func keyView(_ key: KeyboardKey) -> some View {
        let base = key.base
        let isNext = nextKey.flatMap(KeyboardLayout.baseKey(for:)) == base
        let isTarget = targetKeys.contains(base)
        let inExercise = exerciseKeys.contains(base) || isNext || isTarget
        let flashing = flashingMissID != nil && flashingMissID == miss?.id
        let isMissed = flashing && miss.flatMap { KeyboardLayout.baseKey(for: $0.expected) } == base
        let isWrong = flashing && !isMissed && miss.flatMap { KeyboardLayout.baseKey(for: $0.typed) } == base
        let hand = FingerMap.hand(for: base)

        let fill: Color = if isMissed {
            DS.Palette.error.opacity(0.14)
        } else if isNext {
            Color.accentColor.opacity(0.14)
        } else if isTarget {
            Color.primary.opacity(0.1)
        } else if inExercise {
            Color.primary.opacity(0.06)
        } else {
            Color.primary.opacity(0.02)
        }
        let stroke: Color = if isMissed || isWrong {
            DS.Palette.error
        } else if isNext {
            Color.accentColor
        } else {
            Color.primary.opacity(isTarget ? 0.28 : (inExercise ? 0.16 : 0.07))
        }
        let label: Color = if isMissed {
            DS.Palette.error
        } else if isNext {
            Color.accentColor
        } else if inExercise {
            Color.primary
        } else {
            Color.secondary.opacity(0.5)
        }

        return ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: DS.Radius.key).fill(fill)
            RoundedRectangle(cornerRadius: DS.Radius.key)
                .strokeBorder(stroke, lineWidth: isNext || isMissed || isWrong ? 1.5 : 1)
            if showsNumberRow, let shifted = key.shifted {
                // The shifted symbol, above the key's own character, as printed on the keycap.
                Text(String(shifted))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(nextKey == shifted ? Color.accentColor : label.opacity(0.75))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 3)
            }
            Text(base == " " ? "space" : String(base).uppercased())
                .font(.system(size: base == " " ? 11 : 13, weight: .medium, design: .monospaced))
                .foregroundStyle(label)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Make room for the shifted symbol above it.
                .offset(y: showsNumberRow && key.shifted != nil ? keySize * 0.14 : 0)
            if base == "f" || base == "j" {
                // The raised bumps that help find the home row by touch.
                Capsule()
                    .fill(label.opacity(0.7))
                    .frame(width: 8, height: 1.5)
                    .padding(.bottom, 9)
            }
            if inExercise, base != " " {
                Capsule()
                    .fill(HandStyle.tint(for: hand).opacity(isTarget ? 0.95 : 0.7))
                    .frame(width: keySize - 18, height: isTarget ? 3 : 2)
                    .padding(.bottom, 3)
            }
        }
        .frame(width: base == " " ? KeyboardLayout.spaceBarWidth * (keySize + gap) - gap : keySize, height: keySize)
        .motion(DS.Motion.quick, value: isNext)
        .motion(DS.Motion.quick, value: isMissed)
    }
}

/// The recommended finger for the next key. A recommendation only: Keyflow
/// cannot see which finger is used.
struct FingerGuideView: View {
    let nextKey: Character?
    /// Leaves out the hand labels; the dot colours still tell the hands apart.
    var compact = false

    var body: some View {
        let finger = nextKey.flatMap(FingerMap.finger(for:))

        VStack(spacing: DS.Space.xs) {
            HStack(alignment: .bottom, spacing: DS.Space.l) {
                hand(.left, fingers: [.leftPinky, .leftRing, .leftMiddle, .leftIndex], active: finger)
                hand(nil, fingers: [.thumb], active: finger)
                hand(.right, fingers: [.rightIndex, .rightMiddle, .rightRing, .rightPinky], active: finger)
            }
            Text(caption(finger))
                .font(DS.Typography.body)
                .foregroundStyle(.secondary)
                .frame(height: 16)
                .contentTransition(.opacity)
                .motion(DS.Motion.quick, value: nextKey)
        }
    }

    private func caption(_ finger: Finger?) -> String {
        guard let nextKey, let finger else { return " " }
        let key = TrainingKeyboardView.name(of: nextKey)
        return finger == .thumb ? "\(key) — either thumb" : "\(key) — \(finger.title)"
    }

    private func hand(_ hand: Hand?, fingers: [Finger], active: Finger?) -> some View {
        VStack(spacing: 5) {
            if !compact {
                HStack(spacing: 5) {
                    if hand != nil {
                        Circle().fill(HandStyle.tint(for: hand).opacity(0.8)).frame(width: 5, height: 5)
                    }
                    Eyebrow(hand?.title ?? "Thumbs")
                }
            }
            HStack(spacing: 3) {
                if compact, hand != nil {
                    Circle().fill(HandStyle.tint(for: hand).opacity(0.8)).frame(width: 5, height: 5)
                }
                ForEach(fingers, id: \.self) { finger in
                    let isActive = finger == active
                    Text(finger.name)
                        .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                        .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(Capsule().fill(isActive ? Color.accentColor.opacity(0.12) : Color.clear))
                        .overlay(Capsule().strokeBorder(isActive ? Color.accentColor.opacity(0.5) : DS.Palette.hairline))
                        .motion(DS.Motion.quick, value: isActive)
                }
            }
        }
    }
}
