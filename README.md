# フリックキー

Android 版 Gboard のような操作の iPhone 用日本語キーボードです。かな漢字変換には [AzooKeyKanaKanjiConverter](https://github.com/azooKey/AzooKeyKanaKanjiConverter) を使っています。

## できること

- かな：12 キー。フリック入力とケータイ入力（同じキーを続けて押す）の両方が使えます。↶ でケータイ入力を 1 つ戻し、小゛゜ で濁点・半濁点・小文字に変えます。
- 英字：QWERTY。シフトは 1 文字だけ大文字になります。
- 数字：テンキー。フリックで記号も入ります。
- 変換：入力中は候補が上に並びます。空白キー（変換）を押すと次の候補に進み、改行キー（確定）で確定します。
- カーソル：◀ ▶ か、空白キーを左右になぞって動かします。入力中に動かすと、カーソルより前の部分だけを変換します。
- もしかして：入力中の文字のどこかを打ち間違えた（同じキーの別の方向や、となりのキーを押した）とみられるとき、直した変換を候補の列の先頭に出します。明らかな誤字なら候補の 1 番目に入るので、変換キー 1 回で直ります。
- 次の語：確定した直後に、次に来そうな語を候補の列に出します。
- Zenzai：カーソルより前の文を見て変換を選ぶ、小さな言語モデル（zenz-v3.2-xsmall）を使います。

## 辞書

azooKey の辞書（約 57 万語）に、mozc-ut の 6 つの辞書から約 236 万語を足して、約 288 万語にしています。作り直しは `dictionary` ワークフロー（`dict/`）で行い、できた辞書は Release「dictionary」に置きます。アプリのビルドは、そこから辞書を取ってくる作りです。

## 開発の流れ（Mac なし）

Windows でコードを書いて push すると、GitHub Actions の macOS で次のことが行われます（`.github/workflows/build.yml`）。

1. XcodeGen で `project.yml` から Xcode プロジェクトを作る
2. シミュレーターで単体テストと UI テストを流す
3. 実機向けに署名なしでビルドする

UI テストで撮った画面は、実行結果の Artifacts にある `screenshots` に入ります。

## iPhone に入れる（Apple Developer Program の登録後）

1. developer.apple.com で Developer Program に登録する（年 12,980 円）
2. App Store Connect で次を用意する
   - アプリ（Bundle ID は自分のものにする。例：`io.github.<ユーザー名>.flickkey`）
   - API キー（ユーザーとアクセス → 統合 → App Store Connect API、役割は「Admin」）
3. GitHub のリポジトリの Settings → Secrets and variables → Actions に次を登録する

   | 名前 | 中身 |
   |---|---|
   | `ASC_KEY_ID` | API キーの ID |
   | `ASC_ISSUER_ID` | Issuer ID |
   | `ASC_KEY_P8` | ダウンロードした `.p8` ファイルの中身 |
   | `TEAM_ID` | チーム ID |
   | `BUNDLE_ID` | 2 で決めた Bundle ID |

4. Actions → testflight → Run workflow で TestFlight に送る（このワークフローはまだ一度も動かしていません）
5. iPhone の TestFlight アプリから入れ、設定 → 一般 → キーボード → キーボード → 新しいキーボードを追加 → フリックキー を選ぶ

## まだないもの

- 絵文字・記号の一覧
- 英字の予測変換、キャプスロック
- 削除キーをなぞってまとめて消す操作
- 打鍵時の振動と音（「フルアクセスを許可」が必要になるため）
- 設定画面（キーの高さ・テーマなど）

## 使っているデータとライセンス

| データ | ライセンス |
|---|---|
| [AzooKeyKanaKanjiConverter](https://github.com/azooKey/AzooKeyKanaKanjiConverter) とその辞書 | MIT |
| [mozcdic-ut-jawiki](https://github.com/utuhiro78/mozcdic-ut-jawiki)（Wikipedia の見出し語） | CC BY-SA |
| [mozcdic-ut-neologd](https://github.com/utuhiro78/mozcdic-ut-neologd) | Apache 2.0 |
| [mozcdic-ut-sudachidict](https://github.com/utuhiro78/mozcdic-ut-sudachidict) | Apache 2.0 |
| [mozcdic-ut-personal-names](https://github.com/utuhiro78/mozcdic-ut-personal-names) | Apache 2.0 |
| [mozcdic-ut-place-names](https://github.com/utuhiro78/mozcdic-ut-place-names)（日本郵便の郵便番号データ） | パブリックドメイン |
| [mozcdic-ut-edict2](https://github.com/utuhiro78/mozcdic-ut-edict2) | CC BY-SA 4.0 |
| [zenz-v3.2-xsmall](https://huggingface.co/Miwa-Keita/zenz-v3.2-xsmall-gguf) | CC BY-SA 4.0 |
| [AJIMEE-Bench](https://github.com/azooKey/AJIMEE-Bench)（評価だけに使う） | CC BY-SA 3.0 |
| 日本語版 Wikipedia の本文（n-gram の材料） | CC BY-SA 4.0 |

辞書とモデルは CC BY-SA を含むので、配るときはこの表のように出どころを示します。
