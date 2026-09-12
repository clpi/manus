idprop : (A : Set) → A → A
idprop A x = x

comp : (A B C : Set) → (A → B) → (B → C) → (A → C)
comp A B C f g x = g (f x)

chain20 : (a b c d e f g h i j k l m n o p q r s t u : Set) →
  (a → b) → (b → c) → (c → d) → (d → e) → (e → f) →
  (f → g) → (g → h) → (h → i) → (i → j) → (j → k) →
  (k → l) → (l → m) → (m → n) → (n → o) → (o → p) →
  (p → q) → (q → r) → (r → s) → (s → t) → (t → u) →
  (a → u)
chain20 a b c d e f g h i j k l m n o p q r s t u
  i1 i2 i3 i4 i5 i6 i7 i8 i9 i10 i11 i12 i13 i14 i15 i16 i17 i18 i19 i20 x =
  i20 (i19 (i18 (i17 (i16 (i15 (i14 (i13 (i12 (i11
    (i10 (i9 (i8 (i7 (i6 (i5 (i4 (i3 (i2 (i1 x)))))))))))))))))))
