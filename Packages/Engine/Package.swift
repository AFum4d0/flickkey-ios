// swift-tools-version: 6.1
// 変換エンジンを Zenzai トレイトつきで取り込むためだけのパッケージ（Xcode のプロジェクトからはトレイトを指定しにくい）。
import PackageDescription

let package = Package(
    name: "Engine",
    platforms: [.iOS(.v16)],
    products: [.library(name: "Engine", type: .dynamic, targets: ["Engine"])],
    dependencies: [
        .package(url: "https://github.com/azooKey/AzooKeyKanaKanjiConverter", exact: "0.11.2", traits: ["Zenzai"]),
    ],
    targets: [
        .target(
            name: "Engine",
            dependencies: [.product(name: "KanaKanjiConverterModule", package: "AzooKeyKanaKanjiConverter")],
            swiftSettings: [.interoperabilityMode(.Cxx)]
        ),
    ]
)
