;; NEGATIVE CONTROL FOR THE POLICY, not for the engine: a guest that imports
;; only `clock_time_get` must be ADMITTED by a grant of `clock` and REFUSED by
;; a grant of `filesystem`. A policy that refused everything would pass a
;; refusal-only suite; this is the row that stops it.
(module
  (import "wasi_snapshot_preview1" "clock_time_get"
    (func $clock (param i32 i64 i32) (result i32)))
  (memory (export "memory") 1)
  (func (export "run") (result i32)
    (call $clock (i32.const 1) (i64.const 1000) (i32.const 8))))
