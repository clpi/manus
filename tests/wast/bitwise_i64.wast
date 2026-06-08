;; i64 bitwise operations: and, or, xor, shl, shr_s, shr_u, rotl, rotr, clz, ctz, popcnt
(module
  (func $band   (export "band")   (param i64 i64) (result i64) local.get 0  local.get 1  i64.and)
  (func $bor    (export "bor")    (param i64 i64) (result i64) local.get 0  local.get 1  i64.or)
  (func $bxor   (export "bxor")   (param i64 i64) (result i64) local.get 0  local.get 1  i64.xor)
  (func $shl    (export "shl")    (param i64 i64) (result i64) local.get 0  local.get 1  i64.shl)
  (func $shr_s  (export "shr_s")  (param i64 i64) (result i64) local.get 0  local.get 1  i64.shr_s)
  (func $shr_u  (export "shr_u")  (param i64 i64) (result i64) local.get 0  local.get 1  i64.shr_u)
  (func $rotl   (export "rotl")   (param i64 i64) (result i64) local.get 0  local.get 1  i64.rotl)
  (func $rotr   (export "rotr")   (param i64 i64) (result i64) local.get 0  local.get 1  i64.rotr)
  (func $clz    (export "clz")    (param i64)     (result i64) local.get 0  i64.clz)
  (func $ctz    (export "ctz")    (param i64)     (result i64) local.get 0  i64.ctz)
  (func $popcnt (export "popcnt") (param i64)     (result i64) local.get 0  i64.popcnt)
)

;; and
(assert_return (invoke "band" (i64.const 0xFF) (i64.const 0x0F)) (i64.const 15))
(assert_return (invoke "band" (i64.const 0) (i64.const -1)) (i64.const 0))
(assert_return (invoke "band" (i64.const -1) (i64.const -1)) (i64.const -1))
(assert_return (invoke "band" (i64.const 0xAA) (i64.const 0x55)) (i64.const 0))

;; or
(assert_return (invoke "bor" (i64.const 0xF0) (i64.const 0x0F)) (i64.const 255))
(assert_return (invoke "bor" (i64.const 0) (i64.const 0)) (i64.const 0))
(assert_return (invoke "bor" (i64.const 0xAA) (i64.const 0x55)) (i64.const 255))

;; xor
(assert_return (invoke "bxor" (i64.const 0xFF) (i64.const 0xFF)) (i64.const 0))
(assert_return (invoke "bxor" (i64.const 0xAA) (i64.const 0x55)) (i64.const 255))
(assert_return (invoke "bxor" (i64.const -1) (i64.const 0)) (i64.const -1))

;; shl
(assert_return (invoke "shl" (i64.const 1) (i64.const 0)) (i64.const 1))
(assert_return (invoke "shl" (i64.const 1) (i64.const 8)) (i64.const 256))
(assert_return (invoke "shl" (i64.const 1) (i64.const 63)) (i64.const -9223372036854775808))

;; shr_s (arithmetic right shift)
(assert_return (invoke "shr_s" (i64.const 256) (i64.const 4)) (i64.const 16))
(assert_return (invoke "shr_s" (i64.const -256) (i64.const 4)) (i64.const -16))
(assert_return (invoke "shr_s" (i64.const -1) (i64.const 63)) (i64.const -1))

;; shr_u (logical right shift)
(assert_return (invoke "shr_u" (i64.const 256) (i64.const 4)) (i64.const 16))
(assert_return (invoke "shr_u" (i64.const -1) (i64.const 63)) (i64.const 1))

;; clz (count leading zeros)
(assert_return (invoke "clz" (i64.const 1)) (i64.const 63))
(assert_return (invoke "clz" (i64.const -1)) (i64.const 0))

;; ctz (count trailing zeros)
(assert_return (invoke "ctz" (i64.const 1)) (i64.const 0))
(assert_return (invoke "ctz" (i64.const 256)) (i64.const 8))
(assert_return (invoke "ctz" (i64.const -1)) (i64.const 0))

;; popcnt (population count)
(assert_return (invoke "popcnt" (i64.const 0)) (i64.const 0))
(assert_return (invoke "popcnt" (i64.const -1)) (i64.const 64))
(assert_return (invoke "popcnt" (i64.const 255)) (i64.const 8))
(assert_return (invoke "popcnt" (i64.const 170)) (i64.const 4))
