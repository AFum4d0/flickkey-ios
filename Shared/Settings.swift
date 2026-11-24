import Foundation

/// キーボードの中の設定画面で変える値。キーボード拡張の UserDefaults に置く
/// （フルアクセスなしではアプリと共有できないので、アプリ側には設定画面を置かない）。
@MainActor
final class KeyboardSettings: ObservableObject {
    static let shared = KeyboardSettings()
    private let defaults = UserDefaults.standard

    enum Size: Int, CaseIterable { case small = 44, regular = 50, large = 56 }
    enum Flick: Int, CaseIterable { case short = 14, regular = 22, long = 32 }

    @Published var keySize: Size { didSet { defaults.set(keySize.rawValue, forKey: "keySize") } }
    /// これだけ指を動かしたらフリックとみなす（pt）。
    @Published var flick: Flick { didSet { defaults.set(flick.rawValue, forKey: "flick") } }
    @Published var sound: Bool { didSet { defaults.set(sound, forKey: "sound") } }

    private init() {
        keySize = Size(rawValue: defaults.integer(forKey: "keySize")) ?? .regular
        flick = Flick(rawValue: defaults.integer(forKey: "flick")) ?? .regular
        sound = defaults.object(forKey: "sound") as? Bool ?? true
    }
}
