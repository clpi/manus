;; Control flow: loop, block, br, br_if — numeric iteration patterns
(module
  ;; sum 1..n using loop + br_if
  (func $sum_n (export "sum_n") (param i64) (result i64)
    (local $acc i64)
    (local $i i64)
    i64.const 0
    local.set $acc
    i64.const 1
    local.set $i
    (block $done
      (loop $again
        (br_if $done (i64.gt_s (local.get $i) (local.get 0)))
        (i64.add (local.get $acc) (local.get $i))
        local.set $acc
        (i64.add (local.get $i) (i64.const 1))
        local.set $i
        br $again
      )
    )
    local.get $acc
  )

  ;; iterative fibonacci using loop
  (func $fib (export "fib") (param i64) (result i64)
    (local $a i64)
    (local $b i64)
    (local $c i64)
    (local $i i64)
    (if (i64.le_s (local.get 0) (i64.const 1))
      (then (return (local.get 0)))
    )
    i64.const 0  local.set $a
    i64.const 1  local.set $b
    i64.const 2  local.set $i
    (block $done
      (loop $again
        (br_if $done (i64.gt_s (local.get $i) (local.get 0)))
        (i64.add (local.get $a) (local.get $b)) local.set $c
        (local.get $b)  local.set $a
        (local.get $c)  local.set $b
        (i64.add (local.get $i) (i64.const 1)) local.set $i
        br $again
      )
    )
    local.get $b
  )

  ;; count divisors of n
  (func $count_divisors (export "count_divisors") (param i64) (result i64)
    (local $count i64)
    (local $i i64)
    i64.const 0  local.set $count
    i64.const 1  local.set $i
    (block $done
      (loop $again
        (br_if $done (i64.gt_s (local.get $i) (local.get 0)))
        (if (i64.eq (i64.rem_s (local.get 0) (local.get $i)) (i64.const 0))
          (then
            (i64.add (local.get $count) (i64.const 1))
            local.set $count
          )
        )
        (i64.add (local.get $i) (i64.const 1)) local.set $i
        br $again
      )
    )
    local.get $count
  )
)

;; sum_n
(assert_return (invoke "sum_n" (i64.const 0)) (i64.const 0))
(assert_return (invoke "sum_n" (i64.const 1)) (i64.const 1))
(assert_return (invoke "sum_n" (i64.const 10)) (i64.const 55))
(assert_return (invoke "sum_n" (i64.const 100)) (i64.const 5050))

;; fib
(assert_return (invoke "fib" (i64.const 0)) (i64.const 0))
(assert_return (invoke "fib" (i64.const 1)) (i64.const 1))
(assert_return (invoke "fib" (i64.const 2)) (i64.const 1))
(assert_return (invoke "fib" (i64.const 10)) (i64.const 55))
(assert_return (invoke "fib" (i64.const 20)) (i64.const 6765))

;; count_divisors
(assert_return (invoke "count_divisors" (i64.const 1)) (i64.const 1))
(assert_return (invoke "count_divisors" (i64.const 6)) (i64.const 4))
(assert_return (invoke "count_divisors" (i64.const 7)) (i64.const 2))
(assert_return (invoke "count_divisors" (i64.const 12)) (i64.const 6))
