import KeyflowCore
import SwiftUI

struct PracticeView: View {
    @Bindable var model: TypingSessionModel
    @State private var keyboard = KeyboardMonitor()
    @Environment(\.typingWidth) private var typingWidth

    var body: some View {
        let running = model.phase == .running
        let finished = model.phase == .finished

        VStack(spacing: 0) {
            configuration
                .padding(.top, DS.Space.l)
                .padding(.horizontal, DS.Layout.pagePadding)
                // Out of the way while typing; back the moment the session ends.
                .opacity(running ? 0 : 1)
                .allowsHitTesting(!running)
                .motion(DS.Motion.standard, value: running)

            Spacer(minLength: DS.Space.l)

            Group {
                if model.isEditingCustomText {
                    CustomTextEditorView(model: model)
                        .transition(.opacity)
                } else if finished {
                    VStack(alignment: .leading, spacing: DS.Space.l) {
                        ResultsView(metrics: model.result?.metrics ?? model.metrics, restart: model.restart)
                        SaveStatusView(model: model)
                    }
                    .transition(.opacity)
                } else {
                    TypingAreaView(model: model)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: typingWidth)
            .padding(.horizontal, DS.Layout.pagePadding)

            Spacer(minLength: DS.Space.l)

            HStack(spacing: DS.Space.m) {
                if !finished { RestartButton(action: model.restart) }
                ShortcutHints(finished: finished)
            }
            .frame(height: 28)
            .opacity(model.isEditingCustomText ? 0 : 1)
            .padding(.bottom, DS.Space.l)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .motion(DS.Motion.standard, value: model.phase)
        .motion(DS.Motion.standard, value: model.isEditingCustomText)
        .onAppear { keyboard.start { model.handle($0) } }
        .onDisappear { keyboard.stop() }
    }

    /// Practice type and duration on one line when there is room, two when not.
    private var configuration: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DS.Space.s) {
                modePicker
                separator
                durationAndText
            }
            VStack(spacing: DS.Space.xs) {
                modePicker
                durationAndText
            }
        }
    }

    private var modePicker: some View {
        OptionBar(options: PracticeMode.allCases, selection: $model.mode) { $0.title }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Practice type")
    }

    private var durationAndText: some View {
        HStack(spacing: DS.Space.s) {
            DurationPicker(model: model)
            if model.mode == .customText, !model.isEditingCustomText {
                Button { model.isEditingCustomText = true } label: {
                    Label("Edit Text", systemImage: "square.and.pencil")
                }
                .buttonStyle(.quiet)
            }
        }
    }

    private var separator: some View {
        Rectangle().fill(DS.Palette.hairline).frame(width: 1, height: 16)
    }
}

/// Where the user pastes or types their own passage.
struct CustomTextEditorView: View {
    let model: TypingSessionModel
    @State private var draft = ""
    @FocusState private var editorFocused: Bool

    private var normalized: String { TextNormalizer.normalize(draft) }

    var body: some View {
        let text = normalized
        let words = text.split(separator: " ").count

        VStack(alignment: .leading, spacing: DS.Space.s) {
            Text("Custom Text").font(DS.Typography.pageTitle)
            Text("Paste or type an English passage. Line breaks and extra spaces are collapsed, and curly quotes and long dashes become their keyboard equivalents.")
                .font(DS.Typography.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextEditor(text: $draft)
                .font(.system(size: 14, design: .monospaced))
                .lineSpacing(4)
                .scrollContentBackground(.hidden)
                .padding(DS.Space.s)
                .frame(minHeight: 180, maxHeight: 300)
                .background(DS.Palette.fill, in: RoundedRectangle(cornerRadius: DS.Radius.panel))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.panel)
                        .strokeBorder(editorFocused ? Color.accentColor.opacity(0.6) : DS.Palette.hairline)
                )
                .focused($editorFocused)
                .accessibilityLabel("Custom passage")

            HStack(spacing: DS.Space.xs) {
                Text(text.isEmpty ? "No text yet" : "\(words) words · \(text.count) characters")
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if draft.count > TextNormalizer.maximumLength {
                    Text("Only the first \(TextNormalizer.maximumLength) characters are used.")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Palette.caution)
                }
                Spacer()
                if model.hasCustomText {
                    Button("Cancel") { model.isEditingCustomText = false }
                        .buttonStyle(.quiet)
                        .keyboardShortcut(.cancelAction)
                }
                Button("Clear") { draft = "" }
                    .buttonStyle(.quietGlass)
                    .disabled(draft.isEmpty)
                Button("Start Practice") { model.setCustomText(draft) }
                    .buttonStyle(.keyflowPrimary)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(text.isEmpty)
                    .help("⌘ Return")
            }
        }
        .onAppear {
            draft = model.customText
            editorFocused = true
        }
    }
}
