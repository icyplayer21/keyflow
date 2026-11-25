import Foundation

/// Real English words for the Words stage. Exercises filter this list down
/// to words that use only the keys a category allows.
public enum TrainingWords {
    /// Lower-case, letters only, no single letters except "a". Unique, in a fixed order.
    public static let all: [String] = {
        let sources = WordList.common
            + Corpus.sentences.flatMap { $0.split(separator: " ").map(String.init) }
            + extra.split(separator: " ").map(String.init)
        var seen = Set<String>()
        var words: [String] = []
        for raw in sources {
            let word = raw.lowercased().trimmingCharacters(in: CharacterSet.letters.inverted)
            guard word == "a" || word.count >= 2,
                  word.allSatisfy({ ("a"..."z").contains($0) }),
                  seen.insert(word).inserted else { continue }
            words.append(word)
        }
        return words
    }()

    /// Words chosen so the restricted categories have enough to work with:
    /// home row only, left hand only and right hand only.
    private static let extra = """
    a as ask asks add adds all ad ads dad dads fad fads fall falls flask flasks flag flags gas glad hall halls has \
    had half hash lad lads lag lags lash salad salads sash shall slash dash flash glass ash sag sags gal hag alas \
    lass gash flak \
    were west after great street read best fast case act tax test wear start state card draft trade water dear \
    seed tree free sea tea feet ever gave save wave crew few bread safe rest set get bet wet are ate eat cave \
    grass area stare bag cab car cat bad bat war saw raw draw sad wax zest vase verb beast sweat craft cease fewer \
    greater extract tread regard reward award cards beard fast faster eager garage desert \
    you only him milk pink union lion hook look moon noon join pull hill ink kin poll pump lump plum monk lily \
    loop pool polo yolk mink oil oh hop hip mop pop pin pun up upon in on no my mill kill pill hum hunk junk \
    opinion million minimum pumpkin hulk puppy hippo nylon holy jumpy inky hilly lumpy kimono unpin
    """
}
