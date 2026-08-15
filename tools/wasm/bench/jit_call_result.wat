;; REGRESSION: the operand-stack depth after a NON-INLINED call.
;;
;; The jit emitted `sp -= cnp + cnr` where the depth is `sp - cnp + cnr`, i.e.
;; it SUBTRACTED the result instead of adding it and sat two slots low after
;; every real call that returns a value. A body whose call is its last act
;; hides it (the answer is already in x0), and a shallow stack merely declines
;; ("operand stack shape") -- so the whole corpus missed it. THIS shape does
;; not: the stack is deep enough to absorb the deficit, so the following
;; `i32.add` reads the WRONG REGISTERS and the body answers 1200 instead of 46.
;;
;; $mid is deliberately NON-LEAF (it calls $leaf) so it takes the real-call
;; path rather than being spliced inline.
(module
  (func $leaf (param i32) (result i32) local.get 0 i32.const 3 i32.add)
  (func $mid  (param i32) (result i32) local.get 0 call $leaf i32.const 2 i32.mul)
  (func (export "run") (result i32)
    i32.const 1000
    i32.const 200
    i32.const 30
    i32.const 5
    call $mid          ;; (5+3)*2 = 16
    i32.add            ;; 30 + 16 = 46
    return))
