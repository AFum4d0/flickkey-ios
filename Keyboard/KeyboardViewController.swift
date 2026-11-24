import Combine
import SwiftUI
import UIKit

/// 打鍵音（playInputClick）を鳴らすには、キーボードの view がこれに従っている必要がある。
final class ClickInputView: UIInputView, UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool { true }
}

final class KeyboardViewController: UIInputViewController, TextOutput {
    private let engine = InputEngine()
    private var host: UIHostingController<KeyboardView>?
    private var hasMarked = false
    private var height: NSLayoutConstraint?
    private var lastKeyboardType: UIKeyboardType?
    private var bag: Set<AnyCancellable> = []

    override func loadView() {
        view = ClickInputView(frame: .zero, inputViewStyle: .keyboard)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        engine.output = self
        // 端末の「キーボードのクリック音」がオフなら、playInputClick は鳴らない
        engine.onKey = { if KeyboardSettings.shared.sound { UIDevice.current.playInputClick() } }
        let host = UIHostingController(rootView: KeyboardView(engine: engine))
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(host)
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        let height = view.heightAnchor.constraint(equalToConstant: Theme.totalHeight)
        height.priority = .defaultHigh + 1
        height.isActive = true
        self.height = height
        host.didMove(toParent: self)
        self.host = host
        // 設定でキーの高さを変えたら、キーボード全体の高さも合わせる
        KeyboardSettings.shared.$keySize.dropFirst().receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.height?.constant = Theme.totalHeight }
            .store(in: &bag)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applyFieldTraits(force: true)
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        applyFieldTraits(force: false)
    }

    /// 入力欄の種類に合わせる。モードは欄が替わったときだけ決め直す（打っている途中で勝手に変えない）。
    private func applyFieldTraits(force: Bool) {
        let p = textDocumentProxy
        if force || p.keyboardType != lastKeyboardType {
            lastKeyboardType = p.keyboardType
            engine.autoCapitalize = (p.autocapitalizationType ?? .sentences) != .none
            engine.start(keyboardType: p.keyboardType)
        }
        engine.returnLabel = Self.returnLabel(p.returnKeyType)
        if !engine.isComposing { engine.updateAutoShift() }
    }

    static func returnLabel(_ t: UIReturnKeyType?) -> String? {
        switch t {
        case .go: return "開く"
        case .google, .yahoo, .search: return "検索"
        case .join: return "参加"
        case .next: return "次へ"
        case .route: return "経路"
        case .send: return "送信"
        case .done: return "完了"
        case .continue: return "続ける"
        case .emergencyCall: return "緊急電話"
        default: return nil
        }
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        // needsInputModeSwitchKey はここで正しい値になる
        let onGlobe: (() -> Void)? = needsInputModeSwitchKey ? { [weak self] in self?.advanceToNextInputMode() } : nil
        if (host?.rootView.onGlobe == nil) != (onGlobe == nil) {
            host?.rootView = KeyboardView(engine: engine, onGlobe: onGlobe)
        }
    }

    // MARK: TextOutput

    func setMarked(_ text: String, cursor: Int) {
        let proxy = textDocumentProxy
        if text.isEmpty {
            if hasMarked {
                proxy.setMarkedText("", selectedRange: NSRange(location: 0, length: 0))
                proxy.unmarkText()
                hasMarked = false
            }
            return
        }
        let location = text.prefix(cursor).utf16.count
        proxy.setMarkedText(text, selectedRange: NSRange(location: location, length: 0))
        hasMarked = true
    }

    func commit(_ text: String) {
        let proxy = textDocumentProxy
        if hasMarked {
            proxy.setMarkedText(text, selectedRange: NSRange(location: text.utf16.count, length: 0))
            proxy.unmarkText()
            hasMarked = false
        } else {
            proxy.insertText(text)
        }
    }

    func deleteBackward() { textDocumentProxy.deleteBackward() }

    func moveCursor(by offset: Int) { textDocumentProxy.adjustTextPosition(byCharacterOffset: offset) }

    var contextBefore: String { textDocumentProxy.documentContextBeforeInput ?? "" }
}
