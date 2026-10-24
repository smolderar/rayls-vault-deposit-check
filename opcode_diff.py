"""Opcode-level comparison of two runtime bytecodes (as returned by eth_getCode).
Usage: python opcode_diff.py code-old.hex code-new.hex
A PUSH value is masked only when it points at a JUMPDEST in its own code, because jump addresses shift whenever
code is added. Every other PUSH value (selectors, constants, roles, divisors) is compared as is.
Prints how similar the two opcode streams are and every region that differs, with the opcodes on both sides."""
import sys, difflib

def ops(path):
    h = open(path, encoding="ascii", errors="ignore").read().strip()
    h = h[2:] if h.startswith("0x") else h
    c = bytes.fromhex(h)
    jd, i = set(), 0
    while i < len(c):                      # first pass: real JUMPDEST offsets (outside PUSH data)
        op = c[i]
        if op == 0x5b: jd.add(i)
        i += 1 + (op - 0x5f if 0x60 <= op <= 0x7f else 0)
    out, i = [], 0
    while i < len(c):
        op = c[i]
        if 0x60 <= op <= 0x7f:
            n = op - 0x5f; v = int.from_bytes(c[i + 1:i + 1 + n], "big")
            out.append("PUSH:dest" if (n <= 3 and v in jd) else f"{op:02x}:{c[i + 1:i + 1 + n].hex()}"); i += 1 + n
        else:
            out.append(f"{op:02x}"); i += 1
    return out

a, b = ops(sys.argv[1]), ops(sys.argv[2])
sm = difflib.SequenceMatcher(None, a, b, autojunk=False)
diff = [o for o in sm.get_opcodes() if o[0] != "equal"]
print(f"old: {len(a)} opcodes, new: {len(b)} opcodes, similarity {sm.ratio():.4f}")
print(f"regions that differ: {len(diff)}, opcodes only in new: {sum(j2 - j1 for _, _, _, j1, j2 in diff)}, "
      f"only in old: {sum(i2 - i1 for _, i1, i2, _, _ in diff)}")
# label each differing region so the result is easy to read (the label is a heuristic; the raw opcodes follow it)
from collections import Counter
def num(t): return int(t.split(":")[1], 16) if ":" in t and t != "PUSH:dest" else None
deltas = Counter(num(b[j1]) - num(a[i1]) for tag, i1, i2, j1, j2 in diff
                 if tag == "replace" and i2 - i1 == 1 and j2 - j1 == 1 and a[i1][:2] == b[j1][:2] == "61")
shift = deltas.most_common(1)[0][0] if deltas else None
def label(tag, i1, i2, j1, j2):
    A, B = a[i1:i2], b[j1:j2]
    if all(t.startswith("63:") or t in ("14", "57", "80", "PUSH:dest") for t in A + B) and max(i2, j2) < 400:
        return "dispatcher order"
    if tag == "replace" and len(A) == len(B) == 1 and num(A[0]) is not None and num(B[0]) is not None:
        if A[0][:2] == "61" and num(B[0]) - num(A[0]) == shift: return f"data offset shifted by {shift}"
        return "constant changed"
    if len(A) == 1 and A[0].startswith("7f:") and "39" in B: return "same constant, now copied from code"
    if i1 > len(a) - 15: return "compiler metadata"
    return "new or moved code"
labels = [label(*o) for o in diff]
print("summary:", dict(Counter(labels)))
for (tag, i1, i2, j1, j2), lab in zip(diff, labels):
    show = lambda s: " ".join(s[:8]) + (" ..." if len(s) > 8 else "")
    print(f"  [{lab}] {tag} old {i1}-{i2} ({i2 - i1}): {show(a[i1:i2])}")
    print(f"          new {j1}-{j2} ({j2 - j1}): {show(b[j1:j2])}")
