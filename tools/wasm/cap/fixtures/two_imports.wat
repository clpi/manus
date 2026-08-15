;; Two imports from two different worlds. Withholding one must refuse the
;; module even though the other is granted: a grant is a set, not a threshold.
(module
  (import "wasi_snapshot_preview1" "clock_time_get"
    (func $clock (param i32 i64 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 1)
  (func (export "run") (result i32)
    (call $clock (i32.const 1) (i64.const 1000) (i32.const 8))))
