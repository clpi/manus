;; Does a DENIAL actually stop the EFFECT, or only the import record? proc_exit
;; is the sharpest test: it terminates the process, so if the denial is only
;; cosmetic the exit status says so immediately.
(module
  (import "wasi_snapshot_preview1" "proc_exit" (func $exit (param i32)))
  (memory (export "memory") 1)
  (func (export "run") (result i32)
    (call $exit (i32.const 42))
    (i32.const 7)))
