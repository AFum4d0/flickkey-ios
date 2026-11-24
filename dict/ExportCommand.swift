// CI で AzooKeyKanaKanjiConverter の Sources/CliTool/Subcommands/DictCommands/ に写して使う。
// 辞書の全項目を dict build が読む形（読み TAB 表記 TAB lcid TAB rcid TAB mid TAB 値）で書き出す。
import ArgumentParser
import Foundation
import KanaKanjiConverterModule

extension Subcommands.Dict {
    struct Export: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "export", abstract: "Export all entries as worddict tsv files.")

        @Option(name: [.customLong("dictionary_dir"), .customShort("d")], help: "Dictionary directory (contains louds/).")
        var dictionaryDirectory: String

        @Option(name: [.customLong("out")], help: "Output directory for <first char>.tsv files.")
        var out: String

        mutating func run() throws {
            let dictionaryURL = URL(fileURLWithPath: dictionaryDirectory, isDirectory: true)
            let outURL = URL(fileURLWithPath: out, isDirectory: true)
            try FileManager.default.createDirectory(at: outURL, withIntermediateDirectories: true)
            let store = DicdataStore(dictionaryURL: dictionaryURL)
            let state = store.prepareState()
            var total = 0
            for target in Build.targetChars {
                guard let louds = LOUDS.load(Self.escaped(target), dictionaryURL: dictionaryURL) else {
                    print("no louds for \(target)")
                    continue
                }
                let indices = louds.prefixNodeIndices(chars: [], maxDepth: .max, maxCount: .max)
                let entries = store.getDicdataFromLoudstxt3(identifier: target, indices: indices, state: state)
                let lines = entries.map { "\($0.ruby)\t\($0.word)\t\($0.lcid)\t\($0.rcid)\t\($0.mid)\t\($0.value())" }
                try (lines.joined(separator: "\n") + "\n").write(
                    to: outURL.appendingPathComponent("\(target).tsv"), atomically: true, encoding: .utf8)
                total += entries.count
            }
            print("exported \(total) entries")
        }

        /// DictionaryBuilder.escapedIdentifier と同じ（あちらは internal なので写した）。「カ」→「[30AB]」
        static func escaped(_ s: String) -> String {
            "[" + s.utf16.map { String(format: "%04X", $0) }.joined(separator: "_") + "]"
        }
    }
}
