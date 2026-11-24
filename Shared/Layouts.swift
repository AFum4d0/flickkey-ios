import CoreGraphics

/// 指を置いた位置からの動き。flick の並びは [タップ, 左, 上, 右, 下]（iOS・Gboard と同じ）。
enum FlickDirection: Int, CaseIterable {
    case tap = 0, left, up, right, down

    static func from(dx: CGFloat, dy: CGFloat, threshold: CGFloat = 22) -> FlickDirection {
        guard dx * dx + dy * dy >= threshold * threshold else { return .tap }
        if abs(dx) > abs(dy) { return dx < 0 ? .left : .right }
        return dy < 0 ? .up : .down
    }
}

/// 12 キーの 1 つ。chars はタップ・左・上・右・下の順。トグル（ケータイ入力）は toggle の順に回る。
struct FlickKey: Hashable {
    let chars: [String]
    let toggle: [String]
    /// キーに書く文字。省略時はタップで入る文字。
    let face: String

    init(_ chars: [String], toggle: [String]? = nil, face: String? = nil) {
        self.chars = chars
        self.toggle = toggle ?? chars
        self.face = face ?? chars[0]
    }

    var label: String { chars[0] }

    func char(_ d: FlickDirection) -> String? {
        d.rawValue < chars.count && !chars[d.rawValue].isEmpty ? chars[d.rawValue] : nil
    }
}

/// 12 キーの中央 3 列。空文字の方向は入力しない。
enum Layouts {
    static let modifierLabel = "小゛゜"

    static let kana: [[FlickKey?]] = [
        [k("あいうえお"), k("かきくけこ"), k("さしすせそ")],
        [k("たちつてと"), k("なにぬねの"), k("はひふへほ")],
        [k("まみむめも"), FlickKey(["や", "（", "ゆ", "）", "よ"], toggle: ["や", "ゆ", "よ", "（", "）"]), k("らりるれろ")],
        [nil, FlickKey(["わ", "を", "ん", "ー", ""], toggle: ["わ", "を", "ん", "ー"]),
         FlickKey(["、", "。", "？", "！", "…"], toggle: ["、", "。", "？", "！", "…"], face: "、。?!")],
    ]

    static let number: [[FlickKey?]] = [
        [FlickKey(["1", "☆", "♪", "→", ""]), FlickKey(["2", "¥", "$", "€", ""]), FlickKey(["3", "%", "°", "#", ""])],
        [FlickKey(["4", "○", "*", "・", ""]), FlickKey(["5", "+", "×", "÷", ""]), FlickKey(["6", "<", "=", ">", ""])],
        [FlickKey(["7", "「", "」", ":", ""]), FlickKey(["8", "〒", "々", "〆", ""]), FlickKey(["9", "^", "|", "\\", ""])],
        [FlickKey(["(", ")", "[", "]", ""]), FlickKey(["0", "〜", "…", "", ""]), FlickKey([".", ",", "-", "/", ""])],
    ]

    static let qwerty: [[String]] = [
        Array("qwertyuiop").map(String.init),
        Array("asdfghjkl").map(String.init),
        Array("zxcvbnm").map(String.init),
    ]

    private static func k(_ s: String) -> FlickKey { FlickKey(s.map(String.init)) }
}

/// 「小゛゜」キーで直前の 1 文字を回す。
enum KanaModifier {
    private static let cycles: [[Character]] = [
        "かが", "きぎ", "くぐ", "けげ", "こご", "さざ", "しじ", "すず", "せぜ", "そぞ",
        "ただ", "ちぢ", "てで", "とど", "はばぱ", "ひびぴ", "ふぶぷ", "へべぺ", "ほぼぽ",
        "つっづ", "あぁ", "いぃ", "うぅゔ", "えぇ", "おぉ", "やゃ", "ゆゅ", "よょ", "わゎ",
    ].map(Array.init)

    static func next(_ c: Character) -> Character? {
        for cycle in cycles {
            if let i = cycle.firstIndex(of: c) { return cycle[(i + 1) % cycle.count] }
        }
        return nil
    }
}
