# Routed: retire the `mod-global-written` precheck

**To:** coordinator, for the lane holding `src/codegen.zig`.
**From:** the concat/globals lane. I do not hold `codegen.zig` and have not touched it.
**Status:** the capability this guard stands in for is IMPLEMENTED and measured. The
guard is now the only thing refusing two programs that answer correctly.

## What changed under it

`--backend=direct` now gives a written module-scope binding real storage: one
8-byte `__DATA,__bss` word per name, module-wide, in
`src/native.zig` (`Arm64Compiler.globals`, `internGlobal`, `bssBaseAddr`,
the `load_global` / `store_global` arms) and `src/dnir_lower.zig`
(`collectModuleGlobals`, the `.name` read arm, the `lowerAssignTarget` write arm,
and the entry's initializer prologue). `store_global` is new in
`src/native/ir.zig`.

The set `collectModuleGlobals` claims is deliberately **arm for arm** the set
`module_top_level_written_binding` refuses — `.local_decl`, `.global_decl` and
module-scope `.assign` targets, each tested with "does a function assign this
name". Anything the guard names and the lowering did not claim would be admitted
back onto the old folding and answer wrongly again, so the two must not drift.

## Measured, `od -c`, on the two fixtures written for this gap

Compiler `6c5f44ed` (my build, with the precheck forced open so the storage could
be exercised); oracle is `--backend=c`.

| fixture | before | after | correct |
|---|---|---|---|
| `g066_written_file_scope_global.id` | `6\n5\n` → **`0\n5\n` exit 0** | `6\n5\n` exit 6 | `6\n5\n` exit 6 |
| `g108_untyped_file_scope_global.id` | **`8\n5\n`** | `8\n8\n` exit 0 | `8\n8\n` exit 0 |

Both fixtures say in their own headers: *"Promote this file into the corpus proper
the day the native profile gives a written file-scope binding real storage."*
That day is this one.

## The patch

`src/codegen.zig`, in `can_emit_native_scalar_module`. **Delete** this block:

```zig
        // gap[066] follow-on. A file-scope binding that a FUNCTION WRITES needs
        // real storage the native-scalar profile does not give it: every
        // function body treats the name as its own register-resident local, so
        // the write lands nowhere the next read can see.
        //
        // Measured before this guard: `g: i64 = 0` with `g += i` in a loop
        // printed 3 where C printed 6, and `g += 1` printed 0 where C
        // printed 3 — g's READ folded to the initializer while the write was
        // discarded. Not a bail, not a diagnostic: a running program with a
        // confident wrong number, which is the worst class there is.
        //
        // A read-only file-scope binding is still fine — folding its
        // initializer is correct when nothing can change it — so this refuses
        // only the written case, and DNB001 sends it to the C backend, which
        // now mangles the symbol consistently and answers correctly.
        if (self.module_top_level_written_binding(mod)) |written| {
            self.nativeDiagFailFmt("mod-global-written:{s}", .{written});
            return self.nofit(@src());
        }
```

`module_top_level_written_binding` and `module_functions_assign_name` then have no
callers. Leaving them is harmless; deleting them is tidier and is the lane's call.

## What it unlocks, measured — and what it does not

Over the 789 corpus `.id` files in `lib/ tools/ examples/`, 25 are tagged
`mod-global-written:*`. With the guard forced open **and** the storage in place:

| outcome | files |
|---|---|
| compiles and answers correctly | **2** (the two fixtures) |
| `unresolved-application-facts` | 17 |
| other blockers (`concat`, `graph-dnir-unsupported`, `xs`, `do_block`) | 6 |

So this patch is worth **2 files today**, not 25. The other 17 are behind the
graph item and will fall out of it for free once that lands — the storage is no
longer what stops them. I am flagging the number rather than letting the tag
count imply a bigger win, for the same reason the `any` census turned out to be
87% a mask.

**Do not apply this patch without the storage.** The guard is load-bearing until
`Arm64Compiler.globals` is what answers the read; applied on its own it restores a
silent wrong answer in every program with a written file-scope binding. Measured
with the guard forced open and the storage absent: `0\n5\n` and `8\n5\n` above.

## Also worth promoting, once the patch lands

`examples/native_differential/unsupported/g066_written_file_scope_global.id` and
`g108_untyped_file_scope_global.id` move out of `unsupported/`, and their headers'
"promote this file" paragraphs come true. That is a `gate/expect.sh` ledger move
in the good direction, so it needs re-pinning deliberately rather than drifting.
