import XCTest
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
    }

    private func key(_ label: String, in rows: [[FlickKey?]] = Layouts.kana) -> FlickKey {
        rows.joined().compactMap { $0 }.first { $0.label == label }!
    }

    private func tick(_ s: TimeInterval = 2) { clock += s }

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
