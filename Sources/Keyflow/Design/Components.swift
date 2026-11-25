import SwiftUI

// MARK: - Selection

/// How much weight a row of options carries, so stacked rows read as levels.
enum OptionBarStyle {
    /// The main navigation, and nothing else: a floating glass tray.
    case glass
    /// The second level: plain tabs with a sliding underline.
    case tabs
    /// Everything below: plain text with a soft highlight.
    case plain
}

/// A row of mutually exclusive text options. Quieter than a segmented
/// control: the selection is a soft fill, hover gets a lighter one.
struct OptionBar<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value
    var font: Font = DS.Typography.bodyEmphasis
    var style: OptionBarStyle = .plain
    /// Options the Welcome Journey can point at.
    var tour: (journey: WelcomeJourney, target: (Value) -> TourTarget?)? = nil
    /// An SF Symbol beside each title, for the main navigation.
    var symbol: ((Value) -> String)? = nil
    let title: (Value) -> String
    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let button = OptionButton(title: title(option), symbol: symbol?(option), isSelected: option == selection,
                                          font: font, style: style, highlight: highlight) {
                    selection = option
                }
                if let tour, let target = tour.target(option) {
                    button.tourTarget(target, in: tour.journey)
                } else {
                    button
                }
            }
        }
        .optionTray(style == .glass)
        .motion(DS.Motion.selection, value: selection)
    }
}

private struct OptionButton: View {
    let title: String
    let symbol: String?
    let isSelected: Bool
    let font: Font
    let style: OptionBarStyle
    let highlight: Namespace.ID
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Group {
                if let symbol {
                    Label(title, systemImage: symbol).labelStyle(.titleAndIcon)
                } else {
                    Text(title)
                }
            }
                .font(font)
                .foregroundStyle(isSelected || (style == .tabs && hovering) ? Color.primary : Color.secondary)
                .padding(.horizontal, DS.usesGlass ? 12 : 10)
                .padding(.vertical, style == .tabs ? 8 : 5)
                .background { if style != .tabs { fill } }
                .overlay(alignment: .bottom) {
                    if style == .tabs, isSelected {
                        Capsule()
                            .fill(Color.primary)
                            .frame(height: 2)
                            .padding(.horizontal, 10)
                            .matchedGeometryEffect(id: "selection", in: highlight)
                    }
                }
                .contentShape(AnyShape(shape))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .motion(DS.usesGlass ? DS.Motion.selection : DS.Motion.quick, value: isSelected)
        .motion(DS.Motion.quick, value: hovering)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var shape: some InsettableShape {
        RoundedRectangle(cornerRadius: DS.usesGlass ? 100 : DS.Radius.control)
    }

    @ViewBuilder private var fill: some View {
        if DS.usesGlass {
            ZStack {
                if hovering && !isSelected { shape.fill(DS.Palette.fill) }
                if isSelected {
                    shape.fill(DS.Palette.selected)
                        .matchedGeometryEffect(id: "selection", in: highlight)
                }
            }
        } else {
            shape.fill(isSelected ? DS.Palette.selected : (hovering ? DS.Palette.fill : Color.clear))
        }
    }
}

// MARK: - Buttons

/// Secondary actions: text in secondary colour that firms up on hover.
struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        QuietButton(configuration: configuration)
    }

    private struct QuietButton: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(DS.Typography.body)
                .foregroundStyle(isEnabled ? (hovering ? Color.primary : Color.secondary) : Color.secondary.opacity(0.45))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.control)
                        .fill(configuration.isPressed ? DS.Palette.selected : (hovering && isEnabled ? DS.Palette.hover : Color.clear))
                )
                .contentShape(RoundedRectangle(cornerRadius: DS.Radius.control))
                .onHover { hovering = $0 }
                .motion(DS.Motion.quick, value: hovering)
        }
    }
}

/// The one main action on a screen. Compact, accent-filled.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PrimaryButton(configuration: configuration)
    }

    private struct PrimaryButton: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.isOnGlass) private var isOnGlass
        @State private var hovering = false

        private var label: some View {
            configuration.label
                .font(DS.Typography.bodyEmphasis)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
        }

        var body: some View {
            Group {
                if #available(macOS 26, *), !isOnGlass {
                    label
                        .contentShape(Capsule())
                        .glassEffect(isEnabled ? .regular.tint(.accentColor).interactive() : .regular.tint(.accentColor),
                                     in: Capsule())
                } else {
                    // Flat on macOS 15. Inside a glass panel, solid, because glass must not stack.
                    let radius = DS.usesGlass ? 100 : DS.Radius.control
                    label
                        .background(
                            RoundedRectangle(cornerRadius: radius)
                                .fill(Color.accentColor)
                                .brightness(configuration.isPressed ? -0.08 : (hovering ? 0.04 : 0))
                        )
                        .contentShape(RoundedRectangle(cornerRadius: radius))
                }
            }
            .opacity(isEnabled ? 1 : 0.4)
            .onHover { hovering = $0 }
            .motion(DS.Motion.quick, value: hovering)
        }
    }
}

extension ButtonStyle where Self == QuietButtonStyle {
    static var quiet: QuietButtonStyle { QuietButtonStyle() }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var keyflowPrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

/// Starts the current exercise again.
struct RestartButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Restart", systemImage: "arrow.clockwise")
        }
        .buttonStyle(.quiet)
        .help("Restart (Tab)")
    }
}

// MARK: - Text and numbers

/// A small upper-case label.
struct Eyebrow: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(DS.Typography.eyebrow)
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }
}

/// A number with its label underneath.
struct Metric: View {
    let value: String
    let label: String
    var size: CGFloat = 20
    var weight: Font.Weight = .medium
    var tint: Color = .primary
    var help: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(DS.Typography.metric(size, weight: weight))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Eyebrow(label)
        }
        .help(help)
        .accessibilityElement(children: .combine)
    }
}

/// Metrics in a line, separated by hairlines.
struct MetricRow: View {
    let metrics: [Metric]

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(metrics.enumerated()), id: \.offset) { index, metric in
                if index > 0 {
                    Rectangle()
                        .fill(DS.Palette.hairline)
                        .frame(width: 1, height: 34)
                        .padding(.horizontal, DS.Space.l)
                }
                metric
            }
        }
    }
}

struct SectionHeader: View {
    let title: String
    var caption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(DS.Typography.sectionTitle)
            if let caption {
                Text(caption)
                    .font(DS.Typography.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// What a section says when it has nothing to show yet.
struct EmptyNote: View {
    let text: String
    init(_ text: String = "Not enough data yet.") { self.text = text }

    var body: some View {
        Text(text)
            .font(DS.Typography.body)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A 3-point progress line.
struct ThinProgressBar: View {
    let fraction: Double
    var tint: Color = .accentColor

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(DS.Palette.hairline)
                Capsule().fill(tint).frame(width: geometry.size.width * min(1, max(0, fraction)))
            }
        }
        .frame(height: 3)
        .motion(DS.Motion.quick, value: fraction)
        .accessibilityElement()
        .accessibilityValue("\(Int((fraction * 100).rounded())) percent")
    }
}

// MARK: - Shortcut hints

struct KeyCap: View {
    let key: String
    init(_ key: String) { self.key = key }

    var body: some View {
        Text(key)
            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(DS.Palette.hairline))
    }
}

struct ShortcutHints: View {
    var finished = false

    var body: some View {
        HStack(spacing: DS.Space.m) {
            if finished {
                hint("return", "next")
            } else {
                hint("tab", "restart")
                hint("⌥ delete", "delete word")
            }
        }
        .font(DS.Typography.caption)
        .foregroundStyle(.secondary)
    }

    private func hint(_ key: String, _ action: String) -> some View {
        HStack(spacing: 5) {
            KeyCap(key)
            Text(action)
        }
        .fixedSize()
    }
}

// MARK: - Stepping back while typing

extension View {
    /// Live numbers above or below a passage dim while you type, with the top
    /// bar, and come back when you pause or move the mouse. They never go
    /// away, and with assistive technology on they stay as they are (see
    /// `TopBarVisibility`).
    func stepsBackWhileTyping() -> some View {
        modifier(StepsBackWhileTyping())
    }
}

private struct StepsBackWhileTyping: ViewModifier {
    @Environment(AppModel.self) private var app: AppModel?
    static let dimmed = 0.4

    func body(content: Content) -> some View {
        let faded = app?.topBar.isFaded ?? false
        content
            .opacity(faded ? Self.dimmed : 1)
            .motion(DS.Motion.standard, value: faded)
    }
}
