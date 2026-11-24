import SwiftUI
import UIKit

@main
struct FlickKeyApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

/// アプリ内の試し打ち用。キーボードと同じ InputEngine を文字列につなぐ。
@MainActor
final class DemoOutput: ObservableObject, TextOutput {
    @Published private(set) var chars: [Character] = []
    @Published private(set) var cursor = 0
    @Published private(set) var marked = ""
    private var markedCursor = 0

    var text: String { String(chars) }

    func setMarked(_ text: String, cursor: Int) {
        marked = text
        markedCursor = cursor
    }

    func commit(_ text: String) {
        marked = ""
        chars.insert(contentsOf: Array(text), at: cursor)
        cursor += text.count
    }

    func deleteBackward() {
        guard cursor > 0 else { return }
        chars.remove(at: cursor - 1)
        cursor -= 1
    }

    func moveCursor(by offset: Int) {
        cursor = min(max(cursor + offset, 0), chars.count)
    }

    var contextBefore: String { String(chars[..<cursor]) }

    /// 前 + 入力中（下線） + 後。カーソルは縦線で見せる。
    var display: AttributedString {
        var before = AttributedString(String(chars[..<cursor]))
        var m = AttributedString(marked)
        m.underlineStyle = .single
        let after = AttributedString(String(chars[cursor...]))
        before.append(m)
        if marked.isEmpty { before.append(AttributedString("|")) }
        before.append(after)
        return before
    }
}

struct ContentView: View {
    @StateObject private var engine = InputEngine()
    @StateObject private var demo = DemoOutput()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("フリックキー").font(.largeTitle.bold())
            // 「設定を開く」で出るのはこのアプリ自身の設定画面。そこから先の道順だけを書く
            step(1) {
                Button("設定を開く") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .buttonStyle(.borderedProminent)
            }
            step(2) { Text("「キーボード」で「フリックキー」をオンにする") }

            Text(demo.display)
                .font(.title3)
                .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                .padding(12)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("demo-text")
                .accessibilityValue(demo.text + demo.marked)
            Spacer()
        }
        .padding()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            KeyboardView(engine: engine)
        }
        .tint(Theme.accent)
        .onAppear { engine.output = demo }
    }

    private func step(_ n: Int, @ViewBuilder _ content: () -> some View) -> some View {
        HStack(spacing: 12) {
            Text("\(n)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Theme.accent, in: Circle())
                .accessibilityHidden(true)
            content()
        }
    }
}
