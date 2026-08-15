;; GENERATED GRID POINT -- do not hand-edit; regenerate with the sweep that
;; produced it (see HANDOFF.md "the call/stack-depth grid").
;;
;; ONE point on the axis three of the five 2026-08-15 jit faults lay on:
;; call arity x operand-stack depth BENEATH the call x call kind x result
;; arity. The emitter's stack arithmetic was wrong by a constant on this axis
;; and the previous 65-fixture corpus contained no point that could see it:
;; at arity 1 the wrong expression and the right one coincide, and at shallow
;; depth the error only DECLINES. Rebuilt against the pre-fix emitter this
;; grid answers wrongly on 21 of its points.
;;
;; point: arity=4 depth=3 kind=indirect results=1
(module
  (type $t (func (param i32 i32 i32 i32) (result i32) ))
  (table 1 funcref)
  (elem (i32.const 0) func $tgt)
  (func $leaf0 (param i32) (result i32) 
    local.get 0
    i32.const 1
    i32.add)
  (func $tgt (param i32 i32 i32 i32) (result i32) 
    local.get 0
    local.get 1
    i32.add
    local.get 2
    i32.add
    local.get 3
    i32.add
    i32.const 1
    i32.add)
  (func (export "run") (result i32)
    i32.const 10
    i32.const 100
    i32.const 1000
    i32.const 2
    i32.const 3
    i32.const 4
    i32.const 5
    i32.const 0
    call_indirect (type $t)
    i32.add
    i32.add
    i32.add
    return))
