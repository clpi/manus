;; MINIMAL PAIR, function half. Byte-for-byte identical to imp_pair_mem.wat
;; except for the import's KIND. If the unit's verdict tracks anything other
;; than the kind byte, these two cannot both be answered correctly.
(module
  (import "env" "x" (func))
  (func (export "run") (result i32) (i32.const 1)))
