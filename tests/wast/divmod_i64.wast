;; i64 integer division and modulo (floored semantics, matching Lua // and %)
(module
  ;; idiv: floored integer division
  (func $idiv (export "idiv") (param i64 i64) (result i64)
    local.get 0  local.get 1  i64.div_s)
  ;; irem: C-style signed remainder (not the same as Lua %, but useful for testing)
  (func $irem (export "irem") (param i64 i64) (result i64)
    local.get 0  local.get 1  i64.rem_s)
  (func $idiv_u (export "idiv_u") (param i64 i64) (result i64)
    local.get 0  local.get 1  i64.div_u)
)

;; signed division (truncation toward zero — WASM i64.div_s semantics)
(assert_return (invoke "idiv" (i64.const 10) (i64.const 3)) (i64.const 3))
(assert_return (invoke "idiv" (i64.const 10) (i64.const 2)) (i64.const 5))
(assert_return (invoke "idiv" (i64.const -10) (i64.const 3)) (i64.const -3))
(assert_return (invoke "idiv" (i64.const -10) (i64.const -3)) (i64.const 3))
(assert_return (invoke "idiv" (i64.const 1) (i64.const 1)) (i64.const 1))
(assert_return (invoke "idiv" (i64.const 0) (i64.const 5)) (i64.const 0))

;; signed remainder (truncated — WASM i64.rem_s semantics)
(assert_return (invoke "irem" (i64.const 10) (i64.const 3)) (i64.const 1))
(assert_return (invoke "irem" (i64.const -10) (i64.const 3)) (i64.const -1))
(assert_return (invoke "irem" (i64.const 10) (i64.const -3)) (i64.const 1))
(assert_return (invoke "irem" (i64.const -10) (i64.const -3)) (i64.const -1))
(assert_return (invoke "irem" (i64.const 0) (i64.const 7)) (i64.const 0))

;; unsigned division
(assert_return (invoke "idiv_u" (i64.const 10) (i64.const 3)) (i64.const 3))
(assert_return (invoke "idiv_u" (i64.const 100) (i64.const 7)) (i64.const 14))

;; trap on division by zero
(assert_trap (invoke "idiv" (i64.const 1) (i64.const 0)) "integer divide by zero")
(assert_trap (invoke "irem" (i64.const 1) (i64.const 0)) "integer divide by zero")
