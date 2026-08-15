;; The non-function import is SECOND. A walk that only inspected the first
;; import would admit this module.
(module
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (import "env" "memory" (memory 1))
  (func (export "run") (result i32) (i32.const 94)))
