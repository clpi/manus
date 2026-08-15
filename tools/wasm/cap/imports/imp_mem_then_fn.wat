;; A memory import with a maximum FOLLOWED by a real function import. If the
;; walk mis-sizes the memory import it reads the next import from the wrong
;; offset, and every claim the resolver makes about the function import is
;; made about the wrong bytes.
(module
  (import "env" "memory" (memory 1 2))
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (func (export "run") (result i32) (i32.const 95)))
