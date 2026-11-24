import Foundation
import KanaKanjiConverterModule

/// 文字の出し先。キーボードでは textDocumentProxy、アプリの試し打ち画面では文字列。
@MainActor
protocol TextOutput: AnyObject {
    /// 入力中の文字（下線つき）を置き換える。空文字なら消す。cursor は文字数。
    func setMarked(_ text: String, cursor: Int)
    /// 入力中の文字を text に置き換えて確定する。入力中の文字がなければそのまま挿入する。
    func commit(_ text: String)
    func deleteBackward()
    func moveCursor(by offset: Int)
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
    private let options: ConvertRequestOptions = {
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

    // MARK: キー

    func flick(_ key: FlickKey, _ d: FlickDirection) {
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
        selected = nil
        toggleKey = nil
        guard let last = text.convertTargetBeforeCursor.last, let n = KanaModifier.next(last) else { return }
        replaceLast(with: String(n))
    }

    func letter(_ s: String) {
        insertDirect(shift ? s.uppercased() : s)
        shift = false
    }

    func space() {
        toggleKey = nil
        guard isComposing, !candidates.isEmpty else {
            insertDirect(" ")
            return
        }
        selected = selected.map { ($0 + 1) % candidates.count } ?? 0
        render()
    }

    func enter() {
        toggleKey = nil
        if isComposing {
            commitAll()
        } else {
            output?.commit("\n")
        }
    }

    func backspace() {
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
    }

    func switchMode() {
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
        defer { composing = text.convertTarget }
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
