;; f64 arithmetic: add, sub, mul, div, sqrt, abs, neg, ceil, floor, trunc, nearest, min, max, copysign
(module
  (func $fadd     (export "fadd")     (param f64 f64) (result f64) local.get 0  local.get 1  f64.add)
  (func $fsub     (export "fsub")     (param f64 f64) (result f64) local.get 0  local.get 1  f64.sub)
  (func $fmul     (export "fmul")     (param f64 f64) (result f64) local.get 0  local.get 1  f64.mul)
  (func $fdiv     (export "fdiv")     (param f64 f64) (result f64) local.get 0  local.get 1  f64.div)
  (func $fsqrt    (export "fsqrt")    (param f64)     (result f64) local.get 0  f64.sqrt)
  (func $fabs     (export "fabs")     (param f64)     (result f64) local.get 0  f64.abs)
  (func $fneg     (export "fneg")     (param f64)     (result f64) local.get 0  f64.neg)
  (func $fceil    (export "fceil")    (param f64)     (result f64) local.get 0  f64.ceil)
  (func $ffloor   (export "ffloor")   (param f64)     (result f64) local.get 0  f64.floor)
  (func $ftrunc   (export "ftrunc")   (param f64)     (result f64) local.get 0  f64.trunc)
  (func $fnearest (export "fnearest") (param f64)     (result f64) local.get 0  f64.nearest)
  (func $fmin     (export "fmin")     (param f64 f64) (result f64) local.get 0  local.get 1  f64.min)
  (func $fmax     (export "fmax")     (param f64 f64) (result f64) local.get 0  local.get 1  f64.max)
  (func $f2i      (export "f2i")      (param f64)     (result i64) local.get 0  i64.trunc_f64_s)
  (func $i2f      (export "i2f")      (param i64)     (result f64) local.get 0  f64.convert_i64_s)
)

;; basic arithmetic
(assert_return (invoke "fadd" (f64.const 1.5) (f64.const 2.5)) (f64.const 4.0))
(assert_return (invoke "fsub" (f64.const 5.0) (f64.const 3.0)) (f64.const 2.0))
(assert_return (invoke "fmul" (f64.const 2.0) (f64.const 3.5)) (f64.const 7.0))
(assert_return (invoke "fdiv" (f64.const 7.0) (f64.const 2.0)) (f64.const 3.5))

;; sqrt
(assert_return (invoke "fsqrt" (f64.const 4.0)) (f64.const 2.0))
(assert_return (invoke "fsqrt" (f64.const 9.0)) (f64.const 3.0))
(assert_return (invoke "fsqrt" (f64.const 0.0)) (f64.const 0.0))

;; abs / neg
(assert_return (invoke "fabs" (f64.const -5.0)) (f64.const 5.0))
(assert_return (invoke "fabs" (f64.const 5.0))  (f64.const 5.0))
(assert_return (invoke "fneg" (f64.const 3.0))  (f64.const -3.0))
(assert_return (invoke "fneg" (f64.const -3.0)) (f64.const 3.0))

;; rounding
(assert_return (invoke "fceil"    (f64.const 1.1))  (f64.const 2.0))
(assert_return (invoke "fceil"    (f64.const -1.9)) (f64.const -1.0))
(assert_return (invoke "ffloor"   (f64.const 1.9))  (f64.const 1.0))
(assert_return (invoke "ffloor"   (f64.const -1.1)) (f64.const -2.0))
(assert_return (invoke "ftrunc"   (f64.const 1.9))  (f64.const 1.0))
(assert_return (invoke "ftrunc"   (f64.const -1.9)) (f64.const -1.0))
(assert_return (invoke "fnearest" (f64.const 1.4))  (f64.const 1.0))
(assert_return (invoke "fnearest" (f64.const 1.6))  (f64.const 2.0))

;; min / max
(assert_return (invoke "fmin" (f64.const 1.0) (f64.const 2.0)) (f64.const 1.0))
(assert_return (invoke "fmax" (f64.const 1.0) (f64.const 2.0)) (f64.const 2.0))

;; f64 <-> i64 conversion
(assert_return (invoke "f2i" (f64.const 3.9))  (i64.const 3))
(assert_return (invoke "f2i" (f64.const -3.9)) (i64.const -3))
(assert_return (invoke "i2f" (i64.const 42))   (f64.const 42.0))
(assert_return (invoke "i2f" (i64.const -10))  (f64.const -10.0))

;; special values
(assert_return (invoke "fdiv" (f64.const 1.0) (f64.const 0.0)) (f64.const inf))
(assert_return (invoke "fdiv" (f64.const -1.0) (f64.const 0.0)) (f64.const -inf))
