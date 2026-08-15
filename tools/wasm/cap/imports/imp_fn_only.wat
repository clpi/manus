;; THE ADMIT PARTNER. One ordinary granted function import and nothing else:
;; a host that started refusing this is not refusing non-function imports, it
;; is refusing imports.
(module
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (memory 1)
  (export "memory" (memory 0))
  (data (i32.const 100) "imp\n")
  (func (export "run") (result i32)
    (i32.store (i32.const 0) (i32.const 100))
    (i32.store (i32.const 4) (i32.const 4))
    (drop (call $fd_write (i32.const 1) (i32.const 0) (i32.const 1) (i32.const 20)))
    (i32.const 0)))
