from z3 import *
a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r, s, t, u = \
    Bools('a b c d e f g h i j k l m n o p q r s t u')
s = Solver()
s.add(Implies(a, b), Implies(b, c), Implies(c, d), Implies(d, e),
      Implies(e, f), Implies(f, g), Implies(g, h), Implies(h, i),
      Implies(i, j), Implies(j, k), Implies(k, l), Implies(l, m),
      Implies(m, n), Implies(n, o), Implies(o, p), Implies(p, q),
      Implies(q, r), Implies(r, s), Implies(s, t), Implies(t, u),
      Not(Implies(a, u)))
print(s.check())
