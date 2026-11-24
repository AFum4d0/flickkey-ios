"""evaluate コマンドの出力から、1 位正解率・3 位以内正解率を文脈あり/なし別に出す。"""
import json
import sys

name, path = sys.argv[1], sys.argv[2]
data = json.load(open(path, encoding="utf-8"))
items = data["result"] if isinstance(data, dict) and "result" in data else data
def rate(xs, k):
    return sum(1 for x in xs if 0 <= x["max_rank"] < k) / max(len(xs), 1)
ctx = [x for x in items if x.get("left_context")]
noctx = [x for x in items if not x.get("left_context")]
row = f"| {name} | {rate(items,1):.1%} | {rate(items,3):.1%} | {rate(ctx,1):.1%} | {rate(noctx,1):.1%} |"
print(row)
with open("scores.md", "a", encoding="utf-8") as f:
    f.write(row + "\n")
