;; i64 arithmetic: add, sub, mul, neg
(module
  (func $add (export "add") (param i64 i64) (result i64)
    local.get 0  local.get 1  i64.add)
  (func $sub (export "sub") (param i64 i64) (result i64)
    local.get 0  local.get 1  i64.sub)
  (func $mul (export "mul") (param i64 i64) (result i64)
    local.get 0  local.get 1  i64.mul)
  (func $neg (export "neg") (param i64) (result i64)
    i64.const 0  local.get 0  i64.sub)
)

;; add
(assert_return (invoke "add" (i64.const 0) (i64.const 0)) (i64.const 0))
(assert_return (invoke "add" (i64.const 1) (i64.const 2)) (i64.const 3))
(assert_return (invoke "add" (i64.const -1) (i64.const 1)) (i64.const 0))
(assert_return (invoke "add" (i64.const 100) (i64.const 200)) (i64.const 300))
(assert_return (invoke "add" (i64.const -100) (i64.const -200)) (i64.const -300))
;; overflow wraps
(assert_return (invoke "add" (i64.const 9223372036854775807) (i64.const 1)) (i64.const -9223372036854775808))

;; sub
(assert_return (invoke "sub" (i64.const 5) (i64.const 3)) (i64.const 2))
(assert_return (invoke "sub" (i64.const 0) (i64.const 0)) (i64.const 0))
(assert_return (invoke "sub" (i64.const 3) (i64.const 5)) (i64.const -2))
(assert_return (invoke "sub" (i64.const -5) (i64.const -3)) (i64.const -2))

;; mul
(assert_return (invoke "mul" (i64.const 3) (i64.const 4)) (i64.const 12))
(assert_return (invoke "mul" (i64.const 0) (i64.const 100)) (i64.const 0))
(assert_return (invoke "mul" (i64.const -3) (i64.const 4)) (i64.const -12))
(assert_return (invoke "mul" (i64.const -3) (i64.const -4)) (i64.const 12))
(assert_return (invoke "mul" (i64.const 1000000) (i64.const 1000000)) (i64.const 1000000000000))

;; neg
(assert_return (invoke "neg" (i64.const 5)) (i64.const -5))
(assert_return (invoke "neg" (i64.const -5)) (i64.const 5))
(assert_return (invoke "neg" (i64.const 0)) (i64.const 0))
