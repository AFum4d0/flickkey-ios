import Foundation
import Engine

/// 文字の出し先。キーボードでは textDocumentProxy、アプリの試し打ち画面では文字列。
@MainActor
protocol TextOutput: AnyObject {
    /// 入力中の文字（下線つき）を置き換える。空文字なら消す。cursor は文字数。
    func setMarked(_ text: String, cursor: Int)
    /// 入力中の文字を text に置き換えて確定する。入力中の文字がなければそのまま挿入する。
    func commit(_ text: String)
    func deleteBackward()
    func moveCursor(by offset: Int)
    /// カーソルより前の文字。Zenzai に文脈として渡す。
    var contextBefore: String { get }
}

enum KeyboardMode: CaseIterable {
    case kana, qwerty, number

    var next: KeyboardMode {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

@MainActor
final class InputEngine: ObservableObject {
    @Published var mode: KeyboardMode = .kana
    @Published var shift = false
    @Published private(set) var composing = ""
    @Published private(set) var candidates: [Candidate] = []
    /// 空白（変換）キーで選んでいる候補。nil なら未変換。
    @Published private(set) var selected: Int?
    /// 確定した直後に出す「次に来そうな語」。何か打つと消える。
    @Published private(set) var predictions: [PostCompositionPredictionCandidate] = []
    private var lastChosen: Candidate?

    /// 「もしかして」：フリックの打ち間違いを直した読みで、はっきり良い変換が見つかったときに出す。
    struct TypoSuggestion {
        let reading: String
        let candidate: Candidate
        /// 明らかな誤字。直した変換を候補の 1 番目に入れ、変換キー 1 回で選べるようにする。
        let obvious: Bool
    }
    @Published private(set) var suggestion: TypoSuggestion?
    /// 打つ手が止まってから確かめるまでの時間。テストでは自動で確かめず checkTypos() を呼ぶ。
    var typoCheckDelay: UInt64? = 350_000_000
    /// 打ち間違いを直した読みの変換が、元の読みよりこれだけ（対数の出やすさで）良ければ出す。
    var typoMargin: Float = 3
    /// これ以上良ければ明らかな誤字とみなす。
    var obviousTypoMargin: Float = 8
    private var typoTask: Task<Void, Never>?

    /// Zenzai の重み（zenz-v3.2-xsmall）がキーボード拡張に入っていれば使う。
    static let zenzWeight: URL? = {
        let url = InputEngine.resources.appendingPathComponent("zenz.gguf")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }()
    /// テストで Zenzai を切るため。
    var useZenzai = true

    weak var output: TextOutput?
    /// テストで時刻を差し替える。
    var now: () -> Date = Date.init
    /// 同じキーをこの秒数以内にもう一度押すとケータイ入力として次の文字に回る。
    var toggleInterval: TimeInterval = 1.0

    private var text = ComposingText()
    private var toggleKey: FlickKey?
    private var toggleIndex = 0
    private var toggleTime = Date.distantPast
    /// 辞書はキーボード拡張の中にだけ入れ、アプリからも拡張の中を読む（2 重に持たない）。
    static let resources: URL = {
        let main = Bundle.main.bundleURL
        return main.pathExtension == "appex" ? main : main.appendingPathComponent("PlugIns/FlickKeyboard.appex")
    }()
    private let converter = KanaKanjiConverter(dictionaryURL: InputEngine.resources.appendingPathComponent("Dictionary"))
    private let baseOptions: ConvertRequestOptions = {
        let dir = (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory).appendingPathComponent("learning", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return ConvertRequestOptions(
            N_best: 10,
            requireJapanesePrediction: true,
            requireEnglishPrediction: false,
            keyboardLanguage: .ja_JP,
            learningType: .inputAndOutput,
            memoryDirectoryURL: dir,
            sharedContainerURL: dir,
            textReplacer: TextReplacer {
                let dir = InputEngine.resources.appendingPathComponent("EmojiDictionary")
                if #available(iOS 18.4, *) { return dir.appendingPathComponent("emoji_all_E16.0.txt") }
                if #available(iOS 17.4, *) { return dir.appendingPathComponent("emoji_all_E15.1.txt") }
                return dir.appendingPathComponent("emoji_all_E15.0.txt")
            },
            specialCandidateProviders: KanaKanjiConverter.defaultSpecialCandidateProviders,
            metadata: .init(versionString: "FlickKey 0.1")
        )
    }()

    var isComposing: Bool { !text.isEmpty }
    /// Zenzai のモデルを読み込めたか（読めないと黙って辞書だけの変換になる）。
    var zenzStatus: String { converter.zenzStatus }

    /// 毎回の変換に使う設定。Zenzai にはカーソルより前の 20 文字を文脈として渡す。
    private var options: ConvertRequestOptions {
        var o = baseOptions
        if useZenzai, let weight = Self.zenzWeight {
            // ponytail: 推論の回数（inferenceLimit）は実機の速さを測って決める。本人の打ち癖（personalization）は後で足す
            o.zenzaiMode = .on(weight: weight, inferenceLimit: 5, personalizationMode: nil,
                               versionDependentMode: .v3(.init(leftSideContext: output?.contextBefore, maxLeftSideContextLength: 20)))
        }
        return o
    }

    // MARK: キー

    func flick(_ key: FlickKey, _ d: FlickDirection) {
        predictions = []
        guard let s = key.char(d) else { return }
        if mode != .kana {
            insertDirect(s)
            return
        }
        if d == .tap, key == toggleKey, now().timeIntervalSince(toggleTime) < toggleInterval {
            toggleIndex = (toggleIndex + 1) % key.toggle.count
            toggleTime = now()
            replaceLast(with: key.toggle[toggleIndex])
            return
        }
        commitSelected()
        toggleKey = d == .tap ? key : nil
        toggleIndex = 0
        toggleTime = now()
        text.insertAtCursorPosition(s, inputStyle: .direct)
        render()
    }

    /// ↶：ケータイ入力を 1 つ戻す（お→え）。
    func reverseToggle() {
        guard let key = toggleKey, isComposing else { return }
        toggleIndex = (toggleIndex - 1 + key.toggle.count) % key.toggle.count
        toggleTime = now()
        replaceLast(with: key.toggle[toggleIndex])
    }

    /// 小゛゜：カーソル直前の 1 文字を か→が、は→ば→ぱ のように回す。
    func modify() {
        predictions = []
        selected = nil
        toggleKey = nil
        guard let last = text.convertTargetBeforeCursor.last, let n = KanaModifier.next(last) else { return }
        replaceLast(with: String(n))
    }

    func letter(_ s: String) {
        predictions = []
        insertDirect(shift ? s.uppercased() : s)
        shift = false
    }

    func space() {
        predictions = []
        toggleKey = nil
        guard isComposing, !candidates.isEmpty else {
            insertDirect(" ")
            return
        }
        selected = selected.map { ($0 + 1) % candidates.count } ?? 0
        render()
    }

    func enter() {
        predictions = []
        toggleKey = nil
        if isComposing {
            commitAll()
        } else {
            output?.commit("\n")
        }
    }

    func backspace() {
        predictions = []
        toggleKey = nil
        if selected != nil {
            selected = nil
            render()
        } else if isComposing {
            text.deleteBackwardFromCursorPosition(count: 1)
            render()
        } else {
            output?.deleteBackward()
        }
    }

    func moveCursor(_ offset: Int) {
        predictions = []
        toggleKey = nil
        if isComposing {
            selected = nil
            _ = text.moveCursorFromCursorPosition(count: offset)
            render()
        } else {
            output?.moveCursor(by: offset)
        }
    }

    func choose(_ c: Candidate) {
        toggleKey = nil
        selected = nil
        converter.setCompletedData(c)
        converter.updateLearningData(c)
        text.prefixComplete(composingCount: c.composingCount)
        output?.commit(c.text)
        if text.isEmpty {
            converter.commitUpdateLearningData()
        }
        render()
        if text.isEmpty {
            lastChosen = c
            predictions = Array(converter.requestPostCompositionPredictionCandidates(leftSideCandidate: c, options: options).prefix(10))
        }
    }

    /// 確定の直後に出した「次の語」を選ぶ。
    func choosePrediction(_ p: PostCompositionPredictionCandidate) {
        output?.commit(p.text)
        if let c = lastChosen {
            converter.updateLearningData(c, with: p)
            converter.commitUpdateLearningData()
        }
        lastChosen = nil
        predictions = []
    }

    func chooseSuggestion() {
        guard let s = suggestion else { return }
        toggleKey = nil
        selected = nil
        output?.commit(s.candidate.text)
        text = ComposingText()
        render()
    }

    private func scheduleTypoCheck() {
        typoTask?.cancel()
        suggestion = nil
        guard let delay = typoCheckDelay, isComposing, selected == nil else { return }
        typoTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            await self?.checkTypos()
        }
    }

    /// どこか 1 文字を打ち間違えた場合の読みを、文字数の制限なしで全部試す。
    /// 1 通りごとに手を離し（Task.yield）、次の文字が打たれたら打ち切るので、打つ手は待たされない。
    /// ponytail: 1 文字あたり最大 8 通り変換する。実機で電池や熱が気になれば、裏の変換器に分ける。
    func checkTypos() async {
        suggestion = nil
        let reading = text.convertTarget
        guard !reading.isEmpty, selected == nil, text.isAtEndIndex else { return }
        var o = baseOptions
        o.requireJapanesePrediction = false  // 予測を混ぜず、読み全体の変換どうしで比べる
        func best(_ r: String) -> Candidate? {
            var t = ComposingText()
            t.insertAtCursorPosition(r, inputStyle: .direct)
            return converter.requestCandidates(t, options: o).mainResults.first
        }
        guard let base = best(reading) else { return }
        var found: TypoSuggestion?
        for v in TypoVariants.of(reading) {
            await Task.yield()
            guard !Task.isCancelled, text.convertTarget == reading else { return }
            guard let c = best(v), Float(c.value) > Float(base.value) + typoMargin else { continue }
            if found == nil || Float(c.value) > Float(found!.candidate.value) {
                found = TypoSuggestion(reading: v, candidate: c, obvious: Float(c.value) > Float(base.value) + obviousTypoMargin)
            }
        }
        // 変換器は最後に変換した入力を覚えているので、元の入力に戻しておく
        _ = converter.requestCandidates(text.prefixToCursorPosition(), options: options)
        suggestion = found
        if let found, found.obvious { candidates.insert(found.candidate, at: 0) }
    }

    func switchMode() {
        predictions = []
        commitAll()
        mode = mode.next
        shift = false
    }

    // MARK: 内部

    private func insertDirect(_ s: String) {
        commitAll()
        output?.commit(s)
    }

    /// 空白で選んだ候補があれば、新しい文字を打つ前に確定する（Gboard と同じ）。
    private func commitSelected() {
        if let i = selected, i < candidates.count { choose(candidates[i]) }
    }

    private func commitAll() {
        toggleKey = nil
        commitSelected()
        guard isComposing else { return }
        output?.commit(text.convertTarget)
        text = ComposingText()
        render()
    }

    private func replaceLast(with s: String) {
        text.deleteBackwardFromCursorPosition(count: 1)
        text.insertAtCursorPosition(s, inputStyle: .direct)
        render()
    }

    private func render() {
        defer { composing = text.convertTarget; scheduleTypoCheck() }
        guard isComposing else {
            candidates = []
            selected = nil
            converter.stopComposition()
            output?.setMarked("", cursor: 0)
            return
        }
        // ponytail: 1 打ごとにメインスレッドで変換している。長文で引っかかるなら裏のスレッドへ。
        if selected == nil {
            let result = converter.requestCandidates(text.prefixToCursorPosition(), options: options)
            candidates = Array(result.mainResults.prefix(40))
        }
        if let i = selected {
            output?.setMarked(candidates[i].text, cursor: candidates[i].text.count)
        } else {
            output?.setMarked(text.convertTarget, cursor: text.convertTargetCursorPosition)
        }
    }
}
