;; Control flow: if/else, select, block/br_if
(module
  ;; Simple if: return 1 if a > b, else 0
  (func $gt (export "gt") (param i64 i64) (result i64)
    (if (result i64) (i64.gt_s (local.get 0) (local.get 1))
      (then (i64.const 1))
      (else (i64.const 0))
    )
  )

  ;; Nested if/else: sign function
  (func $sign (export "sign") (param i64) (result i64)
    (if (result i64) (i64.gt_s (local.get 0) (i64.const 0))
      (then (i64.const 1))
      (else
        (if (result i64) (i64.lt_s (local.get 0) (i64.const 0))
          (then (i64.const -1))
          (else (i64.const 0))
        )
      )
    )
  )

  ;; select: like ternary — select(a, b, cond) returns a if cond != 0, else b
  (func $sel_i64 (export "sel_i64") (param i64 i64 i32) (result i64)
    local.get 0  local.get 1  local.get 2  select)

  ;; clamp using if
  (func $clamp (export "clamp") (param i64 i64 i64) (result i64)
    (local $v i64)
    local.get 0
    local.set $v
    (if (i64.lt_s (local.get $v) (local.get 1))
      (then (local.get 1) (local.set $v))
    )
    (if (i64.gt_s (local.get $v) (local.get 2))
      (then (local.get 2) (local.set $v))
    )
    local.get $v
  )

  ;; abs using select: select val1 val2 cond → val1 if cond!=0, else val2
  (func $abs (export "abs") (param i64) (result i64)
    (local.get 0)                             ;; val1: x (returned when x >= 0)
    (i64.sub (i64.const 0) (local.get 0))    ;; val2: -x (returned when x < 0)
    (i64.ge_s (local.get 0) (i64.const 0))  ;; cond: x >= 0
    select
  )
)

;; gt
(assert_return (invoke "gt" (i64.const 5) (i64.const 3)) (i64.const 1))
(assert_return (invoke "gt" (i64.const 3) (i64.const 5)) (i64.const 0))
(assert_return (invoke "gt" (i64.const 5) (i64.const 5)) (i64.const 0))

;; sign
(assert_return (invoke "sign" (i64.const 10)) (i64.const 1))
(assert_return (invoke "sign" (i64.const -10)) (i64.const -1))
(assert_return (invoke "sign" (i64.const 0)) (i64.const 0))

;; select
(assert_return (invoke "sel_i64" (i64.const 10) (i64.const 20) (i32.const 1)) (i64.const 10))
(assert_return (invoke "sel_i64" (i64.const 10) (i64.const 20) (i32.const 0)) (i64.const 20))

;; clamp
(assert_return (invoke "clamp" (i64.const 5) (i64.const 0) (i64.const 10)) (i64.const 5))
(assert_return (invoke "clamp" (i64.const -1) (i64.const 0) (i64.const 10)) (i64.const 0))
(assert_return (invoke "clamp" (i64.const 15) (i64.const 0) (i64.const 10)) (i64.const 10))

;; abs
(assert_return (invoke "abs" (i64.const 5)) (i64.const 5))
(assert_return (invoke "abs" (i64.const -5)) (i64.const 5))
(assert_return (invoke "abs" (i64.const 0)) (i64.const 0))
