import json
d=json.load(open('items.json',encoding='utf-8'))
base={'ア':'a','イ':'i','ウ':'u','エ':'e','オ':'o','カ':'ka','キ':'ki','ク':'ku','ケ':'ke','コ':'ko','サ':'sa','シ':'si','ス':'su','セ':'se','ソ':'so','タ':'ta','チ':'ti','ツ':'tu','テ':'te','ト':'to','ナ':'na','ニ':'ni','ヌ':'nu','ネ':'ne','ノ':'no','ハ':'ha','ヒ':'hi','フ':'hu','ヘ':'he','ホ':'ho','マ':'ma','ミ':'mi','ム':'mu','メ':'me','モ':'mo','ヤ':'ya','ユ':'yu','ヨ':'yo','ラ':'ra','リ':'ri','ル':'ru','レ':'re','ロ':'ro','ワ':'wa','ヲ':'wo','ン':'nn','ガ':'ga','ギ':'gi','グ':'gu','ゲ':'ge','ゴ':'go','ザ':'za','ジ':'zi','ズ':'zu','ゼ':'ze','ゾ':'zo','ダ':'da','ヂ':'di','ヅ':'du','デ':'de','ド':'do','バ':'ba','ビ':'bi','ブ':'bu','ベ':'be','ボ':'bo','パ':'pa','ピ':'pi','プ':'pu','ペ':'pe','ポ':'po','ァ':'xa','ィ':'xi','ゥ':'xu','ェ':'xe','ォ':'xo','ャ':'xya','ュ':'xyu','ョ':'xyo','ッ':'xtu','ヮ':'xwa','ヴ':'vu','ヵ':'xka','ヶ':'xke','ヰ':'wyi','ヱ':'wye','ー':'-','、':',','。':'.','「':'[','」':']','（':'(','）':')','『':'z[','』':'z]','…':'z.','・':'/'}
out=[]
for x in d:
    r=''.join(base[c] for c in x['input'])
    out.append({'i':x['index'],'ctx':x['context_text'],'romaji':r,'answers':x['expected_output'],'kana':x['input']})
json.dump(out,open('gime_items.json','w',encoding='utf-8'),ensure_ascii=False)
print(len(out), sum(len(o['romaji']) for o in out)); print(out[0]['romaji'][:80])
