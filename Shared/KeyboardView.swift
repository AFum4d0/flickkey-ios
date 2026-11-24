import SwiftUI
import UIKit

enum Theme {
    static let background = dynamic(0xE8EAED, 0x1E2023)
    static let key = dynamic(0xFFFFFF, 0x3B3E43)
    static let functionKey = dynamic(0xCBD0D6, 0x2A2D31)
    static let pressed = dynamic(0xB4BAC2, 0x55595F)
    static let accent = dynamic(0x2F7D6D, 0x4DB39B)
    static let popup = dynamic(0xFFFFFF, 0x4A4E54)

    static let keyHeight: CGFloat = 50
    static let gap: CGFloat = 6
    static let barHeight: CGFloat = 42
    static var totalHeight: CGFloat { barHeight + keyHeight * 4 + gap * 5 }

    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? rgb(dark) : rgb(light) })
    }

    private static func rgb(_ v: UInt32) -> UIColor {
        UIColor(red: CGFloat(v >> 16 & 0xFF) / 255, green: CGFloat(v >> 8 & 0xFF) / 255,
                blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}

struct KeyboardView: View {
    @ObservedObject var engine: InputEngine
    /// ホームボタンのある iPhone では地球儀キーが必要（needsInputModeSwitchKey）。
    var onGlobe: (() -> Void)?

    var body: some View {
        VStack(spacing: Theme.gap) {
            CandidateBar(engine: engine)
            Group {
                switch engine.mode {
                case .kana: TwelveKeyPad(engine: engine, rows: Layouts.kana, onGlobe: onGlobe)
                case .number: TwelveKeyPad(engine: engine, rows: Layouts.number, onGlobe: onGlobe)
                case .qwerty: QwertyPad(engine: engine, onGlobe: onGlobe)
                }
            }
            .padding(.horizontal, Theme.gap / 2)
        }
        .padding(.bottom, Theme.gap)
        .frame(height: Theme.totalHeight)
        .background(Theme.background)
    }
}

// MARK: 候補

struct CandidateBar: View {
    @ObservedObject var engine: InputEngine

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(Array(engine.candidates.enumerated()), id: \.offset) { i, c in
                        Button { engine.choose(c) } label: {
                            Text(c.text)
                                .font(.system(size: 18))
                                .foregroundStyle(i == engine.selected ? Color.white : Color.primary)
                                .padding(.horizontal, 12)
                                .frame(height: Theme.barHeight - 8)
                                .background(i == engine.selected ? Theme.accent : Color.clear,
                                            in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .id(i)
                        .accessibilityIdentifier("candidate-\(i)")
                    }
                }
                .padding(.horizontal, 6)
            }
            .onChange(of: engine.selected) { i in
                if let i { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(i, anchor: .center) } }
            }
        }
        .frame(height: Theme.barHeight)
    }
}

// MARK: 12 キー（かな・数字）

struct TwelveKeyPad: View {
    @ObservedObject var engine: InputEngine
    let rows: [[FlickKey?]]
    var onGlobe: (() -> Void)?
    @State private var pressed: FlickKey?

    var body: some View {
        GeometryReader { g in pad(unit: (g.size.width - Theme.gap * 4) / 5) }
            .frame(height: Theme.keyHeight * 4 + Theme.gap * 3)
    }

    /// 5 列（左 1・中央 3・右 1）を同じ幅にする。
    private func pad(unit: CGFloat) -> some View {
        HStack(spacing: Theme.gap) {
            VStack(spacing: Theme.gap) {
                FunctionKey(symbol: "arrow.uturn.backward", label: "戻す", id: "reverse") { engine.reverseToggle() }
                RepeatKey(symbol: "arrowtriangle.left.fill", label: "左へ", id: "left") { engine.moveCursor(-1) }
                if let onGlobe {
                    FunctionKey(symbol: "globe", label: "次のキーボード", id: "globe", action: onGlobe)
                }
                ModeKey(engine: engine)
                    .frame(height: onGlobe == nil ? Theme.keyHeight * 2 + Theme.gap : Theme.keyHeight)
            }
            .frame(width: unit)

            VStack(spacing: Theme.gap) {
                ForEach(rows.indices, id: \.self) { r in
                    HStack(spacing: Theme.gap) {
                        ForEach(rows[r].indices, id: \.self) { c in
                            if let key = rows[r][c] {
                                FlickKeyView(key: key, showHints: engine.mode == .number, pressed: $pressed) {
                                    engine.flick(key, $0)
                                }
                                .zIndex(pressed == key ? 1 : 0)
                            } else {
                                FunctionKey(text: Layouts.modifierLabel, label: "濁点・小文字", id: "modifier") { engine.modify() }
                            }
                        }
                    }
                    .zIndex(pressed != nil && rows[r].contains(pressed) ? 1 : 0)
                }
            }
            .frame(width: unit * 3 + Theme.gap * 2)
            .zIndex(1)

            VStack(spacing: Theme.gap) {
                RepeatKey(symbol: "delete.left", label: "削除", id: "backspace") { engine.backspace() }
                RepeatKey(symbol: "arrowtriangle.right.fill", label: "右へ", id: "right") { engine.moveCursor(1) }
                SpaceKey(engine: engine, title: engine.isComposing ? "変換" : "空白")
                EnterKey(engine: engine)
            }
            .frame(width: unit)
        }
    }
}

/// 押すと周りにフリック先を出す。離した方向の文字を入れる。
struct FlickKeyView: View {
    let key: FlickKey
    let showHints: Bool
    @Binding var pressed: FlickKey?
    let action: (FlickDirection) -> Void
    @State private var direction: FlickDirection = .tap

    var body: some View {
        let active = pressed == key
        VStack(spacing: 0) {
            Text(key.label).font(.system(size: 22))
            if showHints {
                Text(key.chars.dropFirst().joined()).font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: Theme.keyHeight, maxHeight: Theme.keyHeight)
        .background(active ? Theme.pressed : Theme.key, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            if active {
                GeometryReader { g in FlickGuide(key: key, direction: direction, cell: g.size) }
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged {
                    pressed = key
                    direction = .from(dx: $0.translation.width, dy: $0.translation.height)
                }
                .onEnded {
                    action(.from(dx: $0.translation.width, dy: $0.translation.height))
                    pressed = nil
                    direction = .tap
                }
        )
        .accessibilityElement()
        .accessibilityLabel(key.label)
        .accessibilityIdentifier("key-\(key.label)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action(.tap) }
    }
}

/// キーを中心に十字に並べたフリック先。選んでいる方向を塗る。
struct FlickGuide: View {
    let key: FlickKey
    let direction: FlickDirection
    let cell: CGSize

    var body: some View {
        let offsets: [FlickDirection: CGSize] = [
            .tap: .zero, .left: CGSize(width: -cell.width, height: 0), .up: CGSize(width: 0, height: -cell.height),
            .right: CGSize(width: cell.width, height: 0), .down: CGSize(width: 0, height: cell.height),
        ]
        ZStack {
            ForEach(FlickDirection.allCases, id: \.self) { d in
                if let s = key.char(d) {
                    Text(s)
                        .font(.system(size: 24, weight: d == direction ? .semibold : .regular))
                        .foregroundStyle(d == direction ? Color.white : Color.primary)
                        .frame(width: cell.width, height: cell.height)
                        .background(d == direction ? Theme.accent : Theme.popup, in: RoundedRectangle(cornerRadius: 8))
                        .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
                        .offset(offsets[d]!)
                        .zIndex(d == direction ? 1 : 0)
                }
            }
        }
        .frame(width: cell.width, height: cell.height)
    }
}

// MARK: QWERTY

struct QwertyPad: View {
    @ObservedObject var engine: InputEngine
    var onGlobe: (() -> Void)?

    var body: some View {
        VStack(spacing: Theme.gap) {
            row(Layouts.qwerty[0])
            row(Layouts.qwerty[1]).padding(.horizontal, 16)
            HStack(spacing: Theme.gap) {
                FunctionKey(symbol: engine.shift ? "shift.fill" : "shift", label: "シフト", id: "shift") { engine.shift.toggle() }
                    .frame(width: 44)
                row(Layouts.qwerty[2])
                RepeatKey(symbol: "delete.left", label: "削除", id: "backspace") { engine.backspace() }
                    .frame(width: 44)
            }
            HStack(spacing: Theme.gap) {
                ModeKey(engine: engine).frame(width: 52)
                if let onGlobe {
                    FunctionKey(symbol: "globe", label: "次のキーボード", id: "globe", action: onGlobe).frame(width: 44)
                }
                SpaceKey(engine: engine, title: "space")
                LetterKey(text: ".", engine: engine).frame(width: 40)
                EnterKey(engine: engine).frame(width: 72)
            }
        }
    }

    private func row(_ letters: [String]) -> some View {
        HStack(spacing: 4) {
            ForEach(letters, id: \.self) { LetterKey(text: engine.shift ? $0.uppercased() : $0, engine: engine) }
        }
    }
}

struct LetterKey: View {
    let text: String
    @ObservedObject var engine: InputEngine
    @GestureState private var down = false

    var body: some View {
        Text(text)
            .font(.system(size: 22))
            .frame(maxWidth: .infinity, minHeight: Theme.keyHeight, maxHeight: Theme.keyHeight)
            .background(down ? Theme.pressed : Theme.key, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).updating($down) { _, s, _ in s = true }
                .onEnded { _ in engine.letter(text.lowercased()) })
            .accessibilityElement()
            .accessibilityLabel(text)
            .accessibilityIdentifier("key-\(text)")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { engine.letter(text.lowercased()) }
    }
}

// MARK: 機能キー

struct FunctionKey: View {
    var symbol: String?
    var text: String?
    let label: String
    let id: String
    var tint: Color = Theme.functionKey
    let action: () -> Void

    init(symbol: String? = nil, text: String? = nil, label: String, id: String,
         tint: Color = Theme.functionKey, action: @escaping () -> Void) {
        self.symbol = symbol; self.text = text; self.label = label; self.id = id; self.tint = tint; self.action = action
    }

    var body: some View {
        Button(action: action) {
            KeyFace(symbol: symbol, text: text, fill: tint)
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }
}

struct KeyFace: View {
    var symbol: String?
    var text: String?
    var fill: Color
    var foreground: Color = .primary

    var body: some View {
        Group {
            if let symbol { Image(systemName: symbol).font(.system(size: 18)) }
            else { Text(text ?? "").font(.system(size: 16)) }
        }
        .foregroundStyle(foreground)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minHeight: Theme.keyHeight)
        .background(fill, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// 押している間くり返す（削除・カーソル）。
struct RepeatKey: View {
    let symbol: String
    let label: String
    let id: String
    let action: () -> Void
    @State private var task: Task<Void, Never>?

    var body: some View {
        KeyFace(symbol: symbol, fill: task == nil ? Theme.functionKey : Theme.pressed)
            .frame(height: Theme.keyHeight)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard task == nil else { return }
                        action()
                        task = Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 400_000_000)
                            while !Task.isCancelled {
                                action()
                                try? await Task.sleep(nanoseconds: 70_000_000)
                            }
                        }
                    }
                    .onEnded { _ in task?.cancel(); task = nil }
            )
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityIdentifier(id)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
    }
}

/// タップで空白（入力中なら変換）。左右になぞるとカーソルが動く。
struct SpaceKey: View {
    @ObservedObject var engine: InputEngine
    let title: String
    @State private var steps = 0
    @State private var swiping = false
    @State private var down = false

    var body: some View {
        KeyFace(text: title, fill: down ? Theme.pressed : Theme.key)
            .frame(height: Theme.keyHeight)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        down = true
                        let s = Int(v.translation.width / 14)
                        if s != steps {
                            engine.moveCursor(s - steps)
                            steps = s
                            swiping = true
                        }
                    }
                    .onEnded { _ in
                        if !swiping { engine.space() }
                        steps = 0; swiping = false; down = false
                    }
            )
            .accessibilityElement()
            .accessibilityLabel(title)
            .accessibilityIdentifier("space")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { engine.space() }
    }
}

struct EnterKey: View {
    @ObservedObject var engine: InputEngine

    var body: some View {
        Button { engine.enter() } label: {
            KeyFace(symbol: engine.isComposing ? nil : "return", text: "確定", fill: Theme.accent, foreground: .white)
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(engine.isComposing ? "確定" : "改行")
        .accessibilityIdentifier("enter")
    }
}

/// かな → ABC → 123 と切り替える。今のモードを太字で見せる。
struct ModeKey: View {
    @ObservedObject var engine: InputEngine

    var body: some View {
        Button { engine.switchMode() } label: {
            HStack(spacing: 1) {
                part("あ", .kana); part("a", .qwerty); part("1", .number)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(minHeight: Theme.keyHeight)
            .background(Theme.functionKey, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("入力切り替え")
        .accessibilityIdentifier("mode")
    }

    private func part(_ s: String, _ m: KeyboardMode) -> some View {
        Text(s)
            .font(.system(size: engine.mode == m ? 17 : 12, weight: engine.mode == m ? .bold : .regular))
            .foregroundStyle(engine.mode == m ? Color.primary : Color.secondary)
    }
}
