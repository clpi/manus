;; A MEMORY import. wasmtime: `unknown import: wasi_snapshot_preview1::memory`.
(module
  (import "wasi_snapshot_preview1" "memory" (memory 1))
  (func (export "run") (result i32) (i32.const 99)))
