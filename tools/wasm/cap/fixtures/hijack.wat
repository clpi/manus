;; THE HIJACK. The exact module this host once executed `fd_write` for: the
;; field name has length 8 with name[0]='f', name[1]='d', name[3]='w', which is
;; every bit the old mask tested, and the module name is not preview1.
;; wasmtime: `unknown import: totally_not_wasi::fdxwrite`, refuses to
;; instantiate. This host must refuse it TWICE over — once because the names do
;; not resolve, once because the pair is in no grant.
(module
  (import "totally_not_wasi" "fdxwrite"
    (func $fdxwrite (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 1)
  (data (i32.const 100) "HIJACKED\n")
  (func (export "_start")
    (i32.store (i32.const 8) (i32.const 100))
    (i32.store (i32.const 12) (i32.const 9))
    (drop (call $fdxwrite (i32.const 1) (i32.const 8) (i32.const 1) (i32.const 20)))))
