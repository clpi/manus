;; NO IMPORTS AT ALL. Must run identically under every grant including `none`:
;; a grant governs what a guest may REACH, never what it may COMPUTE. If this
;; row ever moves, the mechanism has started refusing programs it has no
;; opinion about.
(module
  (func (export "run") (result i32)
    (i32.add (i32.const 20) (i32.const 22))))
