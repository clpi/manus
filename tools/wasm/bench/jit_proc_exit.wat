;; REGRESSION: `fd_write` dispatch, and `proc_exit` TERMINATING.
;;
;; Two separate wrong answers meet in this one body.
;;
;;   1. The jit dispatched its emitted fd_write on `imk == 1`, a leftover from
;;      when that slot held a boolean "the field name matched". It is now the
;;      preview1 ROSTER INDEX, and 1 is `args_get`, so every real `fd_write`
;;      fell through to the zero-filling stub and printed NOTHING.
;;   2. `proc_exit` fell through to the same stub, which emits no instruction
;;      at all -- so it was a NO-OP and everything after it still ran.
;;
;; The oracle and the interpreter print `once` and stop. A jit with either bug
;; prints nothing, or prints twice.
(module
  (import "wasi_snapshot_preview1" "proc_exit" (func $pe (param i32)))
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fw (param i32 i32 i32 i32) (result i32)))
  (func (export "_start")
    i32.const 60000 i32.const 10000 i32.store      ;; iov.base
    i32.const 60004 i32.const 5     i32.store      ;; iov.len
    i32.const 1 i32.const 60000 i32.const 1 i32.const 60008 call $fw drop
    i32.const 0 call $pe
    i32.const 1 i32.const 60000 i32.const 1 i32.const 60008 call $fw drop)
  (memory 4)
  (export "memory" (memory 0))
  (data (i32.const 10000) "once\n"))
