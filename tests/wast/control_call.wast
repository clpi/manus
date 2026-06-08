;; Control flow: direct calls, indirect calls (call_indirect), return, unreachable
(module
  ;; helper: double
  (func $double (param i64) (result i64)
    (i64.mul (local.get 0) (i64.const 2)))

  ;; direct call to helper
  (func $quadruple (export "quadruple") (param i64) (result i64)
    (call $double (call $double (local.get 0))))

  ;; recursive call: factorial
  (func $factorial (export "factorial") (param i64) (result i64)
    (if (result i64) (i64.le_s (local.get 0) (i64.const 1))
      (then (i64.const 1))
      (else (i64.mul (local.get 0) (call $factorial (i64.sub (local.get 0) (i64.const 1)))))
    )
  )

  ;; mutual recursion: is_even / is_odd (forward declared via table)
  (table 2 funcref)
  (type $i64_to_i32 (func (param i64) (result i32)))
  (elem (i32.const 0) $is_even_impl $is_odd_impl)

  (func $is_even_impl (param i64) (result i32)
    (if (result i32) (i64.eqz (local.get 0))
      (then (i32.const 1))
      (else (call_indirect (type $i64_to_i32) (i64.sub (local.get 0) (i64.const 1)) (i32.const 1)))
    )
  )
  (func $is_odd_impl (param i64) (result i32)
    (if (result i32) (i64.eqz (local.get 0))
      (then (i32.const 0))
      (else (call_indirect (type $i64_to_i32) (i64.sub (local.get 0) (i64.const 1)) (i32.const 0)))
    )
  )

  (func (export "is_even") (param i64) (result i32)
    (call_indirect (type $i64_to_i32) (local.get 0) (i32.const 0)))
  (func (export "is_odd") (param i64) (result i32)
    (call_indirect (type $i64_to_i32) (local.get 0) (i32.const 1)))

  ;; early return
  (func $first_positive (export "first_positive") (param i64 i64 i64) (result i64)
    (if (i64.gt_s (local.get 0) (i64.const 0)) (then (return (local.get 0))))
    (if (i64.gt_s (local.get 1) (i64.const 0)) (then (return (local.get 1))))
    (if (i64.gt_s (local.get 2) (i64.const 0)) (then (return (local.get 2))))
    (i64.const -1)
  )
)

;; quadruple
(assert_return (invoke "quadruple" (i64.const 3)) (i64.const 12))
(assert_return (invoke "quadruple" (i64.const 0)) (i64.const 0))
(assert_return (invoke "quadruple" (i64.const 5)) (i64.const 20))

;; factorial
(assert_return (invoke "factorial" (i64.const 0)) (i64.const 1))
(assert_return (invoke "factorial" (i64.const 1)) (i64.const 1))
(assert_return (invoke "factorial" (i64.const 5)) (i64.const 120))
(assert_return (invoke "factorial" (i64.const 10)) (i64.const 3628800))

;; is_even / is_odd via call_indirect
(assert_return (invoke "is_even" (i64.const 0)) (i32.const 1))
(assert_return (invoke "is_even" (i64.const 2)) (i32.const 1))
(assert_return (invoke "is_even" (i64.const 3)) (i32.const 0))
(assert_return (invoke "is_odd" (i64.const 1)) (i32.const 1))
(assert_return (invoke "is_odd" (i64.const 4)) (i32.const 0))

;; first_positive
(assert_return (invoke "first_positive" (i64.const 1) (i64.const 2) (i64.const 3)) (i64.const 1))
(assert_return (invoke "first_positive" (i64.const -1) (i64.const 5) (i64.const 3)) (i64.const 5))
(assert_return (invoke "first_positive" (i64.const -1) (i64.const -2) (i64.const 7)) (i64.const 7))
(assert_return (invoke "first_positive" (i64.const -1) (i64.const -2) (i64.const -3)) (i64.const -1))
