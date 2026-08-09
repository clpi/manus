(module
  ;; Heavy compute benchmark: nested loops + arithmetic
  (func $compute (param $n i32) (result i32)
    (local $i i32)
    (local $j i32)
    (local $sum i32)
    (local $prod i32)
    (local $temp i32)
    
    i32.const 0
    local.set $sum
    i32.const 1
    local.set $prod
    i32.const 0
    local.set $i
    
    (block $break_outer
      (loop $continue_outer
        local.get $i
        local.get $n
        i32.ge_s
        br_if $break_outer
        
        i32.const 0
        local.set $j
        
        (block $break_inner
          (loop $continue_inner
            local.get $j
            local.get $n
            i32.ge_s
            br_if $break_inner
            
            ;; temp = i * j + sum
            local.get $i
            local.get $j
            i32.mul
            local.get $sum
            i32.add
            local.set $temp
            
            ;; sum = sum + temp
            local.get $sum
            local.get $temp
            i32.add
            local.set $sum
            
            ;; prod = (prod * 3 + 1) & 0x7FFFFFFF
            local.get $prod
            i32.const 3
            i32.mul
            i32.const 1
            i32.add
            i32.const 0x7FFFFFFF
            i32.and
            local.set $prod
            
            ;; j++
            local.get $j
            i32.const 1
            i32.add
            local.set $j
            
            br $continue_inner
          )
        )
        
        ;; i++
        local.get $i
        i32.const 1
        i32.add
        local.set $i
        
        br $continue_outer
      )
    )
    
    ;; return sum ^ prod
    local.get $sum
    local.get $prod
    i32.xor
  )
  
  (func $main (result i32)
    i32.const 500
    call $compute
  )
  
  (export "_start" (func $main))
)