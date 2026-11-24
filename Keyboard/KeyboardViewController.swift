import SwiftUI
import UIKit

final class KeyboardViewController: UIInputViewController, TextOutput {
    private let engine = InputEngine()
    private var host: UIHostingController<KeyboardView>?
    private var hasMarked = false

    override func viewDidLoad() {
        super.viewDidLoad()
        engine.output = self
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
        host.didMove(toParent: self)
        self.host = host
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
}
