;; REGRESSION: `call_indirect` with more than ONE argument.
;;
;; The jit emitted `sp -= 1 - xnp + xnr`, which inverts the sign of BOTH
;; operand counts. At one argument the two spellings coincide, so every
;; single-argument `call_indirect` was right and the arm looked correct; at two
;; the index is never popped and the value read back IS THE TABLE INDEX.
;; call_indirect_typed answered 3 -- its last dispatch's index -- for
;; 1034562941.
;;
;; Both arities are exercised here and the answers are distinguishable from the
;; indices that would be returned instead (7/9 vs 0/2/3).
(module
  (type $un (func (param i32) (result i32)))
  (type $bin (func (param i32 i32) (result i32)))
  (func (;0;) (type $un) local.get 0 i32.const 100 i32.add)
  (func (;1;) (type $un) local.get 0 i32.const 7 i32.mul)
  (func (;2;) (type $bin) local.get 0 local.get 1 i32.add)
  (func (;3;) (type $bin) local.get 0 local.get 1 i32.sub)
  (func (export "run") (result i32)
    i32.const 11
    i32.const 0
    call_indirect (type $un)     ;; func 0 -> 111
    i32.const 1000
    i32.const 2
    call_indirect (type $bin)    ;; func 2 -> 1111
    i32.const 40
    i32.const 3
    call_indirect (type $bin)    ;; func 3 -> 1071
    i32.const 1
    call_indirect (type $un))    ;; func 1 -> 7497
  (table 4 funcref)
  (elem (i32.const 0) func 0 1 2 3))
