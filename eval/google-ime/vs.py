"""evaluate の出力（r*.json）と Google 日本語入力の結果を 1 問ずつ比べる。

使い方: python vs.py <r.json> [<r.json> ...]
r.json の items は AJIMEE-Bench の evaluation_items.json と同じ順に並んでいる。
"""
import json
import sys
from pathlib import Path

google = json.load(open(Path(__file__).with_name("results-2026-11-24.json"), encoding="utf-8"))
g = [r["ok"] for r in google]
print(f"Google 日本語入力: 1 位 {sum(g)}/200")
for path in sys.argv[1:]:
    ours = [0 == x["max_rank"] for x in json.load(open(path, encoding="utf-8"))["items"]]
    assert len(ours) == len(g) == 200
    only_g = sum(a and not b for a, b in zip(g, ours))
    only_o = sum(b and not a for a, b in zip(g, ours))
    print(f"{path}: 1 位 {sum(ours)}/200  Google だけ正解 {only_g} / こちらだけ正解 {only_o}")
