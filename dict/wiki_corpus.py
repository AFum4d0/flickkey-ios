"""WikiExtractor の出力（標準入力）から、n-gram の学習に使う文を 1 行 1 文で書き出す。

使い方: python -m wikiextractor.WikiExtractor <dump.bz2> -o - -q | python wiki_corpus.py <out.txt> <上限MB>
"""
import re
import sys
import unicodedata

out_path, limit = sys.argv[1], int(sys.argv[2]) * 1_000_000
written = 0
skip_title = False
kana_or_kanji = re.compile(r"[\u3040-\u30ff\u4e00-\u9fff]")

with open(out_path, "w", encoding="utf-8") as out:
    for line in sys.stdin:
        if line.startswith("<doc"):
            skip_title = True  # 次の行は記事名
            continue
        if line.startswith("</doc>") or skip_title:
            skip_title = False
            continue
        line = unicodedata.normalize("NFKC", line.strip())
        for s in line.split("。"):
            s = s.strip()
            # 短すぎる・長すぎる・日本語の少ない行（表や英文）は外す
            if not 8 <= len(s) <= 150 or len(kana_or_kanji.findall(s)) < len(s) * 0.5:
                continue
            s += "。"
            out.write(s + "\n")
            written += len(s.encode("utf-8")) + 1
            if written >= limit:
                print(f"{written / 1e6:.0f} MB written", file=sys.stderr)
                sys.exit(0)
print(f"{written / 1e6:.0f} MB written (dump ended)", file=sys.stderr)
