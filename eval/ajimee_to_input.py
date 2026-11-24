"""AJIMEE-Bench の evaluation_items.json を、変換エンジンの evaluate コマンドの入力形式に直す。"""
import json
import sys

def to_hiragana(s: str) -> str:
    return "".join(chr(ord(c) - 0x60) if "ァ" <= c <= "ヶ" else c for c in s)

items = json.load(open(sys.argv[1], encoding="utf-8"))
out = [{
    "query": to_hiragana(it["input"]),
    "answer": it["expected_output"],
    "tag": ["context"] if it["context_text"] else ["no_context"],
    "left_context": it["context_text"] or None,
} for it in items]
json.dump(out, open(sys.argv[2], "w", encoding="utf-8"), ensure_ascii=False)
print(f"{len(out)} items")
