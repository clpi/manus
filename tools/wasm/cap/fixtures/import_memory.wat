;; A NON-FUNCTION import. The grant governs function imports; this asks whether
;; anything else in the import section can reach the host. wasmtime refuses it
;; (unknown import); what this engine does is the question.
(module
  (import "wasi_snapshot_preview1" "memory" (memory 1))
  (func (export "run") (result i32) (i32.const 99)))
