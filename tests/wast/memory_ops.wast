;; Memory: load, store, grow, size — linear memory operations
(module
  (memory (export "memory") 1)

  ;; store/load i64
  (func $store_i64 (export "store_i64") (param i32 i64)
    local.get 0  local.get 1  i64.store)
  (func $load_i64 (export "load_i64") (param i32) (result i64)
    local.get 0  i64.load)

  ;; store/load i32
  (func $store_i32 (export "store_i32") (param i32 i32)
    local.get 0  local.get 1  i32.store)
  (func $load_i32 (export "load_i32") (param i32) (result i32)
    local.get 0  i32.load)

  ;; store/load f64
  (func $store_f64 (export "store_f64") (param i32 f64)
    local.get 0  local.get 1  f64.store)
  (func $load_f64 (export "load_f64") (param i32) (result f64)
    local.get 0  f64.load)

  ;; memory.size / memory.grow
  (func $mem_size (export "mem_size") (result i32)
    memory.size)
  (func $mem_grow (export "mem_grow") (param i32) (result i32)
    local.get 0  memory.grow)

  ;; byte store/load (i32.store8 / i32.load8_u)
  (func $store_byte (export "store_byte") (param i32 i32)
    local.get 0  local.get 1  i32.store8)
  (func $load_byte (export "load_byte") (param i32) (result i32)
    local.get 0  i32.load8_u)

  ;; array fill: store n consecutive i64 values then sum
  (func $fill_and_sum (export "fill_and_sum") (param i32 i64 i32) (result i64)
    (local $i i32)
    (local $sum i64)
    ;; fill: memory[base + i*8] = val for i in 0..count
    i32.const 0  local.set $i
    (block $done
      (loop $again
        (br_if $done (i32.ge_u (local.get $i) (local.get 2)))
        (i32.add (local.get 0) (i32.mul (local.get $i) (i32.const 8)))
        local.get 1
        i64.store
        (i32.add (local.get $i) (i32.const 1))  local.set $i
        br $again
      )
    )
    ;; sum
    i64.const 0  local.set $sum
    i32.const 0  local.set $i
    (block $done2
      (loop $again2
        (br_if $done2 (i32.ge_u (local.get $i) (local.get 2)))
        (i64.add (local.get $sum)
          (i64.load (i32.add (local.get 0) (i32.mul (local.get $i) (i32.const 8)))))
        local.set $sum
        (i32.add (local.get $i) (i32.const 1))  local.set $i
        br $again2
      )
    )
    local.get $sum
  )
)

;; i64 round-trip
(invoke "store_i64" (i32.const 0) (i64.const 42))
(assert_return (invoke "load_i64" (i32.const 0)) (i64.const 42))

(invoke "store_i64" (i32.const 0) (i64.const -1))
(assert_return (invoke "load_i64" (i32.const 0)) (i64.const -1))

(invoke "store_i64" (i32.const 16) (i64.const 9999999))
(assert_return (invoke "load_i64" (i32.const 16)) (i64.const 9999999))

;; i32 round-trip
(invoke "store_i32" (i32.const 0) (i32.const 100))
(assert_return (invoke "load_i32" (i32.const 0)) (i32.const 100))

;; f64 round-trip
(invoke "store_f64" (i32.const 32) (f64.const 3.14))
(assert_return (invoke "load_f64" (i32.const 32)) (f64.const 3.14))

;; byte round-trip
(invoke "store_byte" (i32.const 0) (i32.const 255))
(assert_return (invoke "load_byte" (i32.const 0)) (i32.const 255))
(invoke "store_byte" (i32.const 0) (i32.const 0))
(assert_return (invoke "load_byte" (i32.const 0)) (i32.const 0))

;; memory.size starts at 1
(assert_return (invoke "mem_size") (i32.const 1))

;; fill_and_sum: fill 4 slots with 5, expect sum = 20
(assert_return (invoke "fill_and_sum" (i32.const 100) (i64.const 5) (i32.const 4)) (i64.const 20))
;; fill 3 slots with 10 at offset 200
(assert_return (invoke "fill_and_sum" (i32.const 200) (i64.const 10) (i32.const 3)) (i64.const 30))
