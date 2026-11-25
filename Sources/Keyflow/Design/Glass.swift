import SwiftUI

// Liquid Glass for the controls Keyflow draws itself. Glass belongs to the
// floating layer only: tabs, pickers, action buttons and overlays. Typing text,
// keyboards, numbers and charts stay solid so they stay readable.
//
// On macOS 15 every helper here falls back to the flat look. On macOS 26 and
// later the system adapts glass to Reduce Transparency and Increase Contrast.

extension DS {
    /// True where the system has Liquid Glass.
    static var usesGlass: Bool {
        if #available(macOS 26, *) { return true }
        return false
    }
}

private struct OnGlassKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// This view already sits on a glass panel. Glass must not stack on glass,
    /// so controls inside draw a plain fill instead.
    var isOnGlass: Bool {
        get { self[OnGlassKey.self] }
        set { self[OnGlassKey.self] = newValue }
    }
}

extension View {
    /// A small floating label or control group over content.
    @ViewBuilder func floatingPill() -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular, in: Capsule())
        } else {
            background(.background.opacity(0.75), in: Capsule())
        }
    }

    /// The glass tray behind the main navigation's `OptionBar`.
    @ViewBuilder func optionTray(_ isOn: Bool) -> some View {
        if #available(macOS 26, *), isOn {
            padding(3).glassEffect(.regular, in: Capsule())
        } else {
            self
        }
    }

    /// The tray behind the main navigation. On macOS 15, where pages scroll
    /// under it with no glass, it needs its own material to stay readable.
    @ViewBuilder func topBarSurface() -> some View {
        if #available(macOS 26, *) {
            self
        } else {
            padding(3).background(.regularMaterial, in: Capsule())
        }
    }

    /// Pins a bar to the top while content scrolls beneath it.
    @ViewBuilder func floatingTopBar<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
        if #available(macOS 26, *) {
            safeAreaBar(edge: .top, spacing: 0, content: bar)
        } else {
            safeAreaInset(edge: .top, spacing: 0, content: bar)
        }
    }

    /// Long pages fade softly under the top bar.
    @ViewBuilder func softScrollEdge() -> some View {
        if #available(macOS 26, *) {
            scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            self
        }
    }
}

/// Lets neighboring glass shapes render together, as one material.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = DS.Space.xs
    @ViewBuilder let content: Content

    var body: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

/// A secondary action beside a primary one: clear glass, or quiet on macOS 15
/// and inside a glass panel.
struct QuietGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        QuietGlassButton(configuration: configuration)
    }

    private struct QuietGlassButton: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.isOnGlass) private var isOnGlass

        var body: some View {
            if #available(macOS 26, *), !isOnGlass {
                configuration.label
                    .font(DS.Typography.body)
                    .foregroundStyle(isEnabled ? Color.primary : Color.secondary.opacity(0.45))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .contentShape(Capsule())
                    .glassEffect(isEnabled ? .regular.interactive() : .regular, in: Capsule())
            } else {
                // The flat look, from the shared quiet style.
                QuietButtonStyle().makeBody(configuration: configuration)
            }
        }
    }
}

extension ButtonStyle where Self == QuietGlassButtonStyle {
    static var quietGlass: QuietGlassButtonStyle { QuietGlassButtonStyle() }
}
