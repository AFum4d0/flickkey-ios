import Foundation

/// 絵文字・記号の一覧の 1 つのタブ。
struct SymbolTab: Identifiable {
    let id: String
    /// タブに出す見本の 1 文字
    let icon: String
    let items: [String]
    /// 顔文字のように横に長いものは列を広くとる
    var wide = false
}

enum Symbols {
    /// 絵文字は azooKey の分類済みデータ（EmojiDictionary/emoji_genre_*.txt）から読む。
    /// 1 行が「分類名<TAB>絵文字,絵文字,…」。肌の色などの部品（Component）は外す。
    static let emojiTabs: [SymbolTab] = {
        let dir = InputEngine.resources.appendingPathComponent("EmojiDictionary")
        let version: String
        if #available(iOS 18.4, *) { version = "E16.0" } else if #available(iOS 17.4, *) { version = "E15.1" } else { version = "E15.0" }
        guard let s = try? String(contentsOf: dir.appendingPathComponent("emoji_genre_\(version).txt"), encoding: .utf8) else { return [] }
        let icons = ["Smileys & People": "😀", "Animals & Nature": "🐶", "Food & Drink": "🍙", "Activities": "⚽",
                     "Travel & Places": "🚗", "Objects": "💡", "Symbols": "❤️", "Flags": "🏁"]
        var byName: [String: [String]] = [:]
        for line in s.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2 else { continue }
            byName[String(parts[0])] = parts[1].split(separator: ",").map(String.init)
        }
        return ["Smileys & People", "Animals & Nature", "Food & Drink", "Activities", "Travel & Places", "Objects", "Symbols", "Flags"]
            .compactMap { name in byName[name].map { SymbolTab(id: name, icon: icons[name]!, items: $0) } }
    }()

    static let marks = SymbolTab(id: "記号", icon: "＃", items: Array(
        "、。，．・：；？！゛゜´｀¨＾￣＿ヽヾゝゞ〃仝々〆〇ー―‐／＼～∥｜…‥‘’“”（）〔〕［］｛｝〈〉《》「」『』【】"
        + "＋－±×÷＝≠＜＞≦≧∞∴♂♀°′″℃￥＄¢£％＃＆＊＠§☆★○●◎◇◆□■△▲▽▼※〒→←↑↓〓"
        + "∈∋⊆⊇⊂⊃∪∩∧∨￢⇒⇔∀∃∠⊥⌒∂∇≡≒≪≫√∽∝∵∫∬Å‰♯♭♪†‡¶◯").map(String.init))

    static let kaomoji = SymbolTab(id: "顔文字", icon: "(^^)", items: [
        "(^^)", "(^_^)", "(*^^*)", "(^o^)", "(≧▽≦)", "(*´▽`*)", "(´・ω・`)", "(・∀・)", "(￣▽￣)", "(^_^;)",
        "(;´Д`)", "(T_T)", "(´；ω；`)", "(>_<)", "(・_・;)", "(´ー`)", "ヽ(・∀・)ﾉ", "(￣ー￣)ﾆﾔﾘ", "(｀・ω・´)",
        "m(_ _)m", "orz", "(*'▽')", "＼(^o^)／", "(⌒▽⌒)", "(o^―^o)", "(；・∀・)", "(・o・)", "(￣□￣;)",
    ], wide: true)

    static var tabs: [SymbolTab] { emojiTabs + [marks, kaomoji] }
}
