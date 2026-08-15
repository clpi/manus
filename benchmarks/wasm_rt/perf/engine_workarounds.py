#!/usr/bin/env python3
"""Scratch-only workarounds so tools/wasm/src/engine.id can be compiled.

Every replacement here works around a defect in the Idol compiler's C backend,
NOT a defect in the engine source. The committed engine.id does not build.
Run against a pristine `git archive HEAD` copy.
"""
import re
import sys

p = sys.argv[1]
s = open(p).read()

# (1) `x:floor()` / `:ceil()` / `:sqrt()` on an f64/f32 emits `x__floor()`,
#     which is not valid C. Minimal repro: `x: f64 = 3.7 ; y = x:floor()`.
s, n1 = re.subn(r'([A-Za-z_][A-Za-z0-9_]*|[0-9]+\.[0-9]+):(floor|ceil|sqrt)\(\)',
                r'math.\2(\1)', s)

# (2) same defect class on `:char()`.
s2 = s.replace('mem.read_byte(lin, bp + k3):char()',
               'string.char(mem.read_byte(lin, bp + k3))')
n2 = 1 if s2 != s else 0
s = s2

# (3) `bytes` in main() is a dynamic value (io read); `bytes:byte(i)` there
#     emits a lua_Value into int64 contexts. The engine's own `s: str`
#     parameters compile correctly, so route through one.
helper = ('# scratch shim: see patch_engine.py note (3)\n'
          'wb(s: str, i: i64): i64\n'
          '  s:byte(i)\n'
          'end\n\n')
anchor = 'uleb_val(s: str, i: i64, n: i64): i64'
assert anchor in s
s = s.replace(anchor, helper + anchor, 1)
s, n3 = re.subn(r'bytes:byte\(([^()]*)\)', r'wb(bytes, \1)', s)

open(p, 'w').write(s)
print(f'math-method:{n1} char:{n2} byte:{n3}')

# (4) `x:len()` emits lua_str_buf_len_i64(), which returns 0 for a string
#     produced by io read (the "buffer length" is unset). Every wasm module
#     then fails the 8-byte magic check. `string.len()` emits
#     lua_str_byte_len() and is correct. Measured on fib.wasm (27791 bytes):
#     b:len() -> 0, string.len(b) -> 27791.
s = open(p).read()
s, n4 = re.subn(r'\b([A-Za-z_][A-Za-z0-9_]*):len\(\)', r'string.len(\1)', s)
open(p, 'w').write(s)
print(f'len:{n4}')
