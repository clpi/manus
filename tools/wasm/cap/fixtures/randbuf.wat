;; random_get writes into guest memory. A denial must leave the buffer alone
;; AND say so; a stub that reports success while leaving zeros is the exact
;; failure this engine already fixed once.
(module
  (import "wasi_snapshot_preview1" "random_get" (func $rg (param i32 i32) (result i32)))
  (memory (export "memory") 1)
  (func (export "run") (result i32)
    (call $rg (i32.const 64) (i32.const 8))))
