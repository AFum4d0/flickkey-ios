import XCTest
import Engine
@testable import FlickKey

@MainActor
final class FlickKeyTests: XCTestCase {
    private var engine: InputEngine!
    private var out: DemoOutput!
    private var clock = Date(timeIntervalSince1970: 0)

    override func setUp() async throws {
        engine = InputEngine()
        out = DemoOutput()
        engine.output = out
        engine.now = { [unowned self] in self.clock }
        engine.useZenzai = false  // 辞書だけの変換で決まった結果を確かめる。Zenzai は testZenzai で見る
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
        let top = engine.candidates.prefix(3).map(\.text)
        print("zenzai:", top)
        XCTAssertTrue(top.contains("記者が汽車で帰社した"), "\(top)")
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

    func testShiftIsOneShot() {
        engine.switchMode()
        engine.shift = true
        engine.letter("h"); engine.letter("i")
        XCTAssertEqual(out.text, "Hi")
    }
}
