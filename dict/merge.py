"""azooKey の辞書（dict export の出力）に mozc-ut の語を足して、dict build が読む worddict を作る。

使い方: python merge.py <export_dir> <ut_dir> <out_dir> [--max N]
ut_dir には mozc-ut の展開済み txt（<名前>.txt）を置く。
"""
import argparse
import collections
import statistics
import sys
from pathlib import Path

# BuildCommand.char2UInt8 と同じ。これ以外の文字を読みに含む語は辞書に入れられない。
ALLOWED = set(
    "　￣‐―〜・、…‥。‘’“”〈〉《》「」『』【】〔〕‖*′〃※´¨゛゜←→↑↓─■□▲△▼▽◆◇○◎●★☆々ゝヽゞヾー〇Q"
    "ァアィイゥウヴェエォオヵカガキギクグヶケゲコゴサザシジ〆スズセゼソゾタダチヂッツヅテデトドナニヌネノ"
    "ハバパヒビピフブプヘベペホボポマミムメモャヤュユョヨラリルレロヮワヰヱヲン仝&A！0123456789？"
    "abcdefghijklmnopqrstuvwxyzBCDEFGHIJKLMNOPRSTUVWXYZ^_=ㇻ()#%'\"+-ㇼ"
)
# BuildCommand.targetChars と同じ。読みの 1 文字目がこの中にない語は、どのファイルにも入らない。
TARGETS = set(
    "￣‐―〜・、…‥。‘’“”〈〉《》「」『』【】〔〕‖*′〃※´¨゛゜←→↑↓─■□▲△▼▽◆◇○◎●★☆々ゝヽゞヾー〇"
    "ァアィイゥウヴェエォオヵカガキギクグヶケゲコゴサザシジ〆スズセゼソゾタダチヂッツヅテデトドナニヌネノ"
    "ハバパヒビピフブプヘベペホボポマミムメモヤユョヨラリルレロヮワヰヱヲン仝0123456789！？()#%&^_'\"=ㇻ"
)

CID = {"personal-names": 1289, "place-names": 1293}  # 人名一般・地名一般。ほかは固有名詞 1288
CID_DEFAULT = 1288
MID = 501  # MIDData.一般


def to_katakana(s: str) -> str:
    return "".join(chr(ord(c) + 0x60) if "ぁ" <= c <= "ゖ" else c for c in s)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("export_dir", type=Path)
    ap.add_argument("ut_dir", type=Path)
    ap.add_argument("out_dir", type=Path)
    ap.add_argument("--max", type=int, default=0, help="足す語数の上限（0 なら全部）")
    a = ap.parse_args()

    existing: dict[str, list[str]] = {}
    seen: set[tuple[str, str]] = set()
    proper_values = []
    for f in a.export_dir.glob("*.tsv"):
        lines = [l for l in f.read_text(encoding="utf-8").splitlines() if l]
        existing[f.stem] = lines
        for l in lines:
            ruby, word, lcid, _, _, value = l.split("\t")
            seen.add((ruby, word))
            if 1288 <= int(lcid) <= 1293:
                proper_values.append(float(value))
    base = statistics.median(proper_values)
    print(f"existing: {len(seen)} entries, proper-noun median value {base:.2f}")

    # (読み, 表記) → [載っている辞書の数, いちばん小さい cost, 品詞]
    new: dict[tuple[str, str], list] = {}
    skipped = collections.Counter()
    for f in sorted(a.ut_dir.glob("*.txt")):
        cid = CID.get(f.stem, CID_DEFAULT)
        for line in f.read_text(encoding="utf-8").splitlines():
            parts = line.split("\t")
            if len(parts) != 5:
                continue
            ruby, word, cost = to_katakana(parts[0]), parts[4], int(parts[3])
            if (ruby, word) in seen:
                skipped["already"] += 1
                continue
            if not ruby or len(ruby) > 40 or len(word) > 32 or not set(ruby) <= ALLOWED or ruby[0] not in TARGETS:
                skipped["chars"] += 1
                continue
            e = new.setdefault((ruby, word), [0, cost, cid])
            e[0] += 1
            e[1] = min(e[1], cost)
            if cid != CID_DEFAULT:
                e[2] = cid

    # 値は対数の出やすさ（大きいほど出やすい）。既存の固有名詞の真ん中より少し下に置き、
    # 載っている辞書が多いほど・cost が小さいほど上げる。読みが短い語は普通の文の変換に
    # 割り込みやすい（「ていしき」→鄭士琦）ので下げる。
    def score(ruby: str, sources: int, cost: int) -> float:
        return (base - 1.5 - min(max(cost - 8000, 0), 1000) / 1000 * 2.0 + 0.5 * (sources - 1)
                - max(0, 6 - len(ruby)) * 0.8)

    items = sorted(new.items(), key=lambda kv: -score(kv[0][0], kv[1][0], kv[1][1]))
    if a.max:
        items = items[: a.max]
    print(f"new: {len(items)} entries (skipped {dict(skipped)})")

    a.out_dir.mkdir(parents=True, exist_ok=True)
    added = collections.defaultdict(list)
    for (ruby, word), (sources, cost, cid) in items:
        added[ruby[0]].append(f"{ruby}\t{word}\t{cid}\t{cid}\t{MID}\t{score(ruby, sources, cost):.4f}")
    for key in set(existing) | set(added):
        lines = existing.get(key, []) + added.get(key, [])
        (a.out_dir / f"{key}.tsv").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"total: {len(seen) + len(items)} entries")


if __name__ == "__main__":
    sys.exit(main())
