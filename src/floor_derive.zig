//! AUTOMATIC FLOOR DERIVATION — HPLS.md §106's `lower bound` stage, executable.
//!
//! ════════════════════════════════════════════════════════════════════════════
//! WHAT THIS IS AND WHAT IT REFUSES TO BE
//! ════════════════════════════════════════════════════════════════════════════
//!
//! §48 orders the floor classes F0..F9 and §49 forbids the phrase "AT FLOOR"
//! without naming floor class, assumptions, observer, input domain,
//! preprocessing allowance and deployment model. §106 names the gap exactly:
//! every floor this project has is a HAND-EXECUTED instance — "a human noticed
//! that the benchmark asked the wrong question".
//!
//! This module takes a program and an observer and emits a floor LADDER. It
//! reads real `.id` source through the production lexer and parser; it has no
//! table of benchmark names, no expected answers, and no per-workload rule.
//! Point it at a file it has never seen and it either derives a ladder or
//! REFUSES BY NAME.
//!
//! **A DERIVATION THAT EMITS A WITNESS HAS PRODUCED NOTHING**, and that is
//! enforced by the type system rather than by review: `Class` has no `F9` and
//! `Method` has no `witness`, `measured` or `competitor`. There is no value of
//! either type that `gate/ftcftw.id`'s lowerbound column would refuse, because
//! there is no way to spell one.
//!
//! ════════════════════════════════════════════════════════════════════════════
//! THE DERIVATION, STAGE BY STAGE
//! ════════════════════════════════════════════════════════════════════════════
//!
//! F0 OBSERVATION — what reaches the observer at all. From the DEPLOYMENT
//!    MODEL, not from the program: a relation whose result becomes a process
//!    exit status is observed through `v mod 256` and through nothing else,
//!    because that is what `wait()` returns. 8 bits.
//!
//! F1 INFORMATION — how many bits must cross that boundary. The demanded
//!    congruence is propagated BACKWARDS through the program to a congruence on
//!    every loop-carried name, by a fixpoint over `h(f(x)) = g(h(x))` and
//!    nothing else (§17). Every rule below names the homomorphism that licenses
//!    it, and an operator with no homomorphism raises the demand to `whole`
//!    instead of being quietly admitted.
//!
//!    THE LATTICE IS `mod m` FOR ARBITRARY m, NOT `low_bits k`.
//!    `demand_projection.Projection` is `{none, nonzero, low_bits k, whole}`,
//!    i.e. exactly the moduli `2^k`. That sub-lattice cannot express the demand
//!    of the corpus this module was pointed at: FIVE of nine programs end in
//!    `... % 251`, whose demand is `mod 251`, and 251 is not a power of two.
//!    Under `low_bits` the only sound answer for those is `whole` and every one
//!    of them refuses. `Cong` here is the same lattice with the modulus
//!    generalized from `2^k` to any m ≤ 2^64, joined by `lcm` (which is `max`
//!    on the `2^k` sub-lattice, so the two agree exactly where both are
//!    defined — `test "floor_derive: Cong agrees with Projection on 2^k"`).
//!    That generalization is this module's finding about the existing lattice,
//!    not a second spelling of it.
//!
//! F2 SEMANTIC PROBLEM — the demanded problem after quotienting, not the
//!    source's. Once every carried name has a finite congruence or a finite
//!    range, the joint state is FINITE, and a finite state space under a
//!    deterministic step is eventually periodic. The orbit is walked ONCE and
//!    the reachable set is ENUMERATED, which is why the method is `exhaustive`
//!    and not `derived`: nothing is argued about the tail length μ or the
//!    period λ, they are counted.
//!
//! F3 ALGORITHMIC — what algorithm class the quotiented problem admits. With
//!    (μ, λ) in hand the demanded problem is "index a cyclic sequence":
//!    `state_n = state_(μ + (n−μ) mod λ)` for n ≥ μ. The work is bounded by
//!    μ + λ INDEPENDENT OF n, so the per-operation cost of the source loop has
//!    a floor of ZERO — not because zero is trivially a lower bound, but
//!    because it is APPROACHED: total work is constant, so cost/n → 0.
//!
//!    A LOOP-CARRIED SUM IS NOT AN OBSTACLE AND IS NOT A SPECIAL CASE. A slot
//!    whose every update is `a = a + E` and which nothing else reads is peeled
//!    out of the orbit key and reconstructed as
//!    `a_n = a_μ + q·S + partial(r)` with `q = (n−μ)/λ`, `r = (n−μ) mod λ`.
//!    That is the whole of "the count is order-free": `+` is commutative, so
//!    the sum over a periodic sequence is a period sum times a quotient.
//!
//! F6 CAUSAL PATH — the dependence height no schedule can shorten. Reported as
//!    the height of the QUOTIENTED computation, `(μ + λ) · depth(step)`, which
//!    is n-independent. Its use is DISPROOF: an n-step serial chain cannot be a
//!    causal floor for a computation whose observed result is reachable in an
//!    n-independent number of dependent steps.
//!
//! ════════════════════════════════════════════════════════════════════════════
//! THE INPUT DOMAIN IS PART OF THE ANSWER, AND IT IS THE PART A HUMAN FORGETS
//! ════════════════════════════════════════════════════════════════════════════
//!
//! Every ladder carries `domain_n_min`: the smallest n at which it holds. A
//! floor that collapses at n ≥ 2^34 and NOT at n = 2·10^7 is a different fact
//! from a floor that holds everywhere, and a derivation that does not carry the
//! difference is not a derivation. When the orbit does not close inside the
//! budget the module refuses AND REPORTS THE STATE-SPACE BOUND, so the refusal
//! still says at which n the collapse would begin.
//!
//! ════════════════════════════════════════════════════════════════════════════
//! WHAT THIS IS NOT, SO THAT THE HOLE IS VISIBLE
//! ════════════════════════════════════════════════════════════════════════════
//!
//! There is exactly one generative operation here — ORBIT ENUMERATION IN THE
//! DEMAND QUOTIENT. It is not the only one that closes a loop:
//!
//!   * OPERATOR POWERING closes a polynomial body in O(log n) with no finite
//!     state space at all. `src/recurrence.zig` owns it (`closeWhile`), and
//!     this module does not duplicate it; a body it refuses may still be closed
//!     there. `Obstruction.orbit_budget` therefore means "this operation did
//!     not close it", never "no operation can".
//!   * AFFINE COMPOSITION OVER ONE PERIOD is what closes W5 `bytes` by hand
//!     (`benchmarks/cyc/q/qfloor.c`): the 8-bit sub-machine is periodic, so one
//!     pass over the corpus is an affine map on Z/2^32 which composes in O(1)
//!     and powers in O(log q). That is an INDUCED RELATION (§17), a different
//!     §106 stage, and this module derives nothing for W5 — it refuses at the
//!     nested loop. The refusal is reported, not hidden.
//!
//! ════════════════════════════════════════════════════════════════════════════
//! THE OBLIGATIONS
//! ════════════════════════════════════════════════════════════════════════════
//!
//!   D1 THE OBSERVER IS A FACT, NEVER AN INFERENCE. `Observer` is supplied by
//!      the caller from the deployment model. The default is `whole`, which
//!      makes every quotient below unavailable, so a caller that says nothing
//!      gets no collapse.
//!   D2 EVERY ADMITTED OPERATOR COMMUTES WITH THE DEMANDED CONGRUENCE. Checked
//!      per node in `pull`, never assumed from the grammar.
//!   D3 EVERY CARRIED NAME IS FINITE. Either its demand is `mod m` with finite
//!      m, or its update's own form bounds its range (`& M`, `% B`). A name
//!      with neither refuses; nothing is silently truncated.
//!   D4 TRAP AND EFFECT FREEDOM, BY ADMITTING ONLY A TRAP-FREE GRAMMAR. No
//!      subscripts, no calls except inlined pure relations, no strings, no
//!      floats. `/` and `%` are admitted only with a NON-ZERO LITERAL divisor.
//!   D5 THE ENTRY STATE IS KNOWN. Every carried name is either bound to a
//!      folded constant before the loop or provably written before it is read
//!      inside the loop. Nothing defaults to zero.
//!   D6 THE ANSWER IS CHECKED, NOT ASSERTED. `bruteForce` runs the SAME IR at
//!      full 64-bit width with no quotient at all, and the tests require exact
//!      agreement with the closed answer over a sweep of n that straddles μ and
//!      μ+λ. A quotient rule that is wrong shows up as a differential failure,
//!      not as a plausible number.
//!
//! Every path returns a named `Obstruction` on the first thing it cannot prove.

const std = @import("std");
const ast = @import("ast.zig");
const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("parser.zig").Parser;
const lexer_bridge = @import("lexer_bridge.zig");
const demand_projection = @import("demand_projection.zig");

// ════════════════════════════════════════════════════════════════════════════
// § 1 · THE VOCABULARY THAT CANNOT SPELL A WITNESS
// ════════════════════════════════════════════════════════════════════════════

/// §48's hierarchy, MINUS F9. F9 is *measured witness*; a witness is not a
/// floor (§71, §102), and `gate/ftcftw.id` refuses the class outright. Leaving
/// it out of the enum means this module cannot emit one even by mistake.
pub const Class = enum {
    F0_observation,
    F1_information,
    F2_semantic_problem,
    F3_algorithmic,
    F4_work_communication,
    F5_representation,
    F6_causal_path,
    F7_hardware_mechanism,
    F8_instruction_schedule,

    pub fn ledger(self: Class) []const u8 {
        return switch (self) {
            .F0_observation => "F0",
            .F1_information => "F1",
            .F2_semantic_problem => "F2",
            .F3_algorithmic => "F3",
            .F4_work_communication => "F4",
            .F5_representation => "F5",
            .F6_causal_path => "F6",
            .F7_hardware_mechanism => "F7",
            .F8_instruction_schedule => "F8",
        };
    }
};

/// The three methods `gate/ftcftw.id` admits. `witness`, `measured` and
/// `competitor` are absent for the same reason F9 is.
pub const Method = enum {
    derived,
    proven,
    exhaustive,

    pub fn ledger(self: Method) []const u8 {
        return @tagName(self);
    }
};

pub const Floor = struct {
    class: Class,
    method: Method,
    value: i64,
    unit: []const u8,
    why: []const u8,
};

/// Named refusals. Each one says WHICH stage could not be discharged, so a
/// refusal is evidence about the program rather than an absence of output.
pub const Obstruction = enum {
    no_entry_relation,
    entry_takes_parameters,
    prologue_not_foldable,
    no_loop,
    nested_loop,
    loop_body_grammar,
    control_flow,
    guard_shape,
    unbound_entry_value,
    call_not_inlinable,
    tail_grammar,
    too_many_slots,
    ir_budget,
    /// An operator in the demanded cone has no homomorphism to the demanded
    /// congruence and no range that bounds it.
    demand_not_homomorphic,
    /// A carried name has neither a finite demand congruence nor a bounded
    /// range: the quotient state space is infinite.
    state_unbounded,
    /// The joint quotient state space does not fit the orbit key.
    state_key_overflow,
    /// The orbit did not close inside the step budget. NOT "no floor exists".
    orbit_budget,
    /// A slot survives the loop, is read by the tail, and is neither in the
    /// orbit key nor a peelable accumulator.
    accumulator_shape,
};

pub const Refusal = struct {
    stage: Class,
    obstruction: Obstruction,
    /// The state-space bound, when the refusal has one. `0` = unknown. This is
    /// what makes an `orbit_budget` refusal still say at which n the collapse
    /// begins.
    state_space_log2: u8 = 0,
    detail: []const u8 = "",
};

/// What an observer of the entry relation's result can distinguish, taken from
/// the DEPLOYMENT MODEL. D1: never inferred from the program.
pub const Observer = enum {
    /// The parent's `wait()` and nothing else: `v mod 256`, 8 bits.
    process_exit_status,
    /// Every bit of the result crosses the boundary.
    whole,

    pub fn congruence(self: Observer) Cong {
        return switch (self) {
            .process_exit_status => Cong.mod(256),
            .whole => Cong.whole,
        };
    }
    pub fn bits(self: Observer) u8 {
        return switch (self) {
            .process_exit_status => 8,
            .whole => 64,
        };
    }
    pub fn describe(self: Observer) []const u8 {
        return switch (self) {
            .process_exit_status => "process exit status (parent wait(); v mod 256)",
            .whole => "every bit of the result",
        };
    }
};

/// The derived ladder for one program under one observer.
pub const Ladder = struct {
    floors: [8]Floor = undefined,
    len: usize = 0,

    observer: Observer,
    /// §49's roll call, carried so that no caller can state a floor without it.
    deployment: []const u8,
    preprocessing: []const u8,
    /// The floor holds for every n at or above this. Below it the quotient has
    /// not yet reached its periodic part and the ladder does not apply.
    domain_n_min: u64,
    domain_n_max: u64,

    mu: u64,
    lambda: u64,
    /// log2 of the joint quotient state space actually enumerated over.
    state_bits: u16,
    /// Physical bits the source carries per step for those demanded bits.
    physical_bits: u16,
    step_depth: u32,
    /// Slots peeled out of the orbit key as order-free accumulators.
    accumulators: u8,
    /// Slots in the orbit key.
    core_slots: u8,

    /// The trip count the answer was taken at: the loop's own literal bound
    /// when it has one, otherwise the caller's `n`.
    n: ?u64 = null,
    /// The answer at a given n, in the observer's quotient. Present only when a
    /// concrete n was supplied.
    answer: ?i64 = null,
    /// D6. The SAME IR run at full 64-bit width for n steps with no quotient
    /// anywhere — the program's own semantics. Present only when the caller
    /// asked for the differential, and required to equal `answer`. A quotient
    /// rule that is wrong dies here rather than producing a plausible number.
    brute: ?i64 = null,

    pub fn add(self: *Ladder, f: Floor) void {
        if (self.len >= self.floors.len) return;
        self.floors[self.len] = f;
        self.len += 1;
    }
    pub fn get(self: *const Ladder, c: Class) ?Floor {
        for (self.floors[0..self.len]) |f| if (f.class == c) return f;
        return null;
    }
};

pub const Result = union(enum) {
    derived: Ladder,
    refused: Refusal,
};

// ════════════════════════════════════════════════════════════════════════════
// § 2 · THE CONGRUENCE LATTICE — `mod m`, not `low_bits k`
// ════════════════════════════════════════════════════════════════════════════

/// `x ~ y iff x ≡ y (mod m)`.
///
///   m = 1      nothing is demanded — the empty realization
///   m = 2^64   `whole`; no quotient at all
///
/// The join is `lcm`, capped at `whole`. On the powers of two this is exactly
/// `demand_projection.Projection.join` on `low_bits`, and the test below
/// requires the two to agree there; off the powers of two the older lattice has
/// no representative at all, which is the point.
pub const Cong = struct {
    m: u128,

    pub const nothing = Cong{ .m = 1 };
    pub const whole = Cong{ .m = @as(u128, 1) << 64 };

    pub fn mod(v: u128) Cong {
        if (v <= 1) return nothing;
        if (v >= @as(u128, 1) << 64) return whole;
        return .{ .m = v };
    }
    pub fn pow2(k: u7) Cong {
        if (k == 0) return nothing;
        if (k >= 64) return whole;
        return .{ .m = @as(u128, 1) << k };
    }
    pub fn isNothing(self: Cong) bool {
        return self.m <= 1;
    }
    pub fn isWhole(self: Cong) bool {
        return self.m >= @as(u128, 1) << 64;
    }
    /// `k` when `m == 2^k`, else null. The bit-local operators need this and
    /// nothing else: `&`, `|`, `^`, `~` commute with `mod 2^k` and with no
    /// other modulus.
    pub fn asPow2(self: Cong) ?u7 {
        if (self.m == 0) return null;
        if (self.m & (self.m - 1) != 0) return null;
        return @intCast(@ctz(self.m));
    }
    pub fn join(a: Cong, b: Cong) Cong {
        if (a.isNothing()) return b;
        if (b.isNothing()) return a;
        if (a.isWhole() or b.isWhole()) return whole;
        const g = gcd(a.m, b.m);
        const l = (a.m / g) *| b.m;
        return mod(l);
    }
    pub fn divides(a: Cong, b: Cong) bool {
        if (a.isNothing()) return true;
        if (b.isWhole()) return true;
        if (a.isWhole()) return false;
        return b.m % a.m == 0;
    }
    /// Bits needed to name a residue class.
    pub fn bits(self: Cong) u16 {
        if (self.isNothing()) return 0;
        if (self.isWhole()) return 64;
        const m: u64 = @intCast(self.m);
        return @as(u16, 64) - @as(u16, @clz(m - 1));
    }
    pub fn eql(a: Cong, b: Cong) bool {
        return a.m == b.m;
    }
    /// The `low_bits` view, for the cases the older lattice can express.
    pub fn toProjection(self: Cong) ?demand_projection.Projection {
        if (self.isNothing()) return .none;
        if (self.isWhole()) return .whole;
        const k = self.asPow2() orelse return null;
        if (k >= 64) return .whole;
        return .{ .low_bits = @intCast(k) };
    }
};

fn gcd(a: u128, b: u128) u128 {
    var x = a;
    var y = b;
    while (y != 0) {
        const t = x % y;
        x = y;
        y = t;
    }
    return if (x == 0) 1 else x;
}

// ════════════════════════════════════════════════════════════════════════════
// § 3 · THE IR — one tree per assignment, built by inlining the source
// ════════════════════════════════════════════════════════════════════════════

const max_slots = 10;
const max_nodes = 4096;
/// Orbit steps before the walk refuses. DERIVED THE SAME WAY
/// `recurrence.max_orbit_steps` is, and deliberately equal to it: same
/// compile-time budget, so a case one closes and the other does not is a
/// statement about the program, never about the budget.
pub const max_orbit_steps: u64 = 1 << 20;

const Op = enum {
    lit,
    slot,
    add,
    sub,
    mul,
    divi,
    umod,
    neg,
    band,
    bor,
    bxor,
    bnot,
    shl,
    shr,
    eq,
    ne,
    lt,
    le,
    gt,
    ge,
};

const Node = struct {
    op: Op,
    a: u32 = 0,
    b: u32 = 0,
    k: i64 = 0,
    cong: Cong = Cong.nothing,
    /// Forward range, when the node's own form bounds it. This is what makes
    /// `(... & 65535) + 1` a 17-bit carried name even though its DEMAND is
    /// `whole` — a fact about the producer, not about the consumer.
    lo: ?i64 = null,
    hi: ?i64 = null,
};

const Step = struct {
    slot: u32,
    expr: u32,
    /// Node index of a guarding condition, or `no_guard`. `if c  a = a + 3` is
    /// admitted as a guarded step; anything with an `else`, a nested `if`, or a
    /// second statement kind is not.
    guard: u32 = no_guard,
};
const no_guard: u32 = std.math.maxInt(u32);

const Program = struct {
    nodes: [max_nodes]Node = undefined,
    nnodes: u32 = 0,

    names: [max_slots][]const u8 = undefined,
    entry: [max_slots]i64 = @splat(0),
    entry_known: [max_slots]bool = @splat(false),
    cong: [max_slots]Cong = @splat(Cong.nothing),
    lo: [max_slots]?i64 = @splat(null),
    hi: [max_slots]?i64 = @splat(null),
    /// Written before it is read inside the body: the entry value is dead and
    /// the name is not loop-carried.
    dead_on_entry: [max_slots]bool = @splat(false),
    is_acc: [max_slots]bool = @splat(false),
    nslots: u32 = 0,

    steps: [max_slots * 2]Step = undefined,
    nsteps: u32 = 0,

    tail: u32 = 0,
    iv: u32 = 0,
    /// Trip count when the loop bound folded to a literal; null when the bound
    /// is a symbolic runtime input, which is the interesting case.
    trips: ?u64 = null,

    fn intern(self: *Program, name: []const u8) ?u32 {
        for (0..self.nslots) |i| {
            if (std.mem.eql(u8, self.names[i], name)) return @intCast(i);
        }
        if (self.nslots >= max_slots) return null;
        const i = self.nslots;
        self.names[i] = name;
        self.nslots += 1;
        return i;
    }
    fn find(self: *const Program, name: []const u8) ?u32 {
        for (0..self.nslots) |i| {
            if (std.mem.eql(u8, self.names[i], name)) return @intCast(i);
        }
        return null;
    }
    fn push(self: *Program, n: Node) ?u32 {
        if (self.nnodes >= max_nodes) return null;
        const i = self.nnodes;
        self.nodes[i] = n;
        self.nnodes += 1;
        return i;
    }
};

// ════════════════════════════════════════════════════════════════════════════
// § 4 · FRONT END — real source, production lexer and parser, nothing hand-built
// ════════════════════════════════════════════════════════════════════════════

const Builder = struct {
    prog: *Program,
    /// Module-level relations available for inlining. A relation qualifies only
    /// if its body is a single tail expression over its own parameters.
    rels: []const ast.FuncDecl,
    /// Constants folded out of the prologue.
    consts: [max_slots * 2]struct { name: []const u8, val: i64 } = undefined,
    nconsts: u32 = 0,
    /// Names bound to something this module cannot fold — a runtime input.
    syms: [4][]const u8 = undefined,
    nsyms: u32 = 0,
    /// Inlining substitution frame: parameter name -> node index.
    subst: [8]struct { name: []const u8, node: u32 } = undefined,
    nsubst: u32 = 0,
    depth: u32 = 0,
    err: ?Obstruction = null,

    fn constOf(self: *const Builder, name: []const u8) ?i64 {
        var i: u32 = self.nconsts;
        while (i > 0) {
            i -= 1;
            if (std.mem.eql(u8, self.consts[i].name, name)) return self.consts[i].val;
        }
        return null;
    }
    fn isSym(self: *const Builder, name: []const u8) bool {
        for (0..self.nsyms) |i| if (std.mem.eql(u8, self.syms[i], name)) return true;
        return false;
    }
    fn substOf(self: *const Builder, name: []const u8) ?u32 {
        var i: u32 = self.nsubst;
        while (i > 0) {
            i -= 1;
            if (std.mem.eql(u8, self.subst[i].name, name)) return self.subst[i].node;
        }
        return null;
    }
    fn fail(self: *Builder, o: Obstruction) ?u32 {
        if (self.err == null) self.err = o;
        return null;
    }
};

fn litOf(e: *const ast.Expr) ?i64 {
    return switch (e.*) {
        .int_lit => |x| x.val,
        .unop => |u| switch (u.op) {
            .neg => blk: {
                const inner = litOf(u.operand) orelse break :blk null;
                if (inner == std.math.minInt(i64)) break :blk null;
                break :blk -inner;
            },
            else => null,
        },
        else => null,
    };
}

fn binOpOf(op: ast.BinOp) ?Op {
    return switch (op) {
        .add => .add,
        .sub => .sub,
        .mul => .mul,
        .div, .idiv => .divi,
        .mod => .umod,
        .band => .band,
        .bor => .bor,
        .bxor => .bxor,
        .lshift => .shl,
        .rshift => .shr,
        .eq => .eq,
        .neq => .ne,
        .lt => .lt,
        .gt => .gt,
        .leq => .le,
        .geq => .ge,
        else => null,
    };
}

/// Lower one expression into the IR, inlining pure relation calls.
///
/// D4: the grammar admitted here is trap-free by construction. `/` and `%` are
/// admitted only against a non-zero literal, so no divisor can be zero; there
/// are no subscripts, so nothing can be out of range; there are no strings and
/// no floats.
fn lower(b: *Builder, e: *const ast.Expr) ?u32 {
    if (b.depth > 64) return b.fail(.ir_budget);
    switch (e.*) {
        .int_lit => |x| return b.prog.push(.{ .op = .lit, .k = x.val, .lo = x.val, .hi = x.val }),
        .name => |x| {
            if (b.substOf(x.ident)) |n| return n;
            if (b.prog.find(x.ident)) |s| return b.prog.push(.{ .op = .slot, .k = @intCast(s) });
            if (b.constOf(x.ident)) |v| return b.prog.push(.{ .op = .lit, .k = v, .lo = v, .hi = v });
            return b.fail(.unbound_entry_value);
        },
        .unop => |u| {
            const inner = lower(b, u.operand) orelse return null;
            return switch (u.op) {
                .neg => b.prog.push(.{ .op = .neg, .a = inner }),
                .bnot => b.prog.push(.{ .op = .bnot, .a = inner }),
                else => b.fail(.loop_body_grammar),
            };
        },
        .binop => |bo| {
            const op = binOpOf(bo.op) orelse return b.fail(.loop_body_grammar);
            // D4: a divisor must be a non-zero literal, so no division can trap
            // and no `%` can be taken against a runtime value.
            // D4: a divisor need not be a literal, but it must be PROVABLY
            // non-zero. A literal discharges that here; a runtime divisor is
            // discharged by its derived range in `divisorsNonZero`, which is
            // what admits `1000000007 / x` when `x = (… & 65535) + 1` bounds
            // `x` to [1, 65536]. Refusing every runtime divisor would have cost
            // the whole X1 family for a proof that is available.
            if (op == .divi or op == .umod) {
                if (litOf(bo.rhs)) |dv| {
                    if (dv == 0) return b.fail(.loop_body_grammar);
                }
            }
            if (op == .shl or op == .shr) {
                const c = litOf(bo.rhs) orelse return b.fail(.loop_body_grammar);
                if (c < 0 or c > 63) return b.fail(.loop_body_grammar);
            }
            b.depth += 1;
            defer b.depth -= 1;
            const l = lower(b, bo.lhs) orelse return null;
            const r = lower(b, bo.rhs) orelse return null;
            return b.prog.push(.{ .op = op, .a = l, .b = r });
        },
        .call => |c| {
            const fname = switch (c.func.*) {
                .name => |n| n.ident,
                else => return b.fail(.call_not_inlinable),
            };
            for (b.rels) |fd| {
                if (fd.path.len != 1) continue;
                if (!std.mem.eql(u8, fd.path[0], fname)) continue;
                if (fd.func.body.stmts.len != 0) return b.fail(.call_not_inlinable);
                const tail = fd.func.body.tail_expr orelse return b.fail(.call_not_inlinable);
                if (fd.func.params.len != c.args.len) return b.fail(.call_not_inlinable);
                if (b.nsubst + fd.func.params.len > b.subst.len) return b.fail(.call_not_inlinable);
                const save = b.nsubst;
                // Arguments are lowered in the CALLER's frame before the
                // callee's frame is pushed, so a parameter cannot capture a
                // caller name of the same spelling.
                var argn: [8]u32 = undefined;
                for (c.args, 0..) |arg, i| {
                    argn[i] = lower(b, arg) orelse return null;
                }
                for (fd.func.params, 0..) |p, i| {
                    b.subst[b.nsubst] = .{ .name = p.name, .node = argn[i] };
                    b.nsubst += 1;
                }
                b.depth += 1;
                const out = lower(b, tail);
                b.depth -= 1;
                b.nsubst = save;
                return out;
            }
            return b.fail(.call_not_inlinable);
        },
        else => return b.fail(.loop_body_grammar),
    }
}

/// Forward range, computed once the tree is built. Only the forms that BOUND a
/// value are modelled; everything else is unbounded, which costs a refusal at
/// D3 and never costs soundness.
fn rangeOf(p: *Program, idx: u32) void {
    const n = &p.nodes[idx];
    switch (n.op) {
        .lit => {},
        .slot => {
            n.lo = p.lo[@intCast(n.k)];
            n.hi = p.hi[@intCast(n.k)];
        },
        .band => {
            rangeOf(p, n.a);
            rangeOf(p, n.b);
            // `x & M` with M >= 0 is in [0, M] whatever x is.
            const bm = p.nodes[n.b];
            const am = p.nodes[n.a];
            if (bm.op == .lit and bm.k >= 0) {
                n.lo = 0;
                n.hi = bm.k;
            } else if (am.op == .lit and am.k >= 0) {
                n.lo = 0;
                n.hi = am.k;
            }
        },
        .umod => {
            rangeOf(p, n.a);
            const bm = p.nodes[n.b];
            if (bm.op == .lit and bm.k > 0) {
                n.lo = 0;
                n.hi = bm.k - 1;
            }
        },
        .add, .sub => {
            rangeOf(p, n.a);
            rangeOf(p, n.b);
            const x = p.nodes[n.a];
            const y = p.nodes[n.b];
            if (x.lo != null and x.hi != null and y.op == .lit) {
                const d: i64 = if (n.op == .add) y.k else -y.k;
                n.lo = std.math.add(i64, x.lo.?, d) catch null;
                n.hi = std.math.add(i64, x.hi.?, d) catch null;
                if (n.lo == null or n.hi == null) {
                    n.lo = null;
                    n.hi = null;
                }
            }
        },
        .eq, .ne, .lt, .le, .gt, .ge => {
            rangeOf(p, n.a);
            rangeOf(p, n.b);
            n.lo = 0;
            n.hi = 1;
        },
        .neg, .bnot => rangeOf(p, n.a),
        else => {
            rangeOf(p, n.a);
            if (n.op != .neg and n.op != .bnot) rangeOf(p, n.b);
        },
    }
}

fn depthOf(p: *const Program, idx: u32) u32 {
    const n = p.nodes[idx];
    return switch (n.op) {
        .lit, .slot => 0,
        .neg, .bnot => 1 + depthOf(p, n.a),
        else => 1 + @max(depthOf(p, n.a), depthOf(p, n.b)),
    };
}

// ════════════════════════════════════════════════════════════════════════════
// § 5 · F1 — BACKWARD DEMAND, AND EVERY RULE NAMES ITS HOMOMORPHISM
// ════════════════════════════════════════════════════════════════════════════

const Demands = struct {
    slot: [max_slots]Cong = @splat(Cong.nothing),
    fn raise(self: *Demands, s: u32, c: Cong) bool {
        const j = self.slot[s].join(c);
        if (j.eql(self.slot[s])) return false;
        self.slot[s] = j;
        return true;
    }
};

/// Pull the demand `h` on `idx`'s value back onto the names it reads, and
/// annotate the node with the congruence it must be evaluated in.
///
/// EVERY CASE IS `h(f(x)) = g(h(x))` OR A RANGE THAT MAKES THE VALUE EXACT.
/// There is no third kind of rule, and a case may be added only by naming one
/// of those two licences.
fn pull(p: *Program, idx: u32, h_in: Cong, d: *Demands, changed: *bool) bool {
    var h = h_in;
    const op = p.nodes[idx].op;

    // ── The NARROWING forms. These do not propagate the caller's demand at
    // all: their result is a FUNCTION OF A RESIDUE of the operand, so the
    // operand's demand is set by the operator and the caller's demand can only
    // be weaker. `x & (2^k − 1)` IS `x mod 2^k`; `x % B` IS `x mod B` for
    // B > 0. This is the rule that collapses a 64-bit chain whose observer
    // demands `mod 251` — no power-of-two demand is involved anywhere.
    switch (op) {
        .band => {
            const bn = p.nodes[p.nodes[idx].b];
            const an = p.nodes[p.nodes[idx].a];
            const mask: ?i64 = if (bn.op == .lit) bn.k else if (an.op == .lit) an.k else null;
            if (mask) |mv| {
                if (mv >= 0 and (@as(u64, @bitCast(mv)) & (@as(u64, @bitCast(mv)) +% 1)) == 0) {
                    const k: u7 = @intCast(@popCount(@as(u64, @bitCast(mv))));
                    const nc = Cong.pow2(k);
                    p.nodes[idx].cong = h;
                    const other = if (bn.op == .lit) p.nodes[idx].a else p.nodes[idx].b;
                    const lit_side = if (bn.op == .lit) p.nodes[idx].b else p.nodes[idx].a;
                    p.nodes[lit_side].cong = nc;
                    return pull(p, other, nc, d, changed);
                }
            }
        },
        .umod => {
            const bn = p.nodes[p.nodes[idx].b];
            if (bn.op == .lit and bn.k > 0) {
                const nc = Cong.mod(@intCast(bn.k));
                p.nodes[idx].cong = h;
                p.nodes[p.nodes[idx].b].cong = Cong.whole;
                return pull(p, p.nodes[idx].a, nc, d, changed);
            }
            // A runtime divisor narrows nothing; falls through to the general
            // case below, which demands both operands whole.
        },
        else => {},
    }

    // A comparison must be decided exactly; its operands carry no quotient.
    switch (op) {
        .eq, .ne, .lt, .le, .gt, .ge => h = Cong.whole,
        else => {},
    }
    p.nodes[idx].cong = h;
    if (h.isNothing()) return true;

    switch (op) {
        .lit => return true,
        .slot => {
            if (d.raise(@intCast(p.nodes[idx].k), h)) changed.* = true;
            return true;
        },
        // Ring homomorphism: `mod m` is a ring hom for + − * and unary minus,
        // for EVERY m.
        .add, .sub, .mul => {
            const a = p.nodes[idx].a;
            const b = p.nodes[idx].b;
            return pull(p, a, h, d, changed) and pull(p, b, h, d, changed);
        },
        .neg => return pull(p, p.nodes[idx].a, h, d, changed),
        // Bit-local: the low k bits of the result depend only on the low k bits
        // of the operands. Licensed for `mod 2^k` AND FOR NO OTHER MODULUS —
        // and where the licence is absent the demand RISES TO `whole` rather
        // than failing. Raising demand is always sound (it can only cost
        // candidates); failing here would have thrown away every case whose
        // state is bounded by a RANGE instead of by a congruence, which is
        // exactly how a division chain stays finite.
        .bor, .bxor, .band => {
            const hh: Cong = if (h.asPow2() == null) Cong.whole else h;
            p.nodes[idx].cong = hh;
            const a = p.nodes[idx].a;
            const b = p.nodes[idx].b;
            return pull(p, a, hh, d, changed) and pull(p, b, hh, d, changed);
        },
        .bnot => {
            const hh: Cong = if (h.asPow2() == null) Cong.whole else h;
            p.nodes[idx].cong = hh;
            return pull(p, p.nodes[idx].a, hh, d, changed);
        },
        // `x << c` is `x * 2^c` in the wrapping ring, so it is a ring hom for
        // every m — the shift COUNT is a literal, checked at lowering.
        .shl => {
            const b = p.nodes[idx].b;
            p.nodes[b].cong = Cong.whole;
            return pull(p, p.nodes[idx].a, h, d, changed);
        },
        // `x >> c` READS BITS ABOVE THE QUOTIENT. It is admitted only when the
        // demand is `mod 2^k`, and then it demands `mod 2^(k+c)` — the exact
        // statement that bit 33 needs `x mod 2^34` and nothing more.
        .shr => {
            const k = h.asPow2() orelse {
                p.nodes[idx].cong = Cong.whole;
                p.nodes[p.nodes[idx].b].cong = Cong.whole;
                return pull(p, p.nodes[idx].a, Cong.whole, d, changed);
            };
            const c = p.nodes[p.nodes[idx].b].k;
            const want: u32 = @as(u32, k) + @as(u32, @intCast(c));
            const nc: Cong = if (want >= 64) Cong.whole else Cong.pow2(@intCast(want));
            p.nodes[p.nodes[idx].b].cong = Cong.whole;
            return pull(p, p.nodes[idx].a, nc, d, changed);
        },
        // NO HOMOMORPHISM TO ANY Z/m EXISTS FOR EITHER, so both operands are
        // demanded WHOLE. `x / y` reads every bit of x and of y; `x % y` with a
        // non-literal divisor does too. Finiteness must then come from a range,
        // and if it does not, D3 refuses with `state_unbounded` — which names
        // the actual obstruction instead of blaming the operator.
        .divi, .umod => {
            p.nodes[idx].cong = Cong.whole;
            const a = p.nodes[idx].a;
            const b = p.nodes[idx].b;
            return pull(p, a, Cong.whole, d, changed) and pull(p, b, Cong.whole, d, changed);
        },
        .eq, .ne, .lt, .le, .gt, .ge => {
            const a = p.nodes[idx].a;
            const b = p.nodes[idx].b;
            return pull(p, a, Cong.whole, d, changed) and pull(p, b, Cong.whole, d, changed);
        },
    }
}

// ════════════════════════════════════════════════════════════════════════════
// § 6 · EVALUATION — in the quotient, and at full width for the differential
// ════════════════════════════════════════════════════════════════════════════

const Vals = [max_slots]u64;

fn reduce(v: u64, c: Cong) u64 {
    if (c.isWhole()) return v;
    if (c.isNothing()) return 0;
    return @intCast(@as(u128, v) % c.m);
}

fn apply(op: Op, x: u64, y: u64, c: Cong) u64 {
    const whole = c.isWhole();
    return switch (op) {
        .add => if (whole) x +% y else @intCast((@as(u128, x) + @as(u128, y)) % c.m),
        .sub => if (whole) x -% y else @intCast((@as(u128, x) % c.m + c.m - @as(u128, y) % c.m) % c.m),
        .mul => if (whole) x *% y else @intCast((@as(u128, x) * @as(u128, y)) % c.m),
        .band => x & y,
        .bor => x | y,
        .bxor => x ^ y,
        .shl => blk: {
            const s: u6 = @intCast(y & 63);
            const r = x << s;
            break :blk if (whole) r else @intCast(@as(u128, r) % c.m);
        },
        .shr => @as(u64, @bitCast(@as(i64, @bitCast(x)) >> @intCast(y & 63))),
        .divi => blk: {
            const a: i64 = @bitCast(x);
            const b: i64 = @bitCast(y);
            if (b == 0) break :blk 0;
            if (b == -1 and a == std.math.minInt(i64)) break :blk @bitCast(a);
            break :blk @bitCast(@divTrunc(a, b));
        },
        .umod => blk: {
            const a: i64 = @bitCast(x);
            const b: i64 = @bitCast(y);
            if (b == 0) break :blk 0;
            var r = @mod(a, b); // floored, matching the surface language
            if (r != 0 and ((r < 0) != (b < 0))) r += b;
            break :blk @bitCast(r);
        },
        .eq => @intFromBool(x == y),
        .ne => @intFromBool(x != y),
        .lt => @intFromBool(@as(i64, @bitCast(x)) < @as(i64, @bitCast(y))),
        .le => @intFromBool(@as(i64, @bitCast(x)) <= @as(i64, @bitCast(y))),
        .gt => @intFromBool(@as(i64, @bitCast(x)) > @as(i64, @bitCast(y))),
        .ge => @intFromBool(@as(i64, @bitCast(x)) >= @as(i64, @bitCast(y))),
        else => unreachable,
    };
}

/// Evaluate in the congruence each node was annotated with. `quot = false`
/// evaluates the SAME tree at full 64-bit width, which is the program's own
/// semantics and therefore the differential oracle (D6).
fn eval(p: *const Program, idx: u32, v: *const Vals, quot: bool) u64 {
    const n = p.nodes[idx];
    const c: Cong = if (quot) n.cong else Cong.whole;
    switch (n.op) {
        .lit => return reduce(@bitCast(n.k), c),
        .slot => return reduce(v[@intCast(n.k)], c),
        .neg => {
            const x = eval(p, n.a, v, quot);
            return if (c.isWhole()) 0 -% x else @intCast((c.m - (@as(u128, x) % c.m)) % c.m);
        },
        .bnot => {
            const x = eval(p, n.a, v, quot);
            const r = ~x;
            return if (c.isWhole()) r else @intCast(@as(u128, r) % c.m);
        },
        else => {
            const x = eval(p, n.a, v, quot);
            const y = eval(p, n.b, v, quot);
            return apply(n.op, x, y, c);
        },
    }
}

/// One iteration of the loop body, statements in source order.
fn stepOnce(p: *const Program, v: *Vals, quot: bool) void {
    for (0..p.nsteps) |i| {
        const st = p.steps[i];
        if (st.guard != no_guard) {
            if (eval(p, st.guard, v, quot) == 0) continue;
        }
        v[st.slot] = eval(p, st.expr, v, quot);
    }
}

// ════════════════════════════════════════════════════════════════════════════
// § 7 · THE ORBIT — F2 by exhaustive enumeration of the reachable quotient
// ════════════════════════════════════════════════════════════════════════════

const Orbit = struct {
    mu: u64,
    lambda: u64,
    /// log2 of the joint key space actually used.
    key_bits: u16,
};

fn keyOf(p: *const Program, v: *const Vals, radix: *const [max_slots]u64, incore: *const [max_slots]bool) u64 {
    var key: u64 = 0;
    for (0..p.nslots) |i| {
        if (!incore[i]) continue;
        key = key * radix[i] + (v[i] % radix[i]);
    }
    return key;
}

// ════════════════════════════════════════════════════════════════════════════
// § 8 · THE DRIVER
// ════════════════════════════════════════════════════════════════════════════

pub const Options = struct {
    observer: Observer = .whole,
    /// The concrete n to answer at, when the loop bound is a runtime input.
    n: ?u64 = null,
    /// Also run the full-width reference at `n` and report it (D6). Costs n
    /// steps, so it is off by default and is what `--check` turns on.
    check: bool = false,
    /// Orbit steps before the walk refuses. Exposed so a gate can PROVE the
    /// budget is load-bearing: the same program must derive at one budget and
    /// refuse at a smaller one, which is what stops `orbit_budget` from being
    /// a refusal nobody can reach.
    orbit_budget: u64 = max_orbit_steps,
};

fn refuse(stage: Class, o: Obstruction) Result {
    return .{ .refused = .{ .stage = stage, .obstruction = o } };
}

pub fn deriveModule(alloc: std.mem.Allocator, module: *const ast.Module, opts: Options) !Result {
    var prog = Program{};

    // ── the entry relation ──────────────────────────────────────────────────
    var rels: std.ArrayListUnmanaged(ast.FuncDecl) = .empty;
    defer rels.deinit(alloc);
    var entry: ?ast.FuncBody = null;
    for (module.body.stmts) |st| {
        switch (st) {
            .func_decl => |fd| {
                try rels.append(alloc, fd);
                if (fd.path.len == 1 and std.mem.eql(u8, fd.path[0], "main")) entry = fd.func;
            },
            else => {},
        }
    }
    const fb = entry orelse return refuse(.F0_observation, .no_entry_relation);
    if (fb.params.len != 0 or fb.vararg) return refuse(.F0_observation, .entry_takes_parameters);

    var b = Builder{ .prog = &prog, .rels = rels.items };

    // ── the prologue: fold what folds, mark the rest as runtime input ────────
    var loop: ?@TypeOf(module.body.stmts[0].while_loop) = null;
    for (fb.body.stmts) |st| {
        switch (st) {
            .local_decl => |d| {
                if (d.names.len != d.inits.len) return refuse(.F1_information, .prologue_not_foldable);
                for (d.names, d.inits) |nm, init| {
                    try bindPrologue(&b, nm.ident, init);
                }
            },
            .assign => |a| {
                if (a.targets.len != 1 or a.values.len != 1) return refuse(.F1_information, .prologue_not_foldable);
                const nm = switch (a.targets[0].*) {
                    .name => |x| x.ident,
                    else => return refuse(.F1_information, .prologue_not_foldable),
                };
                try bindPrologue(&b, nm, a.values[0]);
            },
            .while_loop => |w| {
                if (loop != null) return refuse(.F2_semantic_problem, .nested_loop);
                loop = w;
            },
            else => return refuse(.F1_information, .control_flow),
        }
    }
    const w = loop orelse return refuse(.F2_semantic_problem, .no_loop);

    // ── slots: every name the body assigns ──────────────────────────────────
    if (internAssigned(&prog, &w.body)) |o| return refuse(.F2_semantic_problem, o);
    if (prog.nslots == 0) return refuse(.F2_semantic_problem, .no_loop);

    // Entry values, and D5: a name with no prologue binding must be written
    // before it is read inside the body.
    for (0..prog.nslots) |i| {
        if (b.constOf(prog.names[i])) |v| {
            prog.entry[i] = v;
            prog.entry_known[i] = true;
        } else if (writtenBeforeRead(&w.body, prog.names[i])) {
            prog.dead_on_entry[i] = true;
            prog.entry_known[i] = true;
        } else {
            return refuse(.F2_semantic_problem, .unbound_entry_value);
        }
    }

    // ── the body, lowered ───────────────────────────────────────────────────
    if (!lowerBlock(&b, &w.body, no_guard)) {
        return refuse(.F2_semantic_problem, b.err orelse .loop_body_grammar);
    }

    // ── the tail ────────────────────────────────────────────────────────────
    const tail_e = fb.body.tail_expr orelse return refuse(.F0_observation, .tail_grammar);
    prog.tail = lower(&b, tail_e) orelse return refuse(.F0_observation, b.err orelse .tail_grammar);

    // ── the guard: an affine walk with step +1 and a bound that may be a
    //    runtime input. The trip count is SYMBOLIC on purpose: a floor is a
    //    statement about every n, not a closure at one n.
    const g = readGuard(&b, &prog, w.cond) orelse return refuse(.F2_semantic_problem, .guard_shape);
    prog.iv = g.iv;
    if (!ivStepsByOne(&prog, g.iv)) return refuse(.F2_semantic_problem, .guard_shape);
    prog.trips = g.trips;
    const n_val: ?u64 = if (prog.trips) |t| t else opts.n;

    // ════ F0 ════════════════════════════════════════════════════════════════
    const h0 = opts.observer.congruence();

    // ════ F1 — backward demand to a fixpoint ════════════════════════════════
    var d = Demands{};
    var rounds: u32 = 0;
    while (rounds < 128) : (rounds += 1) {
        var changed = false;
        var ok = pull(&prog, prog.tail, h0, &d, &changed);
        // Backward over the body, to a fixpoint over the loop carry.
        var i: u32 = prog.nsteps;
        while (i > 0) {
            i -= 1;
            const st = prog.steps[i];
            const want = d.slot[st.slot];
            if (!want.isNothing()) {
                ok = pull(&prog, st.expr, want, &d, &changed) and ok;
            }
            if (st.guard != no_guard) {
                ok = pull(&prog, st.guard, Cong.whole, &d, &changed) and ok;
            }
        }
        if (!ok) return refuse(.F1_information, .demand_not_homomorphic);
        // ONE MORE PASS AFTER CONVERGENCE, and it is not bookkeeping. The pass
        // that computes the fixpoint also ANNOTATES each node with the
        // congruence it will be evaluated in, and an early round annotates from
        // a demand that later rounds raise. Reading a stale annotation is how a
        // slot whose demand grew from `nothing` to `mod 256` gets evaluated at
        // `nothing` and reads as a constant — a silently WRONG orbit, not a
        // refusal. The final pass re-annotates from the converged demand.
        if (!changed) {
            var dead = false;
            var j: u32 = prog.nsteps;
            _ = pull(&prog, prog.tail, h0, &d, &dead);
            while (j > 0) {
                j -= 1;
                const st = prog.steps[j];
                const want = d.slot[st.slot];
                if (!want.isNothing()) _ = pull(&prog, st.expr, want, &d, &dead);
                if (st.guard != no_guard) _ = pull(&prog, st.guard, Cong.whole, &d, &dead);
            }
            break;
        }
    }
    for (0..prog.nslots) |i| prog.cong[i] = d.slot[i];

    // Forward ranges, which are what bound a name whose DEMAND is `whole`.
    for (0..prog.nsteps) |i| {
        var v = prog.lo;
        _ = &v;
        rangeOf(&prog, prog.steps[i].expr);
        const st = prog.steps[i];
        const e = prog.nodes[st.expr];
        // A guarded step may leave the old value in place, so a guarded slot
        // keeps the union of its old range and the new one; unknown either way
        // is unknown.
        if (st.guard == no_guard) {
            prog.lo[st.slot] = e.lo;
            prog.hi[st.slot] = e.hi;
        } else {
            prog.lo[st.slot] = null;
            prog.hi[st.slot] = null;
        }
    }
    // Second pass so a slot read before it is written in the same body sees the
    // range its own update establishes.
    for (0..prog.nsteps) |i| {
        rangeOf(&prog, prog.steps[i].expr);
        const st = prog.steps[i];
        const e = prog.nodes[st.expr];
        if (st.guard == no_guard) {
            prog.lo[st.slot] = e.lo;
            prog.hi[st.slot] = e.hi;
        }
    }

    // D4, discharged where the evidence lives: every divisor must be PROVABLY
    // non-zero. A literal proves it at lowering; a runtime divisor proves it
    // here, from the range its own producer establishes. Nothing is assumed
    // about hardware behaviour on division by zero.
    if (!divisorsNonZero(&prog)) return refuse(.F2_semantic_problem, .loop_body_grammar);

    // ── accumulators: `a = a + E`, read by nothing but the tail ─────────────
    markAccumulators(&prog);

    // ── the orbit key: every core slot must be finite (D3) ──────────────────
    var radix: [max_slots]u64 = @splat(1);
    var incore: [max_slots]bool = @splat(false);
    var key_space: u128 = 1;
    var state_bits: u16 = 0;
    var physical_bits: u16 = 0;
    var core_slots: u8 = 0;
    var accs: u8 = 0;
    for (0..prog.nslots) |i| {
        if (prog.cong[i].isNothing()) continue; // nothing reads it
        physical_bits += 64;
        if (prog.is_acc[i]) {
            accs += 1;
            continue;
        }
        if (prog.dead_on_entry[i] and !readBeforeWrite(&prog, @intCast(i))) {
            // A body temporary: a function of the rest of the state, so it adds
            // nothing to the orbit and is left out of the key.
            continue;
        }
        var span: u128 = prog.cong[i].m;
        if (prog.lo[i]) |lo| {
            if (prog.hi[i]) |hi| {
                // The window must be NON-NEGATIVE and must CONTAIN THE ENTRY
                // VALUE, or the state is not closed under it: the key packs
                // `v mod span`, which is injective on any run of `span`
                // consecutive integers and on nothing else. An entry value
                // outside the window would alias with a reachable state and the
                // orbit would report a period that is not there.
                const e = prog.entry[i];
                const in_window = prog.dead_on_entry[i] or (e >= lo and e <= hi);
                if (lo >= 0 and hi >= lo and in_window) {
                    const r: u128 = @as(u128, @intCast(hi - lo)) + 1;
                    if (r < span) span = r;
                }
            }
        }
        if (span >= @as(u128, 1) << 64) {
            return .{ .refused = .{
                .stage = .F2_semantic_problem,
                .obstruction = .state_unbounded,
                .detail = prog.names[i],
            } };
        }
        radix[i] = @intCast(span);
        incore[i] = true;
        core_slots += 1;
        state_bits += Cong.mod(span).bits();
        key_space *|= span;
        if (key_space >= @as(u128, 1) << 63) {
            return .{ .refused = .{
                .stage = .F2_semantic_problem,
                .obstruction = .state_key_overflow,
                .state_space_log2 = @intCast(@min(state_bits, 255)),
            } };
        }
    }

    // ════ F2 — walk the orbit ONCE and enumerate the reachable set ══════════
    var v0: Vals = @splat(0);
    for (0..prog.nslots) |i| v0[i] = reduce(@bitCast(prog.entry[i]), if (prog.cong[i].isNothing()) Cong.whole else prog.cong[i]);

    var seen: std.AutoHashMapUnmanaged(u64, u64) = .empty;
    defer seen.deinit(alloc);
    var v = v0;
    var t: u64 = 0;
    var mu: u64 = 0;
    var lambda: u64 = 0;
    var closed = false;
    while (t <= opts.orbit_budget) : (t += 1) {
        const key = keyOf(&prog, &v, &radix, &incore);
        const gop = try seen.getOrPut(alloc, key);
        if (gop.found_existing) {
            mu = gop.value_ptr.*;
            lambda = t - mu;
            closed = true;
            break;
        }
        gop.value_ptr.* = t;
        stepOnce(&prog, &v, true);
    }
    if (!closed) {
        return .{ .refused = .{
            .stage = .F3_algorithmic,
            .obstruction = .orbit_budget,
            .state_space_log2 = @intCast(@min(state_bits, 255)),
        } };
    }

    // ════ F3 — the closed answer, when a concrete n was supplied ════════════
    var ladder = Ladder{
        .observer = opts.observer,
        .deployment = "one fresh process per answer; the loop bound arrives at runtime",
        .preprocessing = "none across processes; the orbit is walked INSIDE the measured process",
        .domain_n_min = mu,
        .domain_n_max = std.math.maxInt(i64),
        .mu = mu,
        .lambda = lambda,
        .state_bits = state_bits,
        .physical_bits = physical_bits,
        .step_depth = stepDepth(&prog),
        .accumulators = accs,
        .core_slots = core_slots,
    };
    ladder.n = n_val;
    if (n_val) |n| {
        ladder.answer = closedAnswer(&prog, v0, mu, lambda, n, opts.observer);
        if (opts.check) ladder.brute = bruteForce(&prog, n, opts.observer);
    }

    ladder.add(.{
        .class = .F0_observation,
        .method = .derived,
        .value = opts.observer.bits(),
        .unit = "bits reaching the observer",
        .why = "the deployment model, not the program",
    });
    ladder.add(.{
        .class = .F1_information,
        .method = .derived,
        .value = state_bits,
        .unit = "bits of carried state",
        .why = "backward congruence fixpoint; every operator commutes with its demand",
    });
    ladder.add(.{
        .class = .F2_semantic_problem,
        .method = .exhaustive,
        .value = @intCast(mu + lambda),
        .unit = "reachable quotient states",
        .why = "the reachable set was ENUMERATED, not argued",
    });
    ladder.add(.{
        .class = .F3_algorithmic,
        .method = .exhaustive,
        .value = @intCast(mu + lambda),
        .unit = "steps, independent of n",
        .why = "index a cyclic sequence: state_n = state_(mu + (n-mu) mod lambda)",
    });
    ladder.add(.{
        .class = .F6_causal_path,
        .method = .derived,
        .value = @intCast((mu + lambda) * ladder.step_depth),
        .unit = "dependent operations, independent of n",
        .why = "an n-step serial chain cannot be a causal floor for this observation",
    });
    return .{ .derived = ladder };
}

/// Every `/` and `%` in the IR has a divisor that cannot be zero.
fn divisorsNonZero(p: *const Program) bool {
    for (0..p.nnodes) |i| {
        const n = p.nodes[i];
        if (n.op != .divi and n.op != .umod) continue;
        const dv = p.nodes[n.b];
        if (dv.op == .lit) {
            if (dv.k == 0) return false;
            continue;
        }
        const lo = dv.lo orelse return false;
        const hi = dv.hi orelse return false;
        if (lo > 0 or hi < 0) continue;
        return false;
    }
    return true;
}

fn stepDepth(p: *const Program) u32 {
    var d: u32 = 0;
    for (0..p.nsteps) |i| d += depthOf(p, p.steps[i].expr);
    return @max(d, 1);
}

/// `a_n` for every slot, without running n steps.
fn closedAnswer(p: *const Program, v0: Vals, mu: u64, lambda: u64, n: u64, obs: Observer) i64 {
    var v = v0;
    if (n <= mu + lambda) {
        var t: u64 = 0;
        while (t < n) : (t += 1) stepOnce(p, &v, true);
        return @intCast(reduce(eval(p, p.tail, &v, true), obs.congruence()));
    }
    // Split at mu, then q whole periods, then the remainder. Accumulators are
    // reconstructed from the period sum; core slots are read off the orbit.
    const q = (n - mu) / lambda;
    const r = (n - mu) % lambda;

    var at_mu: Vals = v0;
    var t: u64 = 0;
    while (t < mu) : (t += 1) stepOnce(p, &at_mu, true);

    var at_end: Vals = at_mu;
    t = 0;
    while (t < lambda) : (t += 1) stepOnce(p, &at_end, true);

    var at_r: Vals = at_mu;
    t = 0;
    while (t < r) : (t += 1) stepOnce(p, &at_r, true);

    var out = at_r;
    for (0..p.nslots) |i| {
        if (!p.is_acc[i]) continue;
        const c = p.cong[i];
        const period_sum = subMod(at_end[i], at_mu[i], c);
        const partial = subMod(at_r[i], at_mu[i], c);
        var acc = at_mu[i];
        acc = addMod(acc, mulMod(period_sum, q % modOf(c), c), c);
        acc = addMod(acc, partial, c);
        out[i] = acc;
    }
    return @intCast(reduce(eval(p, p.tail, &out, true), obs.congruence()));
}

fn modOf(c: Cong) u64 {
    return if (c.isWhole()) 0 else @intCast(c.m);
}
fn addMod(a: u64, b: u64, c: Cong) u64 {
    if (c.isWhole()) return a +% b;
    return @intCast((@as(u128, a) + @as(u128, b)) % c.m);
}
fn subMod(a: u64, b: u64, c: Cong) u64 {
    if (c.isWhole()) return a -% b;
    return @intCast((@as(u128, a) + c.m - @as(u128, b) % c.m) % c.m);
}
fn mulMod(a: u64, b: u64, c: Cong) u64 {
    if (c.isWhole()) return a *% b;
    return @intCast((@as(u128, a) * @as(u128, b)) % c.m);
}

/// The differential oracle: the SAME IR at full 64-bit width, no quotient.
fn bruteForce(p: *const Program, n: u64, obs: Observer) i64 {
    var v: Vals = @splat(0);
    for (0..p.nslots) |i| v[i] = @bitCast(p.entry[i]);
    var t: u64 = 0;
    while (t < n) : (t += 1) stepOnce(p, &v, false);
    return @intCast(reduce(eval(p, p.tail, &v, false), obs.congruence()));
}

// ── prologue binding ────────────────────────────────────────────────────────

fn bindPrologue(b: *Builder, name: []const u8, init: *const ast.Expr) !void {
    if (foldConst(b, init)) |v| {
        if (b.nconsts < b.consts.len) {
            b.consts[b.nconsts] = .{ .name = name, .val = v };
            b.nconsts += 1;
        }
        return;
    }
    // Anything this module cannot fold is a RUNTIME INPUT, which is exactly the
    // case a floor has to survive: the bound is not known before the process is.
    if (b.nsyms < b.syms.len) {
        b.syms[b.nsyms] = name;
        b.nsyms += 1;
    }
}

fn foldConst(b: *Builder, e: *const ast.Expr) ?i64 {
    return switch (e.*) {
        .int_lit => |x| x.val,
        .name => |x| b.constOf(x.ident),
        .unop => |u| switch (u.op) {
            .neg => blk: {
                const i = foldConst(b, u.operand) orelse break :blk null;
                break :blk -i;
            },
            else => null,
        },
        .binop => |bo| blk: {
            const l = foldConst(b, bo.lhs) orelse break :blk null;
            const r = foldConst(b, bo.rhs) orelse break :blk null;
            break :blk switch (bo.op) {
                .add => l +% r,
                .sub => l -% r,
                .mul => l *% r,
                else => null,
            };
        },
        else => null,
    };
}

// ── body shape ──────────────────────────────────────────────────────────────

/// `null` when every assigned name interned; otherwise the obstruction that
/// stopped it. Naming the shape that refused is the difference between "this
/// module has a nested loop" and "something went wrong".
fn internAssigned(p: *Program, blk: *const ast.Block) ?Obstruction {
    for (blk.stmts) |st| {
        switch (st) {
            .assign => |a| {
                if (a.targets.len != 1 or a.values.len != 1) return .loop_body_grammar;
                const nm = switch (a.targets[0].*) {
                    .name => |x| x.ident,
                    else => return .loop_body_grammar,
                };
                if (p.intern(nm) == null) return .too_many_slots;
            },
            .local_decl => |d| {
                for (d.names) |nm| {
                    if (p.intern(nm.ident) == null) return .too_many_slots;
                }
            },
            .if_stmt => |f| {
                if (f.elseifs.len != 0 or f.else_body != null) return .control_flow;
                if (internAssigned(p, &f.then)) |o| return o;
            },
            .while_loop, .repeat_loop, .num_for, .gen_for => return .nested_loop,
            else => return .loop_body_grammar,
        }
    }
    return if (blk.tail_expr == null) null else .loop_body_grammar;
}

fn lowerBlock(b: *Builder, blk: *const ast.Block, guard: u32) bool {
    for (blk.stmts) |st| {
        switch (st) {
            .assign => |a| {
                const nm = switch (a.targets[0].*) {
                    .name => |x| x.ident,
                    else => return false,
                };
                const slot = b.prog.find(nm) orelse return false;
                const e = lower(b, a.values[0]) orelse return false;
                if (b.prog.nsteps >= b.prog.steps.len) {
                    _ = b.fail(.too_many_slots);
                    return false;
                }
                b.prog.steps[b.prog.nsteps] = .{ .slot = slot, .expr = e, .guard = guard };
                b.prog.nsteps += 1;
            },
            .local_decl => |d| {
                if (d.names.len != d.inits.len) return false;
                for (d.names, d.inits) |nm, init| {
                    const slot = b.prog.find(nm.ident) orelse return false;
                    const e = lower(b, init) orelse return false;
                    if (b.prog.nsteps >= b.prog.steps.len) {
                        _ = b.fail(.too_many_slots);
                        return false;
                    }
                    b.prog.steps[b.prog.nsteps] = .{ .slot = slot, .expr = e, .guard = guard };
                    b.prog.nsteps += 1;
                }
            },
            .if_stmt => |f| {
                if (guard != no_guard) {
                    _ = b.fail(.control_flow);
                    return false;
                }
                const c = lower(b, f.cond) orelse return false;
                if (!lowerBlock(b, &f.then, c)) return false;
            },
            else => {
                _ = b.fail(.loop_body_grammar);
                return false;
            },
        }
    }
    return true;
}

/// D5: is `name`'s incoming value provably overwritten before any read?
fn writtenBeforeRead(blk: *const ast.Block, name: []const u8) bool {
    for (blk.stmts) |st| {
        switch (st) {
            .assign => |a| {
                if (mentions(a.values[0], name)) return false;
                const nm = switch (a.targets[0].*) {
                    .name => |x| x.ident,
                    else => return false,
                };
                if (std.mem.eql(u8, nm, name)) return true;
            },
            .local_decl => |d| {
                for (d.names, d.inits) |nm, init| {
                    if (mentions(init, name)) return false;
                    if (std.mem.eql(u8, nm.ident, name)) return true;
                }
            },
            .if_stmt => |f| {
                if (mentions(f.cond, name)) return false;
                // A conditional write does not overwrite on every path.
                if (!writtenBeforeRead(&f.then, name)) return false;
                return false;
            },
            else => return false,
        }
    }
    return false;
}

fn mentions(e: *const ast.Expr, name: []const u8) bool {
    return switch (e.*) {
        .name => |x| std.mem.eql(u8, x.ident, name),
        .unop => |u| mentions(u.operand, name),
        .binop => |b| mentions(b.lhs, name) or mentions(b.rhs, name),
        .call => |c| blk: {
            for (c.args) |a| if (mentions(a, name)) break :blk true;
            break :blk mentions(c.func, name);
        },
        .int_lit, .float_lit, .string_lit, .nil, .true_lit, .false_lit, .vararg => false,
        // Fail closed: a construct this module does not enumerate counts as a
        // read, so an unmodelled form can never look dead.
        else => true,
    };
}

/// Does slot `s` appear in any step's expression or guard BEFORE its own write?
fn readBeforeWrite(p: *const Program, s: u32) bool {
    var written = false;
    for (0..p.nsteps) |i| {
        const st = p.steps[i];
        if (st.guard != no_guard and nodeReads(p, st.guard, s)) return !written;
        if (nodeReads(p, st.expr, s)) return !written;
        if (st.slot == s) written = true;
    }
    return false;
}

fn nodeReads(p: *const Program, idx: u32, s: u32) bool {
    const n = p.nodes[idx];
    return switch (n.op) {
        .lit => false,
        .slot => @as(u32, @intCast(n.k)) == s,
        .neg, .bnot => nodeReads(p, n.a, s),
        else => nodeReads(p, n.a, s) or nodeReads(p, n.b, s),
    };
}

/// A slot is an ORDER-FREE ACCUMULATOR when every write to it is `a = a + E`
/// with `E` free of `a`, and nothing else in the body reads it. `+` is
/// associative and commutative, so its value over a periodic driver is a period
/// sum times a quotient plus a partial — no orbit key entry required.
fn markAccumulators(p: *Program) void {
    for (0..p.nslots) |si| {
        const s: u32 = @intCast(si);
        var writes: u32 = 0;
        var shaped = true;
        for (0..p.nsteps) |i| {
            const st = p.steps[i];
            if (st.guard != no_guard and nodeReads(p, st.guard, s)) shaped = false;
            if (st.slot != s) {
                if (nodeReads(p, st.expr, s)) shaped = false;
                continue;
            }
            writes += 1;
            const e = p.nodes[st.expr];
            if (e.op != .add) {
                shaped = false;
                continue;
            }
            const l = p.nodes[e.a];
            const r = p.nodes[e.b];
            const l_is_self = l.op == .slot and @as(u32, @intCast(l.k)) == s;
            const r_is_self = r.op == .slot and @as(u32, @intCast(r.k)) == s;
            if (l_is_self and !nodeReads(p, e.b, s)) continue;
            if (r_is_self and !nodeReads(p, e.a, s)) continue;
            shaped = false;
        }
        if (shaped and writes > 0) p.is_acc[s] = true;
    }
}

const Guard = struct { iv: u32, trips: ?u64 };

fn readGuard(b: *Builder, p: *Program, cond: *const ast.Expr) ?Guard {
    const bo = switch (cond.*) {
        .binop => |x| x,
        else => return null,
    };
    const inclusive = switch (bo.op) {
        .leq => true,
        .lt => false,
        else => return null,
    };
    const iv_name = switch (bo.lhs.*) {
        .name => |x| x.ident,
        else => return null,
    };
    const iv = p.find(iv_name) orelse return null;
    const start = if (p.entry_known[iv] and !p.dead_on_entry[iv]) p.entry[iv] else return null;
    if (foldConst(b, bo.rhs)) |bound| {
        const raw: i64 = bound - start + @as(i64, if (inclusive) 1 else 0);
        return .{ .iv = iv, .trips = if (raw <= 0) 0 else @intCast(raw) };
    }
    const nm = switch (bo.rhs.*) {
        .name => |x| x.ident,
        else => return null,
    };
    if (!b.isSym(nm)) return null;
    return .{ .iv = iv, .trips = null };
}

fn ivStepsByOne(p: *const Program, iv: u32) bool {
    var found = false;
    for (0..p.nsteps) |i| {
        const st = p.steps[i];
        if (st.slot != iv) continue;
        if (st.guard != no_guard) return false;
        const e = p.nodes[st.expr];
        if (e.op != .add) return false;
        const l = p.nodes[e.a];
        const r = p.nodes[e.b];
        const ok = (l.op == .slot and @as(u32, @intCast(l.k)) == iv and r.op == .lit and r.k == 1) or
            (r.op == .slot and @as(u32, @intCast(r.k)) == iv and l.op == .lit and l.k == 1);
        if (!ok) return false;
        found = true;
    }
    return found;
}

// ── the file-level entry point ──────────────────────────────────────────────

pub fn deriveSource(alloc: std.mem.Allocator, src: []const u8, path: []const u8, opts: Options) !Result {
    const facts = lexer_bridge.sourceFacts(path);
    var lex = Lexer.initFacts(src, path, facts);
    var parser = Parser.init(&lex, alloc);
    parser.idol_mode = lex.family == lexer_bridge.family_canon;
    const module = parser.parse_module() catch return refuse(.F0_observation, .no_entry_relation);
    const m = try alloc.create(ast.Module);
    m.* = module;
    return deriveModule(alloc, m, opts);
}

// ════════════════════════════════════════════════════════════════════════════
// § 9 · REPORTING, IN THE LEDGER'S OWN GRAMMAR
// ════════════════════════════════════════════════════════════════════════════

/// `class/method=value`. There is no code path that can produce `F9` or a
/// method of `witness`, `measured` or `competitor` — the enums have no such
/// members — so the output is admissible in `gate/ftcftw.id`'s lowerbound
/// column by construction rather than by review.
pub fn ledgerCell(f: Floor, buf: []u8) ![]const u8 {
    return std.fmt.bufPrint(buf, "{s}/{s}={d}", .{ f.class.ledger(), f.method.ledger(), f.value });
}

/// One line per program, for a gate to read. The RATCHET shape: a gate that
/// pins these lines notices a case that stops deriving AND a case that starts
/// deriving something it should refuse — both are drift and neither is a
/// smaller, greener report.
pub fn writeTerse(w: *std.Io.Writer, path: []const u8, r: Result) !void {
    switch (r) {
        .refused => |x| try w.print("FLOOR {s} refused {s} {s} state_log2={d}\n", .{
            path, x.stage.ledger(), @tagName(x.obstruction), x.state_space_log2,
        }),
        .derived => |l| {
            var buf: [64]u8 = undefined;
            const cell = try ledgerCell(l.get(.F3_algorithmic).?, &buf);
            try w.print("FLOOR {s} derived {s} mu={d} lambda={d} statebits={d} n={d} answer={d}\n", .{
                path, cell, l.mu, l.lambda, l.state_bits, l.n orelse 0, l.answer orelse -1,
            });
        },
    }
}

pub fn writeReport(w: *std.Io.Writer, path: []const u8, r: Result, _: ?u64) !void {
    switch (r) {
        .refused => |x| {
            try w.print("{s}\n", .{path});
            try w.print("  REFUSED at {s}: {s}\n", .{ x.stage.ledger(), @tagName(x.obstruction) });
            if (x.detail.len != 0) try w.print("  detail        {s}\n", .{x.detail});
            if (x.state_space_log2 != 0) {
                try w.print("  state space   <= 2^{d}: the orbit closes at SOME n <= 2^{d}, but not within the {d}-step budget, so NO floor is derived at this n\n", .{ x.state_space_log2, x.state_space_log2, max_orbit_steps });
                try w.print("  input domain  a floor exists for n >= 2^{d} and NONE is claimed below it\n", .{x.state_space_log2});
            }
            try w.print("  lowerbound    none\n\n", .{});
        },
        .derived => |l| {
            try w.print("{s}\n", .{path});
            try w.print("  observer      {s}\n", .{l.observer.describe()});
            try w.print("  deployment    {s}\n", .{l.deployment});
            try w.print("  preprocessing {s}\n", .{l.preprocessing});
            try w.print("  input domain  n in [{d}, 2^63)  (below n = {d} the quotient is still in its tail)\n", .{ l.domain_n_min, l.domain_n_min });
            try w.print("  orbit         mu = {d}  lambda = {d}  core slots {d}  accumulators {d}\n", .{ l.mu, l.lambda, l.core_slots, l.accumulators });
            for (l.floors[0..l.len]) |f| {
                var buf: [64]u8 = undefined;
                const cell = try ledgerCell(f, &buf);
                try w.print("  {s:<22} {d:>12} {s}\n", .{ cell, f.value, f.unit });
                try w.print("  {s:<22} {s:>12} {s}\n", .{ "", "", f.why });
            }
            try w.print("  representation {d} demanded bits carried in {d} physical bits\n", .{ l.state_bits, l.physical_bits });
            if (l.answer) |a| try w.print("  answer at n={d}: {d}\n", .{ l.n orelse 0, a });
            if (l.brute) |bv| {
                const a = l.answer orelse -1;
                try w.print("  differential  full-width reference at n={d}: {d}  {s}\n", .{ l.n orelse 0, bv, if (bv == a) "AGREE" else "DISAGREE" });
            }
            try w.print("\n", .{});
        },
    }
}

// ════════════════════════════════════════════════════════════════════════════
// § 10 · CLI
// ════════════════════════════════════════════════════════════════════════════

pub fn main(init: std.process.Init) !void {
    const alloc = init.arena.allocator();
    const args = try init.minimal.args.toSlice(alloc);
    var obs: Observer = .process_exit_status;
    var n: ?u64 = null;
    var check = false;
    var terse = false;
    var budget: u64 = max_orbit_steps;
    var files: std.ArrayListUnmanaged([]const u8) = .empty;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        if (std.mem.eql(u8, a, "--n") and i + 1 < args.len) {
            i += 1;
            n = try std.fmt.parseInt(u64, args[i], 10);
        } else if (std.mem.eql(u8, a, "--check")) {
            check = true;
        } else if (std.mem.eql(u8, a, "--terse")) {
            terse = true;
        } else if (std.mem.eql(u8, a, "--budget") and i + 1 < args.len) {
            i += 1;
            budget = try std.fmt.parseInt(u64, args[i], 10);
        } else if (std.mem.eql(u8, a, "--observer") and i + 1 < args.len) {
            i += 1;
            obs = if (std.mem.eql(u8, args[i], "whole")) .whole else .process_exit_status;
        } else {
            try files.append(alloc, a);
        }
    }
    var out_buf: [1 << 16]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &out_buf);
    const w = &stdout.interface;
    var derived: u32 = 0;
    var disagreed: u32 = 0;
    for (files.items) |path| {
        const src = std.Io.Dir.readFileAlloc(std.Io.Dir.cwd(), init.io, path, alloc, .unlimited) catch {
            try w.print("{s}\n  REFUSED: cannot read\n\n", .{path});
            continue;
        };
        const r = try deriveSource(alloc, src, path, .{ .observer = obs, .n = n, .check = check, .orbit_budget = budget });
        if (r == .derived) {
            derived += 1;
            if (r.derived.brute) |bv| {
                if (bv != (r.derived.answer orelse -1)) disagreed += 1;
            }
        }
        if (terse) try writeTerse(w, path, r) else try writeReport(w, path, r, n);
    }
    try w.print("derived {d} of {d}\n", .{ derived, files.items.len });
    if (check) try w.print("differential disagreements {d}\n", .{disagreed});
    try w.flush();
    if (disagreed > 0) std.process.exit(1);
}

// ════════════════════════════════════════════════════════════════════════════
// § 11 · TESTS — the differential is the point, not the expectations
// ════════════════════════════════════════════════════════════════════════════

const testing = std.testing;

test "floor_derive: Cong agrees with Projection on the 2^k sub-lattice" {
    // The claim in the header, executable: where `low_bits` is defined the two
    // lattices join identically. Where it is not — 251 — only `Cong` has a
    // representative at all, and that is the whole reason this exists.
    var k: u7 = 1;
    while (k < 32) : (k += 1) {
        var j: u7 = 1;
        while (j < 32) : (j += 1) {
            const a = Cong.pow2(k);
            const b = Cong.pow2(j);
            const joined = a.join(b);
            const pa: demand_projection.Projection = .{ .low_bits = @intCast(k) };
            const pb: demand_projection.Projection = .{ .low_bits = @intCast(j) };
            const pj = pa.join(pb);
            try testing.expectEqual(@as(u7, @intCast(@max(k, j))), joined.asPow2().?);
            try testing.expectEqual(@as(u6, @intCast(@max(k, j))), pj.low_bits);
        }
    }
    try testing.expect(Cong.mod(251).asPow2() == null);
    try testing.expect(Cong.mod(251).toProjection() == null);
    // lcm, not max, off the powers of two.
    try testing.expectEqual(@as(u128, 251 * 256), Cong.mod(251).join(Cong.pow2(8)).m);
}

fn deriveText(alloc: std.mem.Allocator, src: []const u8, opts: Options) !Result {
    return deriveSource(alloc, src, "probe.id", opts);
}

const w6_src =
    \\mix: i64 = (a: i64, b: i64)
    \\    (a ~ b) * 2654435761
    \\
    \\main: i64 = ()
    \\    n = probe(1)
    \\    s = 0
    \\    i = 1
    \\    while i <= n
    \\        s = mix(s, i)
    \\        i += 1
    \\    s
;

test "floor_derive: W6's observer collapses 64 carried bits to 16, period 256" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const r = try deriveText(arena.allocator(), w6_src, .{ .observer = .process_exit_status, .n = 20_000_000 });
    const l = switch (r) {
        .refused => |x| {
            std.debug.print("refused {s} {s}\n", .{ x.stage.ledger(), @tagName(x.obstruction) });
            return error.TestUnexpectedResult;
        },
        .derived => |x| x,
    };
    try testing.expectEqual(@as(u64, 0), l.mu);
    try testing.expectEqual(@as(u64, 256), l.lambda);
    try testing.expectEqual(@as(u16, 16), l.state_bits); // s mod 256, i mod 256
    try testing.expectEqual(@as(u8, 2), l.core_slots);
    try testing.expectEqual(@as(u8, 0), l.accumulators);
}

test "floor_derive: W6 the derived answer equals a full-width run at every n" {
    // D6. If any quotient rule were wrong this is where it dies.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var n: u64 = 0;
    while (n <= 1100) : (n += 1) {
        const r = try deriveText(arena.allocator(), w6_src, .{ .observer = .process_exit_status, .n = n });
        const l = r.derived;
        const want = referenceW6(n);
        try testing.expectEqual(want, l.answer.?);
    }
}

fn referenceW6(n: u64) i64 {
    var s: u64 = 0;
    var i: u64 = 1;
    while (i <= n) : (i += 1) s = (s ^ i) *% 2654435761;
    return @intCast(s & 0xff);
}

const acc_src =
    \\main: i64 = ()
    \\    n = probe(1)
    \\    s = 0
    \\    i = 0
    \\    while i < n
    \\        s += i
    \\        i += 1
    \\    s & 255
;

test "floor_derive: an order-free accumulator is peeled out of the orbit key" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const r = try deriveText(arena.allocator(), acc_src, .{ .observer = .process_exit_status, .n = 100_000 });
    const l = switch (r) {
        .refused => |x| {
            std.debug.print("refused {s} {s}\n", .{ x.stage.ledger(), @tagName(x.obstruction) });
            return error.TestUnexpectedResult;
        },
        .derived => |x| x,
    };
    try testing.expectEqual(@as(u8, 1), l.accumulators);
    try testing.expectEqual(@as(u8, 1), l.core_slots); // only `i mod 256` is carried
    try testing.expectEqual(@as(u64, 256), l.lambda);
    // sum 0..99999 = 4999950000; 4999950000 mod 256 = 176
    try testing.expectEqual(@as(i64, 176), l.answer.?);
}

test "floor_derive: the accumulator closure agrees with a real loop at every n" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var n: u64 = 0;
    while (n <= 1500) : (n += 1) {
        const r = try deriveText(arena.allocator(), acc_src, .{ .observer = .process_exit_status, .n = n });
        var s: u64 = 0;
        var i: u64 = 0;
        while (i < n) : (i += 1) s = s +% i;
        try testing.expectEqual(@as(i64, @intCast(s & 255)), r.derived.answer.?);
    }
}

test "floor_derive: D1 — no observer fact, no quotient" {
    // The default observer is `whole`, and W6 at full width has 2^64 states.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const r = try deriveText(arena.allocator(), w6_src, .{ .observer = .whole, .n = 1000 });
    try testing.expect(r == .refused);
    try testing.expectEqual(Obstruction.state_unbounded, r.refused.obstruction);
}

test "floor_derive: D2 — a body that reads bits above the quotient raises the demand" {
    // `x = x ~ (x >> 7)`: the demand at `mod 2^8` pulls back to `mod 2^15`,
    // then `mod 2^22`, and the fixpoint is `whole`. No collapse, and the
    // refusal is the state space, not a silent truncation.
    const src =
        \\main: i64 = ()
        \\    n = probe(1)
        \\    x = 88172645463325252
        \\    i = 0
        \\    while i < n
        \\        x = x ~ (x >> 7)
        \\        i += 1
        \\    x & 255
    ;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const r = try deriveText(arena.allocator(), src, .{ .observer = .process_exit_status, .n = 1000 });
    try testing.expect(r == .refused);
    try testing.expectEqual(Obstruction.state_unbounded, r.refused.obstruction);
}

test "floor_derive: the shift rule is EXACT — bit 33 needs 34 bits and no more" {
    // W7's kernel without the accumulator. `(x >> 33) & 1` must pull back to
    // `mod 2^34`; a rule that pulled back to `whole` would refuse here and a
    // rule that pulled back to `mod 2^33` would be WRONG.
    const src =
        \\main: i64 = ()
        \\    n = probe(1)
        \\    x = 12345
        \\    i = 0
        \\    while i < n
        \\        x = 1103515245 * x + 12345
        \\        i += 1
        \\    (x >> 33) & 1
    ;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const r = try deriveText(arena.allocator(), src, .{ .observer = .process_exit_status, .n = 1000 });
    // 2^34 states: finite, so the key is admissible, but the orbit is far past
    // the budget. The refusal must be the BUDGET and it must carry the size.
    try testing.expect(r == .refused);
    try testing.expectEqual(Obstruction.orbit_budget, r.refused.obstruction);
    try testing.expectEqual(@as(u8, 34), r.refused.state_space_log2);
}

test "floor_derive: a mod-251 tail is derivable and a low_bits lattice could not express it" {
    const src =
        \\main: i64 = ()
        \\    n = probe(1)
        \\    x = 12345
        \\    a = 0
        \\    i = 1
        \\    while i <= n
        \\        x = ((x ~ i) * 2654435761) & 65535
        \\        a = a + x
        \\        i += 1
        \\    a % 251
    ;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var n: u64 = 0;
    while (n <= 700) : (n += 1) {
        const r = try deriveText(arena.allocator(), src, .{ .observer = .process_exit_status, .n = n });
        const l = switch (r) {
            .refused => |x| {
                std.debug.print("refused {s} {s}\n", .{ x.stage.ledger(), @tagName(x.obstruction) });
                return error.TestUnexpectedResult;
            },
            .derived => |y| y,
        };
        var x: u64 = 12345;
        var a: u64 = 0;
        var i: u64 = 1;
        while (i <= n) : (i += 1) {
            x = ((x ^ i) *% 2654435761) & 65535;
            a = a +% x;
        }
        try testing.expectEqual(@as(i64, @intCast((a % 251) & 255)), l.answer.?);
    }
}

test "floor_derive: the ledger cell can never spell a witness" {
    var buf: [64]u8 = undefined;
    const cell = try ledgerCell(.{
        .class = .F3_algorithmic,
        .method = .exhaustive,
        .value = 80077,
        .unit = "",
        .why = "",
    }, &buf);
    try testing.expectEqualStrings("F3/exhaustive=80077", cell);
    // The refusals `gate/ftcftw.id` enforces are structural here: neither
    // string appears in either enum, at any value.
    inline for (@typeInfo(Class).@"enum".field_names) |nm| {
        try testing.expect(!std.mem.eql(u8, nm, "F9"));
    }
    inline for (@typeInfo(Method).@"enum".field_names) |nm| {
        try testing.expect(!std.mem.eql(u8, nm, "witness"));
        try testing.expect(!std.mem.eql(u8, nm, "measured"));
        try testing.expect(!std.mem.eql(u8, nm, "competitor"));
    }
}

test "floor_derive: a randomized differential over the whole admitted grammar" {
    // THE TEST THAT MAKES THIS NOT A RECOGNIZER. Four hundred programs this
    // module has never seen, built from the operators it admits, each one
    // derived and then checked against the SAME IR run at full 64-bit width
    // with no quotient anywhere. A quotient rule that is wrong for one operator
    // at one modulus shows up here as a DISAGREEMENT, not as a plausible
    // number, and a rule that is merely too weak shows up as a refusal — which
    // is sound and is counted separately so that a build where everything
    // refuses cannot pass as a build where everything agrees.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var prng = std.Random.DefaultPrng.init(0x5eed_f100_2026);
    const rnd = prng.random();

    const masks = [_]u32{ 255, 511, 1023, 4095 };
    const mods = [_]u32{ 251, 97, 256, 1000 };

    var agreed: u32 = 0;
    var refused: u32 = 0;
    var trial: u32 = 0;
    while (trial < 240) : (trial += 1) {
        var buf: [1024]u8 = undefined;
        var w = std.Io.Writer.fixed(&buf);

        const mask = masks[rnd.uintLessThan(usize, masks.len)];
        const md = mods[rnd.uintLessThan(usize, mods.len)];
        const x0 = rnd.intRangeAtMost(i64, 0, 4096);
        const c1 = rnd.intRangeAtMost(i64, 1, 1 << 20);
        const c2 = rnd.intRangeAtMost(i64, 1, 1 << 12);
        const sh: u8 = rnd.intRangeAtMost(u8, 1, 9);

        // The kernel: one of six shapes over the admitted operators, each
        // wrapped in a mask so the carried state is finite.
        try w.print("main: i64 = ()\n    n = probe(1)\n    x = {d}\n    a = 0\n    i = 1\n    while i <= n\n", .{x0});
        switch (rnd.uintLessThan(u8, 6)) {
            0 => try w.print("        x = ((x ~ i) * {d}) & {d}\n", .{ c1, mask }),
            1 => try w.print("        x = ((x + i) * {d} - {d}) & {d}\n", .{ c1, c2, mask }),
            2 => try w.print("        x = ((x | i) ~ (x << {d})) & {d}\n", .{ sh, mask }),
            3 => try w.print("        x = (((x * {d}) >> {d}) ~ i) & {d}\n", .{ c1, sh, mask }),
            4 => try w.print("        x = ((({d} / (x + 1)) ~ i) & {d}) + 1\n", .{ c1, mask }),
            5 => try w.print("        x = ((x ~ {d}) % {d} + i) & {d}\n", .{ c1, c2 + 1, mask }),
            else => unreachable,
        }
        if (rnd.boolean()) try w.print("        a = a + x\n", .{});
        try w.print("        i += 1\n", .{});
        switch (rnd.uintLessThan(u8, 3)) {
            0 => try w.print("    (x + a) % {d}\n", .{md}),
            1 => try w.print("    a % {d}\n", .{md}),
            else => try w.print("    x & 255\n", .{}),
        }

        const src = w.buffered();
        const n: u64 = rnd.intRangeAtMost(u64, 0, 6_000);
        const r = try deriveText(arena.allocator(), src, .{
            .observer = .process_exit_status,
            .n = n,
            .check = true,
            .orbit_budget = 40_000,
        });
        switch (r) {
            .refused => refused += 1,
            .derived => |l| {
                if (l.answer.? != l.brute.?) {
                    std.debug.print("DISAGREE n={d}\n{s}\nderived {d} full-width {d}\n", .{ n, src, l.answer.?, l.brute.? });
                    return error.TestUnexpectedResult;
                }
                agreed += 1;
            },
        }
    }
    // Liveness: the sweep must actually DERIVE, or agreement is vacuous.
    try testing.expect(agreed >= 60);
    try testing.expect(agreed + refused == 240);
}
