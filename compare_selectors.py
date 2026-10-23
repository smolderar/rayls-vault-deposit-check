"""List the function selectors in the dispatcher of two deployed bytecodes and compare them.
Usage: python compare_selectors.py code-old.hex code-new.hex
Reads the runtime bytecode as returned by eth_getCode, walks the opcodes (skipping PUSH data) and records every
PUSH4 value that is compared with EQ in the next two opcodes, which is how Solidity's dispatcher matches msg.sig."""
import sys

def opcodes(code):
    i, out = 0, []
    while i < len(code):
        op = code[i]
        if 0x60 <= op <= 0x7f:
            n = op - 0x5f
            out.append((op, code[i + 1:i + 1 + n])); i += 1 + n
        else:
            out.append((op, b"")); i += 1
    return out

def selectors(path):
    hexstr = open(path, encoding="ascii", errors="ignore").read().strip()
    hexstr = hexstr[2:] if hexstr.startswith("0x") else hexstr
    code = bytes.fromhex(hexstr)
    ops = opcodes(code); found = set()
    for k, (op, data) in enumerate(ops):
        if op == 0x63 and any(o == 0x14 for o, _ in ops[k + 1:k + 3]):
            found.add(data.hex())
    return len(code), found

(n_old, old), (n_new, new) = selectors(sys.argv[1]), selectors(sys.argv[2])
print(f"old code: {n_old} bytes, {len(old)} selectors")
print(f"new code: {n_new} bytes, {len(new)} selectors")
print(f"in both: {len(old & new)}")
print("only in new:", ", ".join("0x" + s for s in sorted(new - old)) or "none")
print("only in old:", ", ".join("0x" + s for s in sorted(old - new)) or "none")
