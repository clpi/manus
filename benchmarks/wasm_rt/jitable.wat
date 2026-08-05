(module
  ;; Only opcodes the tier-1 JIT supports: local.*, i32 arith/compare, loop, br_if.
  (func $compute (export "compute") (param $n i32) (result i32)
    (local $i i32) (local $acc i32)
    (local.set $i (i32.const 0))
    (local.set $acc (i32.const 1))
    (loop $L
      (local.set $acc
        (i32.add (i32.mul (local.get $acc) (i32.const 31)) (local.get $i)))
      (local.set $i (i32.add (local.get $i) (i32.const 1)))
      (br_if $L (i32.lt_s (local.get $i) (local.get $n)))
    )
    (local.get $acc)
  )
)
