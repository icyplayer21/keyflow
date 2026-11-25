import Foundation

public enum PracticeMode: String, CaseIterable, Identifiable, Sendable {
    case commonWords, sentences, punctuation, numbersSymbols, customText

    public var id: Self { self }

    public var title: String {
        switch self {
        case .commonWords: "Common Words"
        case .sentences: "Sentences"
        case .punctuation: "Punctuation"
        case .numbersSymbols: "Numbers & Symbols"
        case .customText: "Custom Text"
        }
    }
}

/// What a session was for. Stored with every saved session.
public enum SessionKind: Sendable, Hashable {
    case practice(PracticeMode)
    case test

    public var storageKey: String {
        switch self {
        case .practice(let mode): "practice.\(mode.rawValue)"
        case .test: "test"
        }
    }

    public init?(storageKey: String) {
        if storageKey == "test" {
            self = .test
        } else if storageKey.hasPrefix("practice."),
                  let mode = PracticeMode(rawValue: String(storageKey.dropFirst("practice.".count))) {
            self = .practice(mode)
        } else {
            return nil
        }
    }

    public var title: String {
        switch self {
        case .practice(let mode): mode.title
        case .test: "Test"
        }
    }
}
