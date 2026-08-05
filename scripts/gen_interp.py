import re, sys
# Descriptor source of truth: the Pass 12 M2 generated table
# (src/wasm_semantic.zig -> `duo wasm-tables emit` -> ward_mvp_opcodes.duo)
GEN = "/Users/clp/x/duo/lib/std/wasm/ward_mvp_opcodes.duo"
ops = {m.group(1): int(m.group(2)) for m in
       re.finditer(r"^M\.(OP_\w+)\s*=\s*(\d+)", open(GEN).read(), re.M)}
need = ["OP_loop","OP_end_","OP_br","OP_br_if","OP_return_","OP_local_get","OP_local_set",
        "OP_local_tee","OP_i32_const","OP_i32_eqz","OP_i32_ne","OP_i32_lt_u","OP_i32_add",
        "OP_i32_sub","OP_i32_mul","OP_i32_and","OP_i32_or","OP_i32_xor","OP_i32_shl","OP_i32_shr_u"]
missing = [n for n in need if n not in ops]
if missing: sys.exit("missing from descriptor table: " + str(missing))
imm_ops = ["OP_local_set","OP_br","OP_br_if"]  # hot ops decode inline
himm_fill = "\n".join(f"  mem.write_byte(himm, {ops[n]}, 1)" for n in imm_ops)
consts = "\n".join(f"const {n} = {ops[n]}" for n in need)

body = open('/tmp/run_body.bin','rb').read()
pad  = body + b'\x00'*((-len(body))%8)
words = "\n".join(
    f"  mem.write_i64(code, {i}, {int.from_bytes(pad[i:i+8],'little',signed=True)})"
    for i in range(0,len(pad),8))

src = f'''-- ward WASM interpreter — PURE DUO, zero @c.emit/@c.include.
--
-- Opcode constants below are generated from the Pass 12 M2 descriptor chain
-- (src/wasm_semantic.zig -> `duo wasm-tables emit` -> lib/std/wasm/ward_mvp_opcodes.duo)
-- by ward/scripts_gen_interp.py, so the canonical table stays the single source
-- of truth. They are inlined rather than `req`d because requiring a std module
-- currently fails to compile (BUG C: export table references DCE'd symbols).
--
-- Codegen constraints (filed 2026-08-05, src/codegen.zig locked):
--   BUG A  a branch may not end on a void call -> explicit non-void tail.
--   BUG B  pointer locals must not cross a function boundary -> one function.
--   BUG C  no `req "std.mem"`; mem.* is intercepted by name.
--   BUG D  named consts are illegal as `match` patterns -> if/elseif, which
--          compares properly and lets the descriptor names be used directly.
--   BUG E  mem.alloc local + while + `match` is a compiler panic -> if/elseif.
--   BUG G  variable shift >= 32 is 32-bit -> no LEB sign-extension (masking
--          the raw accumulated bits to 32 already yields the correct i32).
--
-- Shape: ONE hoisted LEB128 decode (was 6 copies), binops share operand
-- fetch/stack adjust (was 15 near-identical blocks), hot opcodes tested first.

{consts}
const M32 = 0xFFFFFFFF

fun run_body(body: any, body_len: i64, guard: i64): i64
  code = mem.alloc(body_len + 16)
  st   = mem.alloc(4096 * 8)
  lo   = mem.alloc(64 * 8)
  ltgt = mem.alloc(64 * 8)
  himm = mem.alloc(256)
  mem.zero(code, body_len + 16)
  mem.zero(st, 4096 * 8)
  mem.zero(lo, 64 * 8)
  mem.zero(ltgt, 64 * 8)
  mem.zero(himm, 256)
{himm_fill}

  ci: i64 = 0
  while ci < body_len
    mem.write_byte(code, ci, string.byte(body, ci + 1))
    ci = ci + 1
  end

  sp: i64 = 0
  pc: i64 = 0
  lsp: i64 = 0

  while pc < body_len
    op: i64 = mem.read_byte(code, pc)
    pc = pc + 1

    if op == OP_i32_const
      sh: i64 = 0
      cont: i64 = 1
      imm: i64 = 0
      while cont == 1
        ib: i64 = mem.read_byte(code, pc)
        pc = pc + 1
        imm = imm | ((ib & 0x7F) << sh)
        sh = sh + 7
        if ib < 0x80
          cont = 0
        end
      end
      imm = imm & M32
      sp = sp + 1
      mem.write_i64(st, sp * 8, imm)
      sp = sp

    elseif op == OP_local_get
      sh: i64 = 0
      cont: i64 = 1
      imm: i64 = 0
      while cont == 1
        ib: i64 = mem.read_byte(code, pc)
        pc = pc + 1
        imm = imm | ((ib & 0x7F) << sh)
        sh = sh + 7
        if ib < 0x80
          cont = 0
        end
      end
      imm = imm & M32
      sp = sp + 1
      mem.write_i64(st, sp * 8, mem.read_i64(lo, imm * 8))
      sp = sp

    elseif op >= OP_i32_add and op <= OP_i32_shr_u
      -- i32 binary ALU: operand fetch and stack adjust shared by all arms.
      b: i64 = mem.read_i64(st, sp * 8)
      a: i64 = mem.read_i64(st, (sp - 1) * 8)
      sp = sp - 1
      r: i64 = 0
      if op == OP_i32_mul
        -- split multiply: a*b with 32-bit operands overflows signed i64
        r = (((a & 0xFFFF) * b) + (((((a >> 16) & 0xFFFF) * b) & 0xFFFF) << 16)) & M32
      elseif op == OP_i32_xor
        r = a ~ b
      elseif op == OP_i32_or
        r = a | b
      elseif op == OP_i32_shr_u
        r = (a & M32) >> (b & 31)
      elseif op == OP_i32_add
        r = (a + b) & M32
      elseif op == OP_i32_sub
        r = (a - b) & M32
      elseif op == OP_i32_and
        r = a & b
      elseif op == OP_i32_shl
        r = ((a & (M32 >> (b & 31))) << (b & 31)) & M32
      end
      mem.write_i64(st, sp * 8, r)
      sp = sp

    elseif op == OP_local_tee
      sh: i64 = 0
      cont: i64 = 1
      imm: i64 = 0
      while cont == 1
        ib: i64 = mem.read_byte(code, pc)
        pc = pc + 1
        imm = imm | ((ib & 0x7F) << sh)
        sh = sh + 7
        if ib < 0x80
          cont = 0
        end
      end
      imm = imm & M32
      mem.write_i64(lo, imm * 8, mem.read_i64(st, sp * 8))
      sp = sp

    else
      -- Cold path: one table-guarded decode shared by every remaining opcode.
      imm2: i64 = 0
      if mem.read_byte(himm, op) ~= 0
        sh2: i64 = 0
        c2: i64 = 1
        while c2 == 1
          jb: i64 = mem.read_byte(code, pc)
          pc = pc + 1
          imm2 = imm2 | ((jb & 0x7F) << sh2)
          sh2 = sh2 + 7
          if jb < 0x80
            c2 = 0
          end
        end
        imm2 = imm2 & M32
      end

      if op == OP_br_if
        cv: i64 = mem.read_i64(st, sp * 8)
        sp = sp - 1
        if cv ~= 0
          pc = mem.read_i64(ltgt, (lsp - 1 - imm2) * 8)
          lsp = lsp - imm2
        end
      elseif op == OP_local_set
        mem.write_i64(lo, imm2 * 8, mem.read_i64(st, sp * 8))
        sp = sp - 1
      elseif op >= OP_i32_eqz and op <= OP_i32_lt_u
        if op == OP_i32_eqz
          av: i64 = mem.read_i64(st, sp * 8)
          rv: i64 = 0
          if (av & M32) == 0
            rv = 1
          end
          mem.write_i64(st, sp * 8, rv)
          sp = sp
        else
          b2: i64 = mem.read_i64(st, sp * 8)
          a2: i64 = mem.read_i64(st, (sp - 1) * 8)
          sp = sp - 1
          r2: i64 = 0
          if op == OP_i32_ne
            if a2 ~= b2
              r2 = 1
            end
          elseif op == OP_i32_lt_u
            if (a2 & M32) < (b2 & M32)
              r2 = 1
            end
          end
          mem.write_i64(st, sp * 8, r2)
          sp = sp
        end
      elseif op == OP_loop
        pc = pc + 1
        mem.write_i64(ltgt, lsp * 8, pc)
        lsp = lsp + 1
      elseif op == OP_end_
        if lsp > 0
          lsp = lsp - 1
        end
      elseif op == OP_br
        pc = mem.read_i64(ltgt, (lsp - 1 - imm2) * 8)
        lsp = lsp - imm2
      elseif op == OP_return_
        pc = body_len
      else
        sp = sp
      end
    end
  end

  last: i64 = 0
  if sp > 0
    last = mem.read_i64(st, sp * 8) & M32
  end
  mem.free(code)
  mem.free(st)
  mem.free(lo)
  mem.free(ltgt)
  mem.free(himm)
  last
end

fun main()
  f = io.open("/tmp/run_body.bin", "rb")
  bytes = f:read("*a")
  f:close()
  t0 = os.clock()
  r: i64 = run_body(bytes, #bytes, 0)
  t1 = os.clock()
  print("result=" .. tostring(r))
  print("seconds=" .. tostring(t1 - t0))
end

main()
'''
open('src/wasm/interp_v2.duo','w').write(src)
print(f"generated interp_v2.duo from descriptor table ({len(need)} opcodes)")
