;; The same guest, but it REPORTS the errno instead of ignoring it, so a denial
;; is visible in the answer rather than only in the absence of output.
;; `run` returns fd_write's errno: 0 success, 76 notcapable, 8 badf.
(module
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 1)
  (data (i32.const 100) "cap\n")
  (func (export "run") (result i32)
    (i32.store (i32.const 8) (i32.const 100))
    (i32.store (i32.const 12) (i32.const 4))
    (call $fd_write (i32.const 1) (i32.const 8) (i32.const 1) (i32.const 20))))
