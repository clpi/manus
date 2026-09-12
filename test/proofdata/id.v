Theorem idprop : forall A : Prop, A -> A.
Proof.
  intros A H.
  exact H.
Qed.

Theorem comp : forall A B C : Prop,
  (A -> B) -> ((B -> C) -> (A -> C)).
Proof.
  intros A B C f g x.
  apply g.
  apply f.
  exact x.
Qed.

Theorem chain20 : forall a b c d e f g h i j k l m n o p q r s t u : Prop,
  (a -> b) -> (b -> c) -> (c -> d) -> (d -> e) -> (e -> f) ->
  (f -> g) -> (g -> h) -> (h -> i) -> (i -> j) -> (j -> k) ->
  (k -> l) -> (l -> m) -> (m -> n) -> (n -> o) -> (o -> p) ->
  (p -> q) -> (q -> r) -> (r -> s) -> (s -> t) -> (t -> u) ->
  (a -> u).
Proof.
  intros a b c d e f g h i j k l m n o p q r s t u
    i1 i2 i3 i4 i5 i6 i7 i8 i9 i10 i11 i12 i13 i14 i15 i16 i17 i18 i19 i20 x.
  apply i20. apply i19. apply i18. apply i17. apply i16.
  apply i15. apply i14. apply i13. apply i12. apply i11.
  apply i10. apply i9. apply i8. apply i7. apply i6.
  apply i5. apply i4. apply i3. apply i2. apply i1. exact x.
Qed.
