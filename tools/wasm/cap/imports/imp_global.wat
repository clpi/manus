;; A GLOBAL import. Import kind byte 3.
(module
  (import "wasi_snapshot_preview1" "g" (global i32))
  (func (export "run") (result i32) (i32.const 97)))
