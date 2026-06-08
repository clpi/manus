;; i64 comparison: eq, ne, lt_s, lt_u, le_s, le_u, gt_s, gt_u, ge_s, ge_u, eqz
(module
  (func $eq   (export "eq")   (param i64 i64) (result i32) local.get 0  local.get 1  i64.eq)
  (func $ne   (export "ne")   (param i64 i64) (result i32) local.get 0  local.get 1  i64.ne)
  (func $lt_s (export "lt_s") (param i64 i64) (result i32) local.get 0  local.get 1  i64.lt_s)
  (func $lt_u (export "lt_u") (param i64 i64) (result i32) local.get 0  local.get 1  i64.lt_u)
  (func $le_s (export "le_s") (param i64 i64) (result i32) local.get 0  local.get 1  i64.le_s)
  (func $le_u (export "le_u") (param i64 i64) (result i32) local.get 0  local.get 1  i64.le_u)
  (func $gt_s (export "gt_s") (param i64 i64) (result i32) local.get 0  local.get 1  i64.gt_s)
  (func $gt_u (export "gt_u") (param i64 i64) (result i32) local.get 0  local.get 1  i64.gt_u)
  (func $ge_s (export "ge_s") (param i64 i64) (result i32) local.get 0  local.get 1  i64.ge_s)
  (func $ge_u (export "ge_u") (param i64 i64) (result i32) local.get 0  local.get 1  i64.ge_u)
  (func $eqz  (export "eqz")  (param i64)     (result i32) local.get 0  i64.eqz)
)

;; eq / ne
(assert_return (invoke "eq"  (i64.const 1)  (i64.const 1))  (i32.const 1))
(assert_return (invoke "eq"  (i64.const 1)  (i64.const 2))  (i32.const 0))
(assert_return (invoke "ne"  (i64.const 1)  (i64.const 2))  (i32.const 1))
(assert_return (invoke "ne"  (i64.const 5)  (i64.const 5))  (i32.const 0))

;; lt_s / le_s / gt_s / ge_s
(assert_return (invoke "lt_s" (i64.const 1)  (i64.const 2))  (i32.const 1))
(assert_return (invoke "lt_s" (i64.const 2)  (i64.const 1))  (i32.const 0))
(assert_return (invoke "lt_s" (i64.const -1) (i64.const 0))  (i32.const 1))
(assert_return (invoke "le_s" (i64.const 2)  (i64.const 2))  (i32.const 1))
(assert_return (invoke "le_s" (i64.const 3)  (i64.const 2))  (i32.const 0))
(assert_return (invoke "gt_s" (i64.const 2)  (i64.const 1))  (i32.const 1))
(assert_return (invoke "gt_s" (i64.const -1) (i64.const 0))  (i32.const 0))
(assert_return (invoke "ge_s" (i64.const 2)  (i64.const 2))  (i32.const 1))
(assert_return (invoke "ge_s" (i64.const 1)  (i64.const 2))  (i32.const 0))

;; lt_u / le_u / gt_u / ge_u (treats -1 as max unsigned)
(assert_return (invoke "lt_u" (i64.const 1)  (i64.const 2))  (i32.const 1))
(assert_return (invoke "lt_u" (i64.const 0)  (i64.const -1)) (i32.const 1))
(assert_return (invoke "gt_u" (i64.const -1) (i64.const 0))  (i32.const 1))
(assert_return (invoke "le_u" (i64.const 5)  (i64.const 5))  (i32.const 1))
(assert_return (invoke "ge_u" (i64.const 5)  (i64.const 5))  (i32.const 1))

;; eqz
(assert_return (invoke "eqz" (i64.const 0)) (i32.const 1))
(assert_return (invoke "eqz" (i64.const 1)) (i32.const 0))
(assert_return (invoke "eqz" (i64.const -1)) (i32.const 0))
