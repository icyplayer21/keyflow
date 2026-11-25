import Foundation

/// The training areas of Typing Mechanics.
public enum MechanicsArea: String, CaseIterable, Identifiable, Sendable {
    case shiftControl, capsLockControl, caseTransitions, numbersSymbols, capitalisationLab

    public var id: Self { self }

    public var title: String {
        switch self {
        case .shiftControl: "Shift Control"
        case .capsLockControl: "Caps Lock Control"
        case .caseTransitions: "Case Transitions"
        case .numbersSymbols: "Numbers & Symbols"
        case .capitalisationLab: "Capitalisation Lab"
        }
    }

    /// For narrow windows.
    public var shortTitle: String {
        switch self {
        case .shiftControl: "Shift"
        case .capsLockControl: "Caps Lock"
        case .caseTransitions: "Case"
        case .numbersSymbols: "Numbers"
        case .capitalisationLab: "Lab"
        }
    }

    public var objective: String {
        switch self {
        case .shiftControl:
            "Capitalise without breaking rhythm. Recommended technique: hold the Shift on the opposite hand to the letter."
        case .capsLockControl:
            "Switch Caps Lock on for a word in capitals and off again straight after. Both switches count toward the time."
        case .caseTransitions:
            "Move between lower and upper case in continuous text without hesitating. Use whichever technique you like."
        case .numbersSymbols:
            "Reach the number row and the shifted symbols without breaking the flow of letters around them."
        case .capitalisationLab:
            "Find out how you capitalise fastest: the same passage with Shift and with Caps Lock, then your own natural way."
        }
    }

    public var drills: [MechanicsDrill] { MechanicsDrill.allCases.filter { $0.area == self } }
}

/// What a correctly typed character must have been produced with.
public enum TechniqueRule: Sendable, Equatable {
    /// Shift (either side), without Caps Lock.
    case shift
    /// Caps Lock (Shift held as well is accepted: it still produces capitals).
    case capsLock
    /// Any observed technique.
    case any
    /// Nothing to check (lower case, digits, space).
    case none

    public func accepts(_ technique: CaseTechnique) -> Bool {
        switch self {
        case .shift: technique.usesShift && !technique.usesCapsLock
        case .capsLock: technique.usesCapsLock
        case .any: technique != .unknown
        case .none: true
        }
    }

    public var title: String {
        switch self {
        case .shift: "Shift"
        case .capsLock: "Caps Lock"
        case .any: "Any technique"
        case .none: "None"
        }
    }
}

/// One progressive stage of a training area.
public enum MechanicsDrill: String, CaseIterable, Identifiable, Sendable {
    // Shift Control
    case singleCapitals, alternatingCase, capitalisedWords, capitalisedSentences
    // Caps Lock Control
    case uppercaseBlocks, capsMixedCase, capsRepeatedTransitions
    // Case Transitions
    case lowerToUpper, upperToLower, multipleTransitions, mixedPatterns
    // Numbers & Symbols
    case numberRow, shiftedSymbols, punctuation, mixedText
    // Capitalisation Lab
    case labShiftOnly, labCapsLockOnly, labFreeChoice

    public var id: Self { self }

    public var area: MechanicsArea {
        switch self {
        case .singleCapitals, .alternatingCase, .capitalisedWords, .capitalisedSentences: .shiftControl
        case .uppercaseBlocks, .capsMixedCase, .capsRepeatedTransitions: .capsLockControl
        case .lowerToUpper, .upperToLower, .multipleTransitions, .mixedPatterns: .caseTransitions
        case .numberRow, .shiftedSymbols, .punctuation, .mixedText: .numbersSymbols
        case .labShiftOnly, .labCapsLockOnly, .labFreeChoice: .capitalisationLab
        }
    }

    /// 1-based position within its area.
    public var stage: Int { (area.drills.firstIndex(of: self) ?? 0) + 1 }

    public var title: String {
        switch self {
        case .singleCapitals: "Single Capitals"
        case .alternatingCase: "Alternating Case"
        case .capitalisedWords: "Natural Words"
        case .capitalisedSentences: "Sentences"
        case .uppercaseBlocks: "Uppercase Blocks"
        case .capsMixedCase: "Mixed Case"
        case .capsRepeatedTransitions: "Repeated Transitions"
        case .lowerToUpper: "Lower to Upper"
        case .upperToLower: "Upper to Lower"
        case .multipleTransitions: "Multiple Transitions"
        case .mixedPatterns: "Mixed Patterns"
        case .numberRow: "Number Row"
        case .shiftedSymbols: "Shifted Symbols"
        case .punctuation: "Punctuation"
        case .mixedText: "Mixed Text"
        case .labShiftOnly: "Shift Only"
        case .labCapsLockOnly: "Caps Lock Only"
        case .labFreeChoice: "Free Choice"
        }
    }

    public var instructions: String {
        switch self {
        case .singleCapitals: "Each capital four times. Press Shift, type the letter, release, and keep a steady beat."
        case .alternatingCase: "Lower case then capital, again and again: the Shift press is the whole exercise."
        case .capitalisedWords: "Real names and places. Capitalise the first letter and carry straight on."
        case .capitalisedSentences: "Ordinary sentences. Capitals should not interrupt your rhythm."
        case .uppercaseBlocks: "Caps Lock on, type the word, Caps Lock off, space. Every word is a full on-and-off cycle."
        case .capsMixedCase: "A word in capitals, then lower case. Turn Caps Lock off before the lower-case text."
        case .capsRepeatedTransitions: "Several words in capitals in one line: switch Caps Lock on and off each time."
        case .lowerToUpper: "Lower-case text running straight into capitals."
        case .upperToLower: "Capitals running straight back into lower case."
        case .multipleTransitions: "Sentences that switch case several times."
        case .mixedPatterns: "Names with capitals in unusual places. Precision matters more than speed."
        case .numberRow: "Years, codes and sequences on the top row. Reach up from the home row and come straight back."
        case .shiftedSymbols: "The symbols above the numbers. Hold Shift on the other hand, reach, release."
        case .punctuation: "Sentence punctuation, typed as your keyboard has it: three full stops for an ellipsis, straight quotes."
        case .mixedText: "Ordinary sentences with numbers and symbols in them. Keep the rhythm through the switch."
        case .labShiftOnly: "Every capital with Shift, including whole words in capitals. Caps Lock does not count here."
        case .labCapsLockOnly: "Every run of capitals with Caps Lock, even a single letter: on before it, off after it."
        case .labFreeChoice: "Capitalise however feels natural. Nothing is marked wrong; Keyflow only notes which method you used."
        }
    }

    /// The technique a correctly typed character at `index` must use.
    ///
    /// - Shift Control: capitals and symbols need Shift; Caps Lock does not count.
    /// - Caps Lock Control: a run of two or more capitals needs Caps Lock; a
    ///   single capital ("Keyflow") may use either; symbols need Shift.
    /// - Case Transitions: any technique, since timing is the point.
    /// - Capitalisation Lab: Shift Only needs Shift for every capital; Caps
    ///   Lock Only needs Caps Lock for every capital, single letters included,
    ///   so the two can be compared at every length; Free Choice accepts any.
    public func rule(at index: Int, in text: [Character]) -> TechniqueRule {
        guard text.indices.contains(index) else { return .none }
        switch CaseRequirement.of(text[index]) {
        case .plain, .unsupported: return .none
        case .shiftedSymbol: return area == .caseTransitions || self == .labFreeChoice ? .any : .shift
        case .uppercaseLetter:
            switch self {
            case .labShiftOnly: return .shift
            case .labCapsLockOnly: return .capsLock
            case .labFreeChoice: return .any
            default: break
            }
            switch area {
            case .shiftControl: return .shift
            case .caseTransitions, .capitalisationLab, .numbersSymbols: return .any
            case .capsLockControl: return Self.uppercaseRun(around: index, in: text).count >= 2 ? .capsLock : .any
            }
        }
    }

    /// The Lab mode compared with this one on the same passage.
    public var labCounterpart: MechanicsDrill? {
        switch self {
        case .labShiftOnly: .labCapsLockOnly
        case .labCapsLockOnly: .labShiftOnly
        default: nil
        }
    }

    /// The run of upper-case letters containing `index`.
    public static func uppercaseRun(around index: Int, in text: [Character]) -> ClosedRange<Int> {
        var start = index, end = index
        while start > 0, CaseRequirement.of(text[start - 1]) == .uppercaseLetter { start -= 1 }
        while end + 1 < text.count, CaseRequirement.of(text[end + 1]) == .uppercaseLetter { end += 1 }
        return start...end
    }
}

/// Exercise text for each drill. Pure and deterministic for a given seed.
public enum MechanicsCatalog {
    public static func text(for drill: MechanicsDrill, seed: UInt64) -> String {
        var rng = SeededGenerator(seed: seed)
        switch drill {
        case .singleCapitals:
            // Alternate hands so both Shift keys get work.
            let left = Array("ASDFQWERTZXCVG").shuffled(using: &rng).prefix(3)
            let right = Array("JKLPUIOHNMY").shuffled(using: &rng).prefix(3)
            return zip(left, right).flatMap { [$0, $1] }
                .map { String(repeating: "\($0) ", count: 4).trimmingCharacters(in: .whitespaces) }
                .joined(separator: " ")
        case .alternatingCase:
            let letters = Array("asdfqwertzxcvgjklpuiohnmy").shuffled(using: &rng).prefix(6)
            return letters.map { c in Array(repeating: "\(c)\(c.uppercased())", count: 3).joined(separator: " ") }
                .joined(separator: " ")
        case .capitalisedWords:
            return pick(12, from: properNouns, using: &rng).joined(separator: " ")
        case .capitalisedSentences:
            return pick(3, from: capitalSentences, using: &rng).joined(separator: " ")
        case .uppercaseBlocks:
            return pick(7, from: uppercaseWords, using: &rng).joined(separator: " ")
        case .capsMixedCase:
            return pick(3, from: capsMixed, using: &rng).joined(separator: " ")
        case .capsRepeatedTransitions:
            return pick(3, from: capsRepeated, using: &rng).joined(separator: " ")
        case .lowerToUpper:
            return pick(5, from: lowerUpper, using: &rng).joined(separator: " ")
        case .upperToLower:
            return pick(5, from: upperLower, using: &rng).joined(separator: " ")
        case .multipleTransitions:
            return pick(3, from: multiple, using: &rng).joined(separator: " ")
        case .mixedPatterns:
            return pick(10, from: mixed, using: &rng).joined(separator: " ")
        case .numberRow:
            return numbers(10, using: &rng).joined(separator: " ")
        case .shiftedSymbols:
            return shiftedSymbolText(using: &rng)
        case .punctuation:
            return pick(4, from: punctuationSentences, using: &rng).joined(separator: " ")
        case .mixedText:
            return pick(4, from: mixedSentences, using: &rng).joined(separator: " ")
        case .labShiftOnly, .labCapsLockOnly:
            return labPassage(seed: seed)
        case .labFreeChoice:
            return pick(3, from: labSentences, using: &rng).joined(separator: " ")
        }
    }

    /// A Lab comparison passage: two runs of capitals of every length
    /// group, each between lower-case words, in shuffled order. Two
    /// lower-case words follow each run, so the passage also holds ordinary
    /// word-to-word changes to compare against. Shift Only and Caps Lock Only
    /// use the same passage for a fair comparison.
    public static func labPassage(seed: UInt64) -> String {
        var rng = SeededGenerator(seed: seed)
        let groups = [labSingles, labPairs, labThreeFour, labFiveSeven, labEightPlus]
        var segments: [String] = []
        for group in groups { segments += pick(2, from: group, using: &rng) }
        segments.shuffle(using: &rng)
        let fillers = WordList.common.filter { word in (3...6).contains(word.count) && word.allSatisfy { ("a"..."z").contains($0) } }
        var words: [String] = []
        for segment in segments {
            if words.isEmpty, let lead = fillers.randomElement(using: &rng) { words.append(lead) }
            words.append(segment)
            for _ in 0..<2 { if let filler = fillers.randomElement(using: &rng) { words.append(filler) } }
        }
        return words.joined(separator: " ")
    }

    private static func pick(_ count: Int, from list: [String], using rng: inout SeededGenerator) -> [String] {
        Array(list.shuffled(using: &rng).prefix(count))
    }

    static let properNouns = [
        "Apple", "London", "Monday", "Australia", "Paris", "Friday", "Canada", "Tokyo", "Sunday", "Berlin",
        "Sarah", "James", "Emma", "Oliver", "July", "August", "Europe", "Africa", "Thursday", "Madrid",
        "Peter", "Lucy", "Boston", "Kenya", "Norway", "Wednesday", "Quebec", "Zurich", "Vienna", "Mexico",
    ]
    static let capitalSentences = [
        "I visited London yesterday.", "Apple released a new product.", "Sarah moved to Canada in June.",
        "We met James at the station.", "The museum in Paris opens on Tuesday.", "Oliver and Emma flew to Tokyo.",
        "My sister lives near Boston.", "The train to Berlin was late again.", "Lucy started a new job in March.",
        "Norway is beautiful in the summer.",
    ]
    static let uppercaseWords = [
        "NASA", "UNESCO", "IMPORTANT", "AUSTRALIA", "WARNING", "URGENT", "LONDON", "NOTICE", "OFFICIAL",
        "HELLO", "RADAR", "LASER", "SCUBA", "DANGER", "STOP", "EXIT", "SALE", "FINAL",
    ]
    static let capsMixed = [
        "NASA is hiring.", "WELCOME to Keyflow.", "IMPORTANT information follows.", "URGENT messages come first.",
        "FREE delivery on all orders.", "NOTE that the office is closed.", "STOP and read the sign.",
        "DANGER signs are red.", "SALE ends on Friday.",
    ]
    static let capsRepeated = [
        "NASA and ESA", "USA and UK", "IMPORTANT: Read this first.", "WHO and UNICEF", "BBC and CNN",
        "FAQ and HELP pages", "PDF or HTML files", "NEW and USED cars", "OPEN and CLOSED signs",
    ]
    static let lowerUpper = [
        "hello NASA", "welcome HOME", "the USA", "read the FAQ", "call the BBC", "visit the UK",
        "please STOP", "this is URGENT", "save as PDF", "send it ASAP",
    ]
    static let upperLower = [
        "NASA is", "USA and", "IMPORTANT information", "UK prices", "BBC news", "FAQ page",
        "HTML code", "URGENT message", "PDF file", "UNESCO sites",
    ]
    static let multiple = [
        "NASA and ESA launched a mission.", "The USA and UK reached an agreement.", "IMPORTANT: Please read this carefully.",
        "The BBC and CNN both reported it.", "Save the file as PDF, not HTML.", "The WHO and UNICEF work together.",
        "Our FAQ answers most USB questions.",
    ]
    /// Years, sequences and codes: every digit appears often.
    static func numbers(_ count: Int, using rng: inout SeededGenerator) -> [String] {
        var tokens = ["12345", "67890", "2026"]
        while tokens.count < count {
            switch Int.random(in: 0..<3, using: &rng) {
            case 0: tokens.append(String(Int.random(in: 1950...2049, using: &rng)))
            case 1: tokens.append(String(Int.random(in: 100...99_999, using: &rng)))
            default:
                let start = Int.random(in: 0...6, using: &rng)
                tokens.append((start..<(start + 4)).map { String($0 % 10) }.joined())
            }
        }
        return Array(tokens.shuffled(using: &rng).prefix(count))
    }

    /// "! @ # $ %" rows, then pairs across the hands ("!*", "@(").
    static func shiftedSymbolText(using rng: inout SeededGenerator) -> String {
        let row = Array("!@#$%^&*()")
        let groups = [Array(row[0..<5]), Array(row[5..<10]), row.shuffled(using: &rng).prefix(5).map { $0 }]
        let left = Array("!@#$%"), right = Array("^&*()")
        let pairs = (0..<4).map { _ in String([left.randomElement(using: &rng)!, right.randomElement(using: &rng)!]) }
        return (groups.map { $0.map(String.init).joined(separator: " ") } + pairs).joined(separator: " ")
    }

    static let punctuationSentences = [
        "Hello, world!", "Wait... What happened?", "\"Are you ready?\"", "It's late; let's go.", "Yes: the plan works.",
        "(Optional) notes follow.", "Is it 'today' or 'tomorrow'?", "Well - maybe not.", "Stop! Look, then listen.",
        "Who said \"never\"?", "First, second; third.",
    ]
    static let mixedSentences = [
        "Version 2.0 is available.", "The result increased by 25%.", "Please enter code 12345.", "Call 555-0142 after 6 pm.",
        "Meet at 10:30 in room 4B.", "Pay $19.99 by May 3.", "We sold 1,250 tickets.", "Use #42 as the tag.",
        "Save 30% on orders over $50!", "Gate 7 opens at 9:15 (not 9:00).",
    ]

    static let labSingles = ["A", "B", "C", "D", "E", "K", "P", "X"]
    static let labPairs = ["UK", "EU", "PC", "TV", "AI", "US", "OK", "ID"]
    static let labThreeFour = ["NASA", "BBC", "USB", "FAQ", "HTML", "NHS", "CEO", "UFO"]
    static let labFiveSeven = ["UNESCO", "URGENT", "NOTICE", "SCUBA", "DANGER", "WARNING", "RADAR"]
    static let labEightPlus = ["IMPORTANT", "AUSTRALIA", "ATTENTION", "CHAMPIONS", "DIRECTIONS", "OFFICIALLY"]
    static let labSentences = [
        "I work at NASA.", "The USA is a large country.", "IMPORTANT information follows.", "We met the CEO in Paris.",
        "Plan B is ready if the UK says no.", "My PC needs a new USB cable.", "The BBC said the UNESCO list grew.",
        "Read the FAQ before you call.", "An A grade in HTML is rare.", "WARNING: the road is closed.",
    ]
    static let mixed = [
        "iPhone", "macOS", "YouTube", "GitHub", "PowerPoint", "eBay", "JavaScript", "LinkedIn", "McDonald",
        "iPad", "PayPal", "WordPress", "iCloud", "DreamWorks", "PlayStation", "TikTok",
    ]
}
