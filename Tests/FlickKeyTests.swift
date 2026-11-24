import XCTest
import Engine
@testable import FlickKey

@MainActor
final class FlickKeyTests: XCTestCase {
    private var engine: InputEngine!
    private var out: DemoOutput!
    private var clock = Date(timeIntervalSince1970: 0)

    override func setUp() async throws {
        UserDefaults.standard.removeObject(forKey: "recentSymbols")
        engine = InputEngine()
        out = DemoOutput()
        engine.output = out
        engine.now = { [unowned self] in self.clock }
        engine.useZenzai = false  // 辞書だけの変換で決まった結果を確かめる。Zenzai は testZenzai で見る
        engine.typoCheckDelay = nil
    }

    private func key(_ label: String, in rows: [[FlickKey?]] = Layouts.kana) -> FlickKey {
        rows.joined().compactMap { $0 }.first { $0.label == label }!
    }

    private func tick(_ s: TimeInterval = 2) { clock += s }

    /// ひらがなを 12 キーで打つ。濁点・小文字は 小゛゜ を押して作る。
    private func type(_ s: String) {
        let keys = Layouts.kana.joined().compactMap { $0 }
        for ch in s {
            var target = String(ch), presses = 0
            while !keys.contains(where: { $0.chars.contains(target) }) {
                // 小゛゜ を何回押すと ch になるか（か→が なら 1 回）を逆にたどる
                let base = keys.flatMap(\.chars).first { b in
                    var c = Character(b); var n = 0
                    while let next = KanaModifier.next(c), n < 3 { c = next; n += 1; if c == ch { presses = n; return true } }
                    return false
                }
                target = base!
            }
            let key = keys.first { $0.chars.contains(target) }!
            tick()
            engine.flick(key, FlickDirection(rawValue: key.chars.firstIndex(of: target)!)!)
            for _ in 0..<presses { engine.modify() }
        }
        XCTAssertEqual(engine.composing.hasSuffix(s), true)
    }

    /// 足した辞書（mozc-ut）の語が出るか。
    func testTechnicalTerms() {
        for (kana, word) in [("びぶんほうていしき", "微分方程式"), ("みとこんどりあ", "ミトコンドリア"),
                             ("ふーりえへんかん", "フーリエ変換"), ("とくがわいえやす", "徳川家康")] {
            type(kana)
            XCTAssertTrue(engine.candidates.prefix(10).contains { $0.text == word }, "\(kana) → \(engine.candidates.prefix(5).map(\.text))")
            engine.enter()
        }
    }

    /// Zenzai が読み込めて、文の流れで同音語を選び分けられるか。
    func testZenzai() throws {
        try XCTSkipIf(InputEngine.zenzWeight == nil, "zenz.gguf が入っていない")
        engine.useZenzai = true
        type("きしゃがきしゃできしゃした")
        #if targetEnvironment(simulator)
        // CI のシミュレーターではモデルを読み込めない（macOS 上の評価 eval.yml では読めている）
        try XCTSkipIf(engine.zenzStatus.contains("could not load"), engine.zenzStatus)
        #endif
        let top = engine.candidates.prefix(3).map(\.text)
        print("zenzai:", top)
        XCTAssertTrue(top.contains("記者が汽車で帰社した"), "\(top) / zenzStatus: \(engine.zenzStatus)")
    }

    /// 確定のあとに次の語が出るか（中身は辞書しだいなので、出たことと選べることだけ見る）。
    func testPredictionAfterCommit() {
        type("きょう")
        let c = engine.candidates.first { $0.text == "今日" }!
        engine.choose(c)
        print("predictions:", engine.predictions.map(\.text))
        if let p = engine.predictions.first {
            engine.choosePrediction(p)
            XCTAssertEqual(out.text, "今日" + p.text)
        }
        engine.flick(key("あ"), .tap)
        XCTAssertTrue(engine.predictions.isEmpty)
    }

    func testTypoNeighbors() {
        let n = TypoVariants.neighbors(of: "う")
        XCTAssertTrue(n.contains("え") && n.contains("あ"))  // 同じキーの別の方向
        XCTAssertTrue(n.contains("く") && n.contains("つ"))  // 右のキー（か）・下のキー（た）の同じ方向
        XCTAssertFalse(n.contains("う"))
    }

    /// 「ありがとえ」と打つと「ありがとう」を勧め、正しく打ったときは勧めない。
    func testTypoSuggestion() async {
        type("ありがとえ")
        await engine.checkTypos()
        XCTAssertEqual(engine.suggestion?.reading, "ありがとう", "\(String(describing: engine.suggestion?.candidate.text))")
        if let s = engine.suggestion, s.obvious {
            // 明らかな誤字なら、変換キー 1 回で直した候補が選ばれる
            XCTAssertEqual(engine.candidates.first?.text, s.candidate.text)
            engine.space()
            XCTAssertEqual(out.marked, s.candidate.text)
            engine.backspace()  // 選択を外すと勧めも消えるので、もう一度確かめる
            await engine.checkTypos()
        }
        engine.chooseSuggestion()
        XCTAssertFalse(engine.isComposing)
        XCTAssertFalse(out.text.isEmpty)
        tick()
        type("ありがとう")
        await engine.checkTypos()
        XCTAssertNil(engine.suggestion)
    }

    /// 長い文の頭の方の打ち間違いも直せる（文字数の制限なし）。
    func testTypoFarFromEnd() async {
        engine.enter()
        type("ありがとえございます")  // 5 文字目の う を え と打った
        await engine.checkTypos()
        XCTAssertEqual(engine.suggestion?.reading, "ありがとうございます", "\(String(describing: engine.suggestion?.candidate.text))")
    }

    func testDirection() {
        XCTAssertEqual(FlickDirection.from(dx: 3, dy: -4), .tap)
        XCTAssertEqual(FlickDirection.from(dx: -40, dy: 5), .left)
        XCTAssertEqual(FlickDirection.from(dx: 5, dy: -40), .up)
        XCTAssertEqual(FlickDirection.from(dx: 40, dy: 10), .right)
        XCTAssertEqual(FlickDirection.from(dx: 0, dy: 40), .down)
    }

    func testModifierCycles() {
        XCTAssertEqual(KanaModifier.next("か"), "が")
        XCTAssertEqual(KanaModifier.next("が"), "か")
        XCTAssertEqual(KanaModifier.next("は"), "ば")
        XCTAssertEqual(KanaModifier.next("ば"), "ぱ")
        XCTAssertEqual(KanaModifier.next("ぱ"), "は")
        XCTAssertEqual(KanaModifier.next("つ"), "っ")
        XCTAssertNil(KanaModifier.next("ん"))
    }

    func testToggleInput() {
        let a = key("あ")
        engine.flick(a, .tap); engine.flick(a, .tap); engine.flick(a, .tap)
        XCTAssertEqual(engine.composing, "う")
        engine.reverseToggle()
        XCTAssertEqual(engine.composing, "い")
        tick()
        engine.flick(a, .tap)
        XCTAssertEqual(engine.composing, "いあ")
        // ▶ でトグルを切ると、すぐ押しても次の文字になる
        engine.moveCursor(1)
        engine.flick(a, .tap)
        XCTAssertEqual(engine.composing, "いああ")
    }

    func testFlickAndConvert() {
        engine.flick(key("か"), .tap)
        engine.flick(key("わ"), .up)      // ん
        tick()
        engine.flick(key("さ"), .left)    // し
        engine.modify()                   // じ
        XCTAssertEqual(engine.composing, "かんじ")
        XCTAssertEqual(out.marked, "かんじ")
        let kanji = try! XCTUnwrap(engine.candidates.first { $0.text == "漢字" })
        engine.choose(kanji)
        XCTAssertEqual(out.text, "漢字")
        XCTAssertFalse(engine.isComposing)
        XCTAssertEqual(out.marked, "")
    }

    func testSpaceSelectsAndEnterCommits() {
        engine.flick(key("あ"), .tap)
        engine.space()
        XCTAssertEqual(engine.selected, 0)
        let first = engine.candidates[0].text
        XCTAssertEqual(out.marked, first)
        engine.enter()
        XCTAssertEqual(out.text, first)
        engine.enter()
        XCTAssertEqual(out.text, first + "\n")
    }

    func testBackspaceAndCursor() {
        engine.flick(key("か"), .tap)
        engine.backspace()
        XCTAssertFalse(engine.isComposing)
        engine.switchMode() // ABC
        engine.letter("a"); engine.letter("b")
        engine.moveCursor(-1)
        engine.letter("c")
        XCTAssertEqual(out.text, "acb")
        engine.backspace()
        XCTAssertEqual(out.text, "ab")
    }

    func testNumberMode() {
        engine.switchMode(); engine.switchMode()
        XCTAssertEqual(engine.mode, .number)
        engine.flick(key("1", in: Layouts.number), .tap)
        engine.flick(key("5", in: Layouts.number), .up)
        XCTAssertEqual(out.text, "1×")
        XCTAssertFalse(engine.isComposing)
    }

    /// シフトの 2 度押しで大文字が続き、もう 1 回で戻る。
    func testCapsLock() {
        engine.switchMode()
        engine.tapShift(); engine.tapShift()
        XCTAssertTrue(engine.capsLock)
        engine.letter("a"); engine.letter("b")
        engine.tapShift()
        XCTAssertFalse(engine.capsLock)
        engine.letter("c")
        XCTAssertEqual(out.text, "ABc")
    }

    /// 文の頭は自動で大文字、空白 2 回で「. 」。
    func testAutoCapitalizeAndDoubleSpace() {
        engine.autoCapitalize = true
        engine.switchMode()
        XCTAssertTrue(engine.shift)
        engine.letter("h"); engine.letter("i")
        engine.space(); engine.space()
        XCTAssertEqual(out.text, "Hi. ")
        XCTAssertTrue(engine.shift)
        engine.letter("o")
        tick(); engine.space(); tick(); engine.space()  // 間をあけた空白は「. 」にしない
        XCTAssertEqual(out.text, "Hi. O  ")
    }

    /// 削除キーを左へなぞった分だけ、入力中の文字も確定した文字も消せる（あるより多くは消さない）。
    func testSwipeDelete() {
        type("あいう")
        engine.deleteBackward(count: 2)
        XCTAssertEqual(engine.composing, "あ")
        engine.enter()
        XCTAssertEqual(engine.deletableCount, 1)
        engine.deleteBackward(count: 5)
        XCTAssertEqual(out.text, "")
    }

    func testFieldType() {
        engine.start(keyboardType: .numberPad)
        XCTAssertEqual(engine.mode, .number)
        engine.start(keyboardType: .emailAddress)
        XCTAssertEqual(engine.mode, .qwerty)
        engine.start(keyboardType: .default)
        XCTAssertEqual(engine.mode, .kana)
    }

    func testRecentSymbols() {
        engine.insertSymbol("😀"); engine.insertSymbol("★"); engine.insertSymbol("😀")
        XCTAssertEqual(out.text, "😀★😀")
        XCTAssertEqual(engine.recentSymbols, ["😀", "★"])
        XCTAssertEqual(InputEngine().recentSymbols, ["😀", "★"])  // 次に開いたときも残る
    }

    func testEmojiTabsLoaded() {
        XCTAssertGreaterThanOrEqual(Symbols.emojiTabs.count, 8, "emoji_genre が読めていない")
        XCTAssertTrue(Symbols.emojiTabs[0].items.contains("😀"))
    }

    func testShiftIsOneShot() {
        engine.switchMode()
        engine.shift = true
        engine.letter("h"); engine.letter("i")
        XCTAssertEqual(out.text, "Hi")
    }
}
