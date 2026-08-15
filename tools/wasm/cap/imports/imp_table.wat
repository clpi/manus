;; A TABLE import. Same question as the memory one, different import kind byte.
(module
  (import "wasi_snapshot_preview1" "table" (table 1 funcref))
  (func (export "run") (result i32) (i32.const 98)))
