;; ADMITTED-SIDE FIXTURE. Imports fd_write, writes "cap\n" to stdout, exits 0.
;; Named imports are exact preview1 names on the exact module name, so every
;; check in the host must let this through under a grant containing fd_write.
(module
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 1)
  (data (i32.const 100) "cap\n")
  (func (export "_start")
    (i32.store (i32.const 8) (i32.const 100))
    (i32.store (i32.const 12) (i32.const 4))
    (drop (call $fd_write (i32.const 1) (i32.const 8) (i32.const 1) (i32.const 20)))))
