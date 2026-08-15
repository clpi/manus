;; A memory import WITH A MAXIMUM: limits flags = 1, so the encoding is three
;; bytes (flags, min, max) not two.
(module
  (import "env" "memory" (memory 1 2))
  (func (export "run") (result i32) (i32.const 96)))
