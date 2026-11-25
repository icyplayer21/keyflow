import Foundation

public enum WordList {
    /// High-frequency English words, lowercase, letters only.
    public static let common: [String] = unique(raw.split(separator: " ").map(String.init))

    private static func unique(_ words: [String]) -> [String] {
        var seen = Set<String>()
        return words.filter { seen.insert($0).inserted }
    }

    private static let raw = """
    the be to of and a in that have I it for not on with he as you do at this but his by from they \
    we say her she or an will my one all would there their what so up out if about who get which go \
    me when make can like time no just him know take people into year your good some could them see \
    other than then now look only come its over think also back after use two how our work first \
    well way even new want because any these give day most us great between need large often hand \
    high place hold turn follow mean again point play small number off always move live night write \
    bring without before under water room mother area money story fact month lot right study book \
    eye job word though business issue side kind four head far black long both little house yes \
    since provide service around friend important father sit away until power hour game line end \
    among ever stand bad lose however member pay law meet car city almost include continue set later \
    community much name five once white least president learn real change team minute best several \
    idea kid body information nothing ago lead social understand whether watch together young same \
    still school never last let thought keep children begin life while might next sound below \
    something world family group country problem system program question during government company \
    part child woman man thing case week student state different every those very where should each \
    many through down find here tell more does made call been must such why ask went men read land \
    home try picture animal answer earth light own page plant cover food sun open seem run
    """
}
