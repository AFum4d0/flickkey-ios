import SwiftUI

/// 押している間くり返し消す。左へなぞると、なぞった分をまとめて消す（離したときに消す）。
struct DeleteKey: View {
    @ObservedObject var engine: InputEngine
    @State private var task: Task<Void, Never>? = nil
    @State private var down = false
    /// 左へなぞっている間の、消す予定の文字数。nil ならなぞっていない
    @State private var count: Int? = nil

    var body: some View {
        KeyFace(symbol: count == nil ? "delete.left" : nil, text: count.map { "−\($0)" },
                fill: down ? Theme.pressed : Theme.functionKey)
            .frame(height: Theme.keyHeight)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        if !down {
                            down = true
                            engine.backspace()
                            task = Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 400_000_000)
                                while !Task.isCancelled {
                                    engine.backspace()
                                    try? await Task.sleep(nanoseconds: 70_000_000)
                                }
                            }
                        }
                        // 押した時に 1 文字消えている。なぞった分はその先から 12pt ごとに 1 文字
                        if v.translation.width < -20 {
                            task?.cancel()
                            count = min(Int(-v.translation.width - 20) / 12, engine.deletableCount)
                        } else if count != nil {
                            count = 0
                        }
                    }
                    .onEnded { _ in
                        task?.cancel(); task = nil
                        if let count, count > 0 { engine.deleteBackward(count: count) }
                        count = nil; down = false
                    }
            )
            .accessibilityElement()
            .accessibilityLabel("削除")
            .accessibilityIdentifier("backspace")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { engine.backspace() }
    }
}

/// キーの代わりに出す絵文字・記号・顔文字の一覧。下の列でタブを選ぶ。
struct EmojiPanel: View {
    @ObservedObject var engine: InputEngine
    @State private var tab: String? = nil

    private var tabs: [SymbolTab] {
        let recent = SymbolTab(id: "最近", icon: "🕘", items: engine.recentSymbols)
        return (engine.recentSymbols.isEmpty ? [] : [recent]) + Symbols.tabs
    }

    var body: some View {
        let tabs = tabs
        let current = tabs.first { $0.id == tab } ?? tabs.first
        VStack(spacing: Theme.gap) {
            ScrollView {
                if let current {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: current.wide ? 96 : 42), spacing: 2)], spacing: 2) {
                        ForEach(Array(current.items.enumerated()), id: \.offset) { i, s in
                            Button { engine.insertSymbol(s) } label: {
                                Text(s)
                                    .font(.system(size: current.wide ? 16 : 28))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                                    .frame(maxWidth: .infinity, minHeight: 42)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(PressStyle())
                            .accessibilityIdentifier("symbol-\(i)")
                        }
                    }
                }
            }
            .id(current?.id)  // タブを替えたら先頭から見せる

            HStack(spacing: 2) {
                Button { engine.toggle(.emoji) } label: {
                    KeyFace(symbol: "keyboard", fill: Theme.functionKey).frame(width: 52, height: Theme.keyHeight)
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("キーボードに戻る")
                .accessibilityIdentifier("panel-close")

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        ForEach(tabs) { t in
                            Button { tab = t.id } label: {
                                Text(t.icon)
                                    .font(.system(size: t.wide ? 13 : 20))
                                    .frame(minWidth: 40, minHeight: 40)
                                    .padding(.horizontal, t.wide ? 4 : 0)
                                    .background(t.id == current?.id ? Theme.key : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(t.id)
                            .accessibilityAddTraits(t.id == current?.id ? .isSelected : [])
                        }
                    }
                }

                DeleteKey(engine: engine).frame(width: 52, height: Theme.keyHeight)
            }
            .frame(height: Theme.keyHeight)
        }
    }
}

/// キーの代わりに出す設定。変えるとすぐキーボードに反映される。
struct SettingsPanel: View {
    @ObservedObject var engine: InputEngine
    @ObservedObject private var settings = KeyboardSettings.shared

    var body: some View {
        VStack(spacing: 14) {
            row("キーの高さ") {
                Picker("キーの高さ", selection: $settings.keySize) {
                    Text("低い").tag(KeyboardSettings.Size.small)
                    Text("標準").tag(KeyboardSettings.Size.regular)
                    Text("高い").tag(KeyboardSettings.Size.large)
                }
            }
            row("フリックの距離") {
                Picker("フリックの距離", selection: $settings.flick) {
                    Text("短い").tag(KeyboardSettings.Flick.short)
                    Text("標準").tag(KeyboardSettings.Flick.regular)
                    Text("長い").tag(KeyboardSettings.Flick.long)
                }
            }
            Toggle("打鍵音", isOn: $settings.sound)
                .accessibilityIdentifier("setting-sound")
            Spacer(minLength: 0)
            Button { engine.toggle(.settings) } label: {
                KeyFace(text: "完了", fill: Theme.accent, foreground: .white).frame(height: Theme.keyHeight)
            }
            .buttonStyle(PressStyle())
            .accessibilityIdentifier("panel-close")
        }
        .pickerStyle(.segmented)
        .font(.system(size: 15))
        .tint(Theme.accent)
        .padding(.horizontal, 10)
        .padding(.top, 6)
    }

    private func row(_ title: String, @ViewBuilder _ control: () -> some View) -> some View {
        HStack {
            Text(title)
            Spacer()
            control().frame(width: 190)
        }
    }
}
