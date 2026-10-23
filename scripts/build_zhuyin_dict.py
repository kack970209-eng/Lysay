"""把小麦注音（McBopomofo）编译好的 data.txt 转成键盘用的紧凑注音词库。

输入每行：读音 词 分数，例如 “ㄋㄧˇ-ㄏㄠˇ 你好 -5.088”
输出每行：读音<TAB>最高分<TAB>词1 词2 …（同一读音按分数由高到低）
整个文件按 UTF-8 字节序排序，键盘端用二分查找。

用法：python scripts/build_zhuyin_dict.py data.txt Resources/Zhuyin/zhuyin.txt
"""
import re
import sys
from collections import defaultdict

SRC, DST = sys.argv[1], sys.argv[2]
KEY_RE = re.compile(r"^[ㄅ-ㄩˊˇˋ˙]+(-[ㄅ-ㄩˊˇˋ˙]+)*$")
MAX_CANDIDATES = 80

entries = defaultdict(dict)
with open(SRC, encoding="utf-8") as f:
    for line in f:
        parts = line.rstrip("\n").split(" ")
        if len(parts) != 3:
            continue
        key, value, score = parts
        if not KEY_RE.match(key) or value.startswith("MACRO@"):
            continue
        try:
            sc = float(score)
        except ValueError:
            continue
        old = entries[key].get(value)
        if old is None or sc > old:
            entries[key][value] = sc

lines = []
for key, values in entries.items():
    ranked = sorted(values.items(), key=lambda kv: -kv[1])[:MAX_CANDIDATES]
    best = ranked[0][1]
    lines.append((key.encode("utf-8"), f"{key}\t{best:.4f}\t{' '.join(v for v, _ in ranked)}\n"))

lines.sort(key=lambda x: x[0])
with open(DST, "w", encoding="utf-8", newline="\n") as f:
    for _, text in lines:
        f.write(text)
print(f"{len(lines)} readings -> {DST}")
