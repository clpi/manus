;; environ_sizes_get is the one function this host ALREADY withheld, by a
;; hardcoded zero. Under a grant that denies it the answer must change from
;; "success, zero variables" to "notcapable" -- withholding by policy and
;; withholding by value are different facts and must not look the same.
(module
  (import "wasi_snapshot_preview1" "environ_sizes_get" (func $es (param i32 i32) (result i32)))
  (memory (export "memory") 1)
  (func (export "run") (result i32)
    (call $es (i32.const 8) (i32.const 16))))
