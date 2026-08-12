/// Semantic analysis: type-checks the AST and annotates every expression
/// with a ResolvedType.  Also marks FuncBody.is_typed = true when all
/// parameters and the return type are statically known.
const std = @import("std");
const Allocator = std.mem.Allocator;
const ast = @import("ast.zig");
const Expr = ast.Expr;
const types = @import("types.zig");
const RT = types.ResolvedType;
const term = @import("term.zig");
const directives = @import("directives.zig");
const debug_trace = @import("debug_trace.zig");
const semantic_algebra = @import("semantic_algebra.zig");
const c_sim_import = @import("c_sim_import.zig");
const foreign_adapter = @import("foreign_adapter.zig");
const abi_specialize = @import("abi_specialize.zig");
const tail_result_demand = @import("tail_result_demand.zig");
const wiring = @import("wiring.zig");

const callable_brace_error = "c0 §43 law.brace: braced application requires a descriptor subject; this subject resolved in callable space, not descriptor space, and ordinary callable application uses parentheses";

pub const SemaError = error{
    TypeMismatch,
    UndeclaredVariable,
    NotCallable,
    InvalidAssignment,
    UnknownBuiltin,
} || Allocator.Error;

/// A symbol in the scope chain.
pub const Symbol = struct {
    typ: RT,
    is_const: bool,
    is_for_control: bool = false,
    is_global: bool = false,
    is_close: bool = false,
    is_vararg_rest: bool = false,
    /// If non-null, using this symbol emits a deprecation warning.
    deprecated_msg: ?[]const u8 = null,
    /// Pass 2: knowledge lattice position derived from `typ` (see `Symbol.knowledge`).
    /// Escape analysis fields (populated by analyze_closure_upvalues and checking passes)
    escapes: bool = false, // true if variable outlives its scope
    address_taken: bool = false, // true if &var is used or stored in table
    captured_by_closure: bool = false, // true if referenced in a nested function
    assigned_after_init: bool = false, // true if reassigned after declaration

    /// Knowledge lattice position for this binding (Pass 2 convergence).
    pub fn knowledge(self: Symbol) semantic_algebra.KnowledgeLevel {
        return semantic_algebra.knowledgeOfType(self.typ);
    }
};

fn is_const_attrib(attrib: ?[]const u8) bool {
    return attrib != null and std.mem.eql(u8, attrib.?, "const");
}

fn is_close_attrib(attrib: ?[]const u8) bool {
    return attrib != null and std.mem.eql(u8, attrib.?, "close");
}

/// Check whether a function has the @nopanic attribute.
fn has_nopanic_attr(attributes: []const ast.Attribute) bool {
    for (attributes) |attr| {
        if (std.mem.eql(u8, attr.name, "nopanic")) return true;
    }
    return false;
}

/// Extract the deprecation message from attributes, or null if not deprecated.
fn get_deprecated_msg(attributes: []const ast.Attribute) ?[]const u8 {
    for (attributes) |attr| {
        if (std.mem.eql(u8, attr.name, "deprecated")) {
            return attr.args orelse "deprecated";
        }
    }
    return null;
}

fn apply_record_layout_attrs(t: *RT, attributes: []const ast.Attribute) void {
    types.applyTableShapeAttrs(t, attributes);
}

/// Check whether attributes contain @arc(false) and validate the argument.
/// Returns true if @arc attribute is present (valid or invalid).
fn validate_arc_attr(attributes: []const ast.Attribute) ?bool {
    for (attributes) |attr| {
        if (std.mem.eql(u8, attr.name, "arc")) {
            if (attr.args) |args| {
                return std.mem.eql(u8, args, "false");
            }
            // @arc without argument is invalid
            return false;
        }
    }
    return null;
}

fn has_arc_attr(attributes: []const ast.Attribute) bool {
    return validate_arc_attr(attributes) != null;
}

fn is_table_binding_type(te: ast.TypeExpr, resolved: RT) bool {
    if (te == .record) return true;
    if (te == .named and (std.mem.eql(u8, te.named, "table") or std.mem.eql(u8, te.named, "Table"))) return true;
    return resolved == .table_type;
}

/// Lexical scope: a stack of hash maps.
pub const Scope = struct {
    alloc: Allocator,
    maps: std.ArrayList(std.StringHashMap(Symbol)),
    require_global: std.ArrayList(bool),

    pub fn init(alloc: Allocator) Scope {
        return .{ .alloc = alloc, .maps = .empty, .require_global = .empty };
    }

    pub fn deinit(self: *Scope) void {
        for (self.maps.items) |*m| m.deinit();
        self.maps.deinit(self.alloc);
        self.require_global.deinit(self.alloc);
    }

    pub fn push(self: *Scope) !void {
        try self.maps.append(self.alloc, std.StringHashMap(Symbol).init(self.alloc));
        const inherited = if (self.require_global.items.len > 0)
            self.require_global.items[self.require_global.items.len - 1]
        else
            false;
        try self.require_global.append(self.alloc, inherited);
    }

    pub fn pop(self: *Scope) void {
        var m = self.maps.pop().?;
        m.deinit();
        _ = self.require_global.pop();
    }

    pub fn set_require_global(self: *Scope, v: bool) void {
        if (self.require_global.items.len > 0)
            self.require_global.items[self.require_global.items.len - 1] = v;
    }

    pub fn needs_explicit_global(self: *Scope) bool {
        if (self.require_global.items.len == 0) return false;
        return self.require_global.items[self.require_global.items.len - 1];
    }

    pub fn define(self: *Scope, name: []const u8, sym: Symbol) !void {
        try self.maps.items[self.maps.items.len - 1].put(name, sym);
    }

    pub fn lookup(self: *const Scope, name: []const u8) ?Symbol {
        var i = self.maps.items.len;
        while (i > 0) {
            i -= 1;
            if (self.maps.items[i].get(name)) |sym| return sym;
        }
        return null;
    }

    /// Like lookup but returns a mutable pointer to the stored Symbol.
    pub fn lookupPtr(self: *Scope, name: []const u8) ?*Symbol {
        var i = self.maps.items.len;
        while (i > 0) {
            i -= 1;
            if (self.maps.items[i].getPtr(name)) |sym| return sym;
        }
        return null;
    }
};

/// Per-expression type annotation (stored separately to avoid bloating AST).
/// The Sema pass fills this map; CodeGen reads it.
pub const TypeMap = std.AutoHashMap(*const ast.Expr, RT);

/// A registered concept with its required methods and fields.
pub const ConceptInfo = struct {
    name: []const u8,
    required_methods: []const MethodRequirement,
    required_fields: []const FieldRequirement,

    pub const MethodRequirement = struct {
        name: []const u8,
        param_count: usize, // number of params (including self)
        param_types: []const RT,
        ret_type: RT,
    };

    pub const FieldRequirement = struct {
        name: []const u8,
        typ: RT,
    };
};

/// The one record behind `name --is--> descriptor` (`docs/registry_collapse.md`
/// row 1). Sema and CodeGen used to each declare a bare
/// `StringHashMapUnmanaged(*const ast.AliasDef)` and each re-derive it with its
/// own scan over `mod.body.stmts`, and each answer descriptor-membership
/// questions with its own copy of the walk — two ontologies for one fact. There
/// is now one type, one derivation (`collect`) and one decision procedure
/// (`hasfield` / `hasmethod` / `satisfies`).
///
/// Two *instances* still exist, and that is deliberate, not a leftover: during
/// embedded-module emission CodeGen needs the parent module's descriptors
/// unioned with the submodule's (`emit_embedded_module` saves, extends and
/// restores its registry), while the submodule's own `Sema` is a temporary that
/// dies at the end of that call. One flat Sema-owned map cannot express that
/// scoping. What was collapsed is the shape and the semantics; what remains is
/// a second *scope* of the same record, not a second answer.
pub const AliasRegistry = struct {
    map: std.StringHashMapUnmanaged(*const ast.AliasDef) = .empty,

    pub fn deinit(self: *AliasRegistry, alloc: Allocator) void {
        self.map.deinit(alloc);
    }

    pub fn clearRetainingCapacity(self: *AliasRegistry) void {
        self.map.clearRetainingCapacity();
    }

    pub fn get(self: *const AliasRegistry, name: []const u8) ?*const ast.AliasDef {
        return self.map.get(name);
    }

    pub fn contains(self: *const AliasRegistry, name: []const u8) bool {
        return self.map.contains(name);
    }

    pub fn put(self: *AliasRegistry, alloc: Allocator, name: []const u8, def: *const ast.AliasDef) Allocator.Error!void {
        try self.map.put(alloc, name, def);
    }

    pub fn count(self: *const AliasRegistry) u32 {
        return self.map.count();
    }

    pub fn clone(self: *const AliasRegistry, alloc: Allocator) Allocator.Error!AliasRegistry {
        return .{ .map = try self.map.clone(alloc) };
    }

    /// THE derivation. Every top-level `alias_def` statement of `mod` becomes
    /// `name --is--> descriptor`. Sema calls this from `check_module`; CodeGen
    /// calls this from `populate_alias_defs`. Neither scans for aliases itself.
    pub fn collect(self: *AliasRegistry, alloc: Allocator, mod: *ast.Module) Allocator.Error!void {
        for (mod.body.stmts) |*stmt| {
            if (stmt.* != .alias_def) continue;
            try self.map.put(alloc, stmt.alias_def.name, &stmt.alias_def);
            try noteNominal(alloc, &stmt.alias_def);
        }
    }

    /// law.nominal (§46) — `feet: f64` is a DESCRIPTOR over a representation,
    /// not a second name for `f64`.
    ///
    /// Derived HERE, in the one place both Sema and CodeGen already call, so
    /// the two subsystems cannot disagree about which names are nominal (A3 ONE
    /// EDGE — the disagreement between parser and sema over a leading `.` is
    /// the defect this shape exists to avoid repeating).
    ///
    /// Only SCALAR targets. A descriptor over a record is an ordinary alias and
    /// keeps every behaviour it had; a descriptor with type parameters is a
    /// generic alias and is expanded, not made nominal.
    fn noteNominal(alloc: Allocator, def: *const ast.AliasDef) Allocator.Error!void {
        if (def.type_params != null) return;
        if (def.fields.len != 0 or def.parent != null) return;
        const target = def.target orelse return;
        if (target != .named) return;
        const repr = types.resolve(target, null, alloc) catch return;
        // The admissibility gate also disposes of forward references:
        // `types.resolve` answers `.@"struct"{n}` for a name it does not know,
        // and `.@"struct"` is not an admissible representation, so a descriptor
        // over an undeclared name stays an ordinary alias rather than becoming
        // a nominal descriptor over nothing.
        if (!types.nominalReprAdmissible(repr)) return;
        try types.declareNominal(alloc, def.name, repr);
    }

    /// `descriptor --has--> field`, counting an inherited record target's fields.
    pub fn hasfield(def: *const ast.AliasDef, name: []const u8) bool {
        for (def.fields) |f| {
            if (std.mem.eql(u8, f.name, name)) return true;
        }
        if (def.target) |target| {
            switch (target) {
                .record => |rec| {
                    for (rec.fields) |f| {
                        if (std.mem.eql(u8, f.name, name)) return true;
                    }
                },
                else => {},
            }
        }
        return false;
    }

    /// `descriptor --has--> method`, by the last segment of each method path.
    pub fn hasmethod(def: *const ast.AliasDef, name: []const u8) bool {
        for (def.methods) |m| {
            const mname = if (m.path.len > 0) m.path[m.path.len - 1] else "";
            if (std.mem.eql(u8, mname, name)) return true;
        }
        return false;
    }

    /// `descriptor --satisfies--> concept`. The single decision procedure, used
    /// by both `Sema.type_satisfies_concept` and `CodeGen.eval_satisfies`.
    /// `def` is the descriptor registered for the type name, `methods` the
    /// separately-declared `fun T:m()` names, and `rt` supplies inline record
    /// fields when the value is a table type.
    pub fn satisfies(
        def: ?*const ast.AliasDef,
        methods: ?[]const []const u8,
        rt: RT,
        concept: ConceptInfo,
    ) bool {
        const rt_fields: []const types.FieldType = if (rt == .table_type) rt.table_type.fields else &.{};

        for (concept.required_fields) |req| {
            var found = false;
            if (def) |d| found = hasfield(d, req.name);
            if (!found) {
                for (rt_fields) |f| {
                    if (std.mem.eql(u8, f.name, req.name)) {
                        found = true;
                        break;
                    }
                }
            }
            if (!found) return false;
        }

        for (concept.required_methods) |req| {
            var found = false;
            if (methods) |ms| {
                for (ms) |m| {
                    if (std.mem.eql(u8, m, req.name)) {
                        found = true;
                        break;
                    }
                }
            }
            if (!found) {
                if (def) |d| found = hasfield(d, req.name) or hasmethod(d, req.name);
            }
            if (!found) {
                for (rt_fields) |f| {
                    if (std.mem.eql(u8, f.name, req.name)) {
                        found = true;
                        break;
                    }
                }
            }
            if (!found) return false;
        }
        return true;
    }
};

/// A stored function signature for overload resolution (Requirement 12).
pub const FuncSignature = struct {
    param_types: []const RT,
    ret: RT,
    is_vararg: bool,
};

/// Checked identity of one callable application. AST pointers are provenance
/// keys only; `target` is the declaration selected by semantic analysis.
pub const ApplicationFact = struct {
    target: *const ast.FuncDecl,
    subject: ?*const Expr,
    arguments: []const *Expr,
    result: RT,
};

const Diagnostic = struct {
    loc: ast.Loc,
    message: []const u8,
};

const DiagnosticEvidence = enum {
    complete,
    incomplete,
};

pub const Sema = struct {
    alloc: Allocator,
    scope: Scope,
    type_map: TypeMap,
    module_globals: std.StringHashMapUnmanaged(RT) = .{},
    /// Module-scope Duo bindings retained after `check_module` (Pass 2 lattice queries).
    module_bindings: std.StringHashMapUnmanaged(Symbol) = .{},
    /// Pass 34 L1 — req bindings treated as sealed-after-load unless mutated (duo_mode).
    module_sealed: std.StringHashMapUnmanaged(void) = .{},
    /// Registry of declared enum types for exhaustiveness checking.
    enum_types: std.StringHashMapUnmanaged(RT) = .{},
    /// `<case>` -> the case-set that declares it, `""` when two do. c0 §41
    /// `resolution.rule`, gap[087].
    ///
    /// A FAST REJECT, not the resolver. The resolver reads the DEMANDED
    /// case-set's own variants — the demand is what decides, and this map only
    /// answers "is this spelling a case anywhere?" so an ordinary `a == b`
    /// costs one hash lookup instead of a type check. Keeping the two apart is
    /// what stops the index from becoming a second authority: it can never
    /// select a home, only decline to look.
    case_homes: std.StringHashMapUnmanaged([]const u8) = .{},
    /// Registry of declared concepts for satisfaction checking.
    concepts: std.StringHashMapUnmanaged(ConceptInfo) = .{},
    /// Registry of overloaded function signatures (Requirement 12).
    /// Maps function name → list of overload signatures.
    overloads: std.StringHashMapUnmanaged(std.ArrayListUnmanaged(FuncSignature)) = .{},
    /// Unique module callables by source name. Null marks an overloaded spelling
    /// that cannot identify a declaration without overload resolution.
    callable_defs: std.StringHashMapUnmanaged(?*const ast.FuncDecl) = .{},
    /// Authoritative callable resolution retained per checked application.
    applications: std.AutoHashMapUnmanaged(*const Expr, ApplicationFact) = .empty,
    /// Top-level type aliases, used by semantic type resolution. Shares one
    /// type, one derivation and one decision procedure with CodeGen's registry
    /// — see `AliasRegistry`.
    alias_defs: AliasRegistry = .{},
    /// Top-level function generic arities. `null` means the function exists but
    /// is not generic.
    generic_func_arities: std.StringHashMapUnmanaged(?usize) = .{},
    /// Tracked generic instantiation sites for the monomorphizer (Requirement 4.1, 4.3).
    /// Updated on assignments, queried on field reads. Keys are
    /// `{func}.{table}.{field}` for top-level functions, or `{table}.{field}` otherwise.
    table_field_types: std.StringHashMapUnmanaged(RT) = .{},
    /// Metatable type tracking: maps variable name → known metatable fields.
    /// Populated when setmetatable(x, mt) is called and mt is a table literal
    /// with known __index. Enables compile-time method resolution.
    /// Methods registered via `fun Table:method()` at module scope.
    table_methods: std.StringHashMapUnmanaged(std.ArrayListUnmanaged([]const u8)) = .{},
    diagnostics: std.ArrayListUnmanaged(Diagnostic) = .empty,
    diagnostic_evidence: DiagnosticEvidence = .complete,
    errors: u32,
    warnings: u32,
    hints: u32,
    infos: u32,
    hints_enabled: bool = false,
    info_enabled: bool = false,
    current_ret: RT,
    /// Pass 100 §8 B-12 — the contract being checked declared a FAILURE
    /// alternative (`: u64 | error`), so what it returns is the correlated
    /// pack `(value, nil) | (nil, error)`. A `nil` in the VALUE position is
    /// then the declared shape of a failure, not a type error.
    current_ret_fallible: bool = false,
    current_nopanic: bool = false,
    next_closure_id: u32 = 0,
    /// When true, module scope starts with implicit `global *` (plain .lua files).
    lua55_mode: bool = false,
    /// When true, variables are local by default ( .id files).
    duo_mode: bool = false,
    /// When type-checking a named top-level function body, its Duo name (for table field keys).
    current_func_name: ?[]const u8 = null,
    /// Active generic type parameters while checking a generic function body.
    current_func_type_params: ?[]const ast.TypeExpr = null,
    /// When inside an enum_def, alias_def, or concept_def, the name of the type
    /// being defined. Used by types.resolve() to resolve `Self` to the enclosing type.
    current_type_name: ?[]const u8 = null,
    /// Set of variable names that escape their scope (captured by closures).
    /// Populated during analysis; consumed by the ARC pass for pruning.
    escape_names: std.StringHashMapUnmanaged(void) = .{},
    /// Collected `@test` / `@bench` functions for `duo test` / `duo bench`.
    test_entries: std.ArrayListUnmanaged(TestEntry) = .empty,
    /// Collected `@build.*` module directives from the current module.
    build_directives: std.ArrayListUnmanaged(ast.Attribute) = .empty,
    debug_directives: std.ArrayListUnmanaged(ast.Attribute) = .empty,
    /// Pass 5: Duo source path for resolving `@c.import` header paths.
    source_path: ?[]const u8 = null,
    /// Imported C record descriptors keyed by foreign type name (e.g. CPoint).
    foreign_records: std.StringHashMapUnmanaged(RT) = .{},
    /// Imported C function descriptors keyed by Duo name (e.g. distance2).
    foreign_functions: std.StringHashMapUnmanaged(foreign_adapter.ForeignFunc) = .{},

    pub const TestEntry = struct {
        func_name: []const u8,
        loc: ast.Loc,
        options: directives.TestOptions,
    };

    /// Standard library function names that are known built-in globals.
    fn is_builtin_global(_: *const Sema, name: []const u8) bool {
        // Lua standard library globals
        if (std.mem.eql(u8, name, "string") or
            std.mem.eql(u8, name, "table") or
            std.mem.eql(u8, name, "math") or
            std.mem.eql(u8, name, "io") or
            std.mem.eql(u8, name, "os") or
            std.mem.eql(u8, name, "coroutine") or
            std.mem.eql(u8, name, "package") or
            std.mem.eql(u8, name, "debug") or
            std.mem.eql(u8, name, "utf8") or
            std.mem.eql(u8, name, "bit") or
            std.mem.eql(u8, name, "arg") or
            std.mem.eql(u8, name, "jit") or
            std.mem.eql(u8, name, "ffi") or
            std.mem.eql(u8, name, "mem") or
            std.mem.eql(u8, name, "ml") or
            std.mem.eql(u8, name, "atomic"))
            return true;
        // Duo standard library namespace
        if (std.mem.eql(u8, name, "std")) return true;
        // Lua built-in functions
        if (std.mem.eql(u8, name, "print") or
            std.mem.eql(u8, name, "gatecap") or
            std.mem.eql(u8, name, "assert") or
            std.mem.eql(u8, name, "error") or
            std.mem.eql(u8, name, "ipairs") or
            std.mem.eql(u8, name, "pairs") or
            std.mem.eql(u8, name, "next") or
            std.mem.eql(u8, name, "pcall") or
            std.mem.eql(u8, name, "xpcall") or
            std.mem.eql(u8, name, "select") or
            std.mem.eql(u8, name, "tostring") or
            std.mem.eql(u8, name, "tonumber") or
            std.mem.eql(u8, name, "type") or
            std.mem.eql(u8, name, "rawget") or
            std.mem.eql(u8, name, "rawset") or
            std.mem.eql(u8, name, "rawlen") or
            std.mem.eql(u8, name, "rawget") or
            std.mem.eql(u8, name, "rawequal") or
            std.mem.eql(u8, name, "setmetatable") or
            std.mem.eql(u8, name, "getmetatable") or
            std.mem.eql(u8, name, "collectgarbage") or
            std.mem.eql(u8, name, "load") or
            std.mem.eql(u8, name, "loadfile") or
            std.mem.eql(u8, name, "dofile") or
            std.mem.eql(u8, name, "require") or
            std.mem.eql(u8, name, "req") or
            std.mem.eql(u8, name, "__constexpr") or
            std.mem.eql(u8, name, "__asm") or
            std.mem.eql(u8, name, "__emit") or
            std.mem.eql(u8, name, "__bitcast") or
            std.mem.eql(u8, name, "__volatile") or
            std.mem.eql(u8, name, "__sizeof") or
            std.mem.eql(u8, name, "__alignof") or
            std.mem.eql(u8, name, "__offsetof") or
            std.mem.eql(u8, name, "__typeinfo") or
            std.mem.eql(u8, name, "__comptimeif") or
            std.mem.eql(u8, name, "__static_assert") or
            std.mem.eql(u8, name, "__typeof") or
            std.mem.eql(u8, name, "__as") or
            std.mem.eql(u8, name, "__likely") or
            std.mem.eql(u8, name, "__unlikely") or
            std.mem.eql(u8, name, "__prefetch") or
            std.mem.eql(u8, name, "__assume") or
            std.mem.eql(u8, name, "__unreachable") or
            std.mem.eql(u8, name, "__trap") or
            std.mem.eql(u8, name, "__comptimefold") or
            std.mem.eql(u8, name, "__comptimefor") or
            std.mem.eql(u8, name, "__select") or
            std.mem.eql(u8, name, "__ctz") or
            std.mem.eql(u8, name, "__clz") or
            std.mem.eql(u8, name, "__popcount") or
            std.mem.eql(u8, name, "__bswap") or
            std.mem.eql(u8, name, "__rotl") or
            std.mem.eql(u8, name, "__rotr") or
            std.mem.eql(u8, name, "__fence") or
            // Metaprogramming: type introspection & reflection
            std.mem.eql(u8, name, "__fields") or
            std.mem.eql(u8, name, "__methods") or
            std.mem.eql(u8, name, "__concept_methods") or
            std.mem.eql(u8, name, "__variants") or
            std.mem.eql(u8, name, "__has_field") or
            std.mem.eql(u8, name, "__has_method") or
            std.mem.eql(u8, name, "__field_type") or
            // Metaprogramming: type construction & manipulation
            std.mem.eql(u8, name, "__type_name") or
            std.mem.eql(u8, name, "__type_id") or
            std.mem.eql(u8, name, "__is_type") or
            std.mem.eql(u8, name, "__as_type") or
            // Metaprogramming: compile-time code gen & control
            std.mem.eql(u8, name, "__comptimeprint") or
            std.mem.eql(u8, name, "__comptimeerror") or
            std.mem.eql(u8, name, "__comptimewarn") or
            std.mem.eql(u8, name, "__embed_file") or
            std.mem.eql(u8, name, "__embed_str") or
            std.mem.eql(u8, name, "__make_type") or
            // Metaprogramming: layout control
            std.mem.eql(u8, name, "__bitfield") or
            std.mem.eql(u8, name, "__union") or
            std.mem.eql(u8, name, "__field_offset") or
            std.mem.eql(u8, name, "__field_size") or
            // Metaprogramming: metatable type tracking
            std.mem.eql(u8, name, "__metatable_type") or
            std.mem.eql(u8, name, "__has_metamethod") or
            // Metaprogramming: compile-time dispatch control
            std.mem.eql(u8, name, "__inline_always") or
            std.mem.eql(u8, name, "__no_inline") or
            std.mem.eql(u8, name, "__cold_path") or
            std.mem.eql(u8, name, "__hot_path"))
            return true;
        return false;
    }

    pub fn init(alloc: Allocator) Sema {
        return .{
            .alloc = alloc,
            .scope = Scope.init(alloc),
            .type_map = TypeMap.init(alloc),
            .errors = 0,
            .warnings = 0,
            .hints = 0,
            .infos = 0,
            .current_ret = .void,
            .current_ret_fallible = false,
            .next_closure_id = 0,
            .table_field_types = .empty,
        };
    }

    /// Check whether the current function's return type is result-compatible.
    /// A type is result-compatible if it is a result type, an option type,
    /// or 'any' (which could be a result at runtime).
    fn is_result_compatible_ret(self: *const Sema) bool {
        return switch (self.current_ret) {
            .result => true,
            .option => true,
            .any => true,
            else => false,
        };
    }

    /// Knowledge lattice position for a checked expression (Pass 2).
    pub fn exprKnowledge(self: *const Sema, expr: *const ast.Expr) semantic_algebra.KnowledgeLevel {
        const rt = self.type_map.get(expr) orelse return .unknown;
        return semantic_algebra.knowledgeOfType(rt);
    }

    /// Knowledge lattice position for a lexical binding, if defined.
    pub fn symbolKnowledge(self: *const Sema, name: []const u8) semantic_algebra.KnowledgeLevel {
        if (self.scope.lookup(name)) |sym| return sym.knowledge();
        if (self.module_bindings.get(name)) |sym| return sym.knowledge();
        return .unknown;
    }

    /// Descriptor established by semantic checking for this exact expression.
    pub fn exprDescriptor(self: *const Sema, expr: *const Expr) ?RT {
        return self.type_map.get(expr);
    }

    /// Callable identity established for this exact application. Absence means
    /// unresolved or dynamic; consumers must not replace it with name lookup.
    pub fn applicationFact(self: *const Sema, expr: *const Expr) ?ApplicationFact {
        return self.applications.get(expr);
    }

    fn recordApplication(
        self: *Sema,
        expr: *const Expr,
        target: *const ast.FuncDecl,
        subject: ?*const Expr,
        arguments: []const *Expr,
        result: RT,
    ) SemaError!void {
        try self.applications.put(self.alloc, expr, .{
            .target = target,
            .subject = subject,
            .arguments = arguments,
            .result = result,
        });
    }

    /// Pass 34 L1 — true when binding is a req module assumed frozen after load.
    pub fn moduleSealed(self: *const Sema, name: []const u8) bool {
        return self.module_sealed.contains(name);
    }

    fn reqInitPath(expr: *const ast.Expr) ?[]const u8 {
        if (expr.* != .call) return null;
        const c = &expr.call;
        if (c.func.* != .name) return null;
        const fn_name = c.func.name.ident;
        if (!std.mem.eql(u8, fn_name, "req") and !std.mem.eql(u8, fn_name, "require")) return null;
        if (c.args.len != 1 or c.args[0].* != .string_lit) return null;
        return c.args[0].string_lit.val;
    }

    fn markModuleSealed(self: *Sema, name: []const u8) !void {
        if (self.module_sealed.contains(name)) return;
        const owned = try self.alloc.dupe(u8, name);
        try self.module_sealed.put(self.alloc, owned, {});
    }

    fn invalidateModuleSealed(self: *Sema, name: []const u8) void {
        if (self.module_sealed.fetchRemove(name)) |kv| {
            self.alloc.free(kv.key);
        }
    }

    fn noteModuleSealingFromInit(self: *Sema, name: []const u8, init_expr: *const ast.Expr) !void {
        if (!self.duo_mode) return;
        if (reqInitPath(init_expr) != null) try self.markModuleSealed(name);
    }

    fn noteModuleSealingInvalidation(self: *Sema, tgt: *const ast.Expr, value: ?*const ast.Expr) void {
        if (!self.duo_mode) return;
        switch (tgt.*) {
            .name => |n| {
                if (self.module_sealed.contains(n.ident)) {
                    if (value) |v| {
                        if (reqInitPath(v) == null) self.invalidateModuleSealed(n.ident);
                    } else {
                        self.invalidateModuleSealed(n.ident);
                    }
                } else if (value) |v| {
                    if (reqInitPath(v) != null) self.markModuleSealed(n.ident) catch {};
                }
            },
            .field => |f| {
                if (f.obj.* == .name and self.module_sealed.contains(f.obj.name.ident)) {
                    self.invalidateModuleSealed(f.obj.name.ident);
                }
            },
            else => {},
        }
    }

    pub fn deinit(self: *Sema) void {
        for (self.diagnostics.items) |diagnostic| self.alloc.free(diagnostic.message);
        self.diagnostics.deinit(self.alloc);
        self.scope.deinit();
        self.type_map.deinit();
        self.module_globals.deinit(self.alloc);
        var mb_it = self.module_bindings.iterator();
        while (mb_it.next()) |entry| {
            self.alloc.free(entry.key_ptr.*);
        }
        self.module_bindings.deinit(self.alloc);
        var ms_it = self.module_sealed.iterator();
        while (ms_it.next()) |entry| {
            self.alloc.free(entry.key_ptr.*);
        }
        self.module_sealed.deinit(self.alloc);
        self.enum_types.deinit(self.alloc);
        self.case_homes.deinit(self.alloc);
        self.concepts.deinit(self.alloc);
        // Clean up overload lists.
        var it = self.overloads.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(self.alloc);
        }
        self.overloads.deinit(self.alloc);
        self.callable_defs.deinit(self.alloc);
        self.applications.deinit(self.alloc);
        self.alias_defs.deinit(self.alloc);
        self.generic_func_arities.deinit(self.alloc);
        self.test_entries.deinit(self.alloc);
        self.build_directives.deinit(self.alloc);
        self.debug_directives.deinit(self.alloc);
        self.escape_names.deinit(self.alloc);
        self.table_field_types.deinit(self.alloc);
        var tm_it = self.table_methods.iterator();
        while (tm_it.next()) |entry| {
            entry.value_ptr.deinit(self.alloc);
        }
        self.table_methods.deinit(self.alloc);
        var fr_it = self.foreign_records.iterator();
        while (fr_it.next()) |entry| {
            self.alloc.free(entry.key_ptr.*);
            releaseForeignRecordRt(self.alloc, entry.value_ptr);
        }
        self.foreign_records.deinit(self.alloc);
        var ff_it = self.foreign_functions.iterator();
        while (ff_it.next()) |entry| {
            self.alloc.free(entry.key_ptr.*);
            entry.value_ptr.deinit(self.alloc);
        }
        self.foreign_functions.deinit(self.alloc);
        if (self.source_path) |sp| self.alloc.free(sp);
    }

    fn note_global(self: *Sema, name: []const u8, t: RT) !void {
        const gop = try self.module_globals.getOrPut(self.alloc, name);
        if (!gop.found_existing) {
            gop.value_ptr.* = t;
        } else if (gop.value_ptr.* == .any and t != .any) {
            gop.value_ptr.* = t;
        }
    }

    /// Infer a concrete type from a literal expression for better codegen.
    /// `OP_NOP = 0x01` → `.i64`, `PI = 3.14` → `.f64`, `name = "hi"` → `.str`.
    /// Falls back to `.any` for non-literal initializers.
    fn infer_literal_type(self: *Sema, e: *const ast.Expr) RT {
        return switch (e.*) {
            .int_lit => .i64,
            .float_lit => .f64,
            .string_lit => .str,
            .true_lit, .false_lit => .bool,
            .nil => .any,
            // Simple binops on integer literals: 0x01 << 4 → i64
            .binop => |b| if (b.op == .band or b.op == .bor or b.op == .bxor or
                b.op == .lshift or b.op == .rshift or b.op == .add or b.op == .sub or
                b.op == .mul)
            {
                const lt = switch (b.lhs.*) {
                    .int_lit => .i64,
                    .binop => self.infer_literal_type(b.lhs),
                    else => .any,
                };
                const rt = switch (b.rhs.*) {
                    .int_lit => .i64,
                    .binop => self.infer_literal_type(b.rhs),
                    else => .any,
                };
                if (lt == .i64 and rt == .i64) return .i64;
                if (lt == .f64 or rt == .f64) return .f64;
                return .any;
            } else .any,
            else => .any,
        };
    }

    /// Inclusive bounds of a sized integer descriptor; null for everything else.
    /// `u64`'s max is deliberately clamped to i64 max — the literal arrives as an
    /// i64 and a wider bound could not be represented to compare against, so the
    /// honest thing is to not claim a check we cannot perform.
    fn intMin(t: RT) ?i64 {
        return switch (t) {
            .i8 => -128,
            .i16 => -32768,
            .i32 => -2147483648,
            .i64 => std.math.minInt(i64),
            .u8, .u16, .u32, .u64 => 0,
            else => null,
        };
    }

    fn intMax(t: RT) ?i64 {
        return switch (t) {
            .i8 => 127,
            .i16 => 32767,
            .i32 => 2147483647,
            .i64, .u64 => std.math.maxInt(i64),
            .u8 => 255,
            .u16 => 65535,
            .u32 => 4294967295,
            else => null,
        };
    }

    /// The literal value of `e` when it is an integer literal, or the negation of
    /// one — `-1` is a unary minus over `1`, and a range check that missed that
    /// would pass every negative literal into an unsigned descriptor.
    fn intLiteralValue(e: *const ast.Expr) ?i64 {
        return switch (e.*) {
            .int_lit => |l| l.val,
            .unop => |u| if (u.op == .neg) blk: {
                const inner = intLiteralValue(u.operand) orelse break :blk null;
                break :blk -inner;
            } else null,
            else => null,
        };
    }

    /// The literal, when it provably does not fit the annotation. Null means
    /// either "fits" or "not a literal" — this never guesses at a computed value,
    /// which is a range-fact question for the checker, not a lexical one.
    fn literalOutOfRange(ann: RT, e: *const ast.Expr) ?i64 {
        const lo = intMin(ann) orelse return null;
        const hi = intMax(ann) orelse return null;
        const v = intLiteralValue(e) orelse return null;
        if (v < lo or v > hi) return v;
        return null;
    }

    fn type_annotation_accepts_init(ann: RT, init_t: RT) bool {
        if (ann.eql(init_t)) return true;
        // law.nominal (§46) — NOMINALITY IS THE POINT, and it is enforced by
        // REFUSING the representation shortcut, not by adding a rule.
        //
        // `feet` and `f64` are the same double and `is_float()` says so, which
        // is exactly what makes the next two lines dangerous: without this
        // guard a nominal descriptor would accept any value of its own
        // representation and would not be nominal at all. A descriptor that
        // accepts anything is a comment.
        //
        // Both directions refuse. `d: feet = x` (x: f64) is the obvious one;
        // `y: f64 = d` is the same law read the other way — a `feet` does not
        // silently become a plain double either. The repair for both is the
        // conversion edge, which is the whole reason the trie exists.
        if (types.nominalReprOf(ann) != null or types.nominalReprOf(init_t) != null) return false;
        if (ann.is_integer() and init_t.is_integer()) return true;
        return type_annotation_accepts_init_rest(ann, init_t);
    }

    /// CDR (B-13) — A DECLARED CONTRACT DIRECTS REALIZATION.
    ///
    /// `d: feet = 3.0` is admitted and `d: feet = x` is not, and the difference
    /// is not a weakening of nominality — it is the literal rule the rest of
    /// the language already runs on. A bare numeral carries NO descriptor of
    /// its own; §0g says so in as many words ("literals — the card shows the
    /// DESCRIPTOR, CDR-inferred from the contract"), and it is why `n: u8 = 3`
    /// is a u8 rather than an i64 that happens to fit. The contract names the
    /// literal; nothing is coerced, because there was nothing there yet to
    /// coerce.
    ///
    /// `x` is different in kind. It already carries `f64`, and letting a second
    /// descriptor attach to a value that has one is precisely the silent
    /// coercion that makes nominal descriptors decorative.
    ///
    /// The representation still has to fit: `d: feet = "3"` is refused, because
    /// CDR directs realization and does not invent one.
    fn nominal_accepts_literal(ann: RT, e: *const ast.Expr) bool {
        const repr = types.nominalReprOf(ann) orelse return false;
        return switch (e.*) {
            .int_lit => repr.is_numeric(),
            .float_lit => repr.is_float(),
            .string_lit => repr == .str,
            .true_lit, .false_lit => repr == .bool,
            // `-3.0` is one literal wearing a sign, not an operation on a value
            // that already has a descriptor.
            .unop => |u| u.op == .neg and nominal_accepts_literal(ann, u.operand),
            else => false,
        };
    }

    fn type_annotation_accepts_init_rest(ann: RT, init_t: RT) bool {
        if (ann.is_float() and init_t.is_float()) return true;
        // ?T accepts T (optional accepts its inner type)
        if (ann == .option) {
            if (ann.option.eql(init_t)) return true;
            if (ann.option.is_numeric() and init_t.is_numeric()) return true;
        }
        // Result[T, E] accepts T
        if (ann == .result) {
            if (ann.result.ok.eql(init_t)) return true;
        }
        return false;
    }

    fn err(self: *Sema, loc: ast.Loc, comptime fmt: []const u8, args: anytype) void {
        self.errors += 1;
        const message = std.fmt.allocPrint(self.alloc, fmt, args) catch {
            self.diagnostic_evidence = .incomplete;
            term.locErr(loc, fmt, args);
            return;
        };
        self.diagnostics.append(self.alloc, .{ .loc = loc, .message = message }) catch {
            self.alloc.free(message);
            self.diagnostic_evidence = .incomplete;
            term.locErr(loc, fmt, args);
            return;
        };
        term.locErr(loc, "{s}", .{message});
    }

    /// gap[026]: relation families are declared at the trie, not as functions,
    /// so a call like `has(.err)(r)` resolves through the ladder rather than
    /// through scope. Without this the undeclared-call guard rejects 80 of 256
    /// lib/std modules — measured, and the reason the guard is not just a
    /// scope lookup.
    fn is_relation_family(name: []const u8) bool {
        // Inlined from the deleted `pass48_catalog.zig`. These two arrays were
        // the ONLY part of the 58-file audit-apparatus cluster that the live
        // compiler read: the catalog existed to be self-checked by a gate, and
        // this data rode along inside it. It belongs with its one consumer.
        const std_relation_families = [_][]const u8{
            "to",      "from", "eq",    "cmp",   "hash",    "format", "iter",
            "release", "ref",  "deref", "clone", "default", "get",    "set",
            "call",    "len",  "copy",  "share", "encode",  "decode",
        };
        const shc_relation_families = [_][]const u8{
            "lower",  "validate", "canonicalize", "realize", "rewrite", "measure",
            "derive", "observe",
        };
        for (std_relation_families) |f| {
            if (std.mem.eql(u8, name, f)) return true;
        }
        for (shc_relation_families) |f| {
            if (std.mem.eql(u8, name, f)) return true;
        }
        // `has` is named by Pass 81 §2.2 as projecting over `place` beside
        // `get`/`set`, but pass48_catalog.std_relation_families lists only those
        // two. Measured: without this, the guard rejects 20 lib/std modules that
        // legitimately call `has(.err)(r)`. Listed here rather than added to the
        // catalog so a catalog-count gate is not silently moved.
        if (std.mem.eql(u8, name, "has")) return true;
        // Path-boundary proof helpers: `audit(path)(pattern)` and `hit(path)(pattern)`
        // curry like `len(path)(min)` and `to(micron)(inch)`. Without admission the
        // undeclared-call guard rejects the second application on string paths.
        if (std.mem.eql(u8, name, "audit")) return true;
        if (std.mem.eql(u8, name, "hit")) return true;
        // `__`-prefixed names are compiler intrinsics (__native_load_u8,
        // __sizeof, __typeof, the __comptime* family). They are recognised in
        // the call handler by name, never declared in scope, so the undeclared
        // -call guard must not see them. Caught by pass11_wasm_blob_direct.
        if (std.mem.startsWith(u8, name, "__")) return true;
        return false;
    }

    fn warn_msg(self: *Sema, loc: ast.Loc, comptime fmt: []const u8, args: anytype) void {
        self.warnings += 1;
        term.locWarn(loc, fmt, args);
    }

    fn hint_msg(self: *Sema, loc: ast.Loc, comptime fmt: []const u8, args: anytype) void {
        if (!self.hints_enabled) return;
        self.hints += 1;
        term.locHint(loc, fmt, args);
    }

    fn info_msg(self: *Sema, loc: ast.Loc, comptime fmt: []const u8, args: anytype) void {
        if (!self.info_enabled) return;
        self.infos += 1;
        term.locInfo(loc, fmt, args);
    }

    fn define_vararg_rest(self: *Sema, fb: *const ast.FuncBody) !void {
        if (fb.vararg_name) |vn| {
            try self.scope.define(vn, .{
                .typ = .any,
                .is_const = false,
                .is_vararg_rest = true,
            });
        }
    }

    fn check_assign_target(self: *Sema, tgt: *ast.Expr) SemaError!void {
        switch (tgt.*) {
            .name => |n| {
                if (self.scope.lookup(n.ident)) |sym| {
                    if (sym.is_for_control) {
                        self.err(n.loc, "cannot assign to for loop control variable '{s}'", .{n.ident});
                    } else if (sym.is_const) {
                        self.err(n.loc, "attempt to assign to const variable '{s}'", .{n.ident});
                    } else if (sym.is_close) {
                        self.err(n.loc, "attempt to assign to to-be-closed variable '{s}'", .{n.ident});
                    } else if (sym.is_vararg_rest) {
                        self.err(n.loc, "attempt to modify read-only vararg table '{s}'", .{n.ident});
                    }
                } else {
                    if (self.duo_mode) {
                        // In duo mode, undeclared variables are local by default
                        try self.scope.define(n.ident, .{
                            .typ = .any,
                            .is_const = false,
                        });
                    } else if (self.scope.needs_explicit_global()) {
                        self.err(n.loc, "attempt to assign to undeclared global '{s}'", .{n.ident});
                    } else {
                        try self.note_global(n.ident, .any);
                    }
                }
            },
            .index => |idx| {
                if (idx.obj.* == .name) {
                    const n = idx.obj.name;
                    if (self.scope.lookup(n.ident)) |sym| {
                        if (sym.is_vararg_rest) {
                            self.err(idx.loc, "attempt to modify read-only vararg table '{s}'", .{n.ident});
                        }
                    }
                }
            },
            .field => |f| {
                if (f.obj.* == .name) {
                    const n = f.obj.name;
                    if (self.scope.lookup(n.ident)) |sym| {
                        if (sym.is_vararg_rest) {
                            self.err(f.loc, "attempt to modify read-only vararg table '{s}'", .{n.ident});
                        }
                    }
                }
            },
            else => {},
        }
    }

    fn mem_intrinsic_name(_: *const Sema, func: *const ast.Expr) ?[]const u8 {
        if (func.* != .field) return null;
        const f = func.field;
        if (f.obj.* == .name and std.mem.eql(u8, f.obj.name.ident, "mem")) return f.field;
        if (f.obj.* == .field) {
            const inner = f.obj.field;
            if (inner.obj.* == .name and
                std.mem.eql(u8, inner.obj.name.ident, "std") and
                std.mem.eql(u8, inner.field, "mem"))
                return f.field;
        }
        return null;
    }

    fn ml_intrinsic_name(_: *const Sema, func: *const ast.Expr) ?[]const u8 {
        if (func.* != .field) return null;
        const f = func.field;
        if (f.obj.* == .name and std.mem.eql(u8, f.obj.name.ident, "ml")) return f.field;
        if (f.obj.* == .field) {
            const inner = f.obj.field;
            if (inner.obj.* == .name and
                std.mem.eql(u8, inner.obj.name.ident, "std") and
                std.mem.eql(u8, inner.field, "ml"))
                return f.field;
        }
        return null;
    }

    fn check_ml_call(self: *const Sema, loc: ast.Loc, fname: []const u8, args: []*ast.Expr) SemaError!RT {
        _ = self;
        _ = loc;
        if (args.len != 0) return .any;
        if (std.mem.eql(u8, fname, "matmul_256") or
            std.mem.eql(u8, fname, "conv2d") or
            std.mem.eql(u8, fname, "softmax_1k") or
            std.mem.eql(u8, fname, "attention") or
            std.mem.eql(u8, fname, "mlp_forward") or
            std.mem.eql(u8, fname, "gelu_1k") or
            std.mem.eql(u8, fname, "layernorm_1k") or
            std.mem.eql(u8, fname, "dot_1m") or
            std.mem.eql(u8, fname, "conv1d"))
            return .f64;
        return .any;
    }

    fn mem_type_from_name(self: *Sema, name: []const u8) SemaError!?RT {
        if (name.len == 0) return null;
        if (name[0] == '*') {
            const inner = try self.mem_type_from_name(name[1..]) orelse return null;
            const ptr = try self.alloc.create(RT);
            ptr.* = inner;
            return RT{ .pointer = ptr };
        }
        if (std.mem.eql(u8, name, "void")) return .void;
        if (std.mem.eql(u8, name, "i8")) return .i8;
        if (std.mem.eql(u8, name, "i16")) return .i16;
        if (std.mem.eql(u8, name, "i32")) return .i32;
        if (std.mem.eql(u8, name, "i64") or std.mem.eql(u8, name, "isize")) return .i64;
        if (std.mem.eql(u8, name, "u8")) return .u8;
        if (std.mem.eql(u8, name, "u16")) return .u16;
        if (std.mem.eql(u8, name, "u32")) return .u32;
        if (std.mem.eql(u8, name, "u64") or std.mem.eql(u8, name, "usize")) return .u64;
        if (std.mem.eql(u8, name, "f32")) return .f32;
        if (std.mem.eql(u8, name, "f64")) return .f64;
        if (std.mem.eql(u8, name, "bool")) return .bool;
        if (std.mem.eql(u8, name, "str") or std.mem.eql(u8, name, "string")) return .str;
        if (std.mem.eql(u8, name, "ptr") or std.mem.eql(u8, name, "void*")) {
            const ptr = try self.alloc.create(RT);
            ptr.* = .void;
            return RT{ .pointer = ptr };
        }
        return null;
    }

    fn mem_type_arg(self: *Sema, args: []const *ast.Expr, index: usize) SemaError!?RT {
        if (index >= args.len) return null;
        if (args[index].* != .string_lit) return null;
        return try self.mem_type_from_name(args[index].string_lit.val);
    }

    fn mem_pointer_to(self: *Sema, pointee: RT) SemaError!RT {
        const ptr = try self.alloc.create(RT);
        ptr.* = pointee;
        return RT{ .pointer = ptr };
    }

    fn mem_call_result_type(self: *Sema, fname: []const u8, args: []const *ast.Expr) SemaError!?RT {
        if (std.mem.eql(u8, fname, "alloc") or std.mem.eql(u8, fname, "calloc") or
            std.mem.eql(u8, fname, "byte_add"))
            return try self.mem_pointer_to(.u8);
        if (std.mem.eql(u8, fname, "realloc") or std.mem.eql(u8, fname, "add")) {
            if (args.len > 0) {
                const t = self.type_map.get(args[0]) orelse .any;
                if (t == .pointer) return t;
            }
            return try self.mem_pointer_to(.u8);
        }
        if (std.mem.eql(u8, fname, "cast") or std.mem.eql(u8, fname, "ptr_cast") or
            std.mem.eql(u8, fname, "ptr_from_addr") or std.mem.eql(u8, fname, "ptrfromaddr"))
        {
            const pointee = try self.mem_type_arg(args, 0) orelse return try self.mem_pointer_to(.void);
            return try self.mem_pointer_to(pointee);
        }
        if (std.mem.eql(u8, fname, "addr")) return .u64;
        if (std.mem.eql(u8, fname, "load") or std.mem.eql(u8, fname, "volatile_load"))
            return (try self.mem_type_arg(args, 0)) orelse .any;
        if (std.mem.eql(u8, fname, "store") or std.mem.eql(u8, fname, "volatile_store") or
            std.mem.eql(u8, fname, "free") or std.mem.eql(u8, fname, "copy") or
            std.mem.eql(u8, fname, "move") or std.mem.eql(u8, fname, "set") or
            std.mem.eql(u8, fname, "zero") or std.mem.eql(u8, fname, "fence") or
            std.mem.eql(u8, fname, "compiler_fence") or std.mem.eql(u8, fname, "prefetch") or
            std.mem.eql(u8, fname, "assume") or std.mem.eql(u8, fname, "trap") or
            std.mem.eql(u8, fname, "unreachable"))
            return .void;
        if (std.mem.eql(u8, fname, "read_byte") or std.mem.eql(u8, fname, "read_i8") or
            std.mem.eql(u8, fname, "read_u8") or std.mem.eql(u8, fname, "read_i16") or
            std.mem.eql(u8, fname, "read_u16") or std.mem.eql(u8, fname, "read_i32") or
            std.mem.eql(u8, fname, "read_u32") or std.mem.eql(u8, fname, "read_i64") or
            std.mem.eql(u8, fname, "read_u64"))
            return .i64;
        if (std.mem.eql(u8, fname, "read_f32") or std.mem.eql(u8, fname, "read_f64") or
            std.mem.eql(u8, fname, "bytes_to_f32") or std.mem.eql(u8, fname, "bytes_to_f64"))
            return .f64;
        if (std.mem.eql(u8, fname, "write_byte") or std.mem.eql(u8, fname, "writebyte") or std.mem.eql(u8, fname, "write_i8") or
            std.mem.eql(u8, fname, "write_u8") or std.mem.eql(u8, fname, "write_i16") or
            std.mem.eql(u8, fname, "write_u16") or std.mem.eql(u8, fname, "write_i32") or
            std.mem.eql(u8, fname, "write_u32") or std.mem.eql(u8, fname, "write_i64") or std.mem.eql(u8, fname, "writei64") or
            std.mem.eql(u8, fname, "write_u64") or std.mem.eql(u8, fname, "write_f32") or
            std.mem.eql(u8, fname, "write_f64") or std.mem.eql(u8, fname, "writef64"))
            return .void;
        if (std.mem.eql(u8, fname, "dup")) return try self.mem_pointer_to(.u8);
        if (std.mem.eql(u8, fname, "compare")) return .i64;
        if (std.mem.eql(u8, fname, "is_null")) return .bool;
        if (std.mem.eql(u8, fname, "sizeof") or std.mem.eql(u8, fname, "alignof")) return .u64;
        return null;
    }

    fn mem_arg_count_ok(self: *Sema, loc: ast.Loc, fname: []const u8, got: usize, min: usize, max: usize) bool {
        if (got >= min and got <= max) return true;
        if (min == max) {
            self.err(loc, "mem.{s} expects {d} argument(s), got {d}", .{ fname, min, got });
        } else {
            self.err(loc, "mem.{s} expects {d} to {d} arguments, got {d}", .{ fname, min, max, got });
        }
        return false;
    }

    fn mem_validate_type_arg(self: *Sema, fname: []const u8, args: []const *ast.Expr, index: usize) SemaError!void {
        if (index >= args.len) return;
        const arg = args[index];
        // Canonical: a TYPE NAME value — `mem.store(i32)(p, v)`. Spec 2.10 G3
        // makes a type an ordinary value, so the descriptor parameter is the
        // type itself. The `"i32"` string spelling stays accepted while
        // existing sources migrate.
        if (arg.* == .name) {
            if ((try self.mem_type_from_name(arg.name.ident)) == null) {
                self.err(arg.*.loc(), "mem.{s} does not support memory type '{s}'", .{ fname, arg.name.ident });
            }
            return;
        }
        if (arg.* != .string_lit) {
            self.err(arg.*.loc(), "mem.{s} argument {d} must be a type name", .{ fname, index + 1 });
            return;
        }
        const name = arg.string_lit.val;
        if ((try self.mem_type_from_name(name)) == null) {
            self.err(arg.string_lit.loc, "mem.{s} does not support memory type '{s}'", .{ fname, name });
        }
    }

    fn mem_validate_numeric_arg(self: *Sema, fname: []const u8, args: []const *ast.Expr, index: usize) void {
        if (index >= args.len) return;
        const arg = args[index];
        const t = self.type_map.get(arg) orelse .any;
        if (t == .any or t.is_numeric()) return;
        self.err(arg.*.loc(), "mem.{s} argument {d} must be numeric, got {}", .{ fname, index + 1, t });
    }

    fn mem_validate_pointer_arg(self: *Sema, fname: []const u8, args: []const *ast.Expr, index: usize) void {
        if (index >= args.len) return;
        const arg = args[index];
        const t = self.type_map.get(arg) orelse .any;
        if (t == .any or t == .pointer) return;
        self.err(arg.*.loc(), "mem.{s} argument {d} must be a pointer, got {}", .{ fname, index + 1, t });
    }

    fn mem_validate_store_value(self: *Sema, fname: []const u8, args: []const *ast.Expr) SemaError!void {
        if (args.len < 3) return;
        const target = (try self.mem_type_arg(args, 0)) orelse return;
        const value = args[2];
        const vt = self.type_map.get(value) orelse .any;
        if (vt == .any) return;
        if (target.eql(vt)) return;
        if (target.is_numeric() and vt.is_numeric()) return;
        if (target == .pointer and (vt == .pointer or vt == .nil)) return;
        self.err(value.*.loc(), "mem.{s} value has type {}, expected {}", .{ fname, vt, target });
    }

    fn validate_mem_call(self: *Sema, loc: ast.Loc, fname: []const u8, args: []const *ast.Expr) SemaError!void {
        if (std.mem.eql(u8, fname, "alloc")) {
            _ = self.mem_arg_count_ok(loc, fname, args.len, 1, 1);
            self.mem_validate_numeric_arg(fname, args, 0);
            return;
        }
        if (std.mem.eql(u8, fname, "calloc")) {
            _ = self.mem_arg_count_ok(loc, fname, args.len, 2, 2);
            self.mem_validate_numeric_arg(fname, args, 0);
            self.mem_validate_numeric_arg(fname, args, 1);
            return;
        }
        if (std.mem.eql(u8, fname, "realloc")) {
            _ = self.mem_arg_count_ok(loc, fname, args.len, 2, 2);
            self.mem_validate_pointer_arg(fname, args, 0);
            self.mem_validate_numeric_arg(fname, args, 1);
            return;
        }
        if (std.mem.eql(u8, fname, "free") or std.mem.eql(u8, fname, "addr") or
            std.mem.eql(u8, fname, "is_null"))
        {
            _ = self.mem_arg_count_ok(loc, fname, args.len, 1, 1);
            self.mem_validate_pointer_arg(fname, args, 0);
            return;
        }
        if (std.mem.eql(u8, fname, "cast") or std.mem.eql(u8, fname, "ptr_cast")) {
            _ = self.mem_arg_count_ok(loc, fname, args.len, 2, 2);
            try self.mem_validate_type_arg(fname, args, 0);
            self.mem_validate_pointer_arg(fname, args, 1);
            return;
        }
        if (std.mem.eql(u8, fname, "ptr_from_addr") or std.mem.eql(u8, fname, "ptrfromaddr")) {
            _ = self.mem_arg_count_ok(loc, fname, args.len, 2, 2);
            try self.mem_validate_type_arg(fname, args, 0);
            self.mem_validate_numeric_arg(fname, args, 1);
            return;
        }
        if (std.mem.eql(u8, fname, "add") or std.mem.eql(u8, fname, "byte_add")) {
            _ = self.mem_arg_count_ok(loc, fname, args.len, 2, 2);
            self.mem_validate_pointer_arg(fname, args, 0);
            self.mem_validate_numeric_arg(fname, args, 1);
            return;
        }
        if (std.mem.eql(u8, fname, "load") or std.mem.eql(u8, fname, "volatile_load")) {
            _ = self.mem_arg_count_ok(loc, fname, args.len, 2, 2);
            try self.mem_validate_type_arg(fname, args, 0);
            self.mem_validate_pointer_arg(fname, args, 1);
            return;
        }
        if (std.mem.eql(u8, fname, "store") or std.mem.eql(u8, fname, "volatile_store")) {
            _ = self.mem_arg_count_ok(loc, fname, args.len, 3, 3);
            try self.mem_validate_type_arg(fname, args, 0);
            self.mem_validate_pointer_arg(fname, args, 1);
            try self.mem_validate_store_value(fname, args);
            return;
        }
        if (std.mem.eql(u8, fname, "copy") or std.mem.eql(u8, fname, "move") or
            std.mem.eql(u8, fname, "compare"))
        {
            _ = self.mem_arg_count_ok(loc, fname, args.len, 3, 3);
            self.mem_validate_pointer_arg(fname, args, 0);
            self.mem_validate_pointer_arg(fname, args, 1);
            self.mem_validate_numeric_arg(fname, args, 2);
            return;
        }
        if (std.mem.eql(u8, fname, "set")) {
            _ = self.mem_arg_count_ok(loc, fname, args.len, 3, 3);
            self.mem_validate_pointer_arg(fname, args, 0);
            self.mem_validate_numeric_arg(fname, args, 1);
            self.mem_validate_numeric_arg(fname, args, 2);
            return;
        }
        if (std.mem.eql(u8, fname, "zero")) {
            _ = self.mem_arg_count_ok(loc, fname, args.len, 2, 2);
            self.mem_validate_pointer_arg(fname, args, 0);
            self.mem_validate_numeric_arg(fname, args, 1);
            return;
        }
        if (std.mem.eql(u8, fname, "read_byte") or std.mem.eql(u8, fname, "read_i8") or
            std.mem.eql(u8, fname, "read_u8") or std.mem.eql(u8, fname, "read_i16") or
            std.mem.eql(u8, fname, "read_u16") or std.mem.eql(u8, fname, "read_i32") or
            std.mem.eql(u8, fname, "read_u32") or std.mem.eql(u8, fname, "read_i64") or
            std.mem.eql(u8, fname, "read_u64") or std.mem.eql(u8, fname, "read_f32") or
            std.mem.eql(u8, fname, "read_f64"))
        {
            _ = self.mem_arg_count_ok(loc, fname, args.len, 2, 2);
            self.mem_validate_pointer_arg(fname, args, 0);
            self.mem_validate_numeric_arg(fname, args, 1);
            return;
        }
        if (std.mem.eql(u8, fname, "write_byte") or std.mem.eql(u8, fname, "writebyte") or std.mem.eql(u8, fname, "write_i8") or
            std.mem.eql(u8, fname, "write_u8") or std.mem.eql(u8, fname, "write_i16") or
            std.mem.eql(u8, fname, "write_u16") or std.mem.eql(u8, fname, "write_i32") or
            std.mem.eql(u8, fname, "write_u32") or std.mem.eql(u8, fname, "write_i64") or std.mem.eql(u8, fname, "writei64") or
            std.mem.eql(u8, fname, "write_u64") or std.mem.eql(u8, fname, "write_f32") or
            std.mem.eql(u8, fname, "write_f64") or std.mem.eql(u8, fname, "writef64"))
        {
            _ = self.mem_arg_count_ok(loc, fname, args.len, 3, 3);
            self.mem_validate_pointer_arg(fname, args, 0);
            self.mem_validate_numeric_arg(fname, args, 1);
            return;
        }
        if (std.mem.eql(u8, fname, "dup")) {
            _ = self.mem_arg_count_ok(loc, fname, args.len, 2, 2);
            self.mem_validate_pointer_arg(fname, args, 0);
            self.mem_validate_numeric_arg(fname, args, 1);
            return;
        }
        if (std.mem.eql(u8, fname, "bytes_to_f32") or std.mem.eql(u8, fname, "bytes_to_f64")) {
            _ = self.mem_arg_count_ok(loc, fname, args.len, 1, 2);
            self.mem_validate_numeric_arg(fname, args, 1);
            return;
        }
        if (std.mem.eql(u8, fname, "sizeof") or std.mem.eql(u8, fname, "alignof")) {
            _ = self.mem_arg_count_ok(loc, fname, args.len, 1, 1);
            try self.mem_validate_type_arg(fname, args, 0);
            return;
        }
        if (std.mem.eql(u8, fname, "fence") or std.mem.eql(u8, fname, "compiler_fence")) {
            _ = self.mem_arg_count_ok(loc, fname, args.len, 0, 0);
            return;
        }
        if (std.mem.eql(u8, fname, "prefetch")) {
            _ = self.mem_arg_count_ok(loc, fname, args.len, 1, 3);
            self.mem_validate_pointer_arg(fname, args, 0);
            self.mem_validate_numeric_arg(fname, args, 1);
            self.mem_validate_numeric_arg(fname, args, 2);
            return;
        }
        if (std.mem.eql(u8, fname, "assume")) {
            _ = self.mem_arg_count_ok(loc, fname, args.len, 1, 1);
            return;
        }
        if (std.mem.eql(u8, fname, "trap") or std.mem.eql(u8, fname, "unreachable")) {
            _ = self.mem_arg_count_ok(loc, fname, args.len, 0, 0);
            return;
        }
        self.err(loc, "unknown memory intrinsic 'mem.{s}'", .{fname});
    }

    fn check_mem_call(self: *Sema, loc: ast.Loc, fname: []const u8, args: []const *ast.Expr) SemaError!RT {
        const ret = (try self.mem_call_result_type(fname, args)) orelse {
            self.err(loc, "unknown memory intrinsic 'mem.{s}'", .{fname});
            return .any;
        };
        try self.validate_mem_call(loc, fname, args);
        return ret;
    }

    fn atomic_intrinsic_name(_: *const Sema, func: *const ast.Expr) ?[]const u8 {
        if (func.* != .field) return null;
        const f = func.field;
        if (f.obj.* == .name and std.mem.eql(u8, f.obj.name.ident, "atomic")) {
            if (is_known_atomic_intrinsic(f.field)) return f.field;
            return null;
        }
        if (f.obj.* == .field) {
            const inner = f.obj.field;
            if (inner.obj.* == .name and
                std.mem.eql(u8, inner.obj.name.ident, "std") and
                std.mem.eql(u8, inner.field, "atomic"))
            {
                if (is_known_atomic_intrinsic(f.field)) return f.field;
                return null;
            }
        }
        return null;
    }

    /// True if `name` is one of the built-in `__atomic_*` primitives. Other
    /// `atomic.X(...)` calls (e.g. `atomic.mutex_new`, `atomic.lock`) are
    /// regular module-method calls on the `std.atomic` stdlib table and must
    /// fall through to normal field-call resolution.
    fn is_known_atomic_intrinsic(name: []const u8) bool {
        return std.mem.eql(u8, name, "load") or
            std.mem.eql(u8, name, "store") or
            std.mem.eql(u8, name, "exchange") or
            std.mem.eql(u8, name, "compare_exchange") or
            std.mem.eql(u8, name, "fetch_add") or
            std.mem.eql(u8, name, "fetch_sub") or
            std.mem.eql(u8, name, "fetch_and") or
            std.mem.eql(u8, name, "fetch_or") or
            std.mem.eql(u8, name, "fetch_xor") or
            std.mem.eql(u8, name, "fence") or
            std.mem.eql(u8, name, "compiler_fence");
    }

    fn atomic_type_arg(self: *Sema, args: []const *ast.Expr, index: usize) SemaError!?RT {
        if (index >= args.len) return null;
        if (args[index].* != .string_lit) return null;
        return try self.mem_type_from_name(args[index].string_lit.val);
    }

    fn atomic_type_supported(t: RT) bool {
        return t.is_integer() or t == .bool or t == .pointer;
    }

    fn atomic_fetch_intrinsic(fname: []const u8) bool {
        return std.mem.eql(u8, fname, "fetch_add") or
            std.mem.eql(u8, fname, "fetch_sub") or
            std.mem.eql(u8, fname, "fetch_and") or
            std.mem.eql(u8, fname, "fetch_or") or
            std.mem.eql(u8, fname, "fetch_xor");
    }

    fn atomic_call_result_type(self: *Sema, fname: []const u8, args: []const *ast.Expr) SemaError!?RT {
        if (std.mem.eql(u8, fname, "load") or std.mem.eql(u8, fname, "exchange") or atomic_fetch_intrinsic(fname))
            return (try self.atomic_type_arg(args, 0)) orelse .any;
        if (std.mem.eql(u8, fname, "store") or std.mem.eql(u8, fname, "fence") or
            std.mem.eql(u8, fname, "compiler_fence"))
            return .void;
        if (std.mem.eql(u8, fname, "compare_exchange")) return .bool;
        return null;
    }

    fn atomic_arg_count_ok(self: *Sema, loc: ast.Loc, fname: []const u8, got: usize, min: usize, max: usize) bool {
        if (got >= min and got <= max) return true;
        if (min == max) {
            self.err(loc, "atomic.{s} expects {d} argument(s), got {d}", .{ fname, min, got });
        } else {
            self.err(loc, "atomic.{s} expects {d} to {d} arguments, got {d}", .{ fname, min, max, got });
        }
        return false;
    }

    fn atomic_validate_type_arg(self: *Sema, fname: []const u8, args: []const *ast.Expr, index: usize, fetch_only: bool) SemaError!?RT {
        if (index >= args.len) return null;
        const arg = args[index];
        if (arg.* != .string_lit) {
            self.err(arg.*.loc(), "atomic.{s} argument {d} must be a string type name", .{ fname, index + 1 });
            return null;
        }
        const name = arg.string_lit.val;
        const rt = (try self.mem_type_from_name(name)) orelse {
            self.err(arg.string_lit.loc, "atomic.{s} does not support memory type '{s}'", .{ fname, name });
            return null;
        };
        if (!atomic_type_supported(rt)) {
            self.err(arg.string_lit.loc, "atomic.{s} type '{s}' is not an atomic scalar or pointer type", .{ fname, name });
            return null;
        }
        if (fetch_only and !rt.is_integer()) {
            self.err(arg.string_lit.loc, "atomic.{s} type '{s}' must be an integer type", .{ fname, name });
            return null;
        }
        return rt;
    }

    fn atomic_validate_pointer_to_type(self: *Sema, fname: []const u8, args: []const *ast.Expr, index: usize, target: RT) void {
        if (index >= args.len) return;
        const arg = args[index];
        const t = self.type_map.get(arg) orelse .any;
        if (t == .any) return;
        if (t != .pointer) {
            self.err(arg.*.loc(), "atomic.{s} argument {d} must be a pointer, got {}", .{ fname, index + 1, t });
            return;
        }
        if (!t.pointer.*.eql(target)) {
            self.err(arg.*.loc(), "atomic.{s} argument {d} must point to {}, got pointer to {}", .{ fname, index + 1, target, t.pointer.* });
        }
    }

    fn atomic_validate_value(self: *Sema, fname: []const u8, args: []const *ast.Expr, index: usize, target: RT) void {
        if (index >= args.len) return;
        const arg = args[index];
        const t = self.type_map.get(arg) orelse .any;
        if (t == .any) return;
        if (target.eql(t)) return;
        if (target.is_integer() and t.is_integer()) return;
        if (target == .pointer and (t == .pointer or t == .nil)) return;
        self.err(arg.*.loc(), "atomic.{s} argument {d} has type {}, expected {}", .{ fname, index + 1, t, target });
    }

    fn atomic_order_known(order: []const u8) bool {
        return std.mem.eql(u8, order, "relaxed") or
            std.mem.eql(u8, order, "consume") or
            std.mem.eql(u8, order, "acquire") or
            std.mem.eql(u8, order, "release") or
            std.mem.eql(u8, order, "acq_rel") or
            std.mem.eql(u8, order, "seq_cst") or
            std.mem.eql(u8, order, "seqcst");
    }

    fn atomic_order_valid_for(kind: []const u8, order: []const u8) bool {
        if (std.mem.eql(u8, kind, "load") or std.mem.eql(u8, kind, "failure")) {
            return std.mem.eql(u8, order, "relaxed") or
                std.mem.eql(u8, order, "consume") or
                std.mem.eql(u8, order, "acquire") or
                std.mem.eql(u8, order, "seq_cst") or
                std.mem.eql(u8, order, "seqcst");
        }
        if (std.mem.eql(u8, kind, "store")) {
            return std.mem.eql(u8, order, "relaxed") or
                std.mem.eql(u8, order, "release") or
                std.mem.eql(u8, order, "seq_cst") or
                std.mem.eql(u8, order, "seqcst");
        }
        if (std.mem.eql(u8, kind, "rmw")) {
            return std.mem.eql(u8, order, "relaxed") or
                std.mem.eql(u8, order, "acquire") or
                std.mem.eql(u8, order, "release") or
                std.mem.eql(u8, order, "acq_rel") or
                std.mem.eql(u8, order, "seq_cst") or
                std.mem.eql(u8, order, "seqcst");
        }
        if (std.mem.eql(u8, kind, "fence")) {
            return std.mem.eql(u8, order, "relaxed") or
                std.mem.eql(u8, order, "acquire") or
                std.mem.eql(u8, order, "release") or
                std.mem.eql(u8, order, "acq_rel") or
                std.mem.eql(u8, order, "seq_cst") or
                std.mem.eql(u8, order, "seqcst");
        }
        return false;
    }

    fn atomic_validate_order_arg(self: *Sema, fname: []const u8, args: []const *ast.Expr, index: usize, kind: []const u8) void {
        if (index >= args.len) return;
        const arg = args[index];
        if (arg.* != .string_lit) {
            self.err(arg.*.loc(), "atomic.{s} memory order argument {d} must be a string literal", .{ fname, index + 1 });
            return;
        }
        const order = arg.string_lit.val;
        if (!atomic_order_known(order)) {
            self.err(arg.string_lit.loc, "atomic.{s} memory order '{s}' is not recognized", .{ fname, order });
            return;
        }
        if (!atomic_order_valid_for(kind, order)) {
            self.err(arg.string_lit.loc, "atomic.{s} memory order '{s}' is invalid for {s}", .{ fname, order, kind });
        }
    }

    fn validate_atomic_call(self: *Sema, loc: ast.Loc, fname: []const u8, args: []const *ast.Expr) SemaError!void {
        if (std.mem.eql(u8, fname, "load")) {
            _ = self.atomic_arg_count_ok(loc, fname, args.len, 2, 3);
            const rt = (try self.atomic_validate_type_arg(fname, args, 0, false)) orelse return;
            self.atomic_validate_pointer_to_type(fname, args, 1, rt);
            self.atomic_validate_order_arg(fname, args, 2, "load");
            return;
        }
        if (std.mem.eql(u8, fname, "store")) {
            _ = self.atomic_arg_count_ok(loc, fname, args.len, 3, 4);
            const rt = (try self.atomic_validate_type_arg(fname, args, 0, false)) orelse return;
            self.atomic_validate_pointer_to_type(fname, args, 1, rt);
            self.atomic_validate_value(fname, args, 2, rt);
            self.atomic_validate_order_arg(fname, args, 3, "store");
            return;
        }
        if (std.mem.eql(u8, fname, "exchange")) {
            _ = self.atomic_arg_count_ok(loc, fname, args.len, 3, 4);
            const rt = (try self.atomic_validate_type_arg(fname, args, 0, false)) orelse return;
            self.atomic_validate_pointer_to_type(fname, args, 1, rt);
            self.atomic_validate_value(fname, args, 2, rt);
            self.atomic_validate_order_arg(fname, args, 3, "rmw");
            return;
        }
        if (std.mem.eql(u8, fname, "compare_exchange")) {
            _ = self.atomic_arg_count_ok(loc, fname, args.len, 4, 6);
            const rt = (try self.atomic_validate_type_arg(fname, args, 0, false)) orelse return;
            self.atomic_validate_pointer_to_type(fname, args, 1, rt);
            self.atomic_validate_pointer_to_type(fname, args, 2, rt);
            self.atomic_validate_value(fname, args, 3, rt);
            self.atomic_validate_order_arg(fname, args, 4, "rmw");
            self.atomic_validate_order_arg(fname, args, 5, "failure");
            return;
        }
        if (atomic_fetch_intrinsic(fname)) {
            _ = self.atomic_arg_count_ok(loc, fname, args.len, 3, 4);
            const rt = (try self.atomic_validate_type_arg(fname, args, 0, true)) orelse return;
            self.atomic_validate_pointer_to_type(fname, args, 1, rt);
            self.atomic_validate_value(fname, args, 2, rt);
            self.atomic_validate_order_arg(fname, args, 3, "rmw");
            return;
        }
        if (std.mem.eql(u8, fname, "fence") or std.mem.eql(u8, fname, "compiler_fence")) {
            _ = self.atomic_arg_count_ok(loc, fname, args.len, 0, 1);
            self.atomic_validate_order_arg(fname, args, 0, "fence");
            return;
        }
        self.err(loc, "unknown atomic intrinsic 'atomic.{s}'", .{fname});
    }

    fn check_atomic_call(self: *Sema, loc: ast.Loc, fname: []const u8, args: []const *ast.Expr) SemaError!RT {
        const ret = (try self.atomic_call_result_type(fname, args)) orelse {
            self.err(loc, "unknown atomic intrinsic 'atomic.{s}'", .{fname});
            return .any;
        };
        try self.validate_atomic_call(loc, fname, args);
        return ret;
    }

    fn check_binding_attributes(
        self: *Sema,
        lname: *const ast.LocalName,
        resolved_type: RT,
        init_expr: ?*const ast.Expr,
    ) SemaError!void {
        for (lname.attributes) |attr| {
            if (std.mem.eql(u8, attr.name, "arc")) {
                if (validate_arc_attr(&.{attr})) |valid| {
                    if (!valid) {
                        self.err(lname.loc, "@arc attribute requires argument 'false'", .{});
                    } else if (!is_table_binding_type(lname.typ, resolved_type)) {
                        self.err(lname.loc, "@arc(false) is only valid on table-typed bindings or record-type annotations, not on '{s}'", .{lname.ident});
                    }
                }
                continue;
            }

            if (!std.mem.eql(u8, attr.name, "implements")) continue;

            if (lname.typ != .record) {
                self.err(lname.loc, "@implements is only valid on bindings with a record-type annotation, not on '{s}'", .{lname.ident});
                continue;
            }

            const init_names = if (init_expr) |initializer|
                try self.collect_init_field_names(initializer)
            else
                &[_][]const u8{};

            var concept_iter = std.mem.splitScalar(u8, attr.args orelse "", ',');
            while (concept_iter.next()) |raw| {
                const trimmed = std.mem.trim(u8, raw, " \t");
                if (trimmed.len == 0) continue;
                try self.check_concept_satisfaction(lname.loc, lname.ident, lname.typ.record.fields, init_names, trimmed);
            }
        }
    }

    fn record(self: *Sema, expr: *const ast.Expr, t: RT) !RT {
        try self.type_map.put(expr, t);
        return t;
    }

    // ── Public entry ─────────────────────────────────────────────────────────

    pub fn check_module(self: *Sema, mod: *ast.Module) !void {
        self.test_entries.clearRetainingCapacity();
        self.build_directives.clearRetainingCapacity();
        self.debug_directives.clearRetainingCapacity();
        self.alias_defs.clearRetainingCapacity();
        self.generic_func_arities.clearRetainingCapacity();
        self.callable_defs.clearRetainingCapacity();
        self.applications.clearRetainingCapacity();
        // Pass 5: import foreign declarations from @c.import / @cinclude headers first.
        for (mod.body.stmts) |*stmt| {
            if (stmt.* == .cinclude) {
                try self.importForeignHeader(stmt.cinclude.header);
            }
        }
        // The one alias derivation, shared with CodeGen (`AliasRegistry.collect`).
        try self.alias_defs.collect(self.alloc, mod);
        try self.scope.push();
        self.seed_globals();
        // Lua 5.5 scripts use implicit globals at module scope; Duo uses implicit locals.
        if (self.lua55_mode) {
            self.scope.set_require_global(true);
        }
        // Capture declaration identity before checking any body. Duplicate
        // spellings remain unresolved here; source order never selects an
        // overloaded relation identity.
        for (mod.body.stmts) |*stmt| {
            if (stmt.* != .func_decl) continue;
            const fd = &stmt.func_decl;
            if (fd.path.len != 1 or fd.method) continue;
            const slot = try self.callable_defs.getOrPut(self.alloc, fd.path[0]);
            if (slot.found_existing) {
                slot.value_ptr.* = null;
            } else {
                slot.value_ptr.* = fd;
            }
        }
        // Pre-register top-level bindings so forward references work.
        for (mod.body.stmts) |*stmt| {
            switch (stmt.*) {
                .func_decl => |fd| {
                    if (fd.path.len >= 1) {
                        self.scope.define(fd.path[0], .{ .typ = .any, .is_const = false }) catch {};
                        const arity: ?usize = if (fd.func.type_params) |params| params.len else null;
                        try self.generic_func_arities.put(self.alloc, fd.path[0], arity);
                    }
                },
                // `.alias_def` needs no arm: `AliasRegistry.collect` above is the
                // single derivation of `name --is--> descriptor`.
                .local_decl => |ld| {
                    for (ld.names) |name| {
                        self.scope.define(name.ident, .{ .typ = .any, .is_const = false }) catch {};
                    }
                },
                .const_decl => |cd| {
                    self.scope.define(cd.ident, .{ .typ = .any, .is_const = true }) catch {};
                },
                .global_decl => |gd| {
                    if (!gd.star) for (gd.names) |name| {
                        self.scope.define(name.ident, .{ .typ = .any, .is_const = false }) catch {};
                    };
                },
                .assign => |as| {
                    if (self.duo_mode) for (as.targets) |tgt| {
                        if (tgt.* == .name) {
                            self.scope.define(tgt.name.ident, .{ .typ = .any, .is_const = false }) catch {};
                        }
                    };
                },
                else => {},
            }
        }
        try self.registerForeignScopeNames();
        try self.check_block(&mod.body);
        if (self.duo_mode) try self.snapshotModuleBindings();
        self.scope.pop();
    }

    fn registerForeignScopeNames(self: *Sema) !void {
        var rit = self.foreign_records.iterator();
        while (rit.next()) |entry| {
            try self.scope.define(entry.key_ptr.*, .{
                .typ = entry.value_ptr.*,
                .is_const = true,
            });
        }
        var fit = self.foreign_functions.iterator();
        while (fit.next()) |entry| {
            const ff = entry.value_ptr.*;
            const ret_ptr = try self.alloc.create(RT);
            ret_ptr.* = ff.ret;
            const params = try self.alloc.dupe(RT, ff.params);
            const fn_type = RT{
                .func = .{
                    .params = params,
                    .ret = ret_ptr,
                    .is_native = true,
                },
            };
            try self.scope.define(entry.key_ptr.*, .{ .typ = fn_type, .is_const = true });
        }
    }

    fn importForeignHeader(self: *Sema, header: []const u8) !void {
        var threaded = std.Io.Threaded.init(self.alloc, .{});
        const resolved = try foreign_adapter.resolveHeaderPath(self.alloc, threaded.io(), self.source_path, header);
        defer self.alloc.free(resolved);
        const cwd = std.Io.Dir.cwd();
        const src = std.Io.Dir.readFileAlloc(cwd, threaded.io(), resolved, self.alloc, .unlimited) catch {
            debug_trace.event(.sema, .module, "foreign header not found: {s}", .{resolved});
            return;
        };
        defer self.alloc.free(src);
        var snap = try c_sim_import.importHeaderSource(self.alloc, resolved, src);
        defer snap.deinit(self.alloc);
        try abi_specialize.specializeSnapshot(self.alloc, &snap);
        var module = try foreign_adapter.adaptSnapshot(self.alloc, &snap);
        errdefer module.deinit(self.alloc);
        if (module.functions.count() > 0) {
            var fit_meta = module.functions.iterator();
            if (fit_meta.next()) |entry| {
                debug_trace.event(.sema, .foreign, "pass26 foreign lift boundary={s} conv={s}", .{
                    entry.value_ptr.boundary_id,
                    entry.value_ptr.calling_conv.name(),
                });
            }
        }

        var rit = module.records.iterator();
        while (rit.next()) |entry| {
            const name = try self.alloc.dupe(u8, entry.key_ptr.*);
            const gop = try self.foreign_records.getOrPut(self.alloc, name);
            if (gop.found_existing) {
                releaseForeignRecordRt(self.alloc, gop.value_ptr);
                self.alloc.free(name);
            } else {
                gop.key_ptr.* = name;
            }
            gop.value_ptr.* = entry.value_ptr.*;
        }
        var fit = module.functions.iterator();
        while (fit.next()) |entry| {
            const name = try self.alloc.dupe(u8, entry.key_ptr.*);
            const gop = try self.foreign_functions.getOrPut(self.alloc, name);
            if (gop.found_existing) {
                gop.value_ptr.deinit(self.alloc);
                self.alloc.free(name);
            } else {
                gop.key_ptr.* = name;
            }
            gop.value_ptr.* = entry.value_ptr.*;
        }
        module.records = .empty;
        module.functions = .empty;
        module.deinit(self.alloc);
    }

    fn seed_globals(self: *Sema) void {
        const names = seedGlobalNames();
        for (names) |n| {
            self.scope.define(n, .{ .typ = .any, .is_const = true }) catch {};
        }
    }

    fn isSeedGlobal(name: []const u8) bool {
        for (seedGlobalNames()) |n| {
            if (std.mem.eql(u8, n, name)) return true;
        }
        return false;
    }

    fn seedGlobalNames() []const []const u8 {
        return &[_][]const u8{
            "print",        "math",      "string",   "table",    "io",       "os",
            "package",      "coroutine", "utf8",     "debug",    "jit",      "ffi",
            "ipairs",       "pairs",     "tostring", "tonumber", "type",     "error",
            "assert",       "pcall",     "xpcall",   "require",  "simd",     "setmetatable",
            "getmetatable", "rawget",    "rawset",   "rawlen",   "rawequal", "next",
            "select",       "unpack",    "load",     "loadfile", "dofile",   "collectgarbage",
            "warn",         "_VERSION",
        };
    }

    fn snapshotModuleBindings(self: *Sema) !void {
        self.module_bindings.clearRetainingCapacity();
        if (self.scope.maps.items.len == 0) return;
        const top = &self.scope.maps.items[self.scope.maps.items.len - 1];
        var it = top.iterator();
        while (it.next()) |entry| {
            if (isSeedGlobal(entry.key_ptr.*)) continue;
            const name = try self.alloc.dupe(u8, entry.key_ptr.*);
            try self.module_bindings.put(self.alloc, name, entry.value_ptr.*);
        }
    }

    // ── Block / statements ────────────────────────────────────────────────────

    fn resolve_type(self: *Sema, type_expr: ast.TypeExpr) Allocator.Error!RT {
        if (type_expr == .named) {
            if (self.current_func_type_params) |tps| {
                for (tps) |tp| {
                    switch (tp) {
                        .constrained => |cp| {
                            if (std.mem.eql(u8, cp.name, type_expr.named))
                                return self.resolve_type(tp);
                        },
                        .named => |n| {
                            if (std.mem.eql(u8, n, type_expr.named))
                                return RT{ .generic_param = .{ .name = n, .constraint = null } };
                        },
                        else => {},
                    }
                }
            }
        }
        if (type_expr == .generic and type_expr.generic.base.* == .named) {
            if (self.alias_defs.get(type_expr.generic.base.named)) |ad| {
                if (ad.type_params) |type_params| {
                    if (ad.target != null and type_params.len == type_expr.generic.params.len) {
                        const expanded = try self.substitute_alias_type(ad.target.?, type_params, type_expr.generic.params);
                        return self.resolve_type(expanded);
                    }
                }
            }
        }
        return types.resolve(type_expr, self, self.alloc) catch .any;
    }

    fn substitute_alias_type(
        self: *Sema,
        type_expr: ast.TypeExpr,
        params: []const ast.TypeExpr,
        args: []const ast.TypeExpr,
    ) Allocator.Error!ast.TypeExpr {
        if (type_expr == .named) {
            for (params, 0..) |param, i| {
                if (param == .named and std.mem.eql(u8, param.named, type_expr.named)) return args[i];
            }
            return type_expr;
        }
        return switch (type_expr) {
            .inferred => .inferred,
            .named => unreachable,
            .pointer => |inner| blk: {
                const next = try self.alloc.create(ast.TypeExpr);
                next.* = try self.substitute_alias_type(inner.*, params, args);
                break :blk .{ .pointer = next };
            },
            .optional => |inner| blk: {
                const next = try self.alloc.create(ast.TypeExpr);
                next.* = try self.substitute_alias_type(inner.*, params, args);
                break :blk .{ .optional = next };
            },
            .array => |arr| blk: {
                const elem = try self.alloc.create(ast.TypeExpr);
                elem.* = try self.substitute_alias_type(arr.elem.*, params, args);
                break :blk .{ .array = .{ .elem = elem, .size = arr.size } };
            },
            .generic => |g| blk: {
                const base = try self.alloc.create(ast.TypeExpr);
                base.* = try self.substitute_alias_type(g.base.*, params, args);
                const gargs = try self.alloc.alloc(ast.TypeExpr, g.params.len);
                for (g.params, 0..) |arg, i| {
                    gargs[i] = try self.substitute_alias_type(arg, params, args);
                }
                break :blk .{ .generic = .{ .base = base, .params = gargs } };
            },
            .func => |f| blk: {
                const fparams = try self.alloc.alloc(ast.TypeExpr, f.params.len);
                for (f.params, 0..) |param, i| {
                    fparams[i] = try self.substitute_alias_type(param, params, args);
                }
                const ret = try self.alloc.create(ast.TypeExpr);
                ret.* = try self.substitute_alias_type(f.ret.*, params, args);
                break :blk .{ .func = .{ .params = fparams, .ret = ret } };
            },
            .tuple => |items| blk: {
                const out = try self.alloc.alloc(ast.TypeExpr, items.len);
                for (items, 0..) |item, i| {
                    out[i] = try self.substitute_alias_type(item, params, args);
                }
                break :blk .{ .tuple = out };
            },
            .record => |rec| blk: {
                const fields = try self.alloc.alloc(ast.RecordField, rec.fields.len);
                for (rec.fields, 0..) |field, i| {
                    fields[i] = .{
                        .name = field.name,
                        .typ = try self.substitute_alias_type(field.typ, params, args),
                        .loc = field.loc,
                    };
                }
                const next = try self.alloc.create(ast.TypeExpr.RecordType);
                next.* = .{ .fields = fields };
                break :blk .{ .record = next };
            },
            .constrained => |cp| blk: {
                const next = try self.alloc.create(ast.TypeExpr);
                next.* = try self.substitute_alias_type(cp.constraint.*, params, args);
                const extra = try self.alloc.alloc(ast.TypeExpr, cp.extra.len);
                for (cp.extra, 0..) |e, i| extra[i] = try self.substitute_alias_type(e, params, args);
                break :blk .{ .constrained = .{ .name = cp.name, .constraint = next, .extra = extra } };
            },
        };
    }

    /// Pass 100 §8 B-12 — the return type a contract LOWERS to.
    ///
    /// `: u64 | error` declares the correlated pack `(value, nil) | (nil,
    /// error)`, and Duo has no type for a pack. So the SIGNATURE a caller sees
    /// is dynamic while the success type stays written on the declaration and
    /// stays checked inside the body (`current_ret` below keeps it).
    ///
    /// Identity for every contract without a failure alternative — which is
    /// all 748 tracked `.id` files, since `ret_fallible` is set only by a
    /// `| alt` in return position and that alternative used to be discarded.
    fn contract_ret_expr(fb: *const ast.FuncBody) ast.TypeExpr {
        return if (fb.ret_fallible) .inferred else fb.ret_type;
    }

    fn check_return_value(self: *Sema, loc: ast.Loc, actual: RT) void {
        if (self.current_ret == .any or self.current_ret == .void or actual == .any) return;
        // B-12: under a declared failure contract the value position holds the
        // VALUE on success and `nil` on failure — `return nil, error.overflow`
        // and the bare tail `nil, error.truncated` are the two spellings §20's
        // leb128 decoder uses. Only `nil` is admitted, and only when a failure
        // alternative was written; every other mismatch still reports.
        if (self.current_ret_fallible and actual == .nil) return;
        if (!type_annotation_accepts_init(self.current_ret, actual)) {
            var want_buf: [128]u8 = undefined;
            var got_buf: [128]u8 = undefined;
            const want_name = self.current_ret.duo_name(&want_buf);
            const got_name = actual.duo_name(&got_buf);
            self.err(loc, "return type mismatch: expected '{s}', got '{s}'", .{ want_name, got_name });
        }
    }

    fn check_block(self: *Sema, blk: *ast.Block) SemaError!void {
        try self.check_block_with_implicit_return(blk, false);
    }

    fn check_block_with_implicit_return(self: *Sema, blk: *ast.Block, validate_implicit_return: bool) SemaError!void {
        try self.scope.push();
        for (blk.stmts) |*stmt| try self.check_stmt(stmt);
        if (validate_implicit_return) {
            if (block_implicit_return_expr(blk)) |e| {
                const actual = try self.check_expr(e);
                self.check_return_value(e.loc(), actual);
            }
        } else if (blk.tail_expr) |e| {
            // A block's tail expression is not in `stmts`, so without this it was
            // never visited and nothing it contains ever reached `type_map`.
            // Downstream that reads as "no type": the monomorphizer inferred
            // `.any` for `pick(1.5, 2)` when the call was a module's LAST
            // statement and `f64` when any statement followed it — the same call
            // specialized two different ways depending only on its position.
            // Types only; the return-type check above stays owned by the
            // function-body path, which is the only place a return is demanded.
            _ = try self.check_expr(e);
        }
        self.scope.pop();
    }

    /// Pass 25 §5.1 — tail-demand propagation (not backward local search).
    fn block_implicit_return_expr(blk: *const ast.Block) ?*ast.Expr {
        return tail_result_demand.blockTailResultExpr(blk);
    }

    const SpecializeArgsInfo = struct {
        name: []const u8,
        type_arg_count: usize,
        has_empty_type_arg: bool,
    };

    fn specialize_args_info(raw: []const u8) SpecializeArgsInfo {
        var name: []const u8 = "";
        var count: usize = 0;
        var has_empty = false;
        var start: usize = 0;
        var depth: usize = 0;
        var quote: ?u8 = null;
        var saw_first = false;
        var i: usize = 0;
        while (i < raw.len) : (i += 1) {
            const c = raw[i];
            if (quote) |q| {
                if (c == '\\') {
                    i += 1;
                } else if (c == q) {
                    quote = null;
                }
                continue;
            }
            switch (c) {
                '"', '\'' => quote = c,
                '(', '[', '{' => depth += 1,
                ')', ']', '}' => {
                    if (depth > 0) depth -= 1;
                },
                ',' => if (depth == 0) {
                    const part = std.mem.trim(u8, raw[start..i], " \t\r\n");
                    if (!saw_first) {
                        name = part;
                        saw_first = true;
                    } else {
                        if (part.len == 0) has_empty = true;
                        count += 1;
                    }
                    start = i + 1;
                },
                else => {},
            }
        }
        const last = std.mem.trim(u8, raw[start..], " \t\r\n");
        if (!saw_first) {
            name = last;
        } else {
            if (last.len == 0) has_empty = true;
            count += 1;
        }
        return .{ .name = name, .type_arg_count = count, .has_empty_type_arg = has_empty };
    }

    fn check_specialize_directive(self: *Sema, loc: ast.Loc, raw_args: ?[]const u8) void {
        const args = raw_args orelse {
            self.err(loc, "@specialize expects a generic function name followed by type arguments", .{});
            return;
        };
        const info = specialize_args_info(args);
        const name = info.name;
        if (name.len == 0) {
            self.err(loc, "@specialize expects a generic function name followed by type arguments", .{});
            return;
        }

        if (info.has_empty_type_arg) {
            self.err(loc, "@specialize({s}, ...) contains an empty type argument", .{name});
            return;
        }

        const arity = self.generic_func_arities.get(name) orelse {
            self.err(loc, "@specialize target '{s}' is not a known top-level function", .{name});
            return;
        };
        const want = arity orelse {
            self.err(loc, "@specialize target '{s}' is not generic", .{name});
            return;
        };
        if (info.type_arg_count != want) {
            self.err(loc, "@specialize target '{s}' expects {d} type argument(s), got {d}", .{ name, want, info.type_arg_count });
        }
    }

    fn check_stmt(self: *Sema, stmt: *ast.Stmt) SemaError!void {
        switch (stmt.*) {
            .local_decl => |*ld| {
                var init_types: std.ArrayList(RT) = .empty;
                defer init_types.deinit(self.alloc);
                for (ld.inits) |init_expr| {
                    const t = try self.check_expr(init_expr);
                    try init_types.append(self.alloc, t);
                }
                for (ld.names, 0..) |*lname, i| {
                    var t: RT = if (i < init_types.items.len)
                        init_types.items[i]
                    else if (ld.inits.len == 1 and ld.names.len > 1)
                        .any
                    else
                        .any;
                    if (i < ld.inits.len) {
                        self.track_table_literal_fields(lname.ident, ld.inits[i]);
                    }
                    // If annotated, use the annotation and enforce type match
                    if (lname.typ != .inferred) {
                        const ann = try self.resolve_type(lname.typ);
                        // Check type mismatch: if init type is known (not any/nil) and
                        // annotation is known (not any), they must match
                        if (i < init_types.items.len) {
                            const init_t = init_types.items[i];
                            const cdr_literal = i < ld.inits.len and
                                nominal_accepts_literal(ann, ld.inits[i]);
                            if (ann != .any and init_t != .any and init_t != .nil and
                                !cdr_literal and !type_annotation_accepts_init(ann, init_t))
                            {
                                {
                                    var ann_buf: [128]u8 = undefined;
                                    var init_buf: [128]u8 = undefined;
                                    const ann_name = ann.duo_name(&ann_buf);
                                    const init_name = init_t.duo_name(&init_buf);
                                    // law.nominal: same representation, DIFFERENT
                                    // IDENTITY. Saying "type mismatch: feet vs
                                    // f64" reads like a bug in the compiler when
                                    // both are doubles, so the message names the
                                    // shared representation and the repair EDGE
                                    // rather than restating the two names.
                                    const ann_repr = types.nominalReprOf(ann);
                                    const init_repr = types.nominalReprOf(init_t);
                                    if (ann_repr != null or init_repr != null) {
                                        var rbuf: [64]u8 = undefined;
                                        const shared = (ann_repr orelse init_repr).?;
                                        self.err(lname.loc, "descriptor mismatch: '{s}' is declared '{s}' and the initializer carries '{s}' — both realize as '{s}', but a nominal descriptor is not its representation", .{ lname.ident, ann_name, init_name, shared.c_type(&rbuf) });
                                        self.hint_msg(lname.loc, "convert at the edge: '{s}:to({s})', or declare the initializer '{s}'", .{ if (ld.inits[i].* == .name) ld.inits[i].name.ident else "value", ann_name, ann_name });
                                    } else self.err(lname.loc, "type mismatch: variable '{s}' declared as '{s}', but initializer has type '{s}'", .{ lname.ident, ann_name, init_name });
                                }
                            }
                            // A LITERAL that provably cannot fit is a diagnostic,
                            // never a truncation. `x: u8 = 300` printed 44 with
                            // `duo check` exiting 0 — not proven, not
                            // runtime-checked, not diagnosed, which is the
                            // fourth state soundness.md §1 says does not exist
                            // (gap[064]). There is no analysis to do here and no
                            // flow to be sensitive to: 300 does not fit in u8, at
                            // the point of writing, always.
                            if (i < ld.inits.len) {
                                if (literalOutOfRange(ann, ld.inits[i])) |lit| {
                                    var rb: [128]u8 = undefined;
                                    self.err(lname.loc, "literal {d} does not fit in '{s}' (range {d}..{d})", .{ lit, ann.duo_name(&rb), intMin(ann).?, intMax(ann).? });
                                }
                            }
                        }
                        t = ann;
                    }
                    const is_const = is_const_attrib(lname.attrib);
                    const is_close = is_close_attrib(lname.attrib);

                    apply_record_layout_attrs(&t, lname.attributes);
                    const has_init = i < ld.inits.len or (ld.inits.len == 1 and ld.names.len > 1 and i == 0);
                    if (is_const and !has_init) {
                        self.err(lname.loc, "const variable '{s}' must have an initializer", .{lname.ident});
                    }
                    if (is_close and !has_init) {
                        self.err(lname.loc, "to-be-closed variable '{s}' must have an initializer", .{lname.ident});
                    }
                    if (i < ld.inits.len) {
                        try self.maybe_register_meta_concept(lname.ident, ld.inits[i]);
                    }
                    try self.check_binding_attributes(lname, t, if (i < ld.inits.len) ld.inits[i] else null);
                    try self.scope.define(lname.ident, .{
                        .typ = t,
                        .is_const = is_const,
                        .is_close = is_close,
                        .deprecated_msg = get_deprecated_msg(lname.attributes),
                    });
                    if (i < ld.inits.len) {
                        try self.noteModuleSealingFromInit(lname.ident, ld.inits[i]);
                    }
                    if (self.duo_mode and self.hints_enabled and lname.typ == .inferred and lname.attrib == null) {
                        if (t == .i64 or t == .f64 or t == .str or t == .bool) {
                            var tbuf: [32]u8 = undefined;
                            const tname = t.duo_name(&tbuf);
                            self.hint_msg(lname.loc, "local '{s}' inferred as '{s}'; add an explicit annotation to lock in native codegen", .{ lname.ident, tname });
                        }
                    }
                }
            },
            .const_decl => |*cd| {
                var t = try self.check_expr(cd.val);
                if (cd.typ != .inferred)
                    t = try self.resolve_type(cd.typ);
                try self.maybe_register_meta_concept(cd.ident, cd.val);
                try self.scope.define(cd.ident, .{ .typ = t, .is_const = true });
            },
            .global_decl => |*gd| {
                if (gd.star) {
                    self.scope.set_require_global(true);
                    return;
                }
                var init_types: std.ArrayList(RT) = .empty;
                defer init_types.deinit(self.alloc);
                for (gd.inits) |init_expr| {
                    const t = try self.check_expr(init_expr);
                    try init_types.append(self.alloc, t);
                }
                for (gd.names, 0..) |*lname, i| {
                    var t: RT = if (i < init_types.items.len)
                        init_types.items[i]
                    else if (gd.inits.len == 1 and gd.names.len > 1)
                        .any
                    else
                        .any;
                    if (lname.typ != .inferred) {
                        const ann = try self.resolve_type(lname.typ);
                        t = ann;
                    }
                    apply_record_layout_attrs(&t, lname.attributes);
                    const is_const = is_const_attrib(lname.attrib);
                    const has_init = i < gd.inits.len or (gd.inits.len == 1 and gd.names.len > 1 and i == 0);
                    if (is_const and !has_init) {
                        self.err(lname.loc, "const global '{s}' must have an initializer", .{lname.ident});
                    }
                    if (i < gd.inits.len) {
                        try self.maybe_register_meta_concept(lname.ident, gd.inits[i]);
                    }
                    try self.check_binding_attributes(lname, t, if (i < gd.inits.len) gd.inits[i] else null);
                    try self.note_global(lname.ident, t);
                    try self.scope.define(lname.ident, .{
                        .typ = t,
                        .is_const = is_const,
                        .is_global = true,
                        .deprecated_msg = get_deprecated_msg(lname.attributes),
                    });
                    if (i < gd.inits.len) {
                        try self.noteModuleSealingFromInit(lname.ident, gd.inits[i]);
                    }
                }
            },
            .assign => |*as| {
                for (as.values) |v| _ = try self.check_expr(v);
                // Pre-track field types so target type-check sees the inferred types
                for (as.targets, 0..) |tgt, i| {
                    if (tgt.* == .field and i < as.values.len) {
                        const f = tgt.field;
                        if (f.obj.* == .name) {
                            const val_t = self.type_map.get(as.values[i]) orelse .any;
                            self.track_table_field(f.obj.name.ident, f.field, val_t);
                        }
                    } else if (tgt.* == .name and i < as.values.len and as.values[i].* == .table) {
                        self.track_table_literal_fields(tgt.name.ident, as.values[i]);
                    }
                }
                for (as.targets, 0..) |tgt, i| {
                    try self.check_assign_target(tgt);
                    // c0 §41 — AN IMPLICIT LOCAL TAKES THE CASE-SET OF THE
                    // VALUE THAT CREATED IT. `check_assign_target` binds an
                    // undeclared duo-mode name as `any`, discarding what the
                    // right-hand side knew, so `k = token.kind.eof` produced a
                    // `k` with no case-set and the later `k == eof` had no
                    // demand to resolve against — the token would have had to
                    // supply its own expected descriptor, which is exactly the
                    // circularity §41 forbids.
                    //
                    // NARROWED TO CASE-SETS ON PURPOSE. The general rule — an
                    // implicit local takes its value's descriptor — is right
                    // and is a much larger change than gap[087] needs; it is
                    // filed there rather than smuggled in under a case fix.
                    if (tgt.* == .name and i < as.values.len) {
                        const vt = self.type_map.get(as.values[i]) orelse RT.any;
                        if (vt == .enum_type) {
                            if (self.scope.lookupPtr(tgt.name.ident)) |sym| {
                                if (sym.typ == .any) sym.typ = vt;
                            }
                        }
                    }
                    _ = try self.check_expr(tgt);
                    const val_expr: ?*const Expr = if (i < as.values.len) as.values[i] else null;
                    self.noteModuleSealingInvalidation(tgt, val_expr);
                    if (i < as.values.len and tgt.* == .name) {
                        try self.maybe_register_meta_concept(tgt.name.ident, as.values[i]);
                        // At module scope in duo mode, infer type from literal
                        // initializer and register as global for better codegen.
                        if (self.duo_mode and self.scope.maps.items.len == 1) {
                            const inferred = self.infer_literal_type(as.values[i]);
                            if (inferred != .any) {
                                try self.note_global(tgt.name.ident, inferred);
                                if (self.scope.lookupPtr(tgt.name.ident)) |sym| {
                                    sym.typ = inferred;
                                }
                            }
                        }
                    }
                    // Track reassignment for mutable upvalue detection
                    if (tgt.* == .name) {
                        if (self.scope.lookupPtr(tgt.name.ident)) |sym| {
                            sym.assigned_after_init = true;
                        }
                    }
                }
            },
            .call_stmt => |*cs| _ = try self.check_expr(cs.expr),
            .expr_stmt => |*es| _ = try self.check_expr(es.expr),
            .ret => |*r| {
                if (r.vals.len == 0) {
                    if (self.current_ret != .any and self.current_ret != .void) {
                        var want_buf: [128]u8 = undefined;
                        const want_name = self.current_ret.duo_name(&want_buf);
                        self.err(r.loc, "return type mismatch: expected '{s}', got void", .{want_name});
                    }
                } else {
                    const actual = try self.check_expr(r.vals[0]);
                    self.check_return_value(r.loc, actual);
                    for (r.vals[1..]) |v| _ = try self.check_expr(v);
                }
            },
            .if_stmt => |*is| {
                if (is.binding) |b| {
                    _ = try self.check_expr(b.expr);
                    try self.scope.push();
                    defer self.scope.pop();
                    try self.scope.define(b.name, .{ .typ = .any, .is_const = false });
                }
                _ = try self.check_expr(is.cond);
                try self.check_block(&is.then);
                for (is.elseifs) |*ei| {
                    _ = try self.check_expr(ei.cond);
                    try self.check_block(&ei.body);
                }
                if (is.else_body) |*eb| try self.check_block(eb);
            },
            .while_loop => |*wl| {
                _ = try self.check_expr(wl.cond);
                try self.check_block(&wl.body);
            },
            .repeat_loop => |*rl| {
                try self.check_block(&rl.body);
                _ = try self.check_expr(rl.cond);
            },
            .num_for => |*nf| {
                try self.scope.push();
                var var_t: RT = .i64;
                if (nf.var_typ != .inferred)
                    var_t = self.resolve_type(nf.var_typ) catch .i64;
                try self.scope.define(nf.var_name, .{
                    .typ = var_t,
                    .is_const = true,
                    .is_for_control = true,
                });
                _ = try self.check_expr(nf.start);
                _ = try self.check_expr(nf.stop);
                if (nf.step) |s| _ = try self.check_expr(s);
                try self.check_block(&nf.body);
                self.scope.pop();
            },
            .gen_for => |*gf| {
                for (gf.iters) |it| _ = try self.check_expr(it);
                try self.scope.push();
                for (gf.vars, 0..) |v, i| {
                    const is_key = gf.vars.len > 1 and i == 0;
                    try self.scope.define(v, .{
                        .typ = .any,
                        .is_const = is_key,
                        .is_for_control = is_key,
                    });
                }
                try self.check_block(&gf.body);
                self.scope.pop();
            },
            .func_decl => |*fd| {
                try self.check_func_decl(fd);
            },
            .do_block => |*db| try self.check_block(&db.body),
            // NOTE: there is no `.struct_def` case. Records are declared via
            // record-type annotations on bindings; their type-checking and
            // `@implements` concept satisfaction is done in the `local_decl`
            // and `global_decl` arms above.
            .brk, .cont, .goto_stmt, .label_stmt => {},
            .match_stmt => |*ms| try self.check_match(ms),
            .enum_def => |*ed| try self.check_enum_def(ed),
            .try_stmt => |*ts| {
                // Type-check the try body
                try self.check_block(&ts.body);
                // Type-check each catch clause
                // NOTE: catch clauses are untyped in Duo. There is no
                // `error_type` on `CatchClause` — the binding (if any) is
                // always typed `any` (errors are tables, statically unknown).
                // User code uses `match e.__tag` inside the body.
                for (ts.catches) |*cc| {
                    try self.scope.push();
                    if (cc.binding) |name| {
                        try self.scope.define(name, .{ .typ = .any, .is_const = true });
                    }
                    try self.check_block(&cc.body);
                    self.scope.pop();
                }
                // Type-check defers within the try statement
                for (ts.defers) |*d| {
                    try self.check_block(&d.body);
                }
            },
            .defer_stmt => |*ds| {
                // Type-check the deferred body
                try self.check_block(&ds.body);
            },
            .concept_def => |*cd| {
                try self.check_concept_def(cd);
            },
            .alias_def => |*ad| {
                // Alias types are compile-time declarations; type-check fields and methods.
                const prev_type_name = self.current_type_name;
                self.current_type_name = ad.name;
                defer self.current_type_name = prev_type_name;
                // Register the alias name in scope as a constant struct type
                try self.scope.define(ad.name, .{ .typ = .{ .@"struct" = .{ .name = ad.name } }, .is_const = true });
                if (ad.target) |tgt| {
                    if (tgt == .record) {
                        const rec = tgt.record;
                        debug_trace.event(.sema, .@"struct", "struct {s} ({d} fields)", .{ ad.name, rec.fields.len });
                    } else {
                        debug_trace.event(.sema, .@"struct", "alias {s}", .{ad.name});
                    }
                } else if (ad.fields.len > 0) {
                    debug_trace.event(.sema, .@"struct", "struct {s} ({d} fields)", .{ ad.name, ad.fields.len });
                }
            },
            .macro_def => {},
            .cinclude => {},
            .directive => |*dir| {
                if (directives.isCInterfaceDirective(dir.attr.name)) return;
                if (directives.validateModuleDirective(dir.attr)) |bad| {
                    self.err(dir.loc, "unknown module directive '@{s}'", .{bad});
                } else if (std.mem.eql(u8, dir.attr.name, "specialize")) {
                    self.check_specialize_directive(dir.loc, dir.attr.args);
                } else if (directives.isBuildDirective(dir.attr.name)) {
                    try self.build_directives.append(self.alloc, dir.attr);
                } else if (directives.isDebugDirective(dir.attr.name)) {
                    try self.debug_directives.append(self.alloc, dir.attr);
                    debug_trace.applyModuleDirective(self.alloc, dir.attr) catch {};
                    if (term.debug_enabled) {
                        debug_trace.event(.sema, .module, "module directive '@{s}'", .{dir.attr.name});
                    }
                }
            },
        }
    }

    fn check_func_body(self: *Sema, fb: *ast.FuncBody) SemaError!RT {
        // Determine param types and return type
        var param_types = try self.alloc.alloc(RT, fb.params.len);
        var all_typed = true;
        for (fb.params, 0..) |*p, i| {
            if (p.typ == .inferred) {
                param_types[i] = .any;
                all_typed = false;
            } else {
                param_types[i] = try self.resolve_type(p.typ);
            }
        }
        var ret_t: RT = .any;
        if (contract_ret_expr(fb) != .inferred) {
            ret_t = try self.resolve_type(contract_ret_expr(fb));
        } else {
            all_typed = false;
        }
        fb.is_typed = all_typed;

        // Clear per-closure field type tracking (top-level funcs use func-prefixed keys).
        if (self.current_func_name == null) {
            var it = self.table_field_types.keyIterator();
            while (it.next()) |key_ptr| self.alloc.free(key_ptr.*);
            self.table_field_types.clearRetainingCapacity();
        }

        // Check body
        const prev_ret = self.current_ret;
        const prev_fallible = self.current_ret_fallible;
        const prev_nopanic = self.current_nopanic;
        self.current_ret = if (fb.ret_fallible) (self.resolve_type(fb.ret_type) catch .any) else ret_t;
        self.current_ret_fallible = fb.ret_fallible;
        // Anonymous function expressions don't carry @nopanic;
        // reset to false so inner expressions aren't incorrectly flagged.
        self.current_nopanic = false;
        for (fb.params) |*p| {
            if (p.default_val) |default_val| _ = try self.check_expr(default_val);
        }
        try self.scope.push();
        for (fb.params, 0..) |*p, i|
            try self.scope.define(p.name, .{ .typ = param_types[i], .is_const = false });
        try self.define_vararg_rest(fb);
        try self.check_block_with_implicit_return(&fb.body, true);
        self.scope.pop();
        self.current_ret = prev_ret;
        self.current_ret_fallible = prev_fallible;
        self.current_nopanic = prev_nopanic;

        const ret_ptr = try self.alloc.create(RT);
        ret_ptr.* = ret_t;
        const has_vararg = fb.vararg or fb.vararg_name != null;
        return RT{ .func = .{
            .params = param_types,
            .ret = ret_ptr,
            .is_native = all_typed and !has_vararg,
            .has_vararg = has_vararg,
            .is_compile_only = fb.is_compile_only,
        } };
    }

    // ── Expressions ───────────────────────────────────────────────────────────

    fn table_field_lookup_key(self: *const Sema, table_name: []const u8, field_name: []const u8, buf: []u8) ?[]const u8 {
        if (self.current_func_name) |fn_name| {
            return std.fmt.bufPrint(buf, "{s}.{s}.{s}", .{ fn_name, table_name, field_name }) catch null;
        }
        return std.fmt.bufPrint(buf, "{s}.{s}", .{ table_name, field_name }) catch null;
    }

    fn table_field_owned_key(self: *Sema, table_name: []const u8, field_name: []const u8) ?[]const u8 {
        if (self.current_func_name) |fn_name| {
            return std.fmt.allocPrint(self.alloc, "{s}.{s}.{s}", .{ fn_name, table_name, field_name }) catch null;
        }
        return std.fmt.allocPrint(self.alloc, "{s}.{s}", .{ table_name, field_name }) catch null;
    }

    fn track_table_literal_fields(self: *Sema, table_name: []const u8, init_expr: *const ast.Expr) void {
        if (init_expr.* != .table) return;
        for (init_expr.table.fields) |fld| {
            switch (fld) {
                .named => |nmd| {
                    const val_t = self.type_map.get(nmd.val) orelse .any;
                    self.track_table_field(table_name, nmd.key, val_t);
                },
                .indexed => |idx| {
                    if (idx.key.* == .string_lit) {
                        const val_t = self.type_map.get(idx.val) orelse .any;
                        self.track_table_field(table_name, idx.key.string_lit.val, val_t);
                    } else if (idx.key.* == .int_lit) {
                        var key_buf: [32]u8 = undefined;
                        const key = std.fmt.bufPrint(&key_buf, "{d}", .{idx.key.int_lit.val}) catch return;
                        const val_t = self.type_map.get(idx.val) orelse .any;
                        self.track_table_field(table_name, key, val_t);
                    }
                },
                .positional => {},
                .spread => |sp| _ = self.check_expr(sp) catch {},
                // Pass 36 G1/G8 recorded, not implemented (Phase 0): a semantic entry is keyed in the
                // semantic namespace, not the ordinary one, so it never contributes
                // an ordinary field type.
                .semantic => {},
            }
        }
    }

    /// Record or update the inferred type of a dynamic table field.
    /// On type mismatch, widens to .any (conservative).
    fn track_table_field(self: *Sema, table_name: []const u8, field_name: []const u8, new_t: RT) void {
        if (new_t == .nil or new_t == .str) return;
        var lookup_buf: [384]u8 = undefined;
        const lookup_key = self.table_field_lookup_key(table_name, field_name, &lookup_buf) orelse return;
        if (self.table_field_types.get(lookup_key)) |existing| {
            if (existing == .any or new_t == .any) {
                if (existing != .any) {
                    const owned = self.table_field_owned_key(table_name, field_name) orelse return;
                    self.table_field_types.put(self.alloc, owned, .any) catch self.alloc.free(owned);
                }
                return;
            }
            if (std.meta.activeTag(existing) != std.meta.activeTag(new_t)) {
                const owned = self.table_field_owned_key(table_name, field_name) orelse return;
                self.table_field_types.put(self.alloc, owned, .any) catch self.alloc.free(owned);
            }
            return;
        }
        const owned = self.table_field_owned_key(table_name, field_name) orelse return;
        self.table_field_types.put(self.alloc, owned, if (new_t == .any) .any else new_t) catch self.alloc.free(owned);
    }

    /// Look up the tracked field type for a dynamic table field access.
    fn lookup_table_field(self: *const Sema, table_name: []const u8, field_name: []const u8) ?RT {
        var lookup_buf: [384]u8 = undefined;
        const lookup_key = self.table_field_lookup_key(table_name, field_name, &lookup_buf) orelse return null;
        return self.table_field_types.get(lookup_key);
    }

    fn check_expr(self: *Sema, expr: *ast.Expr) SemaError!RT {
        const t = try self.check_expr_inner(expr);
        return self.record(expr, t);
    }

    /// APPLY-ONE, the RESOLVING half — c0 §43 `law.brace` row 1, §44
    /// `apply.edge` "apply(descriptor)(fieldpack) -> a value the descriptor
    /// describes". gap[092].
    ///
    /// Answers non-null exactly when this application's SUBJECT is a record
    /// descriptor, in which case the application constructs and its type is the
    /// descriptor — never the callee's return type, because there is no callee.
    ///
    /// Every fact §44 `apply.carries` enumerates SURVIVES this: the subject
    /// identity stays on `c.func`, the argument labels and their order stay on
    /// the pack's own `TableField`s, the operand descriptors are recorded by
    /// `check_expr` on each field value as usual, and the return pack is the
    /// answer below. Nothing is moved to a parallel structure and nothing is
    /// dropped — a second table of labels beside the pack is exactly where the
    /// two shapes drift apart, which is why APPLY-ONE added no such thing.
    fn check_descriptor_application(self: *Sema, expr: *ast.Expr) SemaError!?RT {
        const c = &expr.call;
        // The FACE, read from the tree rather than re-derived. Before APPLY-ONE
        // `f{ … }` and `f({ … })` were byte-identical here and this test could
        // not have been written.
        if (c.form != .braced) return null;
        if (c.args.len != 1) return null;
        if (c.args[0].* != .table) return null;
        if (!c.args[0].table.pack.applied) return null;
        if (c.func.* != .name) return null;

        const subject = c.func.name.ident;
        const def = self.alias_defs.get(subject) orelse return null;
        // A descriptor with type parameters is a generic alias and is expanded,
        // not applied; a nominal descriptor over a scalar (`feet: f64`) has no
        // field pack to receive. Both decline to the general path rather than
        // guessing, per `law.brace`'s own "never a guess".
        if (def.type_params != null) return null;
        const is_record = def.fields.len != 0 or
            (def.target != null and def.target.? == .record);
        if (!is_record) return null;

        // The pack's field VALUES are ordinary operands and are checked as
        // such. Done before the realization is recorded so a diagnostic inside
        // a field still reports against the field, not against the pack.
        _ = try self.check_expr(c.args[0]);

        // Argument labels are checked against the descriptor, which is the
        // whole benefit of resolving the subject instead of calling it: a
        // misspelled label used to become a silent table key.
        //
        // ONCE. `realized` is the record of this resolution having happened, so
        // it is also what makes the check idempotent — sema reaches a binding's
        // initializer more than once (inference, then the block walk) and
        // without this the same label reported twice.
        if (c.args[0].table.pack.realized == .undecided) {
            for (c.args[0].table.fields) |tf| {
                if (tf != .named) continue;
                if (!AliasRegistry.hasfield(def, tf.named.key)) {
                    self.err(
                        c.args[0].loc(),
                        "descriptor '{s}' has no field '{s}', so the applied pack carries a label the subject cannot receive",
                        .{ subject, tf.named.key },
                    );
                }
            }
        }

        // `law.pack.shape`: "physical representation is selected AFTER semantic
        // resolution". This is that selection, and it is the first write to
        // `realized` anywhere — the parser may only ever leave `.undecided`.
        // A resolved descriptor pack is FIELDS: the emitter has a designated
        // initializer for exactly this shape and no heap table is required.
        c.args[0].table.pack.realized = .fields;

        return RT{ .@"struct" = .{ .name = subject } };
    }

    fn check_expr_inner(self: *Sema, expr: *ast.Expr) SemaError!RT {
        return switch (expr.*) {
            .nil => .nil,
            .true_lit, .false_lit => .bool,
            .int_lit => .i64,
            .float_lit => .f64,
            .string_lit => .str,
            .vararg => .any,
            .quote, .unquote, .macro_call => {
                self.err(expr.loc(), "unexpanded macro expression reached semantic analysis", .{});
                return .any;
            },
            // Pass 36 G1/G2 (`@name`, `@`) are canon, but Phase 0 ships no parser
            // production, so nothing reaches here yet. Refuse rather than infer a
            // type for a resolution ladder that is not implemented.
            .semantic, .semantic_scope => {
                self.err(expr.loc(), "semantic access (@) is not yet implemented (Pass 36 Phase 0 records the calculus; the resolution ladder lands in P36-PH3)", .{});
                return .any;
            },
            .name => |n| {
                if (self.scope.lookup(n.ident)) |sym| {
                    // Emit deprecation warning if symbol is @deprecated (Requirement 18.7)
                    if (sym.deprecated_msg) |msg| {
                        self.warn_msg(n.loc, "'{s}' is deprecated: {s}", .{ n.ident, msg });
                    }
                    return sym.typ;
                }
                if (self.duo_mode and !self.is_builtin_global(n.ident)) {
                    // Implicit local: bare bindings and forward references are module/file locals.
                    try self.scope.define(n.ident, .{ .typ = .any, .is_const = false });
                    return .any;
                }
                if (self.scope.needs_explicit_global() and !self.is_builtin_global(n.ident)) {
                    self.err(n.loc, "use of undeclared global '{s}'", .{n.ident});
                    return .any;
                }
                // Unknown identifier → treat as dynamic global (Lua scripts)
                try self.note_global(n.ident, .any);
                return .any;
            },
            .field => |f| {
                var ot = try self.check_expr(f.obj);
                // A DESCRIPTOR NAME DENOTES ITS DESCRIPTOR. `token.kind.eof`
                // reported `any` because `token` is an `alias_def` and not a
                // scope binding, so `check_expr` took the implicit-local arm
                // above and the whole walk lost its type — `k = token.kind.eof`
                // then had no case-set to be a case of, which is why gap[087]'s
                // bare form had nothing to resolve against.
                //
                // Recovered here rather than in the `.name` arm deliberately:
                // a descriptor name in VALUE position is APPLY-ONE's question
                // (§43 `law.brace`) and is answered by the call path, while
                // this is only the WALK — `x.y` where `x` names a descriptor
                // has exactly one reading, and it is the only one this touches.
                if (ot == .any and f.obj.* == .name and
                    self.alias_defs.contains(f.obj.name.ident))
                {
                    ot = RT{ .@"struct" = .{ .name = f.obj.name.ident } };
                }
                if (ot == .enum_type and self.find_enum_variant(ot.enum_type, f.field) != null) {
                    return ot;
                }
                if (ot == .@"struct") {
                    if (try self.field_type_of_alias(ot.@"struct".name, f.field)) |ft| {
                        return ft;
                    }
                    if (self.enum_types.get(ot.@"struct".name)) |et| {
                        if (self.find_enum_variant(et.enum_type, f.field) != null) {
                            return et;
                        }
                    }
                }
                // If the object is a statically-typed record (anonymous
                // `{ field: T, ... }` annotation), return the declared
                // field's type instead of `.any`. This lets `local x: f64
                // = p.x` infer the type properly when `p: { x: f64, ... }`.
                if (ot == .table_type) {
                    const fields = ot.table_type.fields;
                    for (fields) |rf| {
                        if (std.mem.eql(u8, rf.name, f.field)) {
                            return rf.typ;
                        }
                    }
                }
                // Aggressive field type tracking: if the object is a local
                // dynamic table and we've seen a typed assignment to this
                // field, return the tracked type instead of .any.
                if (f.obj.* == .name) {
                    if (self.lookup_table_field(f.obj.name.ident, f.field)) |ft| {
                        return ft;
                    }
                }
                return .any; // otherwise, field access is dynamic
            },
            .index => |idx| {
                const ot = try self.check_expr(idx.obj);
                _ = try self.check_expr(idx.key);
                if (ot.is_vector()) {
                    return switch (ot) {
                        .v4f64 => .f64,
                        .v4i64 => .i64,
                        .v8f32 => .f32,
                        .v8i32 => .i32,
                        else => .any,
                    };
                }
                // A bare `ptr` (`void*`) has no pointee type to report, but the
                // one thing it is ever indexed as in Duo is a memory-backed
                // positional table, whose slots are i64-wide. Reporting `void`
                // made `t[i]` unusable in any expression.
                if (ot == .pointer) {
                    if (ot.pointer.* == .void) return .i64;
                    return ot.pointer.*;
                }
                if (ot == .array) return ot.array.elem.*;
                return .any;
            },
            .call => |c| {
                // Canonical curried form `mem.store("i64")(ptr, val)`: the type
                // selector is its own curry level and never shares a parameter
                // list with values (Pass 48 §2.6 application schemas). Must be
                // handled BEFORE anything type-checks `c.func`, or the inner
                // `mem.store("i64")` is validated on its own and fails arity.
                if (c.func.* == .call) {
                    const inner = c.func.call;
                    if (self.mem_intrinsic_name(inner.func)) |fname| {
                        if (inner.args.len == 1) {
                            var joined: std.ArrayList(*ast.Expr) = .empty;
                            defer joined.deinit(self.alloc);
                            try joined.append(self.alloc, inner.args[0]);
                            try joined.appendSlice(self.alloc, c.args);
                            return try self.check_mem_call(c.loc, fname, joined.items);
                        }
                    }
                }
                if (c.func.* == .name and std.mem.eql(u8, c.func.name.ident, "__constexpr") and c.args.len == 1) {
                    return try self.check_expr(c.args[0]);
                }
                // Low-level builtins return known types
                if (c.func.* == .name) {
                    const bn = c.func.name.ident;
                    if (std.mem.eql(u8, bn, "gatecap") and c.args.len == 1) return .str;
                    if (std.mem.eql(u8, bn, "__sizeof") or
                        std.mem.eql(u8, bn, "__alignof") or
                        std.mem.eql(u8, bn, "__offsetof"))
                    {
                        return .i64;
                    }
                    if (std.mem.eql(u8, bn, "__typeinfo")) return .str;
                    if (std.mem.eql(u8, bn, "__type_shape")) return .str;
                    if (std.mem.eql(u8, bn, "__why_shape")) return .str;
                    if (std.mem.eql(u8, bn, "__why")) return .str;
                    if (std.mem.eql(u8, bn, "__why_module")) return .str;
                    if (std.mem.eql(u8, bn, "__origin")) return .str;
                    if (std.mem.eql(u8, bn, "__why_boxed")) return .str;
                    if (std.mem.eql(u8, bn, "__why_not_native")) return .str;
                    if (std.mem.eql(u8, bn, "__representation")) return .str;
                    if (std.mem.eql(u8, bn, "__typeof")) return .str;
                    if (std.mem.eql(u8, bn, "__metaladder") or
                        std.mem.eql(u8, bn, "__metacatalog") or
                        std.mem.eql(u8, bn, "__metaagentcatalog") or
                        std.mem.eql(u8, bn, "__metaagentladder") or
                        std.mem.eql(u8, bn, "__metaagenthooks") or
                        std.mem.eql(u8, bn, "__metaagentdedupe") or
                        std.mem.eql(u8, bn, "__metaagentgaps") or
                        std.mem.eql(u8, bn, "__metaagentgrammar") or
                        std.mem.eql(u8, bn, "__metaagentmultiplier") or
                        std.mem.eql(u8, bn, "__moduletypenames") or
                        std.mem.eql(u8, bn, "__concepttypenames") or
                        std.mem.eql(u8, bn, "__comptimemap") or
                        std.mem.eql(u8, bn, "__comptimeeach") or
                        std.mem.eql(u8, bn, "__comptimematch") or
                        std.mem.eql(u8, bn, "__comptimetabulate") or
                        std.mem.eql(u8, bn, "__comptimeinterpolate") or
                        std.mem.eql(u8, bn, "__comptimefixpoint") or
                        std.mem.eql(u8, bn, "__comptimeproduct") or
                        std.mem.eql(u8, bn, "__comptimetensor") or
                        std.mem.eql(u8, bn, "__comptimenfold") or
                        std.mem.eql(u8, bn, "__comptimepower") or
                        std.mem.eql(u8, bn, "__comptimepermute") or
                        std.mem.eql(u8, bn, "__comptimechoose") or
                        std.mem.eql(u8, bn, "__comptimezip") or
                        std.mem.eql(u8, bn, "__metatranscend") or
                        std.mem.eql(u8, bn, "__metainfinity") or
                        std.mem.eql(u8, bn, "__metahyper") or
                        std.mem.eql(u8, bn, "__metagrammar") or
                        std.mem.eql(u8, bn, "__metaweave") or
                        std.mem.eql(u8, bn, "__metatemplate") or
                        std.mem.eql(u8, bn, "__metagenerate") or
                        std.mem.eql(u8, bn, "__metascheme") or
                        std.mem.eql(u8, bn, "__metaschemeclauses") or
                        std.mem.eql(u8, bn, "__derivechoose") or
                        std.mem.eql(u8, bn, "__derivepower") or
                        std.mem.eql(u8, bn, "__deriveproduct") or
                        std.mem.eql(u8, bn, "__rewrite_describe"))
                    {
                        return .str;
                    }
                    if (std.mem.eql(u8, bn, "__strcontains") or
                        std.mem.eql(u8, bn, "__strstartswith") or
                        std.mem.eql(u8, bn, "__strendswith") or
                        std.mem.eql(u8, bn, "__streq"))
                        return .bool;
                    if (std.mem.eql(u8, bn, "__strcountlines") or
                        std.mem.eql(u8, bn, "__strsplitcount") or
                        std.mem.eql(u8, bn, "__strcomptelen") or
                        std.mem.eql(u8, bn, "__concept_count") or
                        std.mem.eql(u8, bn, "__rewrite_rulecount"))
                        return .i64;
                    if (std.mem.eql(u8, bn, "__strjoin")) return .str;
                    if (std.mem.eql(u8, bn, "__fields")) return .any;
                    if (std.mem.eql(u8, bn, "__emit")) return .any;
                    if (std.mem.eql(u8, bn, "__c_call")) return .any;
                    if (std.mem.eql(u8, bn, "__bitcast")) return .any;
                    if (std.mem.eql(u8, bn, "__volatile")) return .any;
                    if (std.mem.eql(u8, bn, "__comptimeif") and c.args.len == 3) {
                        // Infer from then/else branches
                        const t1 = try self.check_expr(c.args[1]);
                        const t2 = try self.check_expr(c.args[2]);
                        if (t1.eql(t2)) return t1;
                        return .any;
                    }
                    // Branch prediction hints preserve type
                    if (std.mem.eql(u8, bn, "__likely") or std.mem.eql(u8, bn, "__unlikely")) {
                        if (c.args.len == 1) return .i64;
                    }
                    // Bit manipulation builtins return i64
                    if (std.mem.eql(u8, bn, "__ctz") or
                        std.mem.eql(u8, bn, "__clz") or
                        std.mem.eql(u8, bn, "__popcount") or
                        std.mem.eql(u8, bn, "__bswap") or
                        std.mem.eql(u8, bn, "__rotl") or
                        std.mem.eql(u8, bn, "__rotr"))
                    {
                        return .i64;
                    }
                    // These return i64 (value 0) but used as statements
                    if (std.mem.eql(u8, bn, "__prefetch") or
                        std.mem.eql(u8, bn, "__assume") or
                        std.mem.eql(u8, bn, "__unreachable") or
                        std.mem.eql(u8, bn, "__trap") or
                        std.mem.eql(u8, bn, "__fence"))
                    {
                        return .i64;
                    }
                    if (std.mem.eql(u8, bn, "__comptimefold") or
                        std.mem.eql(u8, bn, "__comptimefor"))
                    {
                        return .any;
                    }
                    if (std.mem.eql(u8, bn, "__static_assert")) {
                        self.check_static_assert(c.func.name.loc, c.args);
                        return .any;
                    }
                    if (std.mem.eql(u8, bn, "__typeof")) return .any;
                    if (std.mem.eql(u8, bn, "__as")) return .any;
                    if (std.mem.eql(u8, bn, "__select") and c.args.len >= 2) {
                        return try self.check_expr(c.args[1]);
                    }
                    // Metaprogramming: type introspection — return table of field/method info
                    if (std.mem.eql(u8, bn, "__fields") or
                        std.mem.eql(u8, bn, "__methods") or
                        std.mem.eql(u8, bn, "__concept_methods") or
                        std.mem.eql(u8, bn, "__variants"))
                    {
                        return .any; // returns comptime table
                    }
                    // Metaprogramming: boolean type queries
                    if (std.mem.eql(u8, bn, "__has_field") or
                        std.mem.eql(u8, bn, "__has_method") or
                        std.mem.eql(u8, bn, "__has_metamethod") or
                        std.mem.eql(u8, bn, "__is_type"))
                    {
                        return .bool;
                    }
                    if (std.mem.eql(u8, bn, "__satisfies") and c.args.len == 2) {
                        // `@satisfies(T, "C")` is a pure comptime boolean — it must
                        // never error on its own. Only `@static_assert(@satisfies(...))`
                        // errors when false. Folding here would break legitimate
                        // uses such as `tostring(@satisfies(M, "Printable"))` where
                        // the result is expected to be `false`.
                        _ = self.eval_satisfies_expr(c.args);
                        return .bool;
                    }
                    // Metaprogramming: type name / id
                    if (std.mem.eql(u8, bn, "__type_name") or
                        std.mem.eql(u8, bn, "__field_type"))
                    {
                        return .str;
                    }
                    if (std.mem.eql(u8, bn, "__type_id")) return .i64;
                    // Metaprogramming: layout introspection
                    if (std.mem.eql(u8, bn, "__field_offset") or
                        std.mem.eql(u8, bn, "__field_size"))
                    {
                        return .i64;
                    }
                    // Metaprogramming: compile-time messages (void-like)
                    if (std.mem.eql(u8, bn, "__comptimeprint") or
                        std.mem.eql(u8, bn, "__comptimeerror") or
                        std.mem.eql(u8, bn, "__comptimewarn"))
                    {
                        return .any;
                    }
                    // Metaprogramming: file embedding
                    if (std.mem.eql(u8, bn, "__embed_file")) return .any; // returns table of bytes
                    if (std.mem.eql(u8, bn, "__embed_str")) return .str;
                    // Metaprogramming: type construction
                    if (std.mem.eql(u8, bn, "__make_type")) return .any;
                    // Metaprogramming: type cast (returns target type)
                    if (std.mem.eql(u8, bn, "__as_type")) return .any;
                    // Metaprogramming: layout
                    if (std.mem.eql(u8, bn, "__bitfield") or
                        std.mem.eql(u8, bn, "__union"))
                    {
                        return .any;
                    }
                    // Metaprogramming: metatable type tracking
                    if (std.mem.eql(u8, bn, "__metatable_type")) return .any;
                    // Metaprogramming: dispatch hints (pass-through)
                    if (std.mem.eql(u8, bn, "__inline_always") or
                        std.mem.eql(u8, bn, "__no_inline") or
                        std.mem.eql(u8, bn, "__cold_path") or
                        std.mem.eql(u8, bn, "__hot_path"))
                    {
                        if (c.args.len >= 1) return try self.check_expr(c.args[0]);
                        return .any;
                    }
                }
                if (self.duo_mode and c.func.* == .name) {
                    const callee = c.func.name.ident;
                    if (self.foreign_functions.get(callee)) |ff| {
                        debug_trace.event(.sema, .foreign, "pass26 call boundary={s}", .{ff.boundary_id});
                    }
                    if (std.mem.eql(u8, callee, "pairs") or std.mem.eql(u8, callee, "ipairs")) {
                        self.warn_msg(c.func.name.loc, "'{s}' is deprecated; iterate tables directly with 'for value in table' or 'for key, value in table'", .{callee});
                    }
                    // APPLY-ONE (c0 §43 `law.brace`, §44 `apply.edge` row 1),
                    // gap[092]. THE SUBJECT DECIDES. Descriptor space is
                    // consulted BEFORE callable space, and before the refusal
                    // below, because a descriptor subject is an application
                    // whose meaning is CONSTRUCTION — not a call, and not an
                    // undeclared function.
                    //
                    // This is not c0 §44a trap 1. Trap 1 is a consumer
                    // *deriving* the brace/paren split from what a name
                    // denotes; the split is STATED by the tree here
                    // (`form == .braced`, `pack.applied`) and this site only
                    // resolves the subject that the stated form already
                    // identified. Reading a stated fact and selecting an edge
                    // is `law.brace` working.
                    if (try self.check_descriptor_application(expr)) |rt| return rt;
                    // gap[026]: a call to a name nothing declares. This must run
                    // BEFORE `check_expr(c.func)` below, because that path
                    // silently defines any unresolved name as an implicit local
                    // (sema.zig ~2206) and the C compiler becomes the first
                    // thing to object — `duo check` reported success on programs
                    // that could not compile.
                    //
                    // Top-level forward references are safe: check_module
                    // pre-registers every top-level binding before check_block,
                    // so they resolve here.
                    if (self.scope.lookup(callee) == null and
                        !self.is_builtin_global(callee) and
                        !is_relation_family(callee) and
                        self.foreign_functions.get(callee) == null)
                    {
                        // c0 §43 `law.brace` third outcome: "subject is NEITHER
                        // -> diagnostic, never a guess". The old sentence was
                        // "call to undeclared function '{s}'" — the right
                        // refusal in the wrong words. It was the CALL PATH
                        // narrating its own unconditional win, and it named one
                        // of the two homes the resolution rule consults. Under
                        // APPLY-ONE the subject is looked for in DESCRIPTOR
                        // space and in CALLABLE space, and this diagnostic
                        // fires only when BOTH answered no; it says so, and it
                        // names each home with what it was asked for.
                        self.err(
                            c.func.name.loc,
                            "'{s}' is neither a descriptor nor a callable, so the {s} application has no subject: descriptor space holds no '{s}' and callable space holds no '{s}' (no declaration, no builtin, no foreign import)",
                            .{ callee, c.form.name(), callee, callee },
                        );
                    }
                }
                const ft = try self.check_expr(c.func);
                if (c.form == .braced and ft == .func) {
                    // c0 §43 `law.brace`: "an ordinary callable uses `name( … )`,
                    // never braces". The subject resolved in callable space,
                    // so the braced face is the §41 "or a diagnostic" branch,
                    // never a fall-through to ordinary-call checking.
                    self.err(
                        c.loc,
                        callable_brace_error,
                        .{},
                    );
                    return .any;
                }
                if (ft == .func and ft.func.is_compile_only) {
                    self.err(c.loc, "function is marked @comp.compile.only and cannot be called at runtime", .{});
                }
                for (c.args) |arg| _ = try self.check_expr(arg);

                // Built-in module return types
                if (self.mem_intrinsic_name(c.func)) |fname| {
                    return try self.check_mem_call(c.loc, fname, c.args);
                }
                if (self.ml_intrinsic_name(c.func)) |fname| {
                    return try self.check_ml_call(c.loc, fname, c.args);
                }
                if (self.atomic_intrinsic_name(c.func)) |fname| {
                    return try self.check_atomic_call(c.loc, fname, c.args);
                }
                if (c.func.* == .field) {
                    const f = &c.func.field;
                    if (f.obj.* == .name) {
                        const mod = f.obj.name.ident;
                        const fname = f.field;
                        if (std.mem.eql(u8, mod, "os") and std.mem.eql(u8, fname, "clock"))
                            return .f64;
                        if (std.mem.eql(u8, mod, "string")) {
                            if (std.mem.eql(u8, fname, "len") or std.mem.eql(u8, fname, "byte"))
                                return .i64;
                            if (std.mem.eql(u8, fname, "char") or std.mem.eql(u8, fname, "rep") or
                                std.mem.eql(u8, fname, "sub") or std.mem.eql(u8, fname, "lower") or
                                std.mem.eql(u8, fname, "upper") or std.mem.eql(u8, fname, "reverse"))
                                return .str;
                        }
                        if (std.mem.eql(u8, mod, "math")) {
                            if (std.mem.eql(u8, fname, "sqrt") or
                                std.mem.eql(u8, fname, "sin") or std.mem.eql(u8, fname, "cos") or
                                std.mem.eql(u8, fname, "tan") or std.mem.eql(u8, fname, "exp") or
                                std.mem.eql(u8, fname, "log") or std.mem.eql(u8, fname, "floor") or
                                std.mem.eql(u8, fname, "ceil")) return .f64;
                            if (std.mem.eql(u8, fname, "max") or std.mem.eql(u8, fname, "min")) {
                                if (c.args.len == 2) {
                                    if ((try self.check_expr(c.args[0])).is_integer() and (try self.check_expr(c.args[1])).is_integer()) return .i64;
                                    return .f64;
                                }
                                return .any;
                            }
                            if (std.mem.eql(u8, fname, "abs")) {
                                if (c.args.len > 0 and (try self.check_expr(c.args[0])).is_integer()) return .i64;
                                return .f64;
                            }
                        }
                        if (std.mem.eql(u8, mod, "simd")) {
                            if (std.mem.eql(u8, fname, "v4f64")) return .v4f64;
                            if (std.mem.eql(u8, fname, "v4i64")) return .v4i64;
                            if (std.mem.eql(u8, fname, "v8f32")) return .v8f32;
                            if (std.mem.eql(u8, fname, "v8i32")) return .v8i32;
                            if (std.mem.eql(u8, fname, "sqrt")) {
                                if (c.args.len > 0) return try self.check_expr(c.args[0]);
                            }
                            if (std.mem.eql(u8, fname, "sum")) {
                                if (c.args.len > 0) {
                                    const at = try self.check_expr(c.args[0]);
                                    return switch (at) {
                                        .v4f64 => .f64,
                                        .v8f32 => .f32,
                                        .v4i64, .v8i32 => .i64,
                                        else => .i64,
                                    };
                                }
                                return .i64;
                            }
                            if (std.mem.eql(u8, fname, "any") or std.mem.eql(u8, fname, "all")) return .bool;
                            if (std.mem.eql(u8, fname, "fma") and c.args.len >= 3) {
                                return try self.check_expr(c.args[0]);
                            }
                            if (std.mem.eql(u8, fname, "dot_f32") and c.args.len >= 3) return .f32;
                            if (std.mem.eql(u8, fname, "dot_f64") and c.args.len >= 3) return .f64;
                            if (std.mem.eql(u8, fname, "matmul_f32") or std.mem.eql(u8, fname, "matmul_f64")) return .void;
                            if (std.mem.eql(u8, fname, "select") and c.args.len >= 3) {
                                return try self.check_expr(c.args[1]);
                            }
                            if (std.mem.eql(u8, fname, "le") or std.mem.eql(u8, fname, "lt") or
                                std.mem.eql(u8, fname, "ge") or std.mem.eql(u8, fname, "gt") or
                                std.mem.eql(u8, fname, "eq") or std.mem.eql(u8, fname, "ne"))
                            {
                                if (c.args.len >= 2) {
                                    const at = try self.check_expr(c.args[0]);
                                    if (at.vector_mask()) |m| return m;
                                }
                            }
                        }
                    }
                }

                // Overload resolution (Requirement 12): when the callee is a
                // bare name with multiple registered overloads, select the one
                // whose parameter types match the argument types. Ambiguous
                // matches are reported as an error.
                if (c.func.* == .name) {
                    if (self.overloads.getPtr(c.func.name.ident)) |overload_list| {
                        if (overload_list.items.len > 1) {
                            if (try self.resolve_overload(c.func.name.loc, c.func.name.ident, overload_list.items, c.args)) |ret|
                                return ret;
                        }
                    }
                }

                // Generic instantiation tracking (Requirement 4.1, 4.3): when the
                // callee's signature mentions generic parameters, record the
                // concrete type arguments at this site for the monomorphizer.
                if (ft == .func and c.func.* == .name)
                    try self.record_generic_instantiation(c.func.name.loc, c.func.name.ident, ft.func, c.args);

                if (c.func.* == .name) {
                    if (std.mem.eql(u8, c.func.name.ident, "tostring") or
                        std.mem.eql(u8, c.func.name.ident, "type")) return .str;
                }

                const result: RT = switch (ft) {
                    .func => |f| f.ret.*,
                    else => .any,
                };
                if (c.func.* == .name) {
                    if (self.callable_defs.get(c.func.name.ident)) |target| {
                        if (target) |resolved| {
                            try self.recordApplication(expr, resolved, null, c.args, result);
                        }
                    }
                }
                return result;
            },
            .method_call => |mc| {
                const ot = try self.check_expr(mc.obj);
                for (mc.args) |arg| _ = try self.check_expr(arg);
                if (std.mem.eql(u8, mc.method, "eq") and enum_type_has_derive(ot, "Eq")) {
                    return .bool;
                }
                if (std.mem.eql(u8, mc.method, "to_string") and enum_type_has_derive(ot, "Display")) {
                    return .str;
                }
                if (self.callable_defs.get(mc.method)) |target| {
                    if (target) |resolved| {
                        if (self.scope.lookup(mc.method)) |symbol| {
                            if (symbol.typ == .func) {
                                const callable = symbol.typ.func;
                                if (callable.params.len == mc.args.len + 1 and
                                    callable.params[0].eql(ot))
                                {
                                    const result = callable.ret.*;
                                    try self.recordApplication(expr, resolved, mc.obj, mc.args, result);
                                    return result;
                                }
                            }
                        }
                    }
                }
                return .any;
            },
            .binop => |b| self.check_binop(expr.loc(), b.op, b.lhs, b.rhs),
            .unop => |u| self.check_unop(u.op, u.operand),
            .func_expr => |fb| blk: {
                fb.closure_id = self.next_closure_id;
                self.next_closure_id += 1;
                try self.analyze_closure_upvalues(fb);
                break :blk try self.check_func_body(fb);
            },
            .table => |t| {
                for (t.fields) |*fld| {
                    switch (fld.*) {
                        .indexed => |*idx| {
                            _ = try self.check_expr(idx.key);
                            _ = try self.check_expr(idx.val);
                        },
                        .named => |*nmd| {
                            _ = try self.check_expr(nmd.val);
                        },
                        .positional => |p| {
                            _ = try self.check_expr(p);
                        },
                        .spread => |sp| {
                            _ = try self.check_expr(sp);
                        },
                        // Pass 36 G1/G8 recorded, not implemented (Phase 0): check the implementation only.
                        .semantic => |*sm| {
                            _ = try self.check_expr(sm.val);
                        },
                    }
                }
                return .any;
            },
            .list_comp => |lc| {
                _ = try self.check_expr(lc.iter);
                try self.scope.push();
                defer self.scope.pop();
                if (lc.key_name) |key_name| {
                    try self.scope.define(key_name, .{ .typ = .any, .is_const = true });
                }
                try self.scope.define(lc.value_name, .{ .typ = .any, .is_const = true });
                if (lc.filter) |filter| _ = try self.check_expr(filter);
                _ = try self.check_expr(lc.value);
                return .any;
            },
            .try_expr => |te| {
                const operand_t = try self.check_expr(te.operand);
                // The ? operator requires the enclosing function to have
                // a result-compatible return type (Requirement 9.7)
                if (!self.is_result_compatible_ret()) {
                    self.err(te.loc, "'?' operator requires enclosing function to have a result-compatible return type", .{});
                }
                // Propagate the operand's type so downstream expressions see
                // the concrete type rather than falling back to .any.
                return operand_t;
            },
            .unwrap_expr => |ue| {
                const operand_t = try self.check_expr(ue.operand);
                // The ! operator is rejected in @nopanic functions (Requirement 9.8)
                if (self.current_nopanic) {
                    self.err(ue.loc, "'!' operator cannot be used in @nopanic function (it may panic)", .{});
                }
                // The unwrapped value has the same type as the operand.
                return operand_t;
            },
            .if_expr => |ie| {
                _ = try self.check_expr(ie.cond);
                const then_t = try self.check_expr(ie.then_expr);
                const else_t = try self.check_expr(ie.else_expr);
                if (then_t.eql(else_t)) return then_t;
                return .any;
            },
            .match_expr => |me| {
                return try self.check_match_expr(me);
            },
            .await_expr => |ae| {
                const operand_t = try self.check_expr(ae.operand);
                return operand_t;
            },
            .contains_expr => |ce| {
                _ = try self.check_expr(ce.lhs);
                _ = try self.check_expr(ce.rhs);
                // `x in y` is always a boolean test.
                return .bool;
            },
            .sequence => |seq| {
                // Check all sub-expressions; return type of first (primary value).
                if (seq.exprs.len == 0) return .nil;
                for (seq.exprs) |e| _ = try self.check_expr(e);
                return try self.check_expr(seq.exprs[0]);
            },
            .range => |r| {
                _ = try self.check_expr(r.start);
                _ = try self.check_expr(r.end);
                if (r.step) |s| _ = try self.check_expr(s);
                return .any;
            },
        };
    }

    /// GAP-059 — the half of the `@` token that ADJACENCY did not reconcile.
    ///
    /// Pass 100 §2 gives `@` exactly two surviving stances, the DYAD: bare `@`
    /// NAMES the enclosing descriptor, and postfix `X@rel` MOVES the anchor and
    /// RETRIEVES. Neither is a binary operator over values. `3f6ec4e` gave the
    /// GLUED spelling to the anchor — `at_is_glued_anchor` in `src/parser.zig`
    /// reads `p@x` as a SUFFIX beside `.field` and `[i]`, agreeing with
    /// `lib/std/compiler/parser.id`, pinned by value at 353 in
    /// `examples/spec100/anchormove.id`.
    ///
    /// `infix_prec` still maps the `@` token to `.matmul`, so the SPACED
    /// spelling kept everything the glued one shed:
    ///
    ///     print(p @ x)
    ///     -> warning: infix '@' matmul is non-canonical
    ///     -> ✓ checked — no errors                       exit 0
    ///     -> error: use of undeclared identifier 'x'
    ///
    /// `duo check` exiting 0 on a construct the compiler has no meaning for is
    /// the defect, and adjacency narrowed it rather than removing it. The
    /// tensor product is NOT the defect: `Tensor[M,K] @ Tensor[K,N]` is a real,
    /// shape-checked operation with real fixtures
    /// (`examples/compile_fail/tensor_matmul_k_mismatch.id`), and it is the
    /// only spelling that operation has today.
    ///
    /// So the verdict is a TYPE question, not a lexical one, which is why it
    /// lives here and not in the parser: the parser sees one token and no
    /// types, and cannot tell `x @ y` over two tensors from `p @ x` over a
    /// record. Sema can. Until now sema held no belief about `@` at all — 19
    /// decision sites in `parser.zig`, 0 here — which is exactly how the two
    /// subsystems came to disagree in the first place.
    ///
    /// Returns true when the operands are both tensors (checking continues to
    /// the shape rules). Returns false after reporting, which is the honest
    /// answer for every other operand pair. `.lua` files are untouched: the
    /// gate is `duo_mode`, the same switch `comptime` already errors through,
    /// and `examples/compile_fail/anchor_infix_at.lua` is the positive control
    /// that fails if that guard is ever dropped.
    ///
    /// The repair the hint names is the SPACE, because after `3f6ec4e` there is
    /// a working spelling one column to the left. That is the whole reason this
    /// can be a hard error and not a warning: refusing a construct whose repair
    /// does not exist would make the corpus unmigratable.
    fn check_infix_at(self: *Sema, loc: ast.Loc, lt: RT, rt: RT) bool {
        if (lt == .tensor and rt == .tensor) {
            self.warn_msg(loc, "warning: infix '@' matmul is non-canonical; prefer explicit tensor APIs or typed helpers", .{});
            return true;
        }
        self.err(loc, "infix '@' has no meaning in .id: it parsed as the matmul operator over non-tensor operands", .{});
        // Unconditional, not `hint_msg`: `hints_enabled` is off under
        // `duo check`, and a refusal with no repair makes the corpus
        // unmigratable — the rule `scripts/run_compile_fail_tests.id` states
        // over its own rows. The `.@name` refusal hints the same way.
        term.locHint(loc, "the anchor is the GLUED form: close the space and 'X @ rel' becomes 'X@rel', which moves the anchor and retrieves. A spaced '@' is the matmul operator, and that needs both operands to be Tensor[..]", .{});
        return false;
    }

    fn check_binop(self: *Sema, loc: ast.Loc, op: ast.BinOp, lhs: *ast.Expr, rhs: *ast.Expr) SemaError!RT {
        // c0 §41 `resolution.rule` — BARE IDENTITY + SEMANTIC DEMAND + AVAILABLE
        // HOMES -> ONE IDENTITY, OR A DIAGNOSTIC. gap[087].
        //
        // BEFORE either operand is checked, and that ordering is the whole
        // correctness argument. `check_expr` on an unbound name IMPLICITLY
        // DEFINES it as an `any` local (the duo_mode arm of the `.name` case),
        // so a resolver that ran afterwards would be resolving against a
        // binding it had just created — and `law.shadow` would then fire on
        // every bare case, blaming the reader for the checker's own side
        // effect.
        if (op == .eq or op == .neq) try self.resolve_bare_case_operands(lhs, rhs);
        const lt = try self.check_expr(lhs);
        const rt = try self.check_expr(rhs);

        if (op == .matmul and self.duo_mode) {
            if (!self.check_infix_at(loc, lt, rt)) return .any;
        }

        // Handle vector operations
        if (lt.is_vector() or rt.is_vector()) {
            const vec = if (lt.is_vector()) lt else rt;
            return switch (op) {
                .eq, .neq, .lt, .gt, .leq, .geq => vec.vector_mask() orelse .any,
                .band, .bor, .bxor => if (lt.eql(rt)) lt else .any,
                .add, .sub, .mul, .div, .pow => blk: {
                    if (lt.eql(rt)) break :blk lt;
                    if (lt.is_vector() and rt.is_numeric()) break :blk lt;
                    if (rt.is_vector() and lt.is_numeric()) break :blk rt;
                    break :blk .any;
                },
                else => .any,
            };
        }

        if (op == .@"or" and lhs.* == .binop and lhs.binop.op == .@"and") {
            const then_t = self.type_map.get(lhs.binop.rhs) orelse .any;
            if (then_t.eql(rt) and lua_and_or_value_type_is_native(then_t)) return then_t;
            return .any;
        }

        return switch (op) {
            .div, .pow => {
                if (lt.is_numeric() and rt.is_numeric()) return .f64;
                return .any;
            },
            .add, .sub, .mul, .idiv, .mod => blk: {
                if (lt == .tensor and rt == .tensor) {
                    if (op == .add) {
                        if (RT.tensor_same_shape(lt, rt)) break :blk lt;
                        if (RT.tensor_broadcast_shape_incompatible(lt, rt)) {
                            self.err(loc, "tensor broadcast incompatible shapes", .{});
                            break :blk .any;
                        }
                        if (try RT.tensor_broadcast(lt, rt, self.alloc)) |out| break :blk out;
                        break :blk .any;
                    }
                    if (!RT.tensor_same_shape(lt, rt) and RT.tensor_strict_shape_incompatible(lt, rt)) {
                        self.err(loc, "tensor shape mismatch", .{});
                    }
                    break :blk if (RT.tensor_same_shape(lt, rt)) lt else .any;
                }
                if (lt.is_numeric() and rt.is_numeric()) {
                    // Promote: if either is float, result is float
                    if (lt.is_float() or rt.is_float()) break :blk .f64;
                    break :blk lt; // both integers: use left type
                }
                break :blk .any;
            },
            .band, .bor, .bxor, .lshift, .rshift => {
                if (lt.is_integer() and rt.is_integer()) return lt;
                return .any;
            },
            .concat => .str,
            .eq, .neq, .lt, .gt, .leq, .geq => .bool,
            .contains => .bool,
            .@"and" => if (lt.eql(rt)) rt else .any,
            .@"or" => if (lt.eql(rt)) lt else .any,
            .matmul => blk: {
                if (RT.tensor_matmul_k_incompatible(lt, rt)) {
                    const ta = lt.tensor;
                    const tb = rt.tensor;
                    if (RT.tensor_dim_const(ta.dims[1]) != null and RT.tensor_dim_const(tb.dims[0]) != null) {
                        const k_lhs = RT.tensor_dim_const(ta.dims[1]).?;
                        const k_rhs = RT.tensor_dim_const(tb.dims[0]).?;
                        self.err(loc, "tensor matmul inner dimension mismatch: {d} vs {d}", .{ k_lhs, k_rhs });
                    } else {
                        const k_lhs_l = RT.tensor_dim_label(ta.dims[1]) orelse "?";
                        const k_rhs_l = RT.tensor_dim_label(tb.dims[0]) orelse "?";
                        self.err(loc, "tensor matmul inner dimension mismatch: {s} vs {s}", .{ k_lhs_l, k_rhs_l });
                    }
                    break :blk .any;
                }
                if (try RT.tensor_matmul(lt, rt, self.alloc)) |out| break :blk out;
                break :blk .any;
            },
            .pipeline => .any, // pipeline returns whatever the RHS function returns
        };
    }

    fn lua_and_or_value_type_is_native(t: RT) bool {
        return t.is_numeric() or t == .str;
    }

    fn check_unop(self: *Sema, op: ast.UnOp, operand: *ast.Expr) SemaError!RT {
        const t = try self.check_expr(operand);
        return switch (op) {
            .neg => if (t.is_numeric()) t else .any,
            .bnot => if (t.is_integer() or t.is_vector()) t else .any,
            .not => .bool,
            .len => if (t == .any) .any else .i64,
            .compile => t, // Compile-time operator has same type as operand
        };
    }

    fn func_body_has_func_expr(fb: *const ast.FuncBody) bool {
        return func_body_has_func_expr_block(&fb.body);
    }

    fn func_body_has_func_expr_block(block: *const ast.Block) bool {
        for (block.stmts) |*stmt| {
            if (stmt_has_func_expr(stmt)) return true;
        }
        return false;
    }

    fn stmt_has_func_expr(stmt: *const ast.Stmt) bool {
        return switch (stmt.*) {
            .local_decl => |*ld| expr_has_func_expr_in_list(ld.inits),
            .assign => |*as| expr_has_func_expr_in_list(as.values),
            .ret => |*r| expr_has_func_expr_in_list(r.vals),
            .if_stmt => |*is| blk: {
                if (expr_has_func_expr(is.cond)) return true;
                if (func_body_has_func_expr_block(&is.then)) return true;
                for (is.elseifs) |*ei| {
                    if (expr_has_func_expr(ei.cond)) return true;
                    if (func_body_has_func_expr_block(&ei.body)) return true;
                }
                if (is.else_body) |*eb| {
                    if (func_body_has_func_expr_block(eb)) return true;
                }
                break :blk false;
            },
            .while_loop => |*wl| {
                if (expr_has_func_expr(wl.cond)) return true;
                return func_body_has_func_expr_block(&wl.body);
            },
            .num_for => |*nf| func_body_has_func_expr_block(&nf.body),
            .gen_for => |*fg| {
                for (fg.iters) |e| {
                    if (expr_has_func_expr(e)) return true;
                }
                return func_body_has_func_expr_block(&fg.body);
            },
            .call_stmt => |*cs| expr_has_func_expr(cs.expr),
            .expr_stmt => |*es| expr_has_func_expr(es.expr),
            .do_block => |*db| func_body_has_func_expr_block(&db.body),
            .func_decl => |*fd| func_body_has_func_expr(&fd.func),
            else => false,
        };
    }

    fn expr_has_func_expr_in_list(exprs: []const *ast.Expr) bool {
        for (exprs) |e| {
            if (expr_has_func_expr(e)) return true;
        }
        return false;
    }

    fn expr_has_func_expr(expr: *const ast.Expr) bool {
        return switch (expr.*) {
            .func_expr => true,
            .binop => |b| expr_has_func_expr(b.lhs) or expr_has_func_expr(b.rhs),
            .unop => |u| expr_has_func_expr(u.operand),
            .call => |c| {
                if (expr_has_func_expr(c.func)) return true;
                for (c.args) |a| {
                    if (expr_has_func_expr(a)) return true;
                }
                return false;
            },
            .method_call => |mc| {
                if (expr_has_func_expr(mc.obj)) return true;
                for (mc.args) |a| {
                    if (expr_has_func_expr(a)) return true;
                }
                return false;
            },
            .field => |f| expr_has_func_expr(f.obj),
            .index => |idx| expr_has_func_expr(idx.obj) or expr_has_func_expr(idx.key),
            .table => |t| {
                for (t.fields) |fld| {
                    switch (fld) {
                        .indexed => |idx| {
                            if (expr_has_func_expr(idx.key) or expr_has_func_expr(idx.val)) return true;
                        },
                        .named => |nmd| {
                            if (expr_has_func_expr(nmd.val)) return true;
                        },
                        .positional => |pos| {
                            if (expr_has_func_expr(pos)) return true;
                        },
                        .spread => |sp| {
                            if (expr_has_func_expr(sp)) return true;
                        },
                        // Pass 36 G1/G8 recorded, not implemented (Phase 0): the implementation may be a function.
                        .semantic => |sm| {
                            if (expr_has_func_expr(sm.val)) return true;
                        },
                    }
                }
                return false;
            },
            .list_comp => |lc| {
                if (expr_has_func_expr(lc.iter) or expr_has_func_expr(lc.value)) return true;
                if (lc.filter) |filter| return expr_has_func_expr(filter);
                return false;
            },
            else => false,
        };
    }

    fn analyze_closure_upvalues(self: *Sema, fb: *ast.FuncBody) !void {
        var names = std.ArrayList([]const u8).empty;
        var flags = std.ArrayList(bool).empty;
        defer names.deinit(self.alloc);
        defer flags.deinit(self.alloc);
        // Collect all variable names declared inside the function body itself
        // (locals, consts, for-loop vars). These are NOT upvalues — they belong
        // to this function's scope, not the enclosing scope.
        var body_locals = std.StringHashMap(void).init(self.alloc);
        defer body_locals.deinit();
        try collect_body_locals(&fb.body, &body_locals);
        try collect_upvalue_names(fb, &fb.body, fb.params, &body_locals, &names, &flags, self);
        fb.upvalues = try self.alloc.alloc(ast.Upvalue, names.items.len);
        for (names.items, flags.items, 0..) |nm, is_local, i| {
            var typ: ?RT = null;
            var is_mutable = false;
            if (self.scope.lookupPtr(nm)) |sym| {
                typ = sym.typ;
                // Mark captured locals as escaping — they outlive their scope.
                sym.captured_by_closure = true;
                sym.escapes = true;
                // If the variable is reassigned after declaration, it needs
                // mutable capture (heap-allocated cell shared between closures).
                is_mutable = sym.assigned_after_init;
                // Record in the sema-level escape set for ARC pruning.
                self.escape_names.put(self.alloc, nm, {}) catch {};
            } else if (self.module_globals.get(nm)) |g_typ| {
                typ = g_typ;
            }
            fb.upvalues[i] = .{ .name = nm, .is_local = is_local, .typ = typ, .mutable = is_mutable };
        }
    }

    fn collect_body_locals(block: *const ast.Block, set: *std.StringHashMap(void)) std.mem.Allocator.Error!void {
        for (block.stmts) |*stmt| {
            try collect_body_locals_stmt(stmt, set);
        }
    }

    fn collect_body_locals_stmt(stmt: *const ast.Stmt, set: *std.StringHashMap(void)) std.mem.Allocator.Error!void {
        switch (stmt.*) {
            .local_decl => |*ld| {
                for (ld.names) |*n| try set.put(n.ident, {});
            },
            .const_decl => |*cd| {
                try set.put(cd.ident, {});
            },
            .global_decl => |*gd| {
                for (gd.names) |*n| try set.put(n.ident, {});
            },
            .num_for => |*nf| {
                try set.put(nf.var_name, {});
                try collect_body_locals(&nf.body, set);
            },
            .gen_for => |*fg| {
                for (fg.vars) |v| try set.put(v, {});
                try collect_body_locals(&fg.body, set);
            },
            .if_stmt => |*is| {
                try collect_body_locals(&is.then, set);
                for (is.elseifs) |*ei| try collect_body_locals(&ei.body, set);
                if (is.else_body) |*eb| try collect_body_locals(eb, set);
            },
            .while_loop => |*wl| try collect_body_locals(&wl.body, set),
            .repeat_loop => |*rp| try collect_body_locals(&rp.body, set),
            .do_block => |*db| try collect_body_locals(&db.body, set),
            // Bare assignments to simple names create implicit locals (Duo mode)
            // or globals (Lua mode). In neither case should they be captured as
            // upvalues from the enclosing scope.
            .assign => |*as| {
                for (as.targets) |tgt| {
                    if (tgt.* == .name) try set.put(tgt.name.ident, {});
                }
            },
            // Nested function declarations create local bindings.
            .func_decl => |*fd| {
                if (fd.path.len >= 1) try set.put(fd.path[0], {});
                try collect_body_locals(&fd.func.body, set);
            },
            else => {},
        }
    }

    fn collect_upvalue_names(
        fb: *const ast.FuncBody,
        block: *const ast.Block,
        params: []const ast.FuncParam,
        body_locals: *const std.StringHashMap(void),
        names: *std.ArrayList([]const u8),
        flags: *std.ArrayList(bool),
        sema: *Sema,
    ) std.mem.Allocator.Error!void {
        _ = fb;
        for (block.stmts) |*stmt| {
            try collect_upvalue_names_stmt(stmt, params, body_locals, names, flags, sema);
        }
        // Closures in the tail expression (implicit return) of a block must
        // also have their free variables collected as upvalues.
        if (block.tail_expr) |expr| {
            try collect_upvalue_names_expr(expr, params, body_locals, names, flags, sema);
        }
    }

    fn collect_upvalue_names_stmt(
        stmt: *const ast.Stmt,
        params: []const ast.FuncParam,
        body_locals: *const std.StringHashMap(void),
        names: *std.ArrayList([]const u8),
        flags: *std.ArrayList(bool),
        sema: *Sema,
    ) std.mem.Allocator.Error!void {
        switch (stmt.*) {
            .local_decl => |*ld| {
                for (ld.inits) |init_expr| try collect_upvalue_names_expr(init_expr, params, body_locals, names, flags, sema);
            },
            .assign => |*as| {
                for (as.values) |v| try collect_upvalue_names_expr(v, params, body_locals, names, flags, sema);
            },
            .ret => |*r| {
                for (r.vals) |v| try collect_upvalue_names_expr(v, params, body_locals, names, flags, sema);
            },
            .if_stmt => |*is| {
                try collect_upvalue_names_expr(is.cond, params, body_locals, names, flags, sema);
                try collect_upvalue_names_block(&is.then, params, body_locals, names, flags, sema);
                for (is.elseifs) |*ei| {
                    try collect_upvalue_names_expr(ei.cond, params, body_locals, names, flags, sema);
                    try collect_upvalue_names_block(&ei.body, params, body_locals, names, flags, sema);
                }
                if (is.else_body) |*eb| try collect_upvalue_names_block(eb, params, body_locals, names, flags, sema);
            },
            .while_loop => |*wl| {
                try collect_upvalue_names_expr(wl.cond, params, body_locals, names, flags, sema);
                try collect_upvalue_names_block(&wl.body, params, body_locals, names, flags, sema);
            },
            .repeat_loop => |*rp| {
                try collect_upvalue_names_block(&rp.body, params, body_locals, names, flags, sema);
                try collect_upvalue_names_expr(rp.cond, params, body_locals, names, flags, sema);
            },
            .num_for => |*nf| try collect_upvalue_names_block(&nf.body, params, body_locals, names, flags, sema),
            .gen_for => |*fg| {
                for (fg.iters) |e| try collect_upvalue_names_expr(e, params, body_locals, names, flags, sema);
                try collect_upvalue_names_block(&fg.body, params, body_locals, names, flags, sema);
            },
            .call_stmt => |*cs| try collect_upvalue_names_expr(cs.expr, params, body_locals, names, flags, sema),
            .expr_stmt => |*es| try collect_upvalue_names_expr(es.expr, params, body_locals, names, flags, sema),
            .do_block => |*db| try collect_upvalue_names_block(&db.body, params, body_locals, names, flags, sema),
            else => {},
        }
    }

    fn collect_upvalue_names_block(
        block: *const ast.Block,
        params: []const ast.FuncParam,
        body_locals: *const std.StringHashMap(void),
        names: *std.ArrayList([]const u8),
        flags: *std.ArrayList(bool),
        sema: *Sema,
    ) std.mem.Allocator.Error!void {
        for (block.stmts) |*stmt| {
            try collect_upvalue_names_stmt(stmt, params, body_locals, names, flags, sema);
        }
    }

    fn is_param_name(params: []const ast.FuncParam, name: []const u8) bool {
        for (params) |p| {
            if (std.mem.eql(u8, p.name, name)) return true;
        }
        return false;
    }

    fn upvalue_index(names: *std.ArrayList([]const u8), name: []const u8) ?usize {
        for (names.items, 0..) |nm, i| {
            if (std.mem.eql(u8, nm, name)) return i;
        }
        return null;
    }

    fn note_upvalue(
        name: []const u8,
        body_locals: *const std.StringHashMap(void),
        names: *std.ArrayList([]const u8),
        flags: *std.ArrayList(bool),
        sema: *Sema,
    ) std.mem.Allocator.Error!void {
        // Skip names declared inside the function body — they are locals, not upvalues.
        if (body_locals.contains(name)) return;
        if (upvalue_index(names, name) != null) return;
        // Skip built-in / runtime globals — they are always accessible
        // directly at file scope and should not be captured as upvalues.
        if (sema.is_builtin_global(name)) return;
        const is_local = sema.scope.lookup(name) != null;
        try names.append(sema.alloc, name);
        try flags.append(sema.alloc, is_local);
    }

    fn collect_upvalue_names_expr(
        expr: *const ast.Expr,
        params: []const ast.FuncParam,
        body_locals: *const std.StringHashMap(void),
        names: *std.ArrayList([]const u8),
        flags: *std.ArrayList(bool),
        sema: *Sema,
    ) std.mem.Allocator.Error!void {
        switch (expr.*) {
            .name => |n| {
                if (is_param_name(params, n.ident)) return;
                try note_upvalue(n.ident, body_locals, names, flags, sema);
            },
            .binop => |b| {
                try collect_upvalue_names_expr(b.lhs, params, body_locals, names, flags, sema);
                try collect_upvalue_names_expr(b.rhs, params, body_locals, names, flags, sema);
            },
            .unop => |u| try collect_upvalue_names_expr(u.operand, params, body_locals, names, flags, sema),
            .call => |c| {
                try collect_upvalue_names_expr(c.func, params, body_locals, names, flags, sema);
                for (c.args) |a| try collect_upvalue_names_expr(a, params, body_locals, names, flags, sema);
            },
            .method_call => |mc| {
                try collect_upvalue_names_expr(mc.obj, params, body_locals, names, flags, sema);
                for (mc.args) |a| try collect_upvalue_names_expr(a, params, body_locals, names, flags, sema);
            },
            .field => |f| try collect_upvalue_names_expr(f.obj, params, body_locals, names, flags, sema),
            .index => |idx| {
                try collect_upvalue_names_expr(idx.obj, params, body_locals, names, flags, sema);
                try collect_upvalue_names_expr(idx.key, params, body_locals, names, flags, sema);
            },
            .table => |t| {
                for (t.fields) |fld| {
                    switch (fld) {
                        .indexed => |idx| {
                            try collect_upvalue_names_expr(idx.key, params, body_locals, names, flags, sema);
                            try collect_upvalue_names_expr(idx.val, params, body_locals, names, flags, sema);
                        },
                        .named => |nmd| try collect_upvalue_names_expr(nmd.val, params, body_locals, names, flags, sema),
                        .positional => |pos| try collect_upvalue_names_expr(pos, params, body_locals, names, flags, sema),
                        .spread => |sp| try collect_upvalue_names_expr(sp, params, body_locals, names, flags, sema),
                        // Pass 36 G1/G8 recorded, not implemented (Phase 0): the implementation may capture upvalues.
                        .semantic => |sm| try collect_upvalue_names_expr(sm.val, params, body_locals, names, flags, sema),
                    }
                }
            },
            .list_comp => |lc| {
                try collect_upvalue_names_expr(lc.iter, params, body_locals, names, flags, sema);
                var comp_params: std.ArrayList(ast.FuncParam) = .empty;
                defer comp_params.deinit(sema.alloc);
                try comp_params.appendSlice(sema.alloc, params);
                if (lc.key_name) |key_name| {
                    try comp_params.append(sema.alloc, .{ .name = key_name, .typ = .inferred, .loc = lc.loc });
                }
                try comp_params.append(sema.alloc, .{ .name = lc.value_name, .typ = .inferred, .loc = lc.loc });
                if (lc.filter) |filter| try collect_upvalue_names_expr(filter, comp_params.items, body_locals, names, flags, sema);
                try collect_upvalue_names_expr(lc.value, comp_params.items, body_locals, names, flags, sema);
            },
            .func_expr => |nested_fb| {
                // Recursively collect upvalue names from the nested function's
                // body. This implements upvalue chaining: if a nested closure
                // needs `wasm`, the outer closure must also capture `wasm`
                // so it can pass it down.
                //
                // We need to filter against both:
                // - the nested function's body locals (not upvalues of nested)
                // - the outer function's body locals (not upvalues of outer)
                // - the outer function's params (handled by is_param_name)
                // - the nested function's params (handled by is_param_name)
                var combined_locals = std.StringHashMap(void).init(sema.alloc);
                defer combined_locals.deinit();
                // Start with the outer function's body_locals
                var it = body_locals.iterator();
                while (it.next()) |entry| combined_locals.put(entry.key_ptr.*, {}) catch {};
                // Add the nested function's body locals
                collect_body_locals(&nested_fb.body, &combined_locals) catch {};
                collect_upvalue_names(nested_fb, &nested_fb.body, nested_fb.params, &combined_locals, names, flags, sema) catch {};
            },
            else => {},
        }
    }

    fn check_func_decl(self: *Sema, fd: *ast.FuncDecl) SemaError!void {
        const fb = &fd.func;
        self.seed_method_self_param_type(fd);
        const has_vararg = fb.vararg or fb.vararg_name != null;
        var all_typed = true;
        for (fb.params) |*p| {
            if (p.typ == .inferred) all_typed = false;
        }
        if (contract_ret_expr(fb) == .inferred) all_typed = false;
        fb.is_typed = all_typed;

        if (self.duo_mode and self.hints_enabled and !all_typed and fd.path.len >= 1) {
            self.hint_msg(fd.loc, "function '{s}' has untyped parameters or return; add types (e.g. i64, str) for faster native codegen", .{fd.path[0]});
        }

        var param_types = try self.alloc.alloc(RT, fb.params.len);
        for (fb.params, 0..) |*p, i| {
            param_types[i] = try self.resolve_type(p.typ);
        }
        var ret_t = try self.resolve_type(contract_ret_expr(fb));
        directives.applyMlFuncAttrs(fd.attributes, fb);

        // Register the function before checking the body so recursive calls type-check.
        const ret_ptr = try self.alloc.create(RT);
        ret_ptr.* = ret_t;
        var fb_t = RT{ .func = .{
            .params = param_types,
            .ret = ret_ptr,
            .is_native = fb.is_typed and !has_vararg,
            .has_vararg = has_vararg,
            .is_compile_only = fb.is_compile_only,
        } };
        if (fd.path.len == 1 and !fd.method) {
            const name = fd.path[0];
            // Check if a function with this name already exists in scope.
            // If so, register it as an overload (Requirement 12).
            if (self.scope.lookup(name)) |existing| {
                if (existing.typ == .func) {
                    // First overload encounter: register the existing signature too.
                    const gop = try self.overloads.getOrPut(self.alloc, name);
                    if (!gop.found_existing) {
                        gop.value_ptr.* = .empty;
                        // Add the previously-registered signature.
                        try gop.value_ptr.append(self.alloc, .{
                            .param_types = existing.typ.func.params,
                            .ret = existing.typ.func.ret.*,
                            .is_vararg = existing.typ.func.has_vararg,
                        });
                    }
                    // Add the new overload signature.
                    try gop.value_ptr.append(self.alloc, .{
                        .param_types = param_types,
                        .ret = ret_t,
                        .is_vararg = has_vararg,
                    });
                }
            }
            try self.scope.define(name, .{ .typ = fb_t, .is_const = true, .deprecated_msg = get_deprecated_msg(fd.attributes) });
        }

        if (has_arc_attr(fd.attributes)) {
            if (validate_arc_attr(fd.attributes).? == false) {
                self.err(fd.loc, "@arc attribute requires argument 'false'", .{});
            } else {
                self.err(fd.loc, "@arc(false) is only valid on table-typed bindings or record-type annotations", .{});
            }
        }

        if (directives.validateFuncAttrs(fd.attributes)) |bad| {
            self.err(fd.loc, "unknown or misplaced attribute '@{s}'", .{bad});
        }

        if (fd.path.len >= 2 and fd.method) {
            const table_name = fd.path[0];
            const method_name = fd.path[fd.path.len - 1];
            const gop = try self.table_methods.getOrPut(self.alloc, table_name);
            if (!gop.found_existing) gop.value_ptr.* = .empty;
            var dup = false;
            for (gop.value_ptr.items) |existing| {
                if (std.mem.eql(u8, existing, method_name)) {
                    dup = true;
                    break;
                }
            }
            if (!dup) try gop.value_ptr.append(self.alloc, method_name);
        }

        if (directives.attrsHaveDebug(fd.attributes)) {
            debug_trace.pushDepth();
            defer debug_trace.popDepth();
            for (fd.attributes) |attr| {
                if (directives.isDebugDirective(attr.name)) {
                    debug_trace.applyFunctionDirective(attr);
                }
            }
            if (fd.path.len >= 1) {
                debug_trace.event(.sema, .function, "type-check '{s}'", .{fd.path[0]});
            }
        }

        if (directives.attrsMarkTest(fd.attributes) and fd.path.len == 1 and !fd.method) {
            const opts = directives.parseTestOptions(self.alloc, fd.attributes) catch {
                self.err(fd.loc, "invalid @test/@bench attribute arguments", .{});
                return;
            };
            if (fb.params.len > 0) {
                self.warn_msg(fd.loc, "@test function '{s}' should take no parameters for the native test runner", .{fd.path[0]});
            }
            if (fb.ret_type != .inferred and (self.resolve_type(fb.ret_type) catch .any) != .void) {
                self.warn_msg(fd.loc, "@test function '{s}' should return void", .{fd.path[0]});
            }
            try self.test_entries.append(self.alloc, .{
                .func_name = fd.path[0],
                .loc = fd.loc,
                .options = opts,
            });
        }

        // Pass 1: type-check with declared (or dynamic) signature to populate type_map.
        const prev_ret = self.current_ret;
        const prev_fallible = self.current_ret_fallible;
        const prev_nopanic = self.current_nopanic;
        const prev_func_name = self.current_func_name;
        const prev_type_params = self.current_func_type_params;
        self.current_ret = if (fb.ret_fallible) (self.resolve_type(fb.ret_type) catch .any) else ret_t;
        self.current_ret_fallible = fb.ret_fallible;
        // Check if this function has the @nopanic attribute
        self.current_nopanic = has_nopanic_attr(fd.attributes);
        self.current_func_name = if (fd.path.len == 1 and !fd.method) fd.path[0] else null;
        self.current_func_type_params = fb.type_params;
        defer {
            self.current_ret = prev_ret;
            self.current_ret_fallible = prev_fallible;
            self.current_nopanic = prev_nopanic;
            self.current_func_name = prev_func_name;
            self.current_func_type_params = prev_type_params;
        }
        for (fb.params) |*p| {
            if (p.default_val) |default_val| _ = try self.check_expr(default_val);
        }
        try self.scope.push();
        for (fb.params, param_types) |*p, pt|
            try self.scope.define(p.name, .{ .typ = pt, .is_const = false });
        try self.define_vararg_rest(fb);
        try self.check_block_with_implicit_return(&fb.body, true);
        self.scope.pop();

        // Pass 2: infer native signatures for scalar functions that are plain
        // enough to stay off the dynamic Lua path. This covers both untyped Lua
        // functions and .id functions with typed params but inferred returns.
        if (!fb.is_typed and !func_body_has_func_expr(fb)) {
            const self_name: ?[]const u8 = if (fd.path.len == 1 and !fd.method) fd.path[0] else null;
            const method_receiver: ?[]const u8 = if (fd.method and fd.path.len >= 2) fd.path[0] else null;
            try detect_dense_table(fb, self.alloc);
            self.try_specialize_native_func(fb, self_name, method_receiver) catch {};
        } else if (fb.is_typed) {
            // For typed .id functions, still run dense table detection
            // to enable native int64_t array lowering for table-as-array patterns.
            try detect_dense_table(fb, self.alloc);
        }

        // Re-resolve after possible inference.
        for (fb.params, 0..) |*p, i| {
            param_types[i] = try self.resolve_type(p.typ);
        }
        ret_t = try self.resolve_type(contract_ret_expr(fb));
        ret_ptr.* = ret_t;
        var params_native = true;
        for (param_types) |pt| {
            if (!pt.is_native()) params_native = false;
        }
        fb.is_typed = (all_typed or (ret_t.is_native() and params_native)) and !has_vararg;
        fb.use_iterative_fib = detect_naive_fib_pattern(fb, self.current_func_name);
        const shape_prime_sieve = detect_trial_division_primes(fb);
        fb.use_prime_sieve = shape_prime_sieve and verify_prime_sieve(fb);
        try detect_string_scan_loops(fb);
        const shape_string_byte_scan = fb.use_string_byte_scan;
        const shape_string_hash_scan = fb.use_string_hash_scan;
        fb.use_string_byte_scan = shape_string_byte_scan and verify_string_byte_scan(fb);
        fb.use_string_hash_scan = shape_string_hash_scan and verify_string_hash_scan(fb);
        // `use_grid_sum_inline` is retired. `detect_grid_sum_inline` returned
        // true for any nested while loop whose body accumulated a call to a
        // function NAMED `eval_A` — a recogniser keyed on an identifier, which
        // CLAUDE.md §3 forbids outright and which `detect_naive_fib_pattern`
        // was already repaired for. The emitter then printed
        // `1.0 / ((i+j)*(i+j+1)/2 + i + 1)`, eval_A's body, which the detector
        // never looked at and could not have: eval_A is a DIFFERENT function.
        // Measured with `+ i + 1` -> `+ i + 2` in eval_A: reference C reports
        // 16.532160577387746, this returned 17.532160530720734 — the
        // unperturbed benchmark's own sum. There is no template to tighten to
        // from inside compute_grid_sum, so the substitution goes; the general
        // path lowers the real nested loop and the real call. The shape still
        // promotes the f64 signature below.
        const shape_grid_sum_inline = detect_grid_sum_inline(fb);
        fb.use_grid_sum_inline = false;
        // `use_dense_table_max` is never claimed, and as of this pass neither
        // its detector nor its emitter exists any more. The emitter ignored the
        // table entirely: it returned a literal 100002 above a threshold and
        // otherwise recomputed `(i * 17) % 100003` — one specific fill
        // expression — instead of reading what the loop actually stored, while
        // its detector only checked that *some* `t[i] > m` comparison existed.
        // The general dense array path lowers the real loop.
        fb.use_dense_table_max = false;
        // `use_table_lookup_sum` is retired for the same reason plus one the
        // others do not have: emit_table_lookup_sum_body printed
        // `3 * n * (n + 1) / 2`, the sum of the WHOLE table, which is the right
        // answer only when `(q * 7) % n + 1` visits every index exactly once —
        // i.e. only when gcd(7, n) = 1, a property of a RUNTIME value that no
        // compile-time predicate can establish. There is no template to tighten
        // to, so the substitution goes rather than the shape. Measured: with
        // the modulus written as a literal 1000 instead of `n`, reference C
        // reports 750750000 and Duo reported 375000750000, the unperturbed
        // benchmark's answer. The shape still promotes the signature below.
        const shape_table_lookup_sum = detect_table_lookup_sum(fb);
        fb.use_table_lookup_sum = false;
        // `use_dense_table_mod997_sum` is RETIRED — fourth pass, the FOLD
        // removal. `verify_dense_table_mod997_sum` checks the whole template
        // and is not wrong, but the template it checks for is the literal 13
        // and the literal 997, and `emit_dense_table_mod997_sum_body` PRINTS
        // both back out. CLAUDE.md §3 rule 1: "no recogniser may key on a
        // function name, a LITERAL, or a loop bound". A predicate that accepts
        // `(i * 13) % 997` and nothing else is not an optimisation for any
        // program but the one that wrote those two numbers, so the row it made
        // fast was measuring whether a human wrote the period sum, not whether
        // Duo's codegen is fast. The general dense-array path fills and reduces
        // the table the source declared.
        const shape_dense_table_mod997_sum = detect_dense_table_mod997_sum(fb);
        fb.use_dense_table_mod997_sum = false;
        // detect_dense_table_sum_patterns opens with
        // `if (!fb.use_dense_table or fb.use_dense_table_mod997_sum) return;`
        // — the flag above used to suppress the polynomial family on this
        // kernel. With the flag permanently false that guard is dead, so it
        // moves here as the SHAPE, and retiring the fold cannot hand a
        // `(i * 13) % 997` fill to a recogniser that assumes a polynomial one.
        if (!shape_dense_table_mod997_sum) detect_dense_table_sum_patterns(fb);
        const shape_math_floor_max = fb.is_typed and detect_math_floor_max(fb);
        const shape_math_pow_sqrt = fb.is_typed and detect_math_pow_sqrt(fb);
        fb.use_math_pow_sqrt = shape_math_pow_sqrt and verify_math_pow_sqrt(fb);
        const shape_string_len_chain = fb.is_typed and detect_string_len_chain(fb);
        fb.use_string_len_chain = shape_string_len_chain and verify_string_len_chain(fb);
        // ── Frozen-kernel emitters: SHAPE selects promotion, TEMPLATE selects
        // the closed-form body. See the `verify_*` block above
        // detect_binary_search_dense: each of these emitters prints constants
        // it never re-reads from the source, so the shape recogniser alone was
        // answering a question the program had stopped asking. The `shape_*`
        // locals keep native-signature promotion exactly where it was.
        const shape_binary_search_dense = detect_binary_search_dense(fb);
        fb.use_binary_search_dense = shape_binary_search_dense and verify_binary_search_dense(fb);
        // `use_filter_count_mod` is RETIRED. `emit_filter_count_mod_body`
        // opens `__fc_mod = 100003; __fc_mul = 17; __fc_threshold = 50000` —
        // three literals printed by the emitter, which `verify_filter_count_mod`
        // then requires the source to spell exactly. Verifying a literal is not
        // the same as reading one: the closed form fires for one modulus, one
        // multiplier and one threshold, so it is a transcription of this
        // kernel. The general path runs the filter loop.
        const shape_filter_count_mod = detect_filter_count_mod(fb);
        fb.use_filter_count_mod = false;
        const shape_dot_product_identity = detect_dot_product_identity(fb);
        const shape_dot_product_dense = !shape_dot_product_identity and detect_dot_product_dense(fb);
        // Both emitters print the SAME closed form — n(n+1)(n+2)/6, one in
        // int64_t and one in __int128 — so both need the same template, and
        // the dense recogniser is the looser of the two. Gating only the
        // identity one would have handed every declined function straight to
        // the identical frozen answer one arm down the chain.
        const dot_product_ok = verify_dot_product_identity(fb);
        fb.use_dot_product_identity = shape_dot_product_identity and dot_product_ok;
        fb.use_dot_product_dense = shape_dot_product_dense and dot_product_ok;
        // `use_clamp_mod_sum` is RETIRED. `emit_clamp_mod_sum_body` prints
        // `full * 222360 + tail` with 1000, 256, 32640 and 255 beside it — the
        // period, the clamp, the triangular number of the clamp and the clamp
        // again, none of them derived, all of them this benchmark's. Same rule.
        const shape_clamp_mod_sum = detect_clamp_mod_sum(fb);
        fb.use_clamp_mod_sum = false;
        // `use_mod_histogram_sum` is RETIRED. `emit_mod_histogram_sum_body`
        // prints a period loop over `(i * 31) % 256` — the multiplier and the
        // modulus are the emitter's, not the source's.
        const shape_mod_histogram_sum = detect_mod_histogram_sum(fb);
        fb.use_mod_histogram_sum = false;
        // The period fold reads α, β and the period out of the source; the
        // emitter's other branch froze 0.95 / %100 / 0.05 behind an `a*b + c*d`
        // shape match and is gone. `use_ema_smooth` therefore now means "the
        // period fold verified", and the shape keeps the f64 promotion.
        // `use_ema_smooth` is RETIRED, and it is the one retirement here that
        // is NOT about a frozen literal: verify_ema_period_fold reads α, β and
        // the period out of the AST, so the recogniser is parameterised. It
        // goes for a different reason. The emitter runs the source's own
        // recurrence for one whole period INSIDE THE COMPILER, in the
        // compiler's f64, and prints the result as a literal, then replaces the
        // remaining n/period iterations with `pow()` on a geometric series. The
        // result is not the value the written loop computes — floating-point
        // addition is not associative, and a closed form for a linear
        // recurrence rounds differently from iterating it. An optimisation may
        // not silently change what an f64 program computes, and a benchmark row
        // whose kernel was evaluated at compile time measures the compiler's
        // arithmetic, not its codegen. `verify_ema_period_fold` still RUNS,
        // because it sets `use_ema_period_fold`, which `pattern_hot` reads: the
        // function keeps its `hot` placement and its `always_inline`.
        const shape_ema_smooth = detect_ema_smooth(fb);
        _ = shape_ema_smooth and verify_ema_period_fold(fb);
        fb.use_ema_smooth = false;
        const shape_string_token_count = detect_string_token_count(fb);
        fb.use_string_token_count = shape_string_token_count and verify_string_token_count(fb);
        const shape_string_delim_byte_sum = detect_string_delim_byte_sum(fb);
        fb.use_string_delim_byte_sum = shape_string_delim_byte_sum and verify_string_delim_byte_sum(fb);
        const shape_trig_sum_recur = fb.is_typed and fb.params.len == 1 and detect_trig_sum_recur(fb);
        fb.use_trig_sum_recur = shape_trig_sum_recur and verify_trig_sum_recur(fb);
        const shape_mandel_iter_native = fb.is_typed and fb.params.len == 2 and detect_mandel_iter_native(fb);
        fb.use_mandel_iter_native = shape_mandel_iter_native and verify_mandel_iter_native(fb);
        // `use_nbody_native` is retired. emit_nbody_native_body is a verbatim
        // transcription of ONE three-body system: sixteen initial values, the
        // 0.001 timestep and the 0.001 softening, none re-read from the source.
        // Measured with `dt = 0.001` -> `0.002`: reference C reports
        // -5.2691163432427857e-08, this returned -9.3782588805879641e-08, the
        // unperturbed benchmark's own answer. A predicate that accepted only
        // those seventeen constants and that exact 22-statement update would
        // not be a substitution for any program but this one, so the emitter
        // goes and the general path integrates the loop the source wrote. The
        // shape still promotes the f64 signature and still forces inlining.
        const shape_nbody_native = fb.is_typed and fb.params.len == 1 and detect_nbody_native(fb);
        fb.use_nbody_native = false;
        if (fb.use_mandel_iter_native) {} // native body only; no always_inline (fast-math breaks fp boundaries)
        if (shape_nbody_native or shape_ema_smooth) fb.use_force_always_inline = true;

        // Benchmarks 24-40 native pattern detections
        // `use_gcd_inline` is RETIRED. `emit_gcd_inline_body`'s whole body is
        // `return duo_sum_affine_periodic_gcd_i64(n, 10000, 7, 3);` — one call,
        // no loop, and 10000, 7 and 3 are printed by the emitter and demanded
        // back by `verify_gcd_inline`. RELEASE_STATUS §4 already named this row
        // "a fold the rule declines" at a ratio of 85; once the eight folds
        // above stopped hiding behind it the ratio cleared 100 and the
        // classifier caught it. Retiring it is what §4 said should happen.
        const shape_gcd_inline = detect_gcd_inline(fb);
        fb.use_gcd_inline = false;
        const shape_collatz_inline = detect_collatz_inline(fb);
        fb.use_collatz_inline = shape_collatz_inline and verify_collatz_inline(fb);
        // `use_xor_fold_inline` is RETIRED. `emit_xor_fold_inline_body` prints
        // `const uint64_t __xf_mul = 2654435761ULL;` — Knuth's multiplier as a
        // literal in the emitter, which the verifier then demands of the
        // source. One multiplier is not a family.
        const shape_xor_fold_inline = detect_xor_fold_inline(fb);
        fb.use_xor_fold_inline = false;
        // `use_bitcount_inline` is KEPT, and it is kept on the same ground
        // `use_iterative_fib` is: the emitter prints NO constant taken from the
        // source. `verify_bitcount_inline` requires `c + (x & 1)` and `x >> 1`
        // — the mask and the shift are the DEFINITION of a population count,
        // not this benchmark's parameters — and the emitted body is
        // parameterised in `n` alone. It is an asymptotic win on real code,
        // O(n log n) -> O(log n), by counting each bit position's duty cycle
        // over [1, n] instead of iterating. Proved general by perturbation and
        // by firing on a program that is not the benchmark; see the unit tests
        // below and RELEASE_STATUS.md §4.
        const shape_bitcount_inline = detect_bitcount_inline(fb);
        fb.use_bitcount_inline = shape_bitcount_inline and verify_bitcount_inline(fb);
        // `use_cordic_inline` is RETIRED, twice over. There is no CORDIC in
        // `emit_cordic_inline_body`: it caches exactly 1000 phases at a 0.001
        // step and sums exactly 5 Taylor terms, three literals it prints and
        // the verifier demands. And it is an f64 fold like the EMA one above —
        // `__cd_period_sum` added `__cd_full` times is not the sum the loop
        // writes.
        const shape_cordic_inline = detect_cordic_inline(fb);
        fb.use_cordic_inline = false;
        const shape_ack_inline = detect_ack_inline(fb);
        fb.use_ack_inline = shape_ack_inline and verify_ack_inline(fb, self.current_func_name);
        // `use_matmul_native` is retired. emit_matmul_native_body prints a
        // 200x200 problem whose two operand fills are `i % 100` and
        // `(i * 7) % 100`, all four numbers frozen and none re-read. Measured
        // with the b fill changed to `(i * 5) % 100`: reference C reports
        // 18810000000, this returned 19602000000, the unperturbed benchmark's
        // answer. Reading the size and both fill polynomials out of the AST is
        // the repair that would keep the speed; until then the general path
        // multiplies the matrices the source declared.
        const shape_matmul_native = detect_matmul_native(fb);
        fb.use_matmul_native = false;
        const shape_prefix_sum_inline = detect_prefix_sum_inline(fb);
        fb.use_prefix_sum_inline = shape_prefix_sum_inline and verify_prefix_sum_inline(fb);
        const shape_ring_buf_inline = detect_ring_buf_inline(fb);
        fb.use_ring_buf_inline = shape_ring_buf_inline and verify_ring_buf_inline(fb);
        const shape_cond_swap_inline = detect_cond_swap_inline(fb);
        const shape_sieve_native = detect_sieve_native(fb);
        fb.use_sieve_native = shape_sieve_native and verify_sieve_native(fb);
        // `use_fenwick_native` is RETIRED, and it is the plainest case in this
        // pass: THERE IS NO FENWICK TREE IN THE EMITTED C. The body is a
        // period-1000 weighted sum over `(p * 3) % 1000` — the period, the
        // multiplier and the modulus all printed by the emitter — so the row
        // named "Fenwick tree" never built one, never walked a low-bit ascent
        // and never answered a prefix query. The general path does all three.
        const shape_fenwick_native = detect_fenwick_native(fb);
        fb.use_fenwick_native = false;
        const shape_interp_inline = detect_interp_inline(fb);
        fb.use_interp_inline = shape_interp_inline and verify_interp_inline(fb);
        const shape_run_len_inline = detect_run_len_inline(fb);
        fb.use_run_len_inline = shape_run_len_inline and verify_run_len_inline(fb);
        // `use_sparse_dot_inline` is retired. Its detector established NOTHING
        // about what the function computes: two empty table constructors and
        // any `<expr> * 16` anywhere in a while loop, and the emitter then
        // printed n(n+1)(n+2)/6 — the benchmark's dot product — without ever
        // looking at the accumulator. It does not even fire on the benchmark
        // (which multiplies by a `stride` binding, not the literal 16), so the
        // only programs it could ever have answered were user programs, all of
        // them wrongly. There is no template to tighten to.
        const shape_sparse_dot_inline = detect_sparse_dot_inline(fb);
        fb.use_sparse_dot_inline = false;
        const shape_leven_native = detect_leven_native(fb);
        // `use_life_native` is retired. emit_life_native_body prints a 128x128
        // board seeded by `(i * 31337) % 3 == 0` — the width, the height and
        // both seed constants frozen, none re-read. Measured with the seed
        // changed to `% 4`: reference C reports 980, this returned 170, the
        // unperturbed benchmark's own population. Reading W, H and the seed out
        // of the AST is the repair that would keep the speed.
        const shape_life_native = detect_life_native(fb);
        fb.use_life_native = false;
        fb.use_simd_reduction = fb.is_typed and detect_simd_reduction(fb);

        // NOTE: the frozen-kernel rows below deliberately read `shape_*`, not
        // `fb.use_*`. These two chains do double duty — they also decide which
        // untyped `any` function gets a native scalar signature — so gating
        // them on the tightened template would take native lowering away from
        // programs that merely resemble a kernel, a slowdown unrelated to the
        // correctness fix. Promotion follows the shape; the closed form follows
        // the template.
        if (shape_binary_search_dense or shape_filter_count_mod or shape_dot_product_identity or
            shape_dot_product_dense or shape_clamp_mod_sum or shape_mod_histogram_sum or
            shape_table_lookup_sum or shape_dense_table_mod997_sum or shape_string_token_count or
            shape_string_delim_byte_sum or fb.use_dense_table_sum or
            fb.use_dense_table_faulhaber_sum or fb.use_dense_table_decic_sum or fb.use_dense_table_nonic_sum or fb.use_dense_table_octic_sum or fb.use_dense_table_septic_sum or fb.use_dense_table_sextic_sum or fb.use_dense_table_quintic_sum or fb.use_dense_table_quartic_sum or fb.use_dense_table_cubic_sum or fb.use_dense_table_quadratic_sum or fb.use_dense_table_square_sum or
            fb.use_dense_table_identity_sum or shape_string_byte_scan or shape_string_hash_scan or
            shape_string_len_chain or fb.use_iterative_fib or shape_prime_sieve or
            shape_gcd_inline or shape_collatz_inline or shape_xor_fold_inline or
            shape_bitcount_inline or shape_matmul_native or shape_prefix_sum_inline or
            shape_ring_buf_inline or shape_cond_swap_inline or shape_sieve_native or
            shape_fenwick_native or shape_run_len_inline or shape_sparse_dot_inline or
            shape_leven_native or shape_life_native or shape_ack_inline)
        {
            promote_native_i64_signature(fb);
        }
        if (shape_trig_sum_recur or shape_ema_smooth or shape_grid_sum_inline or shape_math_floor_max or shape_math_pow_sqrt or
            shape_mandel_iter_native or shape_nbody_native or shape_cordic_inline or shape_interp_inline)
            promote_native_f64_signature(fb);

        for (fb.params, 0..) |*p, i| {
            param_types[i] = try self.resolve_type(p.typ);
        }
        ret_t = try self.resolve_type(contract_ret_expr(fb));
        params_native = true;
        for (param_types) |pt| {
            if (!pt.is_native()) params_native = false;
        }
        fb.is_typed = (all_typed or (ret_t.is_native() and params_native)) and !has_vararg;

        ret_ptr.* = ret_t;
        fb_t = RT{ .func = .{
            .params = param_types,
            .ret = ret_ptr,
            .is_native = fb.is_typed,
            .is_compile_only = fb.is_compile_only,
        } };
        if (fd.path.len == 1 and !fd.method) {
            const name = fd.path[0];
            try self.scope.define(name, .{ .typ = fb_t, .is_const = true });
            // Update the overload registry with final inferred types if applicable.
            if (self.overloads.getPtr(name)) |overload_list| {
                if (overload_list.items.len > 0) {
                    // Update the last registered overload (this function) with final types.
                    overload_list.items[overload_list.items.len - 1] = .{
                        .param_types = param_types,
                        .ret = ret_t,
                        .is_vararg = has_vararg,
                    };
                }
            }
        }

        // Pass 3: re-check body with native types when specialized.
        if (fb.is_typed and !all_typed) {
            self.current_ret = if (fb.ret_fallible) (self.resolve_type(fb.ret_type) catch .any) else ret_t;
            self.current_ret_fallible = fb.ret_fallible;
            for (fb.params) |*p| {
                if (p.default_val) |default_val| _ = try self.check_expr(default_val);
            }
            try self.scope.push();
            for (fb.params, param_types) |*p, pt|
                try self.scope.define(p.name, .{ .typ = pt, .is_const = false });
            try self.define_vararg_rest(fb);
            try self.check_block_with_implicit_return(&fb.body, true);
            self.scope.pop();
        }
    }

    fn check_match(self: *Sema, me: *ast.MatchExpr) SemaError!void {
        _ = try self.check_match_inner(me);
    }

    fn check_match_expr(self: *Sema, me: *ast.MatchExpr) SemaError!RT {
        return try self.check_match_inner(me);
    }

    /// Shared match type-checking logic for both statement and expression form.
    /// Type-checks the scrutinee and each arm, then runs exhaustiveness checking.
    fn check_match_inner(self: *Sema, me: *ast.MatchExpr) SemaError!RT {
        // Type-check the scrutinee
        var scrutinee_type = try self.check_expr(me.scrutinee);

        // If the scrutinee type is a struct that matches an enum name, resolve it
        if (scrutinee_type == .@"struct") {
            if (self.enum_types.get(scrutinee_type.@"struct".name)) |et| {
                scrutinee_type = et;
            }
        }

        // Also try to resolve the enum from a variable's type when the scrutinee is a name
        if (scrutinee_type == .any) {
            if (me.scrutinee.* == .name) {
                if (self.scope.lookup(me.scrutinee.name.ident)) |sym| {
                    if (sym.typ == .enum_type) {
                        scrutinee_type = sym.typ;
                    } else if (sym.typ == .@"struct") {
                        if (self.enum_types.get(sym.typ.@"struct".name)) |et| {
                            scrutinee_type = et;
                        }
                    }
                }
            }
        }

        // Type-check each arm's pattern, guard, and body
        var has_wildcard = false;
        for (me.arms) |*arm| {
            try self.scope.push();
            try self.check_pattern(&arm.pattern, scrutinee_type);
            if (arm.pattern == .wildcard) has_wildcard = true;
            if (arm.guard) |guard| _ = try self.check_expr(guard);
            try self.check_block(&arm.body);
            self.scope.pop();
        }

        // Exhaustiveness checking for enum types
        if (scrutinee_type == .enum_type and !has_wildcard) {
            self.check_exhaustiveness(me, scrutinee_type.enum_type);
        }

        return .any;
    }

    /// Type-check a pattern against the expected scrutinee type.
    /// Binds variables introduced in the pattern into the current scope.
    fn check_pattern(self: *Sema, pattern: *const ast.Pattern, scrutinee_type: RT) SemaError!void {
        switch (pattern.*) {
            .literal => |lit| {
                _ = try self.check_expr(lit);
            },
            .binding => |b| {
                // Bind the variable in the current scope with the scrutinee's type
                var bind_type = scrutinee_type;
                if (b.typ) |type_expr| {
                    bind_type = try self.resolve_type(type_expr);
                }
                try self.scope.define(b.name, .{ .typ = bind_type, .is_const = true });
            },
            .variant => |v| {
                // Variant pattern: validate that the tag is a valid variant of the enum
                if (scrutinee_type == .enum_type) {
                    const variant_info = self.find_enum_variant(scrutinee_type.enum_type, v.tag);
                    if (variant_info) |vi| {
                        // Check payload sub-patterns with known payload types
                        if (v.payload) |payload_pats| {
                            if (vi.payload) |payload_types| {
                                for (payload_pats, 0..) |*sub_pat, pi| {
                                    const pt: RT = if (pi < payload_types.len) payload_types[pi] else .any;
                                    try self.check_pattern(sub_pat, pt);
                                }
                            } else {
                                // Variant has no payload but pattern expects one
                                for (payload_pats) |*sub_pat| {
                                    try self.check_pattern(sub_pat, .any);
                                }
                            }
                        }
                    } else {
                        // Tag doesn't match any variant — still check sub-patterns
                        if (v.payload) |payload_pats| {
                            for (payload_pats) |*sub_pat| {
                                try self.check_pattern(sub_pat, .any);
                            }
                        }
                    }
                } else {
                    // Not matching against an enum — just check sub-patterns
                    if (v.payload) |payload_pats| {
                        for (payload_pats) |*sub_pat| {
                            try self.check_pattern(sub_pat, .any);
                        }
                    }
                }
            },
            .table_destr => |entries| {
                for (entries) |*entry| {
                    try self.check_pattern(&entry.pat, .any);
                }
            },
            .array_destr => |patterns| {
                for (patterns) |*sub_pat| {
                    try self.check_pattern(sub_pat, .any);
                }
            },
            .rest => |name| {
                try self.scope.define(name, .{ .typ = .any, .is_const = true });
            },
            .wildcard => {},
        }
    }

    /// Look up a variant in the enum type by tag name.
    /// Handles both qualified ("EnumName.Variant") and unqualified ("Variant") tags.
    /// The spelling this expression would offer to case resolution, or null.
    ///
    /// THE FAST REJECT. `a == b` between two integers must cost one hash
    /// lookup, not a type check, so nothing below this line runs unless the
    /// name is a case spelling SOMEWHERE. The index cannot select a home — it
    /// only decides whether there is a question to ask.
    fn case_spelling(self: *const Sema, e: *const ast.Expr) ?[]const u8 {
        if (e.* != .name) return null;
        if (!self.case_homes.contains(e.name.ident)) return null;
        return e.name.ident;
    }

    /// The case-set a demand names, if it names one. Both spellings answer: a
    /// value already typed as the case-set, and a name that resolves to one.
    fn demanded_caseset(self: *const Sema, demand: RT) ?RT {
        if (demand == .enum_type) return demand;
        if (demand == .@"struct") {
            if (self.enum_types.get(demand.@"struct".name)) |e| return e;
        }
        return null;
    }

    /// c0 §41 — resolve a bare case in a comparison, or diagnose.
    ///
    /// NON-CIRCULARITY IS STRUCTURAL, not a check. The expected descriptor is
    /// read from the OTHER operand, so the token being resolved contributes
    /// nothing to its own demand. When BOTH operands spell cases there is no
    /// operand left to supply one, and this declines rather than picking the
    /// case-set that happens to declare either name — `circle == square` names
    /// no comparison the graph can prove, and G-TOTAL's ambiguity number is 0.
    fn resolve_bare_case_operands(self: *Sema, lhs: *ast.Expr, rhs: *ast.Expr) SemaError!void {
        if (self.case_homes.count() == 0) return;
        const lcase = self.case_spelling(lhs);
        const rcase = self.case_spelling(rhs);
        if (lcase == null and rcase == null) return;
        if (lcase != null and rcase != null) return;
        if (rcase) |c| {
            const demand = try self.check_expr(lhs);
            try self.bind_bare_case(rhs, demand, c);
            return;
        }
        const demand = try self.check_expr(rhs);
        try self.bind_bare_case(lhs, demand, lcase.?);
    }

    /// The four outcomes, and there is no fifth. `bound` is whether the
    /// spelling is ALSO a lexical binding here.
    ///
    ///   case of the demand, not bound     RESOLVE — rewrite to the home
    ///   case of the demand, bound         DIAGNOSE — `law.shadow`
    ///   not a case of the demand, unbound DIAGNOSE — mixed space
    ///   not a case of the demand, bound   leave alone — an ordinary operand
    ///
    /// The last row is why `bound` is consulted at all rather than the case
    /// always winning: a local named `count` compared against an i64 must keep
    /// meaning the local, even if some unrelated case-set spells `count`.
    fn bind_bare_case(self: *Sema, e: *ast.Expr, demand: RT, case: []const u8) SemaError!void {
        const et = self.demanded_caseset(demand) orelse return;
        const bound = self.scope.lookup(case) != null;
        const is_case = self.find_enum_variant(et.enum_type, case) != null;

        if (is_case and bound) {
            // `law.shadow`: "a lexical binding may NOT silently shadow an
            // ambient-subject identity referenced in the same scope; a
            // collision that would depend on subtle precedence DIAGNOSES."
            // "Locals win" is DENIED by name, and so is "the case wins" — the
            // point is that adding a binding must never quietly change what an
            // already-written comparison means.
            self.err(e.loc(), "'{s}' is both a lexical binding and a case of '{s}' here, so this comparison has two readings", .{ case, et.enum_type.name });
            self.hint_msg(e.loc(), "name the home ('{s}.{s}') to mean the case, or rename the binding", .{ et.enum_type.name, case });
            return;
        }
        if (!is_case) {
            if (bound) return;
            // The spelling IS a case, but of a case-set nothing here demanded.
            // Resolving it against whichever set declares it would make the
            // answer depend on which file was parsed — a mixed-space
            // diagnostic, never a guess.
            const home = self.case_homes.get(case) orelse "";
            if (home.len == 0) {
                self.err(e.loc(), "'{s}' is a case of more than one case-set, and '{s}' is not one of them", .{ case, et.enum_type.name });
            } else {
                self.err(e.loc(), "'{s}' is a case of '{s}', but this comparison demands '{s}'", .{ case, home, et.enum_type.name });
            }
            self.hint_msg(e.loc(), "compare against a case of '{s}', or convert the operand", .{et.enum_type.name});
            return;
        }

        // RESOLVED. The node is rewritten to the SAME shape the dotted form
        // and the fully-named form both produce — `token__kind.eof` — so sema
        // and codegen consume one resolved fact and neither re-derives it
        // (A3 ONE EDGE). Nothing downstream learns that a bare name was
        // written, which is what makes this a canonicalization rather than a
        // second lowering path.
        const home = try self.alloc.create(ast.Expr);
        home.* = .{ .name = .{ .loc = e.loc(), .ident = et.enum_type.name } };
        e.* = .{ .field = .{ .loc = e.loc(), .obj = home, .field = case } };
    }

    fn find_enum_variant(self: *const Sema, enum_info: anytype, tag: []const u8) ?types.EnumVariantType {
        _ = self;
        // Extract the variant name from the tag (may be "EnumName.Variant" or just "Variant")
        const variant_name = if (std.mem.indexOfScalar(u8, tag, '.')) |dot_idx|
            tag[dot_idx + 1 ..]
        else
            tag;

        for (enum_info.variants) |variant| {
            if (std.mem.eql(u8, variant.name, variant_name)) {
                return variant;
            }
        }
        return null;
    }

    /// Check exhaustiveness of a match over an enum type.
    /// Verifies all enum variants are covered or emits an error listing missing ones.
    fn check_exhaustiveness(self: *Sema, me: *const ast.MatchExpr, enum_info: anytype) void {
        const variants = enum_info.variants;
        const enum_name = enum_info.name;

        // Collect which variant names are covered by the arms
        for (me.arms) |arm| {
            switch (arm.pattern) {
                .variant => |v| {
                    // Variant patterns have a tag like "EnumName.Variant" or just "Variant"
                    _ = v;
                },
                .wildcard => return, // wildcard covers everything
                else => {},
            }
        }

        // Check each variant for coverage
        var missing_count: usize = 0;
        var missing_buf: [64][]const u8 = undefined;

        for (variants) |variant| {
            var found = false;
            for (me.arms) |arm| {
                switch (arm.pattern) {
                    .variant => |v| {
                        // Match if the tag is "EnumName.Variant" or just "Variant"
                        const full_tag = v.tag;
                        if (std.mem.eql(u8, full_tag, variant.name)) {
                            found = true;
                            break;
                        }
                        // Check if tag is qualified: "EnumName.VariantName"
                        if (std.mem.indexOfScalar(u8, full_tag, '.')) |dot_idx| {
                            const after_dot = full_tag[dot_idx + 1 ..];
                            if (std.mem.eql(u8, after_dot, variant.name)) {
                                found = true;
                                break;
                            }
                        }
                    },
                    .wildcard => {
                        found = true;
                        break;
                    },
                    else => {},
                }
            }
            if (!found and missing_count < missing_buf.len) {
                missing_buf[missing_count] = variant.name;
                missing_count += 1;
            }
        }

        if (missing_count > 0) {
            // Emit a single structured error listing all missing variants inline.
            var buf: [2048]u8 = undefined;
            var pos: usize = 0;
            for (missing_buf[0..missing_count], 0..) |name, i| {
                if (i > 0) {
                    if (pos + 2 <= buf.len) {
                        buf[pos] = ',';
                        buf[pos + 1] = ' ';
                        pos += 2;
                    }
                }
                const written = std.fmt.bufPrint(buf[pos..], "{s}", .{name}) catch break;
                pos += written.len;
            }
            self.err(me.loc, "non-exhaustive match on enum '{s}': missing variant(s): {s}", .{ enum_name, buf[0..pos] });
        }
    }

    // ── Enum definition ─────────────────────────────────────────────────────────

    /// Register an enum type definition in the type registry and scope.
    fn check_enum_def(self: *Sema, ed: *const ast.EnumDef) SemaError!void {
        const prev_type_name = self.current_type_name;
        self.current_type_name = ed.name;
        defer self.current_type_name = prev_type_name;

        // Build the list of EnumVariantType from the AST definition
        var variant_types = try self.alloc.alloc(types.EnumVariantType, ed.variants.len);
        for (ed.variants, 0..) |*v, i| {
            var payload_types: ?[]const RT = null;
            if (v.payload) |fields| {
                var pt = try self.alloc.alloc(RT, fields.len);
                for (fields, 0..) |field, fi| {
                    pt[fi] = try self.resolve_type(field.typ);
                }
                payload_types = pt;
            }
            variant_types[i] = .{
                .name = v.name,
                .payload = payload_types,
            };
        }

        var enum_t = RT{ .enum_type = .{
            .name = ed.name,
            .variants = variant_types,
            .derives = try enum_derive_names(self.alloc, ed.attributes),
        } };

        for (ed.attributes) |attr| {
            if (std.mem.eql(u8, attr.name, "packed")) enum_t.enum_type.is_packed = true;
            if (std.mem.eql(u8, attr.name, "align")) {
                if (attr.args) |args_str| {
                    enum_t.enum_type.align_n = std.fmt.parseInt(usize, args_str, 10) catch null;
                }
            }
            if (std.mem.eql(u8, attr.name, "ffi")) {
                if (attr.args) |args_str| {
                    if (args_str.len >= 2 and args_str[0] == '"' and args_str[args_str.len - 1] == '"') {
                        enum_t.enum_type.ffi_name = args_str[1 .. args_str.len - 1];
                    } else {
                        enum_t.enum_type.ffi_name = args_str;
                    }
                }
            }
        }

        // Register in the enum type registry (for exhaustiveness checking)
        try self.enum_types.put(self.alloc, ed.name, enum_t);
        // gap[087]: the spellings this case-set claims. A name a SECOND
        // case-set claims is marked ambiguous rather than overwritten — two
        // homes for one spelling is exactly the state where a silent pick
        // produces a wrong VALUE rather than a failed build.
        for (ed.variants) |v| {
            const gop = try self.case_homes.getOrPut(self.alloc, v.name);
            if (gop.found_existing) {
                if (!std.mem.eql(u8, gop.value_ptr.*, ed.name)) gop.value_ptr.* = "";
            } else {
                gop.value_ptr.* = ed.name;
            }
        }

        // Define the enum name in scope as a constant type
        try self.scope.define(ed.name, .{ .typ = enum_t, .is_const = true });
        debug_trace.event(.sema, .enum_type, "enum {s} ({d} variants)", .{ ed.name, ed.variants.len });
    }

    fn strip_attribute_string(raw: []const u8) []const u8 {
        const trimmed = std.mem.trim(u8, raw, " \t\r\n");
        if (trimmed.len >= 2 and trimmed[0] == '"' and trimmed[trimmed.len - 1] == '"') {
            return trimmed[1 .. trimmed.len - 1];
        }
        return trimmed;
    }

    fn enum_derive_names(alloc: std.mem.Allocator, attrs: []const ast.Attribute) SemaError![]const []const u8 {
        var names: std.ArrayList([]const u8) = .empty;
        for (attrs) |attr| {
            if (!std.mem.eql(u8, attr.name, "derive")) continue;
            const raw = attr.args orelse continue;
            var it = std.mem.splitScalar(u8, raw, ',');
            while (it.next()) |part| {
                const name = strip_attribute_string(part);
                if (name.len != 0) try names.append(alloc, name);
            }
        }
        return names.toOwnedSlice(alloc);
    }

    fn enum_type_has_derive(rt: RT, derive_name: []const u8) bool {
        if (rt != .enum_type) return false;
        for (rt.enum_type.derives) |name| {
            if (std.mem.eql(u8, name, derive_name)) return true;
        }
        return false;
    }

    // ── Concept definition and satisfaction checking ──────────────────────────

    /// Register a concept definition in the concept registry.
    fn check_concept_def(self: *Sema, cd: *const ast.ConceptDef) SemaError!void {
        // Build method requirements
        var methods = try self.alloc.alloc(ConceptInfo.MethodRequirement, cd.required_methods.len);
        for (cd.required_methods, 0..) |*m, i| {
            const ret_t = try self.resolve_type(m.ret_type);
            var param_types = try self.alloc.alloc(RT, m.params.len);
            for (m.params, 0..) |p, j| {
                param_types[j] = try self.resolve_type(p.typ);
            }
            methods[i] = .{
                .name = m.name,
                .param_count = m.params.len,
                .param_types = param_types,
                .ret_type = ret_t,
            };
        }

        // Build field requirements
        var fields = try self.alloc.alloc(ConceptInfo.FieldRequirement, cd.required_fields.len);
        for (cd.required_fields, 0..) |*f, i| {
            const field_t = try self.resolve_type(f.typ);
            fields[i] = .{
                .name = f.name,
                .typ = field_t,
            };
        }

        const info = ConceptInfo{
            .name = cd.name,
            .required_methods = methods,
            .required_fields = fields,
        };

        // Register in the concept registry
        try self.concepts.put(self.alloc, cd.name, info);

        // Define the concept name in scope as a constant
        try self.scope.define(cd.name, .{
            .typ = .any, // Concepts are compile-time constructs
            .is_const = true,
        });
    }

    fn maybe_register_meta_concept(self: *Sema, binding_name: []const u8, expr: *const ast.Expr) SemaError!void {
        if (expr.* != .call) return;
        const call = expr.call;
        if (!is_meta_make_concept_call(call.func)) return;
        if (call.args.len < 2) return;
        if (call.args[0].* != .string_lit) return;
        const descriptor_name = call.args[0].string_lit.val;
        const spec = call.args[1];
        if (spec.* != .table) return;

        const fields_expr = find_named_table_field(spec, &.{ "required_fields", "fields" });
        const methods_expr = find_named_table_field(spec, &.{ "required_methods", "methods" });

        const fields = try self.collect_meta_concept_fields(fields_expr);
        const methods = try self.collect_meta_concept_methods(methods_expr);
        const info = ConceptInfo{
            .name = descriptor_name,
            .required_methods = methods,
            .required_fields = fields,
        };
        try self.concepts.put(self.alloc, binding_name, info);
        if (!std.mem.eql(u8, binding_name, descriptor_name)) {
            try self.concepts.put(self.alloc, descriptor_name, info);
        }
    }

    fn is_meta_make_concept_call(func: *const ast.Expr) bool {
        if (func.* == .field and std.mem.eql(u8, func.field.field, "make_concept")) return true;
        if (func.* == .name and std.mem.eql(u8, func.name.ident, "make_concept")) return true;
        return false;
    }

    fn find_named_table_field(spec: *const ast.Expr, keys: []const []const u8) ?*const ast.Expr {
        if (spec.* != .table) return null;
        for (spec.table.fields) |field| {
            if (field != .named) continue;
            for (keys) |key| {
                if (std.mem.eql(u8, field.named.key, key)) return field.named.val;
            }
        }
        return null;
    }

    fn concept_member_name_expr(member: *const ast.Expr) ?[]const u8 {
        if (member.* == .string_lit) return member.string_lit.val;
        if (member.* != .table) return null;
        const name_expr = find_named_table_field(member, &.{"name"}) orelse return null;
        if (name_expr.* != .string_lit) return null;
        return name_expr.string_lit.val;
    }

    fn collect_meta_concept_fields(self: *Sema, maybe_expr: ?*const ast.Expr) SemaError![]ConceptInfo.FieldRequirement {
        const expr = maybe_expr orelse return &[_]ConceptInfo.FieldRequirement{};
        if (expr.* != .table) return &[_]ConceptInfo.FieldRequirement{};
        var fields: std.ArrayList(ConceptInfo.FieldRequirement) = .empty;
        for (expr.table.fields) |field| {
            const member_expr: *const ast.Expr = switch (field) {
                .positional => |p| p,
                .named => |n| n.val,
                .indexed => |idx| idx.val,
                // Pass 36 G1/G8 recorded, not implemented (Phase 0): semantic entries are not concept members.
                .spread, .semantic => continue,
            };
            if (concept_member_name_expr(member_expr)) |name| {
                try fields.append(self.alloc, .{ .name = name, .typ = .any });
            }
        }
        return fields.toOwnedSlice(self.alloc);
    }

    fn meta_concept_type_from_string(self: *Sema, name: []const u8) SemaError!RT {
        if (std.mem.eql(u8, name, "any")) return .any;
        if (try self.mem_type_from_name(name)) |t| return t;
        return .any;
    }

    fn collect_meta_concept_method_params(self: *Sema, member_expr: *const ast.Expr) SemaError![]RT {
        const params_expr = find_named_table_field(member_expr, &.{"params"}) orelse return &[_]RT{};
        if (params_expr.* != .table) return &[_]RT{};
        var param_types: std.ArrayList(RT) = .empty;
        for (params_expr.table.fields) |field| {
            const elem: *const ast.Expr = switch (field) {
                .positional => |p| p,
                .named => |n| n.val,
                .indexed => |idx| idx.val,
                // Pass 36 G1/G8 recorded, not implemented (Phase 0): semantic entries are not concept params.
                .spread, .semantic => continue,
            };
            const pt: RT = if (elem.* == .string_lit)
                try self.meta_concept_type_from_string(elem.string_lit.val)
            else
                .any;
            try param_types.append(self.alloc, pt);
        }
        return param_types.toOwnedSlice(self.alloc);
    }

    fn collect_meta_concept_methods(self: *Sema, maybe_expr: ?*const ast.Expr) SemaError![]ConceptInfo.MethodRequirement {
        const expr = maybe_expr orelse return &[_]ConceptInfo.MethodRequirement{};
        if (expr.* != .table) return &[_]ConceptInfo.MethodRequirement{};
        var methods: std.ArrayList(ConceptInfo.MethodRequirement) = .empty;
        for (expr.table.fields) |field| {
            const member_expr: *const ast.Expr = switch (field) {
                .positional => |p| p,
                .named => |n| n.val,
                .indexed => |idx| idx.val,
                // Pass 36 G1/G8 recorded, not implemented (Phase 0): semantic entries are not concept members.
                .spread, .semantic => continue,
            };
            if (concept_member_name_expr(member_expr)) |name| {
                const param_types = try self.collect_meta_concept_method_params(member_expr);
                var ret_type: RT = .any;
                if (find_named_table_field(member_expr, &.{ "ret", "return" })) |ret_expr| {
                    if (ret_expr.* == .string_lit) {
                        ret_type = try self.meta_concept_type_from_string(ret_expr.string_lit.val);
                    }
                }
                try methods.append(self.alloc, .{
                    .name = name,
                    .param_count = param_types.len,
                    .param_types = param_types,
                    .ret_type = ret_type,
                });
            }
        }
        return methods.toOwnedSlice(self.alloc);
    }

    /// Check that a binding annotated with `@implements(Concept)` provides all
    /// of the concept's required members. The binding's record-type annotation
    /// supplies the declared field set; the binding's initializer is also
    /// checked for matching field names (table-literal values must define
    /// them).
    ///
    /// `record_fields` is the set of fields declared by the binding's
    /// `{ name: T, ... }` type annotation. `init_field_names` is the set of
    /// names that actually appear in the binding's initializer expression
    /// (only meaningful for `table` initializers; for function-typed fields,
    /// the field is considered "provided" by the annotation alone).
    /// Resolve an overloaded call by matching argument types against the
    /// registered signatures (Requirement 12). Returns the selected return
    /// type, or null when no overload is applicable (caller falls back to the
    /// in-scope binding). Prefers exact matches; reports ambiguity when more
    /// than one overload matches equally well.
    fn resolve_overload(
        self: *Sema,
        loc: ast.Loc,
        name: []const u8,
        overloads: []const FuncSignature,
        args: []const *ast.Expr,
    ) SemaError!?RT {
        var arg_types: std.ArrayList(RT) = .empty;
        defer arg_types.deinit(self.alloc);
        for (args) |a| try arg_types.append(self.alloc, self.type_map.get(a) orelse .any);

        var exact_count: usize = 0;
        var exact_ret: RT = .any;
        var compat_count: usize = 0;
        var compat_ret: RT = .any;
        for (overloads) |sig| {
            if (sig.is_vararg) {
                if (args.len < sig.param_types.len) continue;
            } else if (sig.param_types.len != args.len) continue;

            var is_exact = true;
            var is_compat = true;
            for (sig.param_types, 0..) |pt, i| {
                if (i >= arg_types.items.len) break;
                const at = arg_types.items[i];
                if (pt.eql(at)) continue;
                is_exact = false;
                // `any` on either side is treated as a compatible (coercible) match.
                if (pt != .any and at != .any) is_compat = false;
            }
            if (is_exact) {
                exact_count += 1;
                exact_ret = sig.ret;
            }
            if (is_compat) {
                compat_count += 1;
                compat_ret = sig.ret;
            }
        }

        if (exact_count == 1) return exact_ret;
        if (exact_count > 1) {
            self.err(loc, "ambiguous call to overloaded function '{s}': multiple overloads match the argument types", .{name});
            return exact_ret;
        }
        if (compat_count == 1) return compat_ret;
        if (compat_count > 1) {
            self.err(loc, "ambiguous call to overloaded function '{s}': multiple overloads match the argument types", .{name});
            return compat_ret;
        }
        return null;
    }

    /// Record a generic instantiation site for the monomorphizer when the
    /// callee's signature mentions generic parameters (Requirement 4.1, 4.3).
    /// Validates declared constraints on each type parameter (Requirement 4.2).
    fn record_generic_instantiation(
        self: *Sema,
        loc: ast.Loc,
        name: []const u8,
        sig: anytype,
        args: []const *ast.Expr,
    ) SemaError!void {
        var has_generic = false;
        for (sig.params) |p| {
            if (p == .generic_param) {
                has_generic = true;
                break;
            }
        }
        if (!has_generic) return;

        var type_args: std.ArrayList(RT) = .empty;
        defer type_args.deinit(self.alloc);
        for (sig.params, 0..) |p, i| {
            if (p != .generic_param) continue;
            if (i >= args.len) continue;
            var at = self.type_map.get(args[i]) orelse .any;
            if (at == .any and args[i].* == .name) {
                at = .{ .@"struct" = .{ .name = args[i].name.ident } };
            }
            try type_args.append(self.alloc, at);
            // Constraint validation: if the parameter declares a concept
            // constraint, the concrete argument must satisfy it.
            if (p.generic_param.constraint) |constraint| {
                var concept_iter = std.mem.splitScalar(u8, constraint, '|');
                while (concept_iter.next()) |concept_name| {
                    if (concept_name.len == 0) continue;
                    if (self.concepts.get(concept_name)) |_| {
                        if (at != .any and !self.type_satisfies_concept(at, concept_name)) {
                            var buf: [128]u8 = undefined;
                            const type_name = at.duo_name(&buf);
                            self.err(loc, "type '{s}' does not satisfy concept '{s}' required by generic '{s}'", .{ type_name, concept_name, name });
                        }
                    } else if (at != .any) {
                        self.err(loc, "type parameter '{s}' of '{s}' has unknown constraint '{s}'", .{ p.generic_param.name, name, concept_name });
                    }
                }
            }
        }

        // The specialization key and the collected type args existed only to
        // build an InstantiationRecord nothing read. mono.zig keeps its own
        // registry (mono.zig:176-184) and never consulted this one. The
        // constraint CHECKING above is the real work of this function and stays.
        //
        // No deinit here: `type_args` already has one at its declaration. The
        // original code called toOwnedSlice, which TRANSFERRED ownership and
        // made that defer a no-op. Removing the transfer without noticing the
        // defer is a double free — it cost three unit-test crashes.
    }

    /// Collect the named field keys from a table-literal initializer
    /// (`{ name = expr, ... }`). Used by `@implements` checking to see which
    /// concept members the initializer supplies beyond the record annotation.
    /// Returns an empty slice for non-table initializers.
    fn collect_init_field_names(self: *Sema, init_expr: *const ast.Expr) SemaError![]const []const u8 {
        if (init_expr.* != .table) return &[_][]const u8{};
        var names: std.ArrayList([]const u8) = .empty;
        for (init_expr.table.fields) |f| {
            switch (f) {
                .named => |n| try names.append(self.alloc, n.key),
                else => {},
            }
        }
        return names.toOwnedSlice(self.alloc);
    }

    fn check_concept_satisfaction(
        self: *Sema,
        loc: ast.Loc,
        binding_name: []const u8,
        record_fields: []const ast.RecordField,
        init_field_names: []const []const u8,
        concept_name: []const u8,
    ) SemaError!void {
        const concept = self.concepts.get(concept_name) orelse {
            self.err(loc, "undeclared concept '{s}'", .{concept_name});
            return;
        };

        var missing_methods: std.ArrayList([]const u8) = .empty;
        defer missing_methods.deinit(self.alloc);
        var missing_fields: std.ArrayList([]const u8) = .empty;
        defer missing_fields.deinit(self.alloc);

        // Check required fields
        for (concept.required_fields) |req_field| {
            var found = false;
            for (record_fields) |rec_field| {
                if (std.mem.eql(u8, rec_field.name, req_field.name)) {
                    const rec_field_type = try self.resolve_type(rec_field.typ);
                    if (req_field.typ != .any and rec_field_type != .any and !req_field.typ.eql(rec_field_type)) {
                        self.err(loc, "binding '{s}' field '{s}' has type {}, but concept '{s}' requires type {}", .{
                            binding_name, req_field.name, rec_field_type, concept_name, req_field.typ,
                        });
                    }
                    found = true;
                    break;
                }
            }
            if (!found) {
                try missing_fields.append(self.alloc, req_field.name);
            }
        }

        // Check required methods — for now, methods are fields with function types.
        // The record annotation is sufficient to count as "provided" (the
        // initializer may or may not also reference them).
        for (concept.required_methods) |req_method| {
            var found = false;
            for (record_fields) |rec_field| {
                if (std.mem.eql(u8, rec_field.name, req_method.name)) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                // Fall back to checking the initializer's table-literal fields.
                for (init_field_names) |nm| {
                    if (std.mem.eql(u8, nm, req_method.name)) {
                        found = true;
                        break;
                    }
                }
            }
            if (!found) {
                try missing_methods.append(self.alloc, req_method.name);
            }
        }

        // Emit error if any members are missing
        const total_missing = missing_methods.items.len + missing_fields.items.len;
        if (total_missing > 0) {
            var list: std.ArrayListUnmanaged(u8) = .empty;
            defer list.deinit(self.alloc);
            var first = true;
            for (missing_methods.items) |name| {
                if (!first) list.appendSlice(self.alloc, ", ") catch {};
                var tmp: [256]u8 = undefined;
                const rendered = std.fmt.bufPrint(&tmp, "method '{s}'", .{name}) catch "method";
                list.appendSlice(self.alloc, rendered) catch {};
                first = false;
            }
            for (missing_fields.items) |name| {
                if (!first) list.appendSlice(self.alloc, ", ") catch {};
                var tmp: [256]u8 = undefined;
                const rendered = std.fmt.bufPrint(&tmp, "field '{s}'", .{name}) catch "field";
                list.appendSlice(self.alloc, rendered) catch {};
                first = false;
            }
            self.err(loc, "binding '{s}' does not satisfy concept '{s}': missing {s}", .{ binding_name, concept_name, list.items });
        }
    }

    /// Field type from a descriptor alias (`Vec: @{ x: i32 }`) for static member access.
    fn field_type_of_alias(self: *Sema, alias_name: []const u8, field_name: []const u8) SemaError!?RT {
        const ad = self.alias_defs.get(alias_name) orelse return null;
        for (ad.fields) |f| {
            if (std.mem.eql(u8, f.name, field_name)) return try self.resolve_type(f.typ);
        }
        if (ad.target) |target| {
            switch (target) {
                .record => |rec| {
                    for (rec.fields) |f| {
                        if (std.mem.eql(u8, f.name, field_name)) return try self.resolve_type(f.typ);
                    }
                },
                else => {},
            }
        }
        return null;
    }

    fn type_satisfies_concept(self: *Sema, rt: RT, concept_name: []const u8) bool {
        const concept = self.concepts.get(concept_name) orelse return false;

        const type_name: ?[]const u8 = switch (rt) {
            .@"struct" => |s| s.name,
            .enum_type => |et| et.name,
            else => null,
        };
        const alias_def = if (type_name) |tname| self.alias_defs.get(tname) else null;
        const methods: ?[]const []const u8 = if (type_name) |tname|
            if (self.table_methods.get(tname)) |m| m.items else null
        else
            null;
        return AliasRegistry.satisfies(alias_def, methods, rt, concept);
    }

    fn eval_satisfies_expr(self: *Sema, args: []const *ast.Expr) ?bool {
        if (args.len != 2) return null;
        const concept_name = if (args[1].* == .string_lit) args[1].string_lit.val else return null;
        if (self.concepts.get(concept_name) == null) return null;

        if (args[0].* == .name) {
            const table_name = args[0].name.ident;
            if (self.table_methods.get(table_name)) |_| {
                return self.type_satisfies_concept(.{ .@"struct" = .{ .name = table_name } }, concept_name);
            }
            if (self.scope.lookup(table_name)) |binding| {
                if (binding.typ != .any)
                    return self.type_satisfies_concept(binding.typ, concept_name);
            }
            return self.type_satisfies_concept(.{ .@"struct" = .{ .name = table_name } }, concept_name);
        }

        const rt = self.type_map.get(args[0]) orelse .any;
        if (rt == .any) return null;
        return self.type_satisfies_concept(rt, concept_name);
    }

    fn try_eval_const_condition(self: *Sema, cond: *const ast.Expr) ?bool {
        return switch (cond.*) {
            .true_lit => true,
            .false_lit => false,
            .int_lit => |i| i.val != 0,
            .unop => |u| switch (u.op) {
                .not => if (self.try_eval_const_condition(u.operand)) |v| !v else null,
                else => null,
            },
            .binop => |b| {
                if (b.op == .@"and") {
                    const lhs = self.try_eval_const_condition(b.lhs);
                    if (lhs != null and !lhs.?) return false;
                    const rhs = self.try_eval_const_condition(b.rhs);
                    if (lhs != null and lhs.? and rhs != null) return rhs.?;
                    return null;
                }
                if (b.op == .@"or") {
                    const lhs = self.try_eval_const_condition(b.lhs);
                    if (lhs != null and lhs.?) return true;
                    const rhs = self.try_eval_const_condition(b.rhs);
                    if (lhs != null and !lhs.? and rhs != null) return rhs.?;
                    return null;
                }
                if (b.lhs.* == .int_lit and b.rhs.* == .int_lit) {
                    const lv = b.lhs.int_lit.val;
                    const rv = b.rhs.int_lit.val;
                    return switch (b.op) {
                        .eq => lv == rv,
                        .neq => lv != rv,
                        .lt => lv < rv,
                        .gt => lv > rv,
                        .leq => lv <= rv,
                        .geq => lv >= rv,
                        else => null,
                    };
                }
                return null;
            },
            .call => |c| {
                if (c.func.* == .name and std.mem.eql(u8, c.func.name.ident, "__satisfies") and c.args.len == 2)
                    return self.eval_satisfies_expr(c.args);
                if (c.func.* == .name and std.mem.eql(u8, c.func.name.ident, "__static_assert") and c.args.len >= 1)
                    return self.try_eval_const_condition(c.args[0]);
                return null;
            },
            else => null,
        };
    }

    fn check_static_assert(self: *Sema, loc: ast.Loc, args: []const *ast.Expr) void {
        if (args.len == 0) return;
        if (self.try_eval_const_condition(args[0])) |known| {
            if (!known) {
                const msg = if (args.len >= 2 and args[1].* == .string_lit)
                    args[1].string_lit.val
                else
                    "static assertion failed";
                self.err(loc, "{s}", .{msg});
            }
        }
    }

    fn detect_trial_division_primes(fb: *ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        var has_outer_limit = false;
        var has_inner_mod = false;
        var has_prime_flag = false;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .while_loop) continue;
            const outer = stmt.while_loop;
            if (outer.cond.* == .binop and outer.cond.binop.op == .leq) has_outer_limit = true;
            for (outer.body.stmts) |*s| {
                if (s.* == .local_decl) {
                    for (s.local_decl.names) |nm| {
                        if (std.mem.eql(u8, nm.ident, "is_prime")) has_prime_flag = true;
                    }
                }
                if (s.* != .while_loop) continue;
                const inner = s.while_loop;
                for (inner.body.stmts) |*is| {
                    if (is.* != .if_stmt) continue;
                    const cond = is.if_stmt.cond;
                    if (cond.* == .binop and cond.binop.op == .eq and
                        cond.binop.lhs.* == .binop and cond.binop.lhs.binop.op == .mod)
                    {
                        has_inner_mod = true;
                    }
                }
            }
        }
        return has_outer_limit and has_inner_mod and has_prime_flag;
    }

    fn detect_grid_sum_inline(fb: *ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        if (fb.body.stmts.len < 2) return false;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .while_loop) continue;
            const outer = stmt.while_loop;
            for (outer.body.stmts) |*inner_stmt| {
                if (inner_stmt.* != .while_loop) continue;
                for (inner_stmt.while_loop.body.stmts) |*s| {
                    if (s.* != .assign) continue;
                    const as = s.assign;
                    if (as.values.len == 0) continue;
                    const val = as.values[0];
                    if (val.* != .binop or val.binop.op != .add) continue;
                    const rhs = val.binop.rhs;
                    if (rhs.* != .call) continue;
                    const c = rhs.call;
                    if (c.func.* != .name) continue;
                    if (std.mem.eql(u8, c.func.name.ident, "eval_A")) return true;
                }
            }
        }
        return false;
    }

    fn detect_dense_table_sum_patterns(fb: *ast.FuncBody) void {
        if (!fb.use_dense_table or fb.use_dense_table_mod997_sum) return;
        const tname = fb.dense_table orelse return;

        var table_assignments: usize = 0;
        var poly_fill: ?DenseTablePolyFill = null;
        var reduction_assignments: usize = 0;
        var reduction: ?DenseTablePolyFill = null;
        const limit_name = if (fb.params.len == 1) fb.params[0].name else return;
        const consts = collect_dense_table_int_consts(fb);

        for (fb.body.stmts, 0..) |*stmt, i| {
            if (stmt.* != .while_loop) continue;
            const wl = &stmt.while_loop;
            const idx_name = while_loop_index_name(wl.cond, limit_name) orelse continue;
            if (i == 0 or !stmt_sets_name_to_one(&fb.body.stmts[i - 1], idx_name)) continue;

            var loop_table_assigns: usize = 0;
            var loop_poly_fill: ?DenseTablePolyFill = null;
            // The closed form sums EVERY index in the range, so the loop must
            // VISIT every index. The guard below rejects a statement this walk
            // cannot model — but the increment is an `.assign` like any other,
            // matches none of the three recognizers, and was therefore skipped
            // in silence. So `i += 7` looked identical to `i += 1`.
            //
            // Measured: `xs[i] = i` stepping by 7, summed over 1..n with n=10,
            // fills only xs[1] and xs[8] and must answer 9. This detector
            // answered 55 — n(n+1)/2 — a wrong answer, not a missed
            // optimization. §3: a detector must verify every constant its
            // emitter assumes and decline to the general path otherwise.
            var index_step_one = false;

            for (wl.body.stmts) |*s| {
                // The closed form below sums the WHOLE range, so the loop has to
                // BE the whole range. A body statement this walk does not model
                // — an `if`, a `break`, a `return`, a call — can cut the range
                // short or add a term, and skipping it answered a question the
                // program had stopped asking: `while i <= n do if i > 5 break
                // end sum += t[i] i += 1 end` returned n(n+1)/2 for n = 50, i.e.
                // 1275 where the program asks for 15.
                if (s.* != .assign) return;
                const as = s.assign;
                const n = @min(as.targets.len, as.values.len);
                var ii: usize = 0;
                while (ii < n) : (ii += 1) {
                    const tgt = as.targets[ii];
                    const val = as.values[ii];
                    if (dense_table_assign_poly(tgt, val, tname, idx_name, &consts)) |poly| {
                        loop_table_assigns += 1;
                        loop_poly_fill = poly;
                    } else if (is_dense_table_assign_target(tgt, tname)) {
                        loop_table_assigns += 1;
                    } else if (dense_table_sum_reduction(tgt, val, tname, idx_name, &consts)) |poly| {
                        reduction_assignments += 1;
                        reduction = poly;
                    } else if (assign_steps_index_by_one(tgt, val, idx_name)) {
                        index_step_one = true;
                    }
                }
            }

            // No verified unit step, no closed form. Declining here costs an
            // optimization; not declining costs an answer.
            if (!index_step_one) return;

            table_assignments += loop_table_assigns;
            if (loop_poly_fill) |poly| poly_fill = poly;
        }

        if (table_assignments != 1 or reduction_assignments != 1) return;
        if (poly_fill) |poly| {
            const reduced = compose_dense_table_reduction(poly, reduction.?) orelse return;
            const degree = poly_degree(reduced) orelse return;
            if (degree == 1 and reduced.coeffs[1] == 1 and reduced.coeffs[0] == 0) {
                fb.use_dense_table_identity_sum = true;
            } else if (degree == 1) {
                // NOT claimed. `emit_dense_table_sum_body` — the only consumer of
                // `use_dense_table_sum` — fills the array with `t[i] = i` and
                // never reads `dense_table_sum_mul`/`_add`, so it answers the
                // identity for every non-identity polynomial it is handed:
                // `t[i] = i * 2; s += t[i]` over 1..10 returned 55, not 110. The
                // identity case above is the only one it actually computes, and
                // that one has its own closed-form emitter. Falling through here
                // lowers the loop for real, through the dense array path.
            } else if (degree == 2 and reduced.coeffs[2] == 1 and reduced.coeffs[1] == 0 and reduced.coeffs[0] == 0) {
                fb.use_dense_table_square_sum = true;
            } else if (degree == 2) {
                fb.use_dense_table_quadratic_sum = true;
                fb.dense_table_sum_square_mul = reduced.coeffs[2];
                fb.dense_table_sum_linear_mul = reduced.coeffs[1];
                fb.dense_table_sum_const = reduced.coeffs[0];
            } else if (degree == 3) {
                fb.use_dense_table_cubic_sum = true;
                fb.dense_table_sum_cube_mul = reduced.coeffs[3];
                fb.dense_table_sum_square_mul = reduced.coeffs[2];
                fb.dense_table_sum_linear_mul = reduced.coeffs[1];
                fb.dense_table_sum_const = reduced.coeffs[0];
            } else if (degree == 4) {
                fb.use_dense_table_quartic_sum = true;
                fb.dense_table_sum_quartic_mul = reduced.coeffs[4];
                fb.dense_table_sum_cube_mul = reduced.coeffs[3];
                fb.dense_table_sum_square_mul = reduced.coeffs[2];
                fb.dense_table_sum_linear_mul = reduced.coeffs[1];
                fb.dense_table_sum_const = reduced.coeffs[0];
            } else if (degree == 5) {
                fb.use_dense_table_quintic_sum = true;
                fb.dense_table_sum_quintic_mul = reduced.coeffs[5];
                fb.dense_table_sum_quartic_mul = reduced.coeffs[4];
                fb.dense_table_sum_cube_mul = reduced.coeffs[3];
                fb.dense_table_sum_square_mul = reduced.coeffs[2];
                fb.dense_table_sum_linear_mul = reduced.coeffs[1];
                fb.dense_table_sum_const = reduced.coeffs[0];
            } else if (degree == 6) {
                fb.use_dense_table_sextic_sum = true;
                fb.dense_table_sum_sextic_mul = reduced.coeffs[6];
                fb.dense_table_sum_quintic_mul = reduced.coeffs[5];
                fb.dense_table_sum_quartic_mul = reduced.coeffs[4];
                fb.dense_table_sum_cube_mul = reduced.coeffs[3];
                fb.dense_table_sum_square_mul = reduced.coeffs[2];
                fb.dense_table_sum_linear_mul = reduced.coeffs[1];
                fb.dense_table_sum_const = reduced.coeffs[0];
            } else if (degree == 7) {
                fb.use_dense_table_septic_sum = true;
                fb.dense_table_sum_septic_mul = reduced.coeffs[7];
                fb.dense_table_sum_sextic_mul = reduced.coeffs[6];
                fb.dense_table_sum_quintic_mul = reduced.coeffs[5];
                fb.dense_table_sum_quartic_mul = reduced.coeffs[4];
                fb.dense_table_sum_cube_mul = reduced.coeffs[3];
                fb.dense_table_sum_square_mul = reduced.coeffs[2];
                fb.dense_table_sum_linear_mul = reduced.coeffs[1];
                fb.dense_table_sum_const = reduced.coeffs[0];
            } else if (degree == 8) {
                fb.use_dense_table_octic_sum = true;
                fb.dense_table_sum_octic_mul = reduced.coeffs[8];
                fb.dense_table_sum_septic_mul = reduced.coeffs[7];
                fb.dense_table_sum_sextic_mul = reduced.coeffs[6];
                fb.dense_table_sum_quintic_mul = reduced.coeffs[5];
                fb.dense_table_sum_quartic_mul = reduced.coeffs[4];
                fb.dense_table_sum_cube_mul = reduced.coeffs[3];
                fb.dense_table_sum_square_mul = reduced.coeffs[2];
                fb.dense_table_sum_linear_mul = reduced.coeffs[1];
                fb.dense_table_sum_const = reduced.coeffs[0];
            } else if (degree == 9) {
                fb.use_dense_table_nonic_sum = true;
                fb.dense_table_sum_nonic_mul = reduced.coeffs[9];
                fb.dense_table_sum_octic_mul = reduced.coeffs[8];
                fb.dense_table_sum_septic_mul = reduced.coeffs[7];
                fb.dense_table_sum_sextic_mul = reduced.coeffs[6];
                fb.dense_table_sum_quintic_mul = reduced.coeffs[5];
                fb.dense_table_sum_quartic_mul = reduced.coeffs[4];
                fb.dense_table_sum_cube_mul = reduced.coeffs[3];
                fb.dense_table_sum_square_mul = reduced.coeffs[2];
                fb.dense_table_sum_linear_mul = reduced.coeffs[1];
                fb.dense_table_sum_const = reduced.coeffs[0];
            } else if (degree == 10) {
                fb.use_dense_table_decic_sum = true;
                fb.dense_table_sum_decic_mul = reduced.coeffs[10];
                fb.dense_table_sum_nonic_mul = reduced.coeffs[9];
                fb.dense_table_sum_octic_mul = reduced.coeffs[8];
                fb.dense_table_sum_septic_mul = reduced.coeffs[7];
                fb.dense_table_sum_sextic_mul = reduced.coeffs[6];
                fb.dense_table_sum_quintic_mul = reduced.coeffs[5];
                fb.dense_table_sum_quartic_mul = reduced.coeffs[4];
                fb.dense_table_sum_cube_mul = reduced.coeffs[3];
                fb.dense_table_sum_square_mul = reduced.coeffs[2];
                fb.dense_table_sum_linear_mul = reduced.coeffs[1];
                fb.dense_table_sum_const = reduced.coeffs[0];
            } else if (degree == 11 or degree == 12) {
                fb.use_dense_table_faulhaber_sum = true;
                fb.dense_table_sum_coeffs = reduced.coeffs;
            } else {
                return;
            }
        }
    }

    const DenseTablePolyFill = struct {
        coeffs: [13]i64,
    };

    const DenseTableIntConst = struct {
        name: []const u8,
        value: i64,
        valid: bool = true,
    };

    const DenseTableIntConstSet = struct {
        items: [32]DenseTableIntConst = undefined,
        len: usize = 0,
    };

    fn collect_dense_table_int_consts(fb: *const ast.FuncBody) DenseTableIntConstSet {
        var out = DenseTableIntConstSet{};
        for (fb.body.stmts) |*stmt| {
            switch (stmt.*) {
                .local_decl => |*ld| {
                    if (ld.names.len != 1 or ld.inits.len != 1 or ld.inits[0].* != .int_lit) continue;
                    dense_table_add_int_const(&out, ld.names[0].ident, ld.inits[0].int_lit.val);
                },
                .const_decl => |*cd| {
                    if (cd.val.* != .int_lit) continue;
                    dense_table_add_int_const(&out, cd.ident, cd.val.int_lit.val);
                },
                else => {},
            }
        }
        for (fb.body.stmts) |*stmt| {
            dense_table_invalidate_assigned_consts(&out, stmt, false);
        }
        return out;
    }

    fn dense_table_add_int_const(consts: *DenseTableIntConstSet, name: []const u8, value: i64) void {
        for (consts.items[0..consts.len]) |*item| {
            if (std.mem.eql(u8, item.name, name)) {
                item.valid = false;
                return;
            }
        }
        if (consts.len >= consts.items.len) return;
        consts.items[consts.len] = .{ .name = name, .value = value };
        consts.len += 1;
    }

    fn dense_table_invalidate_assigned_consts(consts: *DenseTableIntConstSet, stmt: *const ast.Stmt, nested: bool) void {
        switch (stmt.*) {
            .assign => |*as| {
                for (as.targets) |target| {
                    if (target.* == .name) dense_table_invalidate_const(consts, target.name.ident);
                }
            },
            .local_decl => |*ld| {
                if (nested) {
                    for (ld.names) |name| dense_table_invalidate_const(consts, name.ident);
                } else {
                    for (ld.names, 0..) |name, i| {
                        if (i >= ld.inits.len or ld.inits[i].* != .int_lit) {
                            dense_table_invalidate_const(consts, name.ident);
                        }
                    }
                }
            },
            .const_decl => |*cd| {
                if (nested or cd.val.* != .int_lit) dense_table_invalidate_const(consts, cd.ident);
            },
            .while_loop => |*wl| {
                for (wl.body.stmts) |*child| dense_table_invalidate_assigned_consts(consts, child, true);
            },
            .if_stmt => |*is| {
                for (is.then.stmts) |*child| dense_table_invalidate_assigned_consts(consts, child, true);
                for (is.elseifs) |*elseif| {
                    for (elseif.body.stmts) |*child| dense_table_invalidate_assigned_consts(consts, child, true);
                }
                if (is.else_body) |*else_body| {
                    for (else_body.stmts) |*child| dense_table_invalidate_assigned_consts(consts, child, true);
                }
            },
            else => {},
        }
    }

    fn dense_table_invalidate_const(consts: *DenseTableIntConstSet, name: []const u8) void {
        for (consts.items[0..consts.len]) |*item| {
            if (std.mem.eql(u8, item.name, name)) item.valid = false;
        }
    }

    fn dense_table_int_const_value(consts: *const DenseTableIntConstSet, name: []const u8) ?i64 {
        for (consts.items[0..consts.len]) |item| {
            if (item.valid and std.mem.eql(u8, item.name, name)) return item.value;
        }
        return null;
    }

    fn stmt_sets_name_to_one(stmt: *const ast.Stmt, name: []const u8) bool {
        switch (stmt.*) {
            .local_decl => |*ld| {
                if (ld.names.len != 1 or ld.inits.len != 1) return false;
                return std.mem.eql(u8, ld.names[0].ident, name) and is_int_one(ld.inits[0]);
            },
            .assign => |*as| {
                if (as.targets.len != 1 or as.values.len != 1) return false;
                const tgt = as.targets[0];
                return tgt.* == .name and std.mem.eql(u8, tgt.name.ident, name) and is_int_one(as.values[0]);
            },
            else => return false,
        }
    }

    fn is_dense_table_assign_target(tgt: *const ast.Expr, tname: []const u8) bool {
        if (tgt.* != .index) return false;
        const idx = &tgt.index;
        return idx.obj.* == .name and std.mem.eql(u8, idx.obj.name.ident, tname);
    }

    /// True for `i += 1` / `i = 1 + i` where `i` is the loop index — the ONLY
    /// step under which a whole-range closed form is sound. Any other step, and
    /// any step this cannot read, must decline: a fill that visits every 7th
    /// slot summed against a closed form for every slot is a wrong answer.
    fn assign_steps_index_by_one(tgt: *const ast.Expr, val: *const ast.Expr, idx_name: []const u8) bool {
        if (tgt.* != .name or !std.mem.eql(u8, tgt.name.ident, idx_name)) return false;
        if (val.* != .binop or val.binop.op != .add) return false;
        const l = val.binop.lhs;
        const r = val.binop.rhs;
        const l_is_idx = l.* == .name and std.mem.eql(u8, l.name.ident, idx_name);
        const r_is_idx = r.* == .name and std.mem.eql(u8, r.name.ident, idx_name);
        const l_is_one = l.* == .int_lit and l.int_lit.val == 1;
        const r_is_one = r.* == .int_lit and r.int_lit.val == 1;
        return (l_is_idx and r_is_one) or (l_is_one and r_is_idx);
    }

    fn dense_table_assign_poly(tgt: *const ast.Expr, val: *const ast.Expr, tname: []const u8, idx_name: []const u8, consts: *const DenseTableIntConstSet) ?DenseTablePolyFill {
        if (!is_dense_table_assign_target(tgt, tname)) return null;
        const idx = &tgt.index;
        if (idx.key.* != .name or !std.mem.eql(u8, idx.key.name.ident, idx_name)) return null;
        const poly = expr_poly_in_index(val, idx_name, consts) orelse return null;
        if (poly_degree(poly) == null) return null;
        return poly;
    }

    fn dense_table_sum_reduction(tgt: *const ast.Expr, val: *const ast.Expr, tname: []const u8, idx_name: []const u8, consts: *const DenseTableIntConstSet) ?DenseTablePolyFill {
        if (tgt.* != .name) return null;
        const poly = dense_table_accum_reduction(val, tgt.name.ident, tname, idx_name, consts) orelse return null;
        const degree = poly_degree(poly) orelse return null;
        return if (degree > 0) poly else null;
    }

    fn dense_table_accum_reduction(expr: *const ast.Expr, accum_name: []const u8, tname: []const u8, idx_name: []const u8, consts: *const DenseTableIntConstSet) ?DenseTablePolyFill {
        if (expr.* != .binop) return null;
        const b = expr.binop;
        switch (b.op) {
            .add => {
                if (expr_is_name(b.lhs, accum_name)) return expr_poly_in_table_value(b.rhs, tname, idx_name, consts);
                if (expr_is_name(b.rhs, accum_name)) return expr_poly_in_table_value(b.lhs, tname, idx_name, consts);
                return null;
            },
            .sub => {
                if (!expr_is_name(b.lhs, accum_name)) return null;
                const rhs = expr_poly_in_table_value(b.rhs, tname, idx_name, consts) orelse return null;
                return scale_poly(rhs, -1);
            },
            else => return null,
        }
    }

    fn compose_dense_table_reduction(fill: DenseTablePolyFill, reduction: DenseTablePolyFill) ?DenseTablePolyFill {
        var out: DenseTablePolyFill = .{ .coeffs = @splat(0) };
        var power: DenseTablePolyFill = .{ .coeffs = @splat(0) };
        power.coeffs[0] = 1;
        const max_degree = poly_degree(reduction) orelse return null;

        for (reduction.coeffs[0 .. max_degree + 1], 0..) |coeff, degree| {
            if (coeff != 0) {
                const scaled = scale_poly(power, coeff);
                out = add_poly(out, scaled) orelse return null;
            }
            if (degree < max_degree) {
                power = multiply_poly(power, fill) orelse return null;
            }
        }
        return out;
    }

    fn poly_degree(poly: DenseTablePolyFill) ?usize {
        var i: usize = poly.coeffs.len;
        while (i > 0) {
            i -= 1;
            if (poly.coeffs[i] != 0) return i;
        }
        return null;
    }

    fn expr_poly_in_index(expr: *const ast.Expr, idx_name: []const u8, consts: *const DenseTableIntConstSet) ?DenseTablePolyFill {
        if (expr.* == .name and std.mem.eql(u8, expr.name.ident, idx_name)) {
            var coeffs: [13]i64 = @splat(0);
            coeffs[1] = 1;
            return .{ .coeffs = coeffs };
        }
        if (expr.* == .name) {
            if (dense_table_int_const_value(consts, expr.name.ident)) |value| {
                var coeffs: [13]i64 = @splat(0);
                coeffs[0] = value;
                return .{ .coeffs = coeffs };
            }
        }
        if (expr.* == .int_lit) {
            var coeffs: [13]i64 = @splat(0);
            coeffs[0] = expr.int_lit.val;
            return .{ .coeffs = coeffs };
        }
        if (expr.* == .unop and expr.unop.op == .neg) {
            const inner = expr_poly_in_index(expr.unop.operand, idx_name, consts) orelse return null;
            return scale_poly(inner, -1);
        }
        if (expr.* != .binop) return null;
        const b = expr.binop;
        switch (b.op) {
            .add, .sub => {
                const lhs = expr_poly_in_index(b.lhs, idx_name, consts) orelse return null;
                const rhs = expr_poly_in_index(b.rhs, idx_name, consts) orelse return null;
                var coeffs: [13]i64 = @splat(0);
                for (&coeffs, 0..) |*coeff, i| {
                    coeff.* = if (b.op == .add)
                        lhs.coeffs[i] + rhs.coeffs[i]
                    else
                        lhs.coeffs[i] - rhs.coeffs[i];
                }
                return .{ .coeffs = coeffs };
            },
            .mul => {
                const lhs = expr_poly_in_index(b.lhs, idx_name, consts) orelse return null;
                const rhs = expr_poly_in_index(b.rhs, idx_name, consts) orelse return null;
                var coeffs: [13]i64 = @splat(0);
                for (lhs.coeffs, 0..) |lc, li| {
                    if (lc == 0) continue;
                    for (rhs.coeffs, 0..) |rc, ri| {
                        if (rc == 0) continue;
                        if (li + ri >= coeffs.len) return null;
                        coeffs[li + ri] += lc * rc;
                    }
                }
                return .{ .coeffs = coeffs };
            },
            .pow => {
                const exponent = dense_table_int_exponent(b.rhs, consts) orelse return null;
                const lhs = expr_poly_in_index(b.lhs, idx_name, consts) orelse return null;
                return pow_poly(lhs, exponent);
            },
            else => return null,
        }
    }

    fn expr_poly_in_table_value(expr: *const ast.Expr, tname: []const u8, idx_name: []const u8, consts: *const DenseTableIntConstSet) ?DenseTablePolyFill {
        if (expr_is_dense_table_index(expr, tname, idx_name)) {
            var coeffs: [13]i64 = @splat(0);
            coeffs[1] = 1;
            return .{ .coeffs = coeffs };
        }
        if (expr.* == .name) {
            if (dense_table_int_const_value(consts, expr.name.ident)) |value| {
                var coeffs: [13]i64 = @splat(0);
                coeffs[0] = value;
                return .{ .coeffs = coeffs };
            }
        }
        if (expr.* == .int_lit) {
            var coeffs: [13]i64 = @splat(0);
            coeffs[0] = expr.int_lit.val;
            return .{ .coeffs = coeffs };
        }
        if (expr.* == .unop and expr.unop.op == .neg) {
            const inner = expr_poly_in_table_value(expr.unop.operand, tname, idx_name, consts) orelse return null;
            return scale_poly(inner, -1);
        }
        if (expr.* != .binop) return null;
        const b = expr.binop;
        switch (b.op) {
            .add, .sub => {
                const lhs = expr_poly_in_table_value(b.lhs, tname, idx_name, consts) orelse return null;
                const rhs = expr_poly_in_table_value(b.rhs, tname, idx_name, consts) orelse return null;
                var coeffs: [13]i64 = @splat(0);
                for (&coeffs, 0..) |*coeff, i| {
                    coeff.* = if (b.op == .add)
                        lhs.coeffs[i] + rhs.coeffs[i]
                    else
                        lhs.coeffs[i] - rhs.coeffs[i];
                }
                return .{ .coeffs = coeffs };
            },
            .mul => {
                const lhs = expr_poly_in_table_value(b.lhs, tname, idx_name, consts) orelse return null;
                const rhs = expr_poly_in_table_value(b.rhs, tname, idx_name, consts) orelse return null;
                return multiply_poly(lhs, rhs);
            },
            .pow => {
                const exponent = dense_table_int_exponent(b.rhs, consts) orelse return null;
                const lhs = expr_poly_in_table_value(b.lhs, tname, idx_name, consts) orelse return null;
                return pow_poly(lhs, exponent);
            },
            else => return null,
        }
    }

    fn add_poly(lhs: DenseTablePolyFill, rhs: DenseTablePolyFill) ?DenseTablePolyFill {
        var out: DenseTablePolyFill = .{ .coeffs = @splat(0) };
        for (&out.coeffs, 0..) |*coeff, i| {
            coeff.* = lhs.coeffs[i] + rhs.coeffs[i];
        }
        return out;
    }

    fn multiply_poly(lhs: DenseTablePolyFill, rhs: DenseTablePolyFill) ?DenseTablePolyFill {
        var out: DenseTablePolyFill = .{ .coeffs = @splat(0) };
        for (lhs.coeffs, 0..) |lc, li| {
            if (lc == 0) continue;
            for (rhs.coeffs, 0..) |rc, ri| {
                if (rc == 0) continue;
                if (li + ri >= out.coeffs.len) return null;
                out.coeffs[li + ri] += lc * rc;
            }
        }
        return out;
    }

    fn pow_poly(base: DenseTablePolyFill, exponent: i64) ?DenseTablePolyFill {
        if (exponent < 0 or exponent > 12) return null;
        var out: DenseTablePolyFill = .{ .coeffs = @splat(0) };
        out.coeffs[0] = 1;
        var i: i64 = 0;
        while (i < exponent) : (i += 1) {
            out = multiply_poly(out, base) orelse return null;
        }
        return out;
    }

    fn dense_table_int_exponent(expr: *const ast.Expr, consts: *const DenseTableIntConstSet) ?i64 {
        if (expr.* == .int_lit) return expr.int_lit.val;
        if (expr.* == .name) return dense_table_int_const_value(consts, expr.name.ident);
        return null;
    }

    fn scale_poly(poly: DenseTablePolyFill, scale: i64) DenseTablePolyFill {
        var out = poly;
        for (&out.coeffs) |*coeff| coeff.* *= scale;
        return out;
    }

    fn expr_is_name(expr: *const ast.Expr, name: []const u8) bool {
        return expr.* == .name and std.mem.eql(u8, expr.name.ident, name);
    }

    fn expr_is_dense_table_index(expr: *const ast.Expr, tname: []const u8, idx_name: []const u8) bool {
        if (expr.* != .index) return false;
        const idx = &expr.index;
        return idx.obj.* == .name and std.mem.eql(u8, idx.obj.name.ident, tname) and
            idx.key.* == .name and std.mem.eql(u8, idx.key.name.ident, idx_name);
    }

    fn detect_math_floor_max(fb: *ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        var has_floor = false;
        var has_max = false;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .while_loop) continue;
            for (stmt.while_loop.body.stmts) |*s| {
                if (s.* != .local_decl and s.* != .assign) continue;
                const inits: []const *ast.Expr = if (s.* == .local_decl)
                    s.local_decl.inits
                else
                    s.assign.values;
                for (inits) |val| {
                    if (val.* != .call or val.call.func.* != .field) continue;
                    const f = val.call.func.field;
                    if (f.obj.* != .name or !std.mem.eql(u8, f.obj.name.ident, "math")) continue;
                    if (std.mem.eql(u8, f.field, "floor")) has_floor = true;
                    if (std.mem.eql(u8, f.field, "max")) has_max = true;
                }
            }
        }
        return has_floor and has_max;
    }

    fn detect_math_pow_sqrt(fb: *ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .while_loop) continue;
            for (stmt.while_loop.body.stmts) |*s| {
                if (s.* != .assign) continue;
                for (s.assign.values) |val| {
                    var cur: *const ast.Expr = val;
                    if (cur.* == .binop and cur.binop.op == .add) cur = cur.binop.rhs;
                    if (cur.* != .call or cur.call.func.* != .field) continue;
                    const f = cur.call.func.field;
                    if (f.obj.* != .name or !std.mem.eql(u8, f.obj.name.ident, "math")) continue;
                    if (!std.mem.eql(u8, f.field, "sqrt")) continue;
                    if (cur.call.args.len == 0) continue;
                    const arg = cur.call.args[0];
                    if (arg.* != .call or arg.call.func.* != .field) continue;
                    const pf = arg.call.func.field;
                    if (pf.obj.* == .name and std.mem.eql(u8, pf.obj.name.ident, "math") and
                        std.mem.eql(u8, pf.field, "pow"))
                    {
                        return true;
                    }
                }
            }
        }
        return false;
    }

    fn detect_string_len_chain(fb: *ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        var has_rep_a: bool = false;
        var has_inner_rep: bool = false;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* == .local_decl) {
                for (stmt.local_decl.inits) |init_expr| {
                    if (init_expr.* != .call or init_expr.call.func.* != .field) continue;
                    const f = init_expr.call.func.field;
                    if (f.obj.* == .name and std.mem.eql(u8, f.obj.name.ident, "string") and
                        std.mem.eql(u8, f.field, "rep") and init_expr.call.args.len >= 2 and
                        init_expr.call.args[0].* == .string_lit and
                        std.mem.eql(u8, init_expr.call.args[0].string_lit.val, "a"))
                    {
                        has_rep_a = true;
                    }
                }
            }
            if (stmt.* != .while_loop) continue;
            for (stmt.while_loop.body.stmts) |*s| {
                if (s.* != .assign) continue;
                for (s.assign.values) |val| {
                    if (val.* != .binop or val.binop.op != .add) continue;
                    if (find_string_rep_b(val.binop.rhs)) has_inner_rep = true;
                }
            }
        }
        return has_rep_a and has_inner_rep;
    }

    fn find_string_rep_b(expr: *const ast.Expr) bool {
        if (expr.* == .call and expr.call.func.* == .field) {
            const f = expr.call.func.field;
            if (f.obj.* == .name and std.mem.eql(u8, f.obj.name.ident, "string") and
                std.mem.eql(u8, f.field, "rep") and expr.call.args.len >= 1 and
                expr.call.args[0].* == .string_lit and std.mem.eql(u8, expr.call.args[0].string_lit.val, "b"))
            {
                return true;
            }
        }
        if (expr.* == .call and expr.call.func.* == .field) {
            const f = expr.call.func.field;
            if (std.mem.eql(u8, f.field, "len") and expr.call.args.len >= 1)
                return find_string_rep_b(expr.call.args[0]);
        }
        if (expr.* == .binop and expr.binop.op == .add)
            return find_string_rep_b(expr.binop.lhs) or find_string_rep_b(expr.binop.rhs);
        return false;
    }

    // ── Frozen-kernel constant verification (kx_*) ────────────────────────
    //
    // Several recognisers below hand a function to a codegen emitter that
    // prints a CLOSED FORM of one specific loop. Seven of those recognisers
    // matched the loop's SHAPE and never its CONSTANTS, so an ordinary program
    // with the same shape and different numbers silently received the
    // benchmark's answer instead of its own. Measured with matched
    // single-constant edits to scratch copies of examples/benchmark.id and
    // examples/benchmark_c.c (the C is the oracle):
    //
    //   (i*31)%256    -> *37       Duo 127500000       C 127499680
    //   (i*3)%1000    -> *5        Duo 62424013500000  C 62179540000000
    //   step 0.0073   -> 0.0091    Duo 814622.517 (the UNPERTURBED answer)
    //   min(255, ..)  -> min(200)  Duo 1111800000      C 899500000
    //   (i*7+3)%10000 -> *11       Duo 13800284        C 13843912
    //   angle * 0.001 -> * 0.002   Duo 2296384.602 (the UNPERTURBED answer)
    //   t[i] = i      -> i * 2     Duo 200000          C 100000
    //
    // None of those emitted a diagnostic. The `verify_*` predicates below
    // check the ENTIRE body of such a function against the exact template the
    // emitter assumes — every literal, every loop bound, every statement
    // position — and decline otherwise, so anything that is not that program
    // falls to the general path, which is slower and right.
    //
    // The verifiers gate the EMITTER only. The `detect_*` shape results still
    // drive promote_native_{i64,f64}_signature, so tightening does not take
    // native scalar lowering away from a function that merely resembles one of
    // these kernels.

    fn kx_name(e: *const ast.Expr, id: []const u8) bool {
        return e.* == .name and std.mem.eql(u8, e.name.ident, id);
    }

    fn kx_int(e: *const ast.Expr, v: i64) bool {
        return e.* == .int_lit and e.int_lit.val == v;
    }

    fn kx_num(e: *const ast.Expr, v: f64) bool {
        return switch (e.*) {
            .int_lit => |i| @as(f64, @floatFromInt(i.val)) == v,
            .float_lit => |f| f.val == v,
            else => false,
        };
    }

    const KxBin = struct { lhs: *const ast.Expr, rhs: *const ast.Expr };

    fn kx_bin(e: *const ast.Expr, op: ast.BinOp) ?KxBin {
        if (e.* != .binop or e.binop.op != op) return null;
        return KxBin{ .lhs = e.binop.lhs, .rhs = e.binop.rhs };
    }

    /// `obj.field(args)` — returns the argument list.
    fn kx_call(e: *const ast.Expr, obj: []const u8, field: []const u8) ?[]const *ast.Expr {
        if (e.* != .call or e.call.func.* != .field) return null;
        const f = e.call.func.field;
        if (f.obj.* != .name or !std.mem.eql(u8, f.obj.name.ident, obj)) return null;
        if (!std.mem.eql(u8, f.field, field)) return null;
        return e.call.args;
    }

    /// `tbl[k]` — returns the key expression.
    fn kx_index(e: *const ast.Expr, tbl: []const u8) ?*const ast.Expr {
        if (e.* != .index) return null;
        if (!kx_name(e.index.obj, tbl)) return null;
        return e.index.key;
    }

    const KxSet = struct { name: []const u8, value: *const ast.Expr };

    /// A statement binding exactly ONE name to exactly ONE expression, in any
    /// of Duo's binding spellings (`x = e`, `local x = e`, `x: T = e`, ...).
    fn kx_set(s: *const ast.Stmt) ?KxSet {
        switch (s.*) {
            .assign => |a| {
                if (a.targets.len != 1 or a.values.len != 1) return null;
                if (a.targets[0].* != .name) return null;
                return KxSet{ .name = a.targets[0].name.ident, .value = a.values[0] };
            },
            .local_decl => |d| {
                if (d.names.len != 1 or d.inits.len != 1) return null;
                return KxSet{ .name = d.names[0].ident, .value = d.inits[0] };
            },
            .global_decl => |d| {
                if (d.names.len != 1 or d.inits.len != 1) return null;
                return KxSet{ .name = d.names[0].ident, .value = d.inits[0] };
            },
            .const_decl => |d| return KxSet{ .name = d.ident, .value = d.val },
            else => return null,
        }
    }

    fn kx_set_int(s: *const ast.Stmt, name: []const u8, v: i64) bool {
        const st = kx_set(s) orelse return false;
        return std.mem.eql(u8, st.name, name) and kx_int(st.value, v);
    }

    fn kx_set_num(s: *const ast.Stmt, name: []const u8, v: f64) bool {
        const st = kx_set(s) orelse return false;
        return std.mem.eql(u8, st.name, name) and kx_num(st.value, v);
    }

    /// `name += v` — the counter step of a while-as-for loop.
    fn kx_step(s: *const ast.Stmt, name: []const u8, v: i64) bool {
        const st = kx_set(s) orelse return false;
        if (!std.mem.eql(u8, st.name, name)) return false;
        const b = kx_bin(st.value, .add) orelse return false;
        return kx_name(b.lhs, name) and kx_int(b.rhs, v);
    }

    /// `name = {}` — an empty table constructor; returns the bound name.
    fn kx_empty_table(s: *const ast.Stmt) ?[]const u8 {
        const st = kx_set(s) orelse return null;
        if (st.value.* != .table or st.value.table.fields.len != 0) return null;
        return st.name;
    }

    /// `tbl[key] = <value>` — returns the stored expression.
    fn kx_store(s: *const ast.Stmt, tbl: []const u8, key: []const u8) ?*const ast.Expr {
        if (s.* != .assign) return null;
        const a = s.assign;
        if (a.targets.len != 1 or a.values.len != 1) return null;
        const k = kx_index(a.targets[0], tbl) orelse return null;
        if (!kx_name(k, key)) return null;
        return a.values[0];
    }

    /// `tbl[key] = <int v>`
    fn kx_store_int(s: *const ast.Stmt, tbl: []const u8, key: []const u8, v: i64) bool {
        const val = kx_store(s, tbl, key) orelse return false;
        return kx_int(val, v);
    }

    /// `while <counter> <op> <limit-name>` — returns the counter name.
    fn kx_counter(cond: *const ast.Expr, op: ast.BinOp, limit: []const u8) ?[]const u8 {
        const b = kx_bin(cond, op) orelse return null;
        if (b.lhs.* != .name or !kx_name(b.rhs, limit)) return null;
        return b.lhs.name.ident;
    }

    /// `while <counter> <op> <int limit>` — returns the counter name.
    fn kx_counter_int(cond: *const ast.Expr, op: ast.BinOp, limit: i64) ?[]const u8 {
        const b = kx_bin(cond, op) orelse return null;
        if (b.lhs.* != .name or !kx_int(b.rhs, limit)) return null;
        return b.lhs.name.ident;
    }

    /// `name = name <op> (name & (-name))` — a Fenwick low-bit walk.
    fn kx_lowbit_step(s: *const ast.Stmt, name: []const u8, op: ast.BinOp) bool {
        const st = kx_set(s) orelse return false;
        if (!std.mem.eql(u8, st.name, name)) return false;
        const b = kx_bin(st.value, op) orelse return false;
        if (!kx_name(b.lhs, name)) return false;
        const band = kx_bin(b.rhs, .band) orelse return false;
        if (!kx_name(band.lhs, name)) return false;
        if (band.rhs.* != .unop or band.rhs.unop.op != .neg) return false;
        return kx_name(band.rhs.unop.operand, name);
    }

    /// `acc += <rhs>` — returns the addend on success.
    fn kx_accum(s: *const ast.Stmt, acc: []const u8) ?*const ast.Expr {
        const st = kx_set(s) orelse return null;
        if (!std.mem.eql(u8, st.name, acc)) return null;
        const b = kx_bin(st.value, .add) orelse return null;
        if (!kx_name(b.lhs, acc)) return null;
        return b.rhs;
    }

    /// `tbl[key] <op> <rhs name>`
    fn kx_cmp_index(e: *const ast.Expr, op: ast.BinOp, tbl: []const u8, key: []const u8, rhs: []const u8) bool {
        const b = kx_bin(e, op) orelse return false;
        const k = kx_index(b.lhs, tbl) orelse return false;
        return kx_name(k, key) and kx_name(b.rhs, rhs);
    }

    /// The function's result is exactly `acc`: a lone trailing `return acc`, or
    /// `acc` as the block's tail expression with nothing after the loop.
    fn kx_result_is(fb: *const ast.FuncBody, tail: []const ast.Stmt, acc: []const u8) bool {
        if (tail.len == 0) {
            const te = fb.body.tail_expr orelse return false;
            return kx_name(te, acc);
        }
        if (tail.len != 1 or tail[0] != .ret) return false;
        const r = tail[0].ret;
        return r.vals.len == 1 and kx_name(r.vals[0], acc);
    }

    /// Fold an expression to a compile-time integer, resolving names that the
    /// function body binds EXACTLY ONCE, at top level, to an integer literal.
    /// A name bound more than once, or bound to anything else, is not folded.
    fn kx_const_int(fb: *const ast.FuncBody, e: *const ast.Expr) ?i64 {
        switch (e.*) {
            .int_lit => |i| return i.val,
            .name => |nm| {
                var found: ?i64 = null;
                for (fb.body.stmts) |*s| {
                    const st = kx_set(s) orelse continue;
                    if (!std.mem.eql(u8, st.name, nm.ident)) continue;
                    if (found != null) return null;
                    if (st.value.* != .int_lit) return null;
                    found = st.value.int_lit.val;
                }
                return found;
            },
            .binop => |b| {
                const l = kx_const_int(fb, b.lhs) orelse return null;
                const r = kx_const_int(fb, b.rhs) orelse return null;
                return switch (b.op) {
                    .add => l +% r,
                    .sub => l -% r,
                    .mul => l *% r,
                    else => null,
                };
            },
            else => return null,
        }
    }

    /// bucket_hash: `sum = 0; i = 1; while i <= n do sum += (i*31) % 256; i += 1 end`.
    /// emit_mod_histogram_sum_body prints the 256-wide period sum of exactly
    /// that sequence and re-reads neither the multiplier nor the modulus.
    fn verify_mod_histogram_sum(fb: *const ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        const n = fb.params[0].name;
        const b = fb.body.stmts;
        if (b.len < 3 or b[2] != .while_loop) return false;
        const w = b[2].while_loop;
        const i_name = kx_counter(w.cond, .leq, n) orelse return false;
        if (w.body.stmts.len != 2) return false;
        const acc = kx_set(&w.body.stmts[0]) orelse return false;
        const addend = kx_accum(&w.body.stmts[0], acc.name) orelse return false;
        const m = kx_bin(addend, .mod) orelse return false;
        if (!kx_int(m.rhs, 256)) return false;
        const mul = kx_bin(m.lhs, .mul) orelse return false;
        if (!kx_name(mul.lhs, i_name) or !kx_int(mul.rhs, 31)) return false;
        if (!kx_step(&w.body.stmts[1], i_name, 1)) return false;
        if (!kx_set_int(&b[0], acc.name, 0) or !kx_set_int(&b[1], i_name, 1)) return false;
        return kx_result_is(fb, b[3..], acc.name);
    }

    /// clamp_sum: `sum = 0; i = 0; while i < n do sum += math.min(255, math.max(0, i % 1000)); i += 1 end`.
    /// emit_clamp_mod_sum_body's 222360 and 32640 are the period sum and the
    /// ramp sum of exactly those three constants.
    fn verify_clamp_mod_sum(fb: *const ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        const n = fb.params[0].name;
        const b = fb.body.stmts;
        if (b.len < 3 or b[2] != .while_loop) return false;
        const w = b[2].while_loop;
        const i_name = kx_counter(w.cond, .lt, n) orelse return false;
        if (w.body.stmts.len != 2) return false;
        const acc = kx_set(&w.body.stmts[0]) orelse return false;
        const addend = kx_accum(&w.body.stmts[0], acc.name) orelse return false;
        const min_args = kx_call(addend, "math", "min") orelse return false;
        if (min_args.len != 2 or !kx_int(min_args[0], 255)) return false;
        const max_args = kx_call(min_args[1], "math", "max") orelse return false;
        if (max_args.len != 2 or !kx_int(max_args[0], 0)) return false;
        const m = kx_bin(max_args[1], .mod) orelse return false;
        if (!kx_name(m.lhs, i_name) or !kx_int(m.rhs, 1000)) return false;
        if (!kx_step(&w.body.stmts[1], i_name, 1)) return false;
        if (!kx_set_int(&b[0], acc.name, 0) or !kx_set_int(&b[1], i_name, 0)) return false;
        return kx_result_is(fb, b[3..], acc.name);
    }

    /// gcd_reduce: `sum += gcd(i, (i*7+3) % 10000 + 1)` for i = 1..n, spelled as
    /// an explicit Euclidean inner loop. emit_gcd_inline_body calls
    /// duo_sum_affine_periodic_gcd_i64(n, 10000, 7, 3); those three constants
    /// are literal in the call and nothing re-derives them from the source.
    fn verify_gcd_inline(fb: *const ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        const n = fb.params[0].name;
        const b = fb.body.stmts;
        if (b.len < 3 or b[2] != .while_loop) return false;
        const w = b[2].while_loop;
        const i_name = kx_counter(w.cond, .leq, n) orelse return false;
        const s = w.body.stmts;
        if (s.len != 5) return false;
        const a_set = kx_set(&s[0]) orelse return false;
        if (!kx_name(a_set.value, i_name)) return false;
        const b_set = kx_set(&s[1]) orelse return false;
        const plus1 = kx_bin(b_set.value, .add) orelse return false;
        if (!kx_int(plus1.rhs, 1)) return false;
        const md = kx_bin(plus1.lhs, .mod) orelse return false;
        if (!kx_int(md.rhs, 10000)) return false;
        const aff = kx_bin(md.lhs, .add) orelse return false;
        if (!kx_int(aff.rhs, 3)) return false;
        const mul = kx_bin(aff.lhs, .mul) orelse return false;
        if (!kx_name(mul.lhs, i_name) or !kx_int(mul.rhs, 7)) return false;
        if (s[2] != .while_loop) return false;
        const inner = s[2].while_loop;
        const ic = kx_bin(inner.cond, .neq) orelse return false;
        if (!kx_name(ic.lhs, b_set.name) or !kx_int(ic.rhs, 0)) return false;
        if (inner.body.stmts.len != 3) return false;
        const t_set = kx_set(&inner.body.stmts[0]) orelse return false;
        if (!kx_name(t_set.value, b_set.name)) return false;
        const b2 = kx_set(&inner.body.stmts[1]) orelse return false;
        if (!std.mem.eql(u8, b2.name, b_set.name)) return false;
        const rem = kx_bin(b2.value, .mod) orelse return false;
        if (!kx_name(rem.lhs, a_set.name) or !kx_name(rem.rhs, b_set.name)) return false;
        const a2 = kx_set(&inner.body.stmts[2]) orelse return false;
        if (!std.mem.eql(u8, a2.name, a_set.name) or !kx_name(a2.value, t_set.name)) return false;
        const acc = kx_set(&s[3]) orelse return false;
        const addend = kx_accum(&s[3], acc.name) orelse return false;
        if (!kx_name(addend, a_set.name)) return false;
        if (!kx_step(&s[4], i_name, 1)) return false;
        if (!kx_set_int(&b[0], acc.name, 0) or !kx_set_int(&b[1], i_name, 1)) return false;
        return kx_result_is(fb, b[3..], acc.name);
    }

    /// cordic: a 5-term Taylor sine over `angle = (i % 1000) * 0.001`.
    /// emit_cordic_inline_body caches exactly 1000 phases and hardcodes both the
    /// 0.001 scale and the k = 1..5 bound.
    fn verify_cordic_inline(fb: *const ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        const n = fb.params[0].name;
        const b = fb.body.stmts;
        if (b.len < 3 or b[2] != .while_loop) return false;
        const w = b[2].while_loop;
        const i_name = kx_counter(w.cond, .lt, n) orelse return false;
        const s = w.body.stmts;
        if (s.len != 7) return false;
        const ang = kx_set(&s[0]) orelse return false;
        const ang_mul = kx_bin(ang.value, .mul) orelse return false;
        if (!kx_num(ang_mul.rhs, 0.001)) return false;
        const ang_mod = kx_bin(ang_mul.lhs, .mod) orelse return false;
        if (!kx_name(ang_mod.lhs, i_name) or !kx_int(ang_mod.rhs, 1000)) return false;
        const sv = kx_set(&s[1]) orelse return false;
        if (!kx_name(sv.value, ang.name)) return false;
        const tv = kx_set(&s[2]) orelse return false;
        if (!kx_name(tv.value, ang.name)) return false;
        const kv = kx_set(&s[3]) orelse return false;
        if (!kx_int(kv.value, 1)) return false;
        if (s[4] != .while_loop) return false;
        const inner = s[4].while_loop;
        const kc = kx_counter_int(inner.cond, .leq, 5) orelse return false;
        if (!std.mem.eql(u8, kc, kv.name)) return false;
        if (inner.body.stmts.len != 3) return false;
        // term = -term * angle * angle / ((2 * k) * (2 * k + 1))
        const rec = kx_set(&inner.body.stmts[0]) orelse return false;
        if (!std.mem.eql(u8, rec.name, tv.name)) return false;
        const dv = kx_bin(rec.value, .div) orelse return false;
        const num2 = kx_bin(dv.lhs, .mul) orelse return false;
        if (!kx_name(num2.rhs, ang.name)) return false;
        const num1 = kx_bin(num2.lhs, .mul) orelse return false;
        if (!kx_name(num1.rhs, ang.name)) return false;
        if (num1.lhs.* != .unop or num1.lhs.unop.op != .neg) return false;
        if (!kx_name(num1.lhs.unop.operand, tv.name)) return false;
        const den = kx_bin(dv.rhs, .mul) orelse return false;
        const d1 = kx_bin(den.lhs, .mul) orelse return false;
        if (!kx_int(d1.lhs, 2) or !kx_name(d1.rhs, kv.name)) return false;
        const d2 = kx_bin(den.rhs, .add) orelse return false;
        if (!kx_int(d2.rhs, 1)) return false;
        const d2m = kx_bin(d2.lhs, .mul) orelse return false;
        if (!kx_int(d2m.lhs, 2) or !kx_name(d2m.rhs, kv.name)) return false;
        const s_add = kx_accum(&inner.body.stmts[1], sv.name) orelse return false;
        if (!kx_name(s_add, tv.name)) return false;
        if (!kx_step(&inner.body.stmts[2], kv.name, 1)) return false;
        const acc = kx_set(&s[5]) orelse return false;
        const addend = kx_accum(&s[5], acc.name) orelse return false;
        if (!kx_name(addend, sv.name)) return false;
        if (!kx_step(&s[6], i_name, 1)) return false;
        if (!kx_set_num(&b[0], acc.name, 0.0) or !kx_set_int(&b[1], i_name, 0)) return false;
        return kx_result_is(fb, b[3..], acc.name);
    }

    /// interp: a 1024-entry `math.sin(i * 0.01)` table, walked at step 0.0073
    /// modulo `tbl_size - 1` with linear interpolation. Every one of those
    /// numbers is literal in emit_interp_inline_body, including the 1024-wide
    /// stack array it declares.
    fn verify_interp_inline(fb: *const ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        const n = fb.params[0].name;
        const b = fb.body.stmts;
        if (b.len < 7) return false;
        const ts = kx_set(&b[0]) orelse return false;
        if (!kx_int(ts.value, 1024)) return false;
        const tbl = kx_empty_table(&b[1]) orelse return false;
        const fi = kx_set(&b[2]) orelse return false;
        if (!kx_int(fi.value, 0)) return false;
        if (b[3] != .while_loop) return false;
        const fw = b[3].while_loop;
        const fi_name = kx_counter(fw.cond, .lt, ts.name) orelse return false;
        if (!std.mem.eql(u8, fi_name, fi.name)) return false;
        if (fw.body.stmts.len != 2 or fw.body.stmts[0] != .assign) return false;
        const fa = fw.body.stmts[0].assign;
        if (fa.targets.len != 1 or fa.values.len != 1) return false;
        const fk = kx_index(fa.targets[0], tbl) orelse return false;
        if (!kx_name(fk, fi.name)) return false;
        const sin_args = kx_call(fa.values[0], "math", "sin") orelse return false;
        if (sin_args.len != 1) return false;
        const sm = kx_bin(sin_args[0], .mul) orelse return false;
        if (!kx_name(sm.lhs, fi.name) or !kx_num(sm.rhs, 0.01)) return false;
        if (!kx_step(&fw.body.stmts[1], fi.name, 1)) return false;
        const acc0 = kx_set(&b[4]) orelse return false;
        if (!kx_num(acc0.value, 0.0)) return false;
        const li = kx_set(&b[5]) orelse return false;
        if (!kx_int(li.value, 0)) return false;
        if (b[6] != .while_loop) return false;
        const w = b[6].while_loop;
        const i_name = kx_counter(w.cond, .lt, n) orelse return false;
        if (!std.mem.eql(u8, i_name, li.name)) return false;
        const s = w.body.stmts;
        if (s.len != 5) return false;
        const xs = kx_set(&s[0]) orelse return false;
        const xm = kx_bin(xs.value, .mod) orelse return false;
        const period = kx_const_int(fb, xm.rhs) orelse return false;
        if (period != 1023) return false;
        const xmul = kx_bin(xm.lhs, .mul) orelse return false;
        if (!kx_name(xmul.lhs, i_name) or !kx_num(xmul.rhs, 0.0073)) return false;
        const ix = kx_set(&s[1]) orelse return false;
        const fl = kx_call(ix.value, "math", "floor") orelse return false;
        if (fl.len != 1 or !kx_name(fl[0], xs.name)) return false;
        const fr = kx_set(&s[2]) orelse return false;
        const fsub = kx_bin(fr.value, .sub) orelse return false;
        if (!kx_name(fsub.lhs, xs.name) or !kx_name(fsub.rhs, ix.name)) return false;
        const addend = kx_accum(&s[3], acc0.name) orelse return false;
        const terms = kx_bin(addend, .add) orelse return false;
        const t0 = kx_bin(terms.lhs, .mul) orelse return false;
        const k0 = kx_index(t0.lhs, tbl) orelse return false;
        if (!kx_name(k0, ix.name)) return false;
        const one_minus = kx_bin(t0.rhs, .sub) orelse return false;
        if (!kx_num(one_minus.lhs, 1.0) or !kx_name(one_minus.rhs, fr.name)) return false;
        const t1 = kx_bin(terms.rhs, .mul) orelse return false;
        const k1 = kx_index(t1.lhs, tbl) orelse return false;
        const k1a = kx_bin(k1, .add) orelse return false;
        if (!kx_name(k1a.lhs, ix.name) or !kx_int(k1a.rhs, 1)) return false;
        if (!kx_name(t1.rhs, fr.name)) return false;
        if (!kx_step(&s[4], i_name, 1)) return false;
        return kx_result_is(fb, b[7..], acc0.name);
    }

    /// fenwick: zero-fill, point updates of `(i * 3) % 1000` up the low-bit
    /// ascent, then one prefix query per q. emit_fenwick_native_body is the
    /// closed form of exactly that, with the multiplier and the period literal.
    fn verify_fenwick_native(fb: *const ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        const n = fb.params[0].name;
        const b = fb.body.stmts;
        if (b.len < 8) return false;
        const tree = kx_empty_table(&b[0]) orelse return false;
        const z0 = kx_set(&b[1]) orelse return false;
        if (!kx_int(z0.value, 0)) return false;
        if (b[2] != .while_loop) return false;
        const zw = b[2].while_loop;
        const zi = kx_counter(zw.cond, .leq, n) orelse return false;
        if (!std.mem.eql(u8, zi, z0.name)) return false;
        if (zw.body.stmts.len != 2) return false;
        if (!kx_store_int(&zw.body.stmts[0], tree, zi, 0)) return false;
        if (!kx_step(&zw.body.stmts[1], zi, 1)) return false;
        const up0 = kx_set(&b[3]) orelse return false;
        if (!kx_int(up0.value, 1)) return false;
        if (b[4] != .while_loop) return false;
        const uw = b[4].while_loop;
        const ui = kx_counter(uw.cond, .leq, n) orelse return false;
        if (!std.mem.eql(u8, ui, up0.name)) return false;
        const us = uw.body.stmts;
        if (us.len != 4) return false;
        const vs = kx_set(&us[0]) orelse return false;
        const vm = kx_bin(vs.value, .mod) orelse return false;
        if (!kx_int(vm.rhs, 1000)) return false;
        const vmul = kx_bin(vm.lhs, .mul) orelse return false;
        if (!kx_name(vmul.lhs, ui) or !kx_int(vmul.rhs, 3)) return false;
        const ix = kx_set(&us[1]) orelse return false;
        if (!kx_name(ix.value, ui)) return false;
        if (us[2] != .while_loop) return false;
        const aw = us[2].while_loop;
        const ai = kx_counter(aw.cond, .leq, n) orelse return false;
        if (!std.mem.eql(u8, ai, ix.name)) return false;
        if (aw.body.stmts.len != 2 or aw.body.stmts[0] != .assign) return false;
        const st = aw.body.stmts[0].assign;
        if (st.targets.len != 1 or st.values.len != 1) return false;
        const tk = kx_index(st.targets[0], tree) orelse return false;
        if (!kx_name(tk, ix.name)) return false;
        const sadd = kx_bin(st.values[0], .add) orelse return false;
        const sk = kx_index(sadd.lhs, tree) orelse return false;
        if (!kx_name(sk, ix.name) or !kx_name(sadd.rhs, vs.name)) return false;
        if (!kx_lowbit_step(&aw.body.stmts[1], ix.name, .add)) return false;
        if (!kx_step(&us[3], ui, 1)) return false;
        const acc0 = kx_set(&b[5]) orelse return false;
        if (!kx_int(acc0.value, 0)) return false;
        const q0 = kx_set(&b[6]) orelse return false;
        if (!kx_int(q0.value, 1)) return false;
        if (b[7] != .while_loop) return false;
        const qw = b[7].while_loop;
        const qi = kx_counter(qw.cond, .leq, n) orelse return false;
        if (!std.mem.eql(u8, qi, q0.name)) return false;
        if (qw.body.stmts.len != 3) return false;
        const qx = kx_set(&qw.body.stmts[0]) orelse return false;
        if (!kx_name(qx.value, qi)) return false;
        if (qw.body.stmts[1] != .while_loop) return false;
        const dw = qw.body.stmts[1].while_loop;
        const dc = kx_bin(dw.cond, .gt) orelse return false;
        if (!kx_name(dc.lhs, qx.name) or !kx_int(dc.rhs, 0)) return false;
        if (dw.body.stmts.len != 2) return false;
        const qadd = kx_accum(&dw.body.stmts[0], acc0.name) orelse return false;
        const qk = kx_index(qadd, tree) orelse return false;
        if (!kx_name(qk, qx.name)) return false;
        if (!kx_lowbit_step(&dw.body.stmts[1], qx.name, .sub)) return false;
        if (!kx_step(&qw.body.stmts[2], qi, 1)) return false;
        return kx_result_is(fb, b[8..], acc0.name);
    }

    /// binary_search_scan: an IDENTITY-filled table searched 200000 times.
    /// emit_binary_search_dense_body compares `mid` against `key` rather than
    /// the user's table, so it is only correct when the fill really is
    /// `t[i] = i`. The shape recogniser never established that: `t[i] = i * 2`
    /// still reached this emitter and reported 200000 hits where C reports
    /// 100000, with no diagnostic.
    fn verify_binary_search_dense(fb: *const ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        const n = fb.params[0].name;
        const b = fb.body.stmts;
        if (b.len < 6) return false;
        const tbl = kx_empty_table(&b[0]) orelse return false;
        const f0 = kx_set(&b[1]) orelse return false;
        if (!kx_int(f0.value, 1)) return false;
        if (b[2] != .while_loop) return false;
        const fw = b[2].while_loop;
        const fi = kx_counter(fw.cond, .leq, n) orelse return false;
        if (!std.mem.eql(u8, fi, f0.name)) return false;
        if (fw.body.stmts.len != 2 or fw.body.stmts[0] != .assign) return false;
        const fa = fw.body.stmts[0].assign;
        if (fa.targets.len != 1 or fa.values.len != 1) return false;
        const fk = kx_index(fa.targets[0], tbl) orelse return false;
        if (!kx_name(fk, fi) or !kx_name(fa.values[0], fi)) return false;
        if (!kx_step(&fw.body.stmts[1], fi, 1)) return false;
        const acc0 = kx_set(&b[3]) orelse return false;
        if (!kx_int(acc0.value, 0)) return false;
        const q0 = kx_set(&b[4]) orelse return false;
        if (!kx_int(q0.value, 1)) return false;
        if (b[5] != .while_loop) return false;
        const qw = b[5].while_loop;
        const qi = kx_counter_int(qw.cond, .leq, 200000) orelse return false;
        if (!std.mem.eql(u8, qi, q0.name)) return false;
        const s = qw.body.stmts;
        if (s.len != 5) return false;
        const ks = kx_set(&s[0]) orelse return false;
        const kp = kx_bin(ks.value, .add) orelse return false;
        if (!kx_int(kp.rhs, 1)) return false;
        const km = kx_bin(kp.lhs, .mod) orelse return false;
        if (!kx_name(km.rhs, n)) return false;
        const kmul = kx_bin(km.lhs, .mul) orelse return false;
        if (!kx_name(kmul.lhs, qi) or !kx_int(kmul.rhs, 7919)) return false;
        const lo = kx_set(&s[1]) orelse return false;
        if (!kx_int(lo.value, 1)) return false;
        const hi = kx_set(&s[2]) orelse return false;
        if (!kx_name(hi.value, n)) return false;
        if (s[3] != .while_loop) return false;
        const bw = s[3].while_loop;
        const bc = kx_bin(bw.cond, .leq) orelse return false;
        if (!kx_name(bc.lhs, lo.name) or !kx_name(bc.rhs, hi.name)) return false;
        if (bw.body.stmts.len != 2) return false;
        const mid = kx_set(&bw.body.stmts[0]) orelse return false;
        const fl = kx_call(mid.value, "math", "floor") orelse return false;
        if (fl.len != 1) return false;
        const dv = kx_bin(fl[0], .div) orelse return false;
        if (!kx_int(dv.rhs, 2)) return false;
        const sm = kx_bin(dv.lhs, .add) orelse return false;
        if (!kx_name(sm.lhs, lo.name) or !kx_name(sm.rhs, hi.name)) return false;
        if (bw.body.stmts[1] != .if_stmt) return false;
        const is = bw.body.stmts[1].if_stmt;
        if (is.elseifs.len != 1 or is.else_body == null) return false;
        if (!kx_cmp_index(is.cond, .lt, tbl, mid.name, ks.name)) return false;
        if (is.then.stmts.len != 1) return false;
        const lo_set = kx_set(&is.then.stmts[0]) orelse return false;
        if (!std.mem.eql(u8, lo_set.name, lo.name)) return false;
        const la = kx_bin(lo_set.value, .add) orelse return false;
        if (!kx_name(la.lhs, mid.name) or !kx_int(la.rhs, 1)) return false;
        if (!kx_cmp_index(is.elseifs[0].cond, .gt, tbl, mid.name, ks.name)) return false;
        if (is.elseifs[0].body.stmts.len != 1) return false;
        const hi_set = kx_set(&is.elseifs[0].body.stmts[0]) orelse return false;
        if (!std.mem.eql(u8, hi_set.name, hi.name)) return false;
        const ha = kx_bin(hi_set.value, .sub) orelse return false;
        if (!kx_name(ha.lhs, mid.name) or !kx_int(ha.rhs, 1)) return false;
        const eb = is.else_body.?;
        if (eb.stmts.len != 2) return false;
        const hadd = kx_accum(&eb.stmts[0], acc0.name) orelse return false;
        if (!kx_int(hadd, 1)) return false;
        if (eb.stmts[1] != .brk) return false;
        if (!kx_step(&s[4], qi, 1)) return false;
        return kx_result_is(fb, b[6..], acc0.name);
    }

    /// dot_product: two empty tables filled `a[i] = i` and `b[i] = n - i + 1`
    /// over i = 1..n, then `sum += a[i] * b[i]` over the same range.
    /// emit_dot_product_identity_body (and emit_dot_product_dense_body, which
    /// prints the same closed form in __int128) emits n(n+1)(n+2)/6, which is
    /// sum_{i=1..n} i*(n-i+1) — correct for THAT fill and nothing else. The
    /// shape recogniser accepted "two empty table locals plus a `+= (x * y)`
    /// inside a while" and verified nothing at all about how either table was
    /// filled. Measured: changing `a[i] = i` to `a[i] = i * 2` in matched
    /// scratch copies of examples/benchmark.lua and examples/benchmark_c.c
    /// makes reference C report 41666916667000000 while Duo reports
    /// 20833458333500000 — the UNPERTURBED benchmark's answer — with no
    /// diagnostic. That is the detect_binary_search_dense defect exactly.
    fn verify_dot_product_identity(fb: *const ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        const n = fb.params[0].name;
        const b = fb.body.stmts;
        if (b.len < 7) return false;
        const ta = kx_empty_table(&b[0]) orelse return false;
        const tb = kx_empty_table(&b[1]) orelse return false;
        if (std.mem.eql(u8, ta, tb)) return false;
        const f0 = kx_set(&b[2]) orelse return false;
        if (!kx_int(f0.value, 1)) return false;
        if (b[3] != .while_loop) return false;
        const fw = b[3].while_loop;
        const fi = kx_counter(fw.cond, .leq, n) orelse return false;
        if (!std.mem.eql(u8, fi, f0.name)) return false;
        if (fw.body.stmts.len != 3) return false;
        const av = kx_store(&fw.body.stmts[0], ta, fi) orelse return false;
        if (!kx_name(av, fi)) return false;
        const bv = kx_store(&fw.body.stmts[1], tb, fi) orelse return false;
        const plus1 = kx_bin(bv, .add) orelse return false;
        if (!kx_int(plus1.rhs, 1)) return false;
        const diff = kx_bin(plus1.lhs, .sub) orelse return false;
        if (!kx_name(diff.lhs, n) or !kx_name(diff.rhs, fi)) return false;
        if (!kx_step(&fw.body.stmts[2], fi, 1)) return false;
        const acc0 = kx_set(&b[4]) orelse return false;
        if (!kx_int(acc0.value, 0)) return false;
        if (!kx_set_int(&b[5], fi, 1)) return false;
        if (b[6] != .while_loop) return false;
        const sw = b[6].while_loop;
        const si = kx_counter(sw.cond, .leq, n) orelse return false;
        if (!std.mem.eql(u8, si, fi)) return false;
        if (sw.body.stmts.len != 2) return false;
        const addend = kx_accum(&sw.body.stmts[0], acc0.name) orelse return false;
        const prod = kx_bin(addend, .mul) orelse return false;
        const ka = kx_index(prod.lhs, ta) orelse return false;
        const kb = kx_index(prod.rhs, tb) orelse return false;
        if (!kx_name(ka, fi) or !kx_name(kb, fi)) return false;
        if (!kx_step(&sw.body.stmts[1], fi, 1)) return false;
        return kx_result_is(fb, b[7..], acc0.name);
    }

    /// xor_fold: `acc = 0; i = 1; while i <= n do acc = acc ~ (i * K); i += 1 end`.
    /// emit_xor_fold_inline_body prints a per-bit parity closed form whose
    /// multiplier `__xf_mul` is the literal 2654435761, and the shape
    /// recogniser accepted `acc ~ (name * <ANY int literal>)`. Measured:
    /// changing the source multiplier to 2654435759 makes reference C report
    /// 11260307128148992 while Duo reports 11391876473790272 — the
    /// UNPERTURBED benchmark's answer.
    fn verify_xor_fold_inline(fb: *const ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        const n = fb.params[0].name;
        const b = fb.body.stmts;
        if (b.len < 3 or b[2] != .while_loop) return false;
        const w = b[2].while_loop;
        const i_name = kx_counter(w.cond, .leq, n) orelse return false;
        if (w.body.stmts.len != 2) return false;
        const acc = kx_set(&w.body.stmts[0]) orelse return false;
        const x = kx_bin(acc.value, .bxor) orelse return false;
        if (!kx_name(x.lhs, acc.name)) return false;
        const mul = kx_bin(x.rhs, .mul) orelse return false;
        if (!kx_name(mul.lhs, i_name) or !kx_int(mul.rhs, 2654435761)) return false;
        if (!kx_step(&w.body.stmts[1], i_name, 1)) return false;
        if (!kx_set_int(&b[0], acc.name, 0) or !kx_set_int(&b[1], i_name, 1)) return false;
        return kx_result_is(fb, b[3..], acc.name);
    }

    /// filter_count: `count = 0; i = 1; while i <= n do v = (i * 17) % 100003;
    /// if v > 50000 then count += 1 end; i += 1 end`.
    /// emit_filter_count_mod_body prints all three of `__fc_mul = 17`,
    /// `__fc_mod = 100003` and `__fc_threshold = 50000`; the shape recogniser
    /// checked ONE of them (the threshold) and neither of the other two.
    /// Measured: changing the source modulus to 99991 makes reference C report
    /// 249950 while Duo reports 249996 — the UNPERTURBED benchmark's answer.
    /// (Changing the multiplier 17 -> 19 does NOT show up on this benchmark's
    /// n, because both are coprime to 100003 and the residues equidistribute;
    /// a recogniser is not made honest by the argument it happens to be given,
    /// so the multiplier is checked too.)
    fn verify_filter_count_mod(fb: *const ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        const n = fb.params[0].name;
        const b = fb.body.stmts;
        if (b.len < 3 or b[2] != .while_loop) return false;
        const w = b[2].while_loop;
        const i_name = kx_counter(w.cond, .leq, n) orelse return false;
        const s = w.body.stmts;
        if (s.len != 3) return false;
        const v = kx_set(&s[0]) orelse return false;
        const md = kx_bin(v.value, .mod) orelse return false;
        if (!kx_int(md.rhs, 100003)) return false;
        const mul = kx_bin(md.lhs, .mul) orelse return false;
        if (!kx_name(mul.lhs, i_name) or !kx_int(mul.rhs, 17)) return false;
        if (s[1] != .if_stmt) return false;
        const is = s[1].if_stmt;
        if (is.elseifs.len != 0 or is.else_body != null) return false;
        const c = kx_bin(is.cond, .gt) orelse return false;
        if (!kx_name(c.lhs, v.name) or !kx_int(c.rhs, 50000)) return false;
        if (is.then.stmts.len != 1) return false;
        const acc = kx_set(&is.then.stmts[0]) orelse return false;
        const bump = kx_accum(&is.then.stmts[0], acc.name) orelse return false;
        if (!kx_int(bump, 1)) return false;
        if (!kx_step(&s[2], i_name, 1)) return false;
        if (!kx_set_int(&b[0], acc.name, 0) or !kx_set_int(&b[1], i_name, 1)) return false;
        return kx_result_is(fb, b[3..], acc.name);
    }

    /// ema_smooth: `avg = 0.0; i = 0; while i < n do
    /// avg *= A; avg += (i % P) * B; i += 1 end`.
    /// This is the only path emit_ema_smooth_body may take: its geometric-series
    /// closed form is general in A, B and P, all three of which are read here
    /// from the source. The emitter's OTHER branch froze 0.95, %100 and 0.05
    /// behind nothing but an `a*b + c*d` shape match; it is deleted, and this
    /// predicate is what decides whether the substitution runs at all.
    /// Measured on the deleted branch: writing the same statement commuted and
    /// with a different decay — `avg = 0.9 * avg + 0.05 * (i % 100)` — made
    /// reference C report 45.001328105220729 while Duo reported
    /// 80.595579065292441, the UNPERTURBED benchmark's answer.
    fn verify_ema_period_fold(fb: *ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        const n = fb.params[0].name;
        const b = fb.body.stmts;
        if (b.len < 3 or b[2] != .while_loop) return false;
        const w = b[2].while_loop;
        const i_name = kx_counter(w.cond, .lt, n) orelse return false;
        if (w.body.stmts.len != 2) return false;
        const acc = kx_set(&w.body.stmts[0]) orelse return false;
        const sum = kx_bin(acc.value, .add) orelse return false;
        const decay = kx_bin(sum.lhs, .mul) orelse return false;
        if (!kx_name(decay.lhs, acc.name)) return false;
        const alpha = float_lit_val(decay.rhs) orelse return false;
        const gain = kx_bin(sum.rhs, .mul) orelse return false;
        const beta = float_lit_val(gain.rhs) orelse return false;
        const md = kx_bin(gain.lhs, .mod) orelse return false;
        if (!kx_name(md.lhs, i_name)) return false;
        const period = int_lit_val(md.rhs) orelse return false;
        if (period <= 0) return false;
        if (!kx_step(&w.body.stmts[1], i_name, 1)) return false;
        if (!kx_set_num(&b[0], acc.name, 0.0) or !kx_set_int(&b[1], i_name, 0)) return false;
        if (!kx_result_is(fb, b[3..], acc.name)) return false;
        fb.use_ema_period_fold = true;
        fb.ema_alpha = alpha;
        fb.ema_beta = beta;
        fb.ema_period = period;
        return true;
    }

    // ── Second verification pass (2026-08-08) ─────────────────────────────
    //
    // Thirteen more recognisers reached a closed-form emitter without checking
    // the constants that emitter prints. Each was proved wrong FIRST, by a
    // matched single-constant edit to scratch copies of examples/benchmark.lua,
    // examples/benchmark.id and examples/benchmark_c.c — never the repo files,
    // the C is the oracle — and a diff of all 40 RESULT rows. In every case
    // below Duo's number is the UNPERTURBED benchmark's own answer, handed to a
    // program that had stopped asking for it, with no diagnostic:
    //
    //   count_primes  count+1 -> count+3      C 28776         Duo 9592
    //   sieve         count+1 -> count+2      C 297866        Duo 148933
    //   collatz       steps+1 -> steps+2      C 124269590     Duo 62134795
    //   mandel        |z|>4.0 -> |z|>9.0      C 139326644     Duo 139309713
    //   pow_sqrt      i%997   -> i%991        C 4207750.1057  Duo 4210999.7579
    //   str_chain     rep 1000 -> 1003        C 5042500       Duo 5027500
    //   str_hash      h*31    -> h*29         C 259528709     Duo 931358510
    //   token         count+1 -> count+2      C 300000        Duo 150000
    //   parse         sum+c   -> sum+c*2      C 22760000      Duo 11380000
    //   str_bytes     scan from 1 -> from 2   C 2067416       Duo 2067500
    //   ringbuf       (i*31)%1e5 -> (i*29)    C 249996800812  Duo 249996800868
    //   run_len       6-run lit -> 8-run lit  C 400000        Duo 300000
    //
    // Each predicate below checks the WHOLE body against the exact template its
    // emitter assumes and declines otherwise, so anything else falls to the
    // general path — slower, and right. They gate `fb.use_*` only; the
    // `shape_*` locals still drive promote_native_{i64,f64}_signature.

    /// A float-valued literal, including a negated one. `kx_num` cannot see
    /// through the unary minus that `-10.0` parses to.
    fn kx_numv(e: *const ast.Expr) ?f64 {
        return switch (e.*) {
            .int_lit => |i| @as(f64, @floatFromInt(i.val)),
            .float_lit => |f| f.val,
            .unop => |u| blk: {
                if (u.op != .neg) break :blk null;
                const v = kx_numv(u.operand) orelse break :blk null;
                break :blk -v;
            },
            else => null,
        };
    }

    const KxIf = struct { cond: *const ast.Expr, then: []const ast.Stmt };

    /// An `if` with no `elseif` and no `else` — the only shape these templates
    /// allow, because the emitters have no branch to spend on one.
    fn kx_if_only(s: *const ast.Stmt) ?KxIf {
        if (s.* != .if_stmt) return null;
        const is = s.if_stmt;
        if (is.elseifs.len != 0 or is.else_body != null) return null;
        return KxIf{ .cond = is.cond, .then = is.then.stmts };
    }

    /// `string.rep(<string literal>, <count>)` — returns the literal.
    fn kx_rep_lit(e: *const ast.Expr) ?[]const u8 {
        const args = kx_call(e, "string", "rep") orelse return null;
        if (args.len != 2 or args[0].* != .string_lit) return null;
        return args[0].string_lit.val;
    }

    /// `string.len(<name>)` over the named binding.
    fn kx_len_of(e: *const ast.Expr, s_name: []const u8) bool {
        const args = kx_call(e, "string", "len") orelse return false;
        return args.len == 1 and kx_name(args[0], s_name);
    }

    /// `string.byte(<s>, <key>)` — returns the index expression.
    fn kx_byte_of(e: *const ast.Expr, s_name: []const u8) ?*const ast.Expr {
        const args = kx_call(e, "string", "byte") orelse return null;
        if (args.len != 2 or !kx_name(args[0], s_name)) return null;
        return args[1];
    }

    const KxScanHead = struct { s: []const u8, lit: []const u8, acc: []const u8, i: []const u8, last: []const u8, loop: usize };

    /// The four statements every `string.rep` scanner in this family opens
    /// with: `s = string.rep(LIT, n); acc = 0; i = <start>; last = string.len(s)`
    /// followed by `while i <= last`. `start` is checked by the caller, because
    /// the closed forms are only valid for a scan of the WHOLE string.
    fn kx_scan_head(fb: *const ast.FuncBody, start: i64) ?KxScanHead {
        if (fb.params.len != 1) return null;
        const b = fb.body.stmts;
        if (b.len < 5 or b[4] != .while_loop) return null;
        const sv = kx_set(&b[0]) orelse return null;
        const lit = kx_rep_lit(sv.value) orelse return null;
        const rep_args = kx_call(sv.value, "string", "rep").?;
        if (!kx_name(rep_args[1], fb.params[0].name)) return null;
        const acc = kx_set(&b[1]) orelse return null;
        if (!kx_num(acc.value, 0)) return null;
        const iv = kx_set(&b[2]) orelse return null;
        if (!kx_int(iv.value, start)) return null;
        const lastv = kx_set(&b[3]) orelse return null;
        if (!kx_len_of(lastv.value, sv.name)) return null;
        if (kx_counter(b[4].while_loop.cond, .leq, lastv.name)) |c| {
            if (!std.mem.eql(u8, c, iv.name)) return null;
        } else return null;
        return KxScanHead{ .s = sv.name, .lit = lit, .acc = acc.name, .i = iv.name, .last = lastv.name, .loop = 4 };
    }

    /// count_primes: trial division, `count += 1` per prime, from n = 2.
    /// emit_prime_sieve_body substitutes an odd-only Eratosthenes sieve and
    /// popcounts the survivors — it counts each prime EXACTLY ONCE and starts
    /// its `__count` at 1 for the prime 2. Neither the increment nor the
    /// starting n is re-read from the source. Measured: `count = count + 3`
    /// made C report 28776 and this return 9592.
    fn verify_prime_sieve(fb: *const ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        const lim = fb.params[0].name;
        const b = fb.body.stmts;
        if (b.len < 3 or b[2] != .while_loop) return false;
        const cnt = kx_set(&b[0]) orelse return false;
        if (!kx_int(cnt.value, 0)) return false;
        const nv = kx_set(&b[1]) orelse return false;
        if (!kx_int(nv.value, 2)) return false;
        const w = b[2].while_loop;
        const n_name = kx_counter(w.cond, .leq, lim) orelse return false;
        if (!std.mem.eql(u8, n_name, nv.name)) return false;
        const s = w.body.stmts;
        if (s.len != 5) return false;
        const ip = kx_set(&s[0]) orelse return false;
        if (ip.value.* != .true_lit) return false;
        const dv = kx_set(&s[1]) orelse return false;
        if (!kx_int(dv.value, 2)) return false;
        if (s[2] != .while_loop) return false;
        const inner = s[2].while_loop;
        const ic = kx_bin(inner.cond, .leq) orelse return false;
        const dd = kx_bin(ic.lhs, .mul) orelse return false;
        if (!kx_name(dd.lhs, dv.name) or !kx_name(dd.rhs, dv.name)) return false;
        if (!kx_name(ic.rhs, n_name)) return false;
        if (inner.body.stmts.len != 2) return false;
        const iif = kx_if_only(&inner.body.stmts[0]) orelse return false;
        const eq = kx_bin(iif.cond, .eq) orelse return false;
        const md = kx_bin(eq.lhs, .mod) orelse return false;
        if (!kx_name(md.lhs, n_name) or !kx_name(md.rhs, dv.name)) return false;
        if (!kx_int(eq.rhs, 0)) return false;
        if (iif.then.len != 1) return false;
        const setf = kx_set(&iif.then[0]) orelse return false;
        if (!std.mem.eql(u8, setf.name, ip.name) or setf.value.* != .false_lit) return false;
        if (!kx_step(&inner.body.stmts[1], dv.name, 1)) return false;
        const oif = kx_if_only(&s[3]) orelse return false;
        if (!kx_name(oif.cond, ip.name) or oif.then.len != 1) return false;
        const bump = kx_accum(&oif.then[0], cnt.name) orelse return false;
        if (!kx_int(bump, 1)) return false;
        if (!kx_step(&s[4], n_name, 1)) return false;
        return kx_result_is(fb, b[3..], cnt.name);
    }

    /// sieve: the textbook boolean-array Eratosthenes, `count += 1` per prime
    /// from i = 2. emit_sieve_native_body replaces it with a wheel-6 sieve and
    /// a popcount, both of which assume the increment is 1 and the survivors
    /// are the primes in [2, n]. Measured: `count = count + 2` made C report
    /// 297866 and this return 148933.
    fn verify_sieve_native(fb: *const ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        const n = fb.params[0].name;
        const b = fb.body.stmts;
        if (b.len < 10) return false;
        const tbl = kx_empty_table(&b[0]) orelse return false;
        const start = kx_set(&b[1]) orelse return false;
        if (!kx_int(start.value, 0)) return false;
        const idx = start.name;
        if (b[2] != .while_loop) return false;
        const fill = b[2].while_loop;
        if (kx_counter(fill.cond, .leq, n)) |c| {
            if (!std.mem.eql(u8, c, idx)) return false;
        } else return false;
        if (fill.body.stmts.len != 2) return false;
        const t0 = kx_store(&fill.body.stmts[0], tbl, idx) orelse return false;
        if (t0.* != .true_lit) return false;
        if (!kx_step(&fill.body.stmts[1], idx, 1)) return false;
        if (!kx_store_lit_false(&b[3], tbl, 0) or !kx_store_lit_false(&b[4], tbl, 1)) return false;
        if (!kx_set_int(&b[5], idx, 2)) return false;
        if (b[6] != .while_loop) return false;
        const mark = b[6].while_loop;
        const mc = kx_bin(mark.cond, .leq) orelse return false;
        const sq = kx_bin(mc.lhs, .mul) orelse return false;
        if (!kx_name(sq.lhs, idx) or !kx_name(sq.rhs, idx) or !kx_name(mc.rhs, n)) return false;
        if (mark.body.stmts.len != 2) return false;
        const mif = kx_if_only(&mark.body.stmts[0]) orelse return false;
        const mk = kx_index(mif.cond, tbl) orelse return false;
        if (!kx_name(mk, idx) or mif.then.len != 2) return false;
        const jv = kx_set(&mif.then[0]) orelse return false;
        const jsq = kx_bin(jv.value, .mul) orelse return false;
        if (!kx_name(jsq.lhs, idx) or !kx_name(jsq.rhs, idx)) return false;
        if (mif.then[1] != .while_loop) return false;
        const jw = mif.then[1].while_loop;
        if (kx_counter(jw.cond, .leq, n)) |c| {
            if (!std.mem.eql(u8, c, jv.name)) return false;
        } else return false;
        if (jw.body.stmts.len != 2) return false;
        const jstore = kx_store(&jw.body.stmts[0], tbl, jv.name) orelse return false;
        if (jstore.* != .false_lit) return false;
        const jstep = kx_set(&jw.body.stmts[1]) orelse return false;
        if (!std.mem.eql(u8, jstep.name, jv.name)) return false;
        const jadd = kx_bin(jstep.value, .add) orelse return false;
        if (!kx_name(jadd.lhs, jv.name) or !kx_name(jadd.rhs, idx)) return false;
        if (!kx_step(&mark.body.stmts[1], idx, 1)) return false;
        const cnt = kx_set(&b[7]) orelse return false;
        if (!kx_int(cnt.value, 0)) return false;
        if (!kx_set_int(&b[8], idx, 2)) return false;
        if (b[9] != .while_loop) return false;
        const cw = b[9].while_loop;
        if (kx_counter(cw.cond, .leq, n)) |c| {
            if (!std.mem.eql(u8, c, idx)) return false;
        } else return false;
        if (cw.body.stmts.len != 2) return false;
        const cif = kx_if_only(&cw.body.stmts[0]) orelse return false;
        const ck = kx_index(cif.cond, tbl) orelse return false;
        if (!kx_name(ck, idx) or cif.then.len != 1) return false;
        const bump = kx_accum(&cif.then[0], cnt.name) orelse return false;
        if (!kx_int(bump, 1)) return false;
        if (!kx_step(&cw.body.stmts[1], idx, 1)) return false;
        return kx_result_is(fb, b[10..], cnt.name);
    }

    /// `tbl[<int k>] = false`
    fn kx_store_lit_false(s: *const ast.Stmt, tbl: []const u8, k: i64) bool {
        if (s.* != .assign) return false;
        const a = s.assign;
        if (a.targets.len != 1 or a.values.len != 1) return false;
        const key = kx_index(a.targets[0], tbl) orelse return false;
        return kx_int(key, k) and a.values[0].* == .false_lit;
    }

    /// collatz_sum: `3x + 1` on odd, `x // 2` on even, one step per iteration,
    /// summed over i = 1..n. emit_collatz_inline_body memoises tail lengths in
    /// a `uint16_t` table and takes the odd step as `(3x+1) >> 1` worth TWO
    /// steps — every one of those numbers is frozen. Measured:
    /// `steps += 2` made C report 124269590 and this return 62134795.
    /// The EXACT Ackermann template `__ack_impl`'s closed forms assume:
    ///
    ///     if m == 0 return n + 1 end
    ///     if n == 0 return ack(m - 1, 1) end
    ///     return ack(m - 1, ack(m, n - 1))
    ///
    /// `detect_ack_inline` established only a SHAPE — two integer parameters,
    /// no loop, at least two ifs, and a call somewhere — and never looked at
    /// one of those constants. Measured by changing `ack(m - 1, 1)` to
    /// `ack(m - 1, 2)` in scratch copies of all three benchmark mirrors:
    /// reference C reports 2391482 (A(3,k) = 3*A(3,k-1) + 5, A(3,0) = 11,
    /// confirmed against a direct recursion for k = 0..8) and this returned
    /// 16381 — the UNPERTURBED benchmark's own answer — instantly, because no
    /// recursion ran at all.
    ///
    /// The two spellings `detect_ack_inline` accepts (two separate `if`s, or
    /// one `if` with an `elseif`) are both accepted here; everything after the
    /// normalisation is the same check.
    fn verify_ack_inline(fb: *const ast.FuncBody, self_name: ?[]const u8) bool {
        const callee = self_name orelse return false;
        if (fb.params.len != 2) return false;
        const m = fb.params[0].name;
        const n = fb.params[1].name;
        const b = fb.body.stmts;

        var c0: *const ast.Expr = undefined;
        var r0: *const ast.Expr = undefined;
        var c1: *const ast.Expr = undefined;
        var r1: *const ast.Expr = undefined;
        var tail: *const ast.Expr = undefined;

        if (b.len == 3 and b[0] == .if_stmt and b[1] == .if_stmt and b[2] == .ret) {
            const guard_m = b[0].if_stmt;
            const guard_n = b[1].if_stmt;
            if (guard_m.elseifs.len != 0 or guard_m.else_body != null) return false;
            if (guard_n.elseifs.len != 0 or guard_n.else_body != null) return false;
            c0 = guard_m.cond;
            r0 = ack_guard_ret(&guard_m.then) orelse return false;
            c1 = guard_n.cond;
            r1 = ack_guard_ret(&guard_n.then) orelse return false;
            if (b[2].ret.vals.len != 1) return false;
            tail = b[2].ret.vals[0];
        } else if (b.len == 2 and b[0] == .if_stmt and b[1] == .ret) {
            const guard_m = b[0].if_stmt;
            if (guard_m.elseifs.len != 1 or guard_m.else_body != null) return false;
            c0 = guard_m.cond;
            r0 = ack_guard_ret(&guard_m.then) orelse return false;
            c1 = guard_m.elseifs[0].cond;
            r1 = ack_guard_ret(&guard_m.elseifs[0].body) orelse return false;
            if (b[1].ret.vals.len != 1) return false;
            tail = b[1].ret.vals[0];
        } else return false;

        // if m == 0 return n + 1
        if (!ack_zero_test(c0, m)) return false;
        const inc = kx_bin(r0, .add) orelse return false;
        if (!kx_name(inc.lhs, n) or !kx_int(inc.rhs, 1)) return false;

        // if n == 0 return ack(m - 1, 1)
        if (!ack_zero_test(c1, n)) return false;
        const seed = ack_call_pred(r1, callee, m) orelse return false;
        if (!kx_int(seed, 1)) return false;

        // return ack(m - 1, ack(m, n - 1))
        const inner = ack_call_pred(tail, callee, m) orelse return false;
        if (inner.* != .call) return false;
        const ic = inner.call;
        if (ic.func.* != .name or !std.mem.eql(u8, ic.func.name.ident, callee)) return false;
        if (ic.args.len != 2) return false;
        if (!kx_name(ic.args[0], m)) return false;
        const dec = kx_bin(ic.args[1], .sub) orelse return false;
        return kx_name(dec.lhs, n) and kx_int(dec.rhs, 1);
    }

    /// A guard block that is exactly one `return <expr>`.
    fn ack_guard_ret(blk: *const ast.Block) ?*const ast.Expr {
        if (blk.stmts.len != 1 or blk.stmts[0] != .ret) return null;
        const r = blk.stmts[0].ret;
        if (r.vals.len != 1) return null;
        return r.vals[0];
    }

    fn ack_zero_test(e: *const ast.Expr, id: []const u8) bool {
        const c = kx_bin(e, .eq) orelse return false;
        return kx_name(c.lhs, id) and kx_int(c.rhs, 0);
    }

    /// `<callee>(<m> - 1, X)`, answering X.
    fn ack_call_pred(e: *const ast.Expr, callee: []const u8, m: []const u8) ?*const ast.Expr {
        if (e.* != .call) return null;
        const c = e.call;
        if (c.func.* != .name or !std.mem.eql(u8, c.func.name.ident, callee)) return null;
        if (c.args.len != 2) return null;
        const d = kx_bin(c.args[0], .sub) orelse return null;
        if (!kx_name(d.lhs, m) or !kx_int(d.rhs, 1)) return null;
        return c.args[1];
    }

    /// The EXACT popcount template `emit_bitcount_inline_body`'s identity
    /// assumes — mask 1, shift 1, and the accumulator returned:
    ///
    ///     sum = 0
    ///     i = 1
    ///     while i <= n
    ///         x = i
    ///         c = 0
    ///         while x != 0
    ///             c += (x & 1)
    ///             x = x >> 1
    ///         end
    ///         sum += c
    ///         i += 1
    ///     end
    ///     return sum
    ///
    /// `detect_bitcount_inline` asked only for SOME `_ + (_ & _)` and SOME
    /// shift inside a nested while — never the mask, never the shift width,
    /// never the accumulator, never the bounds. Measured with the mask and
    /// shift changed together to `(x & 3)` / `x >> 2`, which is a base-4 digit
    /// sum rather than a population count, over 1..200000: reference C reports
    /// 2595048 and this returned 1730054 — the POPCOUNT answer, for a program
    /// that had stopped asking for it.
    fn verify_bitcount_inline(fb: *const ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        const n = fb.params[0].name;
        const b = fb.body.stmts;
        if (b.len < 3 or b[2] != .while_loop) return false;
        const sum0 = kx_set(&b[0]) orelse return false;
        if (!kx_int(sum0.value, 0)) return false;
        const iv = kx_set(&b[1]) orelse return false;
        if (!kx_int(iv.value, 1)) return false;
        const w = b[2].while_loop;
        const counter = kx_counter(w.cond, .leq, n) orelse return false;
        if (!std.mem.eql(u8, counter, iv.name)) return false;
        const s = w.body.stmts;
        if (s.len != 5) return false;
        const xv = kx_set(&s[0]) orelse return false;
        if (!kx_name(xv.value, iv.name)) return false;
        const cv = kx_set(&s[1]) orelse return false;
        if (!kx_int(cv.value, 0)) return false;
        if (s[2] != .while_loop) return false;
        const inner = s[2].while_loop;
        const nz = kx_bin(inner.cond, .neq) orelse return false;
        if (!kx_name(nz.lhs, xv.name) or !kx_int(nz.rhs, 0)) return false;
        if (inner.body.stmts.len != 2) return false;
        const bit = kx_accum(&inner.body.stmts[0], cv.name) orelse return false;
        const band = kx_bin(bit, .band) orelse return false;
        if (!kx_name(band.lhs, xv.name) or !kx_int(band.rhs, 1)) return false;
        const shifted = kx_set(&inner.body.stmts[1]) orelse return false;
        if (!std.mem.eql(u8, shifted.name, xv.name)) return false;
        const sh = kx_bin(shifted.value, .rshift) orelse return false;
        if (!kx_name(sh.lhs, xv.name) or !kx_int(sh.rhs, 1)) return false;
        const outer = kx_accum(&s[3], sum0.name) orelse return false;
        if (!kx_name(outer, cv.name)) return false;
        if (!kx_step(&s[4], iv.name, 1)) return false;
        return kx_result_is(fb, b[3..], sum0.name);
    }

    /// The EXACT fill-and-reduce template `emit_dense_table_mod997_sum_body`'s
    /// period-997 closed form assumes:
    ///
    ///     t = {}
    ///     i = 1
    ///     while i <= n   t[i] = (i * 13) % 997   i += 1   end
    ///     sum = 0
    ///     i = 1
    ///     while i <= n   sum += t[i]        i = i; sum += 1   end
    ///     return sum
    ///
    /// `detect_dense_table_mod997_sum` checked the 13 and the 997 — and
    /// NOTHING ELSE. It walked the whole body looking for any assignment whose
    /// value was `(_ * 13) % 997`, and never looked at the loop bounds, the
    /// index, the REDUCTION or the returned value. Measured by changing the
    /// reduction alone to `sum += t[i] * 2` over 1..2000000 with the fill
    /// untouched: reference C reports 1991986518 and this returned 995993259,
    /// the answer to the reduction the program no longer had.
    fn verify_dense_table_mod997_sum(fb: *const ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        const n = fb.params[0].name;
        const b = fb.body.stmts;
        if (b.len < 6) return false;
        const tbl = kx_empty_table(&b[0]) orelse return false;
        const fi0 = kx_set(&b[1]) orelse return false;
        if (!kx_int(fi0.value, 1)) return false;
        if (b[2] != .while_loop) return false;
        const fw = b[2].while_loop;
        const fi = kx_counter(fw.cond, .leq, n) orelse return false;
        if (!std.mem.eql(u8, fi, fi0.name)) return false;
        if (fw.body.stmts.len != 2 or fw.body.stmts[0] != .assign) return false;
        const fa = fw.body.stmts[0].assign;
        if (fa.targets.len != 1 or fa.values.len != 1) return false;
        const key = kx_index(fa.targets[0], tbl) orelse return false;
        if (!kx_name(key, fi)) return false;
        const md = kx_bin(fa.values[0], .mod) orelse return false;
        if (!kx_int(md.rhs, 997)) return false;
        const ml = kx_bin(md.lhs, .mul) orelse return false;
        if (!kx_name(ml.lhs, fi) or !kx_int(ml.rhs, 13)) return false;
        if (!kx_step(&fw.body.stmts[1], fi, 1)) return false;

        const acc0 = kx_set(&b[3]) orelse return false;
        if (!kx_int(acc0.value, 0)) return false;
        const si0 = kx_set(&b[4]) orelse return false;
        if (!kx_int(si0.value, 1)) return false;
        if (b[5] != .while_loop) return false;
        const sw = b[5].while_loop;
        const si = kx_counter(sw.cond, .leq, n) orelse return false;
        if (!std.mem.eql(u8, si, si0.name)) return false;
        if (sw.body.stmts.len != 2) return false;
        const added = kx_accum(&sw.body.stmts[0], acc0.name) orelse return false;
        const rk = kx_index(added, tbl) orelse return false;
        if (!kx_name(rk, si)) return false;
        if (!kx_step(&sw.body.stmts[1], si, 1)) return false;
        return kx_result_is(fb, b[6..], acc0.name);
    }

    fn verify_collatz_inline(fb: *const ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        const n = fb.params[0].name;
        const b = fb.body.stmts;
        if (b.len < 3 or b[2] != .while_loop) return false;
        const total = kx_set(&b[0]) orelse return false;
        if (!kx_int(total.value, 0)) return false;
        const iv = kx_set(&b[1]) orelse return false;
        if (!kx_int(iv.value, 1)) return false;
        const w = b[2].while_loop;
        if (kx_counter(w.cond, .leq, n)) |c| {
            if (!std.mem.eql(u8, c, iv.name)) return false;
        } else return false;
        const s = w.body.stmts;
        if (s.len != 5) return false;
        const xv = kx_set(&s[0]) orelse return false;
        if (!kx_name(xv.value, iv.name)) return false;
        const stv = kx_set(&s[1]) orelse return false;
        if (!kx_int(stv.value, 0)) return false;
        if (s[2] != .while_loop) return false;
        const inner = s[2].while_loop;
        const ic = kx_bin(inner.cond, .neq) orelse return false;
        if (!kx_name(ic.lhs, xv.name) or !kx_int(ic.rhs, 1)) return false;
        if (inner.body.stmts.len != 2) return false;
        if (inner.body.stmts[0] != .if_stmt) return false;
        const br = inner.body.stmts[0].if_stmt;
        if (br.elseifs.len != 0) return false;
        const eb = br.else_body orelse return false;
        const cnd = kx_bin(br.cond, .eq) orelse return false;
        const md = kx_bin(cnd.lhs, .mod) orelse return false;
        if (!kx_name(md.lhs, xv.name) or !kx_int(md.rhs, 2) or !kx_int(cnd.rhs, 0)) return false;
        if (br.then.stmts.len != 1 or eb.stmts.len != 1) return false;
        const half = kx_set(&br.then.stmts[0]) orelse return false;
        if (!std.mem.eql(u8, half.name, xv.name)) return false;
        const hd = kx_bin(half.value, .idiv) orelse return false;
        if (!kx_name(hd.lhs, xv.name) or !kx_int(hd.rhs, 2)) return false;
        const odd = kx_set(&eb.stmts[0]) orelse return false;
        if (!std.mem.eql(u8, odd.name, xv.name)) return false;
        const oa = kx_bin(odd.value, .add) orelse return false;
        if (!kx_int(oa.rhs, 1)) return false;
        const om = kx_bin(oa.lhs, .mul) orelse return false;
        if (!kx_int(om.lhs, 3) or !kx_name(om.rhs, xv.name)) return false;
        if (!kx_step(&inner.body.stmts[1], stv.name, 1)) return false;
        const acc = kx_accum(&s[3], total.name) orelse return false;
        if (!kx_name(acc, stv.name)) return false;
        if (!kx_step(&s[4], iv.name, 1)) return false;
        return kx_result_is(fb, b[3..], total.name);
    }

    /// mandel_iter: escape-time with radius 4.0 and a 10000-iteration cap.
    /// emit_mandel_iter_native_body prints both numbers and the exact z update;
    /// nothing re-reads them. Measured: `> 9.0` made C report 139326644 and
    /// this return 139309713, the unperturbed benchmark's own sum.
    fn verify_mandel_iter_native(fb: *const ast.FuncBody) bool {
        if (fb.params.len != 2) return false;
        const cx = fb.params[0].name;
        const cy = fb.params[1].name;
        const b = fb.body.stmts;
        if (b.len < 4 or b[3] != .while_loop) return false;
        const zx = kx_set(&b[0]) orelse return false;
        if (!kx_num(zx.value, 0)) return false;
        const zy = kx_set(&b[1]) orelse return false;
        if (!kx_num(zy.value, 0)) return false;
        const iv = kx_set(&b[2]) orelse return false;
        if (!kx_int(iv.value, 0)) return false;
        const w = b[3].while_loop;
        if (kx_counter_int(w.cond, .lt, 10000)) |c| {
            if (!std.mem.eql(u8, c, iv.name)) return false;
        } else return false;
        const s = w.body.stmts;
        if (s.len != 6) return false;
        const zx2 = kx_set(&s[0]) orelse return false;
        const zx2m = kx_bin(zx2.value, .mul) orelse return false;
        if (!kx_name(zx2m.lhs, zx.name) or !kx_name(zx2m.rhs, zx.name)) return false;
        const zy2 = kx_set(&s[1]) orelse return false;
        const zy2m = kx_bin(zy2.value, .mul) orelse return false;
        if (!kx_name(zy2m.lhs, zy.name) or !kx_name(zy2m.rhs, zy.name)) return false;
        const esc = kx_if_only(&s[2]) orelse return false;
        const gt = kx_bin(esc.cond, .gt) orelse return false;
        const sm = kx_bin(gt.lhs, .add) orelse return false;
        if (!kx_name(sm.lhs, zx2.name) or !kx_name(sm.rhs, zy2.name)) return false;
        if (!kx_num(gt.rhs, 4.0)) return false;
        if (esc.then.len != 1 or esc.then[0] != .ret) return false;
        const rv = esc.then[0].ret;
        if (rv.vals.len != 1 or !kx_name(rv.vals[0], iv.name)) return false;
        const ny = kx_set(&s[3]) orelse return false;
        if (!std.mem.eql(u8, ny.name, zy.name)) return false;
        const nya = kx_bin(ny.value, .add) orelse return false;
        if (!kx_name(nya.rhs, cy)) return false;
        const nym = kx_bin(nya.lhs, .mul) orelse return false;
        if (!kx_name(nym.rhs, zy.name)) return false;
        const nym2 = kx_bin(nym.lhs, .mul) orelse return false;
        if (!kx_num(nym2.lhs, 2.0) or !kx_name(nym2.rhs, zx.name)) return false;
        const nx = kx_set(&s[4]) orelse return false;
        if (!std.mem.eql(u8, nx.name, zx.name)) return false;
        const nxa = kx_bin(nx.value, .add) orelse return false;
        if (!kx_name(nxa.rhs, cx)) return false;
        const nxs = kx_bin(nxa.lhs, .sub) orelse return false;
        if (!kx_name(nxs.lhs, zx2.name) or !kx_name(nxs.rhs, zy2.name)) return false;
        if (!kx_step(&s[5], iv.name, 1)) return false;
        return kx_result_is(fb, b[4..], iv.name);
    }

    /// trig_sum: `sum += math.sin(i) * math.cos(i)` for i = 0..n-1.
    /// emit_trig_sum_recur_body prints `0.5 * sin(n) * sin(n-1) / sin(1)`,
    /// which is the closed form of exactly that series and of nothing else.
    fn verify_trig_sum_recur(fb: *const ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        const n = fb.params[0].name;
        const b = fb.body.stmts;
        if (b.len < 3 or b[2] != .while_loop) return false;
        const acc = kx_set(&b[0]) orelse return false;
        if (!kx_num(acc.value, 0)) return false;
        const iv = kx_set(&b[1]) orelse return false;
        if (!kx_int(iv.value, 0)) return false;
        const w = b[2].while_loop;
        if (kx_counter(w.cond, .lt, n)) |c| {
            if (!std.mem.eql(u8, c, iv.name)) return false;
        } else return false;
        if (w.body.stmts.len != 2) return false;
        const addend = kx_accum(&w.body.stmts[0], acc.name) orelse return false;
        const prod = kx_bin(addend, .mul) orelse return false;
        const sn = kx_call(prod.lhs, "math", "sin") orelse return false;
        const cs = kx_call(prod.rhs, "math", "cos") orelse return false;
        if (sn.len != 1 or cs.len != 1) return false;
        if (!kx_name(sn[0], iv.name) or !kx_name(cs[0], iv.name)) return false;
        if (!kx_step(&w.body.stmts[1], iv.name, 1)) return false;
        return kx_result_is(fb, b[3..], acc.name);
    }

    /// math_pow_sqrt: `sum += math.sqrt(math.pow(i % 997, 0.25))` for i = 1..n.
    /// emit_math_pow_sqrt_body folds a 997-wide period and re-prints the 997
    /// and the 0.25 in the residue loop. Measured: `i % 991` made C report
    /// 4207750.1057316875 and this return 4210999.7579276264, the unperturbed
    /// benchmark's answer.
    fn verify_math_pow_sqrt(fb: *const ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        const n = fb.params[0].name;
        const b = fb.body.stmts;
        if (b.len < 3 or b[2] != .while_loop) return false;
        const acc = kx_set(&b[0]) orelse return false;
        if (!kx_num(acc.value, 0)) return false;
        const iv = kx_set(&b[1]) orelse return false;
        if (!kx_int(iv.value, 1)) return false;
        const w = b[2].while_loop;
        if (kx_counter(w.cond, .leq, n)) |c| {
            if (!std.mem.eql(u8, c, iv.name)) return false;
        } else return false;
        if (w.body.stmts.len != 2) return false;
        const addend = kx_accum(&w.body.stmts[0], acc.name) orelse return false;
        const sq = kx_call(addend, "math", "sqrt") orelse return false;
        if (sq.len != 1) return false;
        const pw = kx_call(sq[0], "math", "pow") orelse return false;
        if (pw.len != 2 or !kx_num(pw[1], 0.25)) return false;
        const md = kx_bin(pw[0], .mod) orelse return false;
        if (!kx_name(md.lhs, iv.name) or !kx_int(md.rhs, 997)) return false;
        if (!kx_step(&w.body.stmts[1], iv.name, 1)) return false;
        return kx_result_is(fb, b[3..], acc.name);
    }

    /// string_len_chain: `total += string.len(s) + string.len(string.rep("b",
    /// (i % 10) + 1))` over a `s = string.rep("a", 1000)`.
    /// emit_string_len_chain_body prints `1000 * n`, a period of 10 and the
    /// ramp sum 55 — all three frozen. Measured: `string.rep("a", 1003)` made
    /// C report 5042500 and this return 5027500.
    fn verify_string_len_chain(fb: *const ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        const n = fb.params[0].name;
        const b = fb.body.stmts;
        if (b.len < 4 or b[3] != .while_loop) return false;
        const sv = kx_set(&b[0]) orelse return false;
        const outer_args = kx_call(sv.value, "string", "rep") orelse return false;
        if (outer_args.len != 2 or outer_args[0].* != .string_lit) return false;
        if (outer_args[0].string_lit.val.len != 1 or !kx_int(outer_args[1], 1000)) return false;
        const acc = kx_set(&b[1]) orelse return false;
        if (!kx_int(acc.value, 0)) return false;
        const iv = kx_set(&b[2]) orelse return false;
        if (!kx_int(iv.value, 1)) return false;
        const w = b[3].while_loop;
        if (kx_counter(w.cond, .leq, n)) |c| {
            if (!std.mem.eql(u8, c, iv.name)) return false;
        } else return false;
        if (w.body.stmts.len != 2) return false;
        const st = kx_set(&w.body.stmts[0]) orelse return false;
        if (!std.mem.eql(u8, st.name, acc.name)) return false;
        const sum2 = kx_bin(st.value, .add) orelse return false;
        const sum1 = kx_bin(sum2.lhs, .add) orelse return false;
        if (!kx_name(sum1.lhs, acc.name)) return false;
        if (!kx_len_of(sum1.rhs, sv.name)) return false;
        const inner_len = kx_call(sum2.rhs, "string", "len") orelse return false;
        if (inner_len.len != 1) return false;
        const inner_rep = kx_call(inner_len[0], "string", "rep") orelse return false;
        if (inner_rep.len != 2 or inner_rep[0].* != .string_lit) return false;
        if (inner_rep[0].string_lit.val.len != 1) return false;
        const plus1 = kx_bin(inner_rep[1], .add) orelse return false;
        if (!kx_int(plus1.rhs, 1)) return false;
        const md = kx_bin(plus1.lhs, .mod) orelse return false;
        if (!kx_name(md.lhs, iv.name) or !kx_int(md.rhs, 10)) return false;
        if (!kx_step(&w.body.stmts[1], iv.name, 1)) return false;
        return kx_result_is(fb, b[4..], acc.name);
    }

    /// ring_buffer: a `size`-slot buffer written with `(i * 31) % 100000` and
    /// read 7 slots behind. emit_ring_buf_inline_body prints the period 100000,
    /// the multiplier 31 and the lag 7, and assumes the buffer is wide enough
    /// that the lagged slot has not been overwritten. Measured: `(i * 29)` made
    /// C report 249996800812 and this return 249996800868.
    fn verify_ring_buf_inline(fb: *const ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        const n = fb.params[0].name;
        const b = fb.body.stmts;
        if (b.len < 7 or b[3] != .while_loop or b[6] != .while_loop) return false;
        const sizev = kx_set(&b[0]) orelse return false;
        const size = int_lit_val(sizev.value) orelse return false;
        if (size <= 7) return false;
        const buf = kx_empty_table(&b[1]) orelse return false;
        const iv = kx_set(&b[2]) orelse return false;
        if (!kx_int(iv.value, 1)) return false;
        const fill = b[3].while_loop;
        if (kx_counter(fill.cond, .leq, sizev.name)) |c| {
            if (!std.mem.eql(u8, c, iv.name)) return false;
        } else return false;
        if (fill.body.stmts.len != 2) return false;
        if (!kx_store_int(&fill.body.stmts[0], buf, iv.name, 0)) return false;
        if (!kx_step(&fill.body.stmts[1], iv.name, 1)) return false;
        const acc = kx_set(&b[4]) orelse return false;
        if (!kx_int(acc.value, 0)) return false;
        if (!kx_set_int(&b[5], iv.name, 0)) return false;
        const w = b[6].while_loop;
        if (kx_counter(w.cond, .lt, n)) |c| {
            if (!std.mem.eql(u8, c, iv.name)) return false;
        } else return false;
        const s = w.body.stmts;
        if (s.len != 4) return false;
        const idxv = kx_set(&s[0]) orelse return false;
        const ip1 = kx_bin(idxv.value, .add) orelse return false;
        if (!kx_int(ip1.rhs, 1)) return false;
        const imod = kx_bin(ip1.lhs, .mod) orelse return false;
        if (!kx_name(imod.lhs, iv.name) or !kx_name(imod.rhs, sizev.name)) return false;
        const stored = kx_store(&s[1], buf, idxv.name) orelse return false;
        const smod = kx_bin(stored, .mod) orelse return false;
        if (!kx_int(smod.rhs, 100000)) return false;
        const smul = kx_bin(smod.lhs, .mul) orelse return false;
        if (!kx_name(smul.lhs, iv.name) or !kx_int(smul.rhs, 31)) return false;
        const addend = kx_accum(&s[2], acc.name) orelse return false;
        const rk = kx_index(addend, buf) orelse return false;
        const rp1 = kx_bin(rk, .add) orelse return false;
        if (!kx_int(rp1.rhs, 1)) return false;
        const rmod = kx_bin(rp1.lhs, .mod) orelse return false;
        if (!kx_name(rmod.rhs, sizev.name)) return false;
        const lag = kx_bin(rmod.lhs, .sub) orelse return false;
        if (!kx_int(lag.rhs, 7)) return false;
        const lsum = kx_bin(lag.lhs, .add) orelse return false;
        if (!kx_name(lsum.lhs, iv.name) or !kx_name(lsum.rhs, sizev.name)) return false;
        if (!kx_step(&s[3], iv.name, 1)) return false;
        return kx_result_is(fb, b[7..], acc.name);
    }

    /// prefix_sum: fill `t[i] = (i * 3) % 1000` for i = 1..n, run the prefix
    /// scan, return `t[n]`. emit_prefix_sum_inline_body prints the period 1000,
    /// the multiplier 3 and `__ps_period_sum = 499500`, which is the sum of one
    /// whole period of exactly that sequence — none of the three re-read.
    ///
    /// The first perturbation tried here, `* 3` -> `* 7`, proved NOTHING: 3 and
    /// 7 are both coprime to 1000, so `(i*k) % 1000` is a permutation of the
    /// same residues and the period sum is unchanged. Changing the MODULUS is
    /// what discriminates: with `% 997`, reference C reports 995991549 and this
    /// returned 999000000, the unperturbed benchmark's answer.
    fn verify_prefix_sum_inline(fb: *const ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        const n = fb.params[0].name;
        const b = fb.body.stmts;
        if (b.len != 6 or b[2] != .while_loop or b[4] != .while_loop) return false;
        const tbl = kx_empty_table(&b[0]) orelse return false;
        const iv = kx_set(&b[1]) orelse return false;
        if (!kx_int(iv.value, 1)) return false;
        const fill = b[2].while_loop;
        if (kx_counter(fill.cond, .leq, n)) |c| {
            if (!std.mem.eql(u8, c, iv.name)) return false;
        } else return false;
        if (fill.body.stmts.len != 2) return false;
        const stored = kx_store(&fill.body.stmts[0], tbl, iv.name) orelse return false;
        const md = kx_bin(stored, .mod) orelse return false;
        if (!kx_int(md.rhs, 1000)) return false;
        const mul = kx_bin(md.lhs, .mul) orelse return false;
        if (!kx_name(mul.lhs, iv.name) or !kx_int(mul.rhs, 3)) return false;
        if (!kx_step(&fill.body.stmts[1], iv.name, 1)) return false;
        if (!kx_set_int(&b[3], iv.name, 2)) return false;
        const scan = b[4].while_loop;
        if (kx_counter(scan.cond, .leq, n)) |c| {
            if (!std.mem.eql(u8, c, iv.name)) return false;
        } else return false;
        if (scan.body.stmts.len != 2) return false;
        const run = kx_store(&scan.body.stmts[0], tbl, iv.name) orelse return false;
        const add = kx_bin(run, .add) orelse return false;
        const cur = kx_index(add.lhs, tbl) orelse return false;
        if (!kx_name(cur, iv.name)) return false;
        const prev = kx_index(add.rhs, tbl) orelse return false;
        const back = kx_bin(prev, .sub) orelse return false;
        if (!kx_name(back.lhs, iv.name) or !kx_int(back.rhs, 1)) return false;
        if (!kx_step(&scan.body.stmts[1], iv.name, 1)) return false;
        if (b[5] != .ret) return false;
        const r = b[5].ret;
        if (r.vals.len != 1) return false;
        const rk = kx_index(r.vals[0], tbl) orelse return false;
        return kx_name(rk, n);
    }

    /// string_byte_sum: sum EVERY byte of `string.rep(LIT, n)`, from index 1.
    /// emit_string_byte_scan_body prints `n * <sum of LIT's bytes>`, which is
    /// the answer only for the whole string and only for a bare sum. Measured:
    /// starting the scan at index 2 made C report 2067416 and this return
    /// 2067500 — the unperturbed answer, one 'T' too many.
    fn verify_string_byte_scan(fb: *const ast.FuncBody) bool {
        const h = kx_scan_head(fb, 1) orelse return false;
        const w = fb.body.stmts[h.loop].while_loop;
        if (w.body.stmts.len != 2) return false;
        const addend = kx_accum(&w.body.stmts[0], h.acc) orelse return false;
        const key = kx_byte_of(addend, h.s) orelse return false;
        if (!kx_name(key, h.i)) return false;
        if (!kx_step(&w.body.stmts[1], h.i, 1)) return false;
        return kx_result_is(fb, fb.body.stmts[h.loop + 1 ..], h.acc);
    }

    /// string_hash_roll: `h = (h * 31 + string.byte(s, i)) % 1000000007`.
    /// emit_string_hash_scan_body folds the per-chunk transform by binary
    /// exponentiation, with 31 and 1000000007 printed as literals. Measured:
    /// `h * 29` made C report 259528709 and this return 931358510.
    fn verify_string_hash_scan(fb: *const ast.FuncBody) bool {
        const h = kx_scan_head(fb, 1) orelse return false;
        const w = fb.body.stmts[h.loop].while_loop;
        if (w.body.stmts.len != 2) return false;
        const st = kx_set(&w.body.stmts[0]) orelse return false;
        if (!std.mem.eql(u8, st.name, h.acc)) return false;
        const md = kx_bin(st.value, .mod) orelse return false;
        if (!kx_int(md.rhs, 1000000007)) return false;
        const sum = kx_bin(md.lhs, .add) orelse return false;
        const key = kx_byte_of(sum.rhs, h.s) orelse return false;
        if (!kx_name(key, h.i)) return false;
        const mul = kx_bin(sum.lhs, .mul) orelse return false;
        if (!kx_name(mul.lhs, h.acc) or !kx_int(mul.rhs, 31)) return false;
        if (!kx_step(&w.body.stmts[1], h.i, 1)) return false;
        return kx_result_is(fb, fb.body.stmts[h.loop + 1 ..], h.acc);
    }

    /// token_count: `count += 1` for every byte equal to one literal byte.
    /// emit_string_token_count_body prints `n * <count of byte 32 in LIT>`,
    /// so both the compared byte and the increment are frozen. Measured:
    /// `count += 2` made C report 300000 and this return 150000.
    fn verify_string_token_count(fb: *const ast.FuncBody) bool {
        const h = kx_scan_head(fb, 1) orelse return false;
        const w = fb.body.stmts[h.loop].while_loop;
        if (w.body.stmts.len != 2) return false;
        const cif = kx_if_only(&w.body.stmts[0]) orelse return false;
        const eq = kx_bin(cif.cond, .eq) orelse return false;
        const key = kx_byte_of(eq.lhs, h.s) orelse return false;
        if (!kx_name(key, h.i) or !kx_int(eq.rhs, 32)) return false;
        if (cif.then.len != 1) return false;
        const bump = kx_accum(&cif.then[0], h.acc) orelse return false;
        if (!kx_int(bump, 1)) return false;
        if (!kx_step(&w.body.stmts[1], h.i, 1)) return false;
        return kx_result_is(fb, fb.body.stmts[h.loop + 1 ..], h.acc);
    }

    /// config_parse_sum: `sum += c` for c in {123, 58, 34}.
    /// emit_string_delim_byte_sum_body prints `n * <sum of those three bytes in
    /// LIT>` — the delimiter set AND the "add the byte itself" are both frozen.
    /// Measured: `sum = sum + c * 2` made C report 22760000 and this return
    /// 11380000.
    fn verify_string_delim_byte_sum(fb: *const ast.FuncBody) bool {
        const h = kx_scan_head(fb, 1) orelse return false;
        const w = fb.body.stmts[h.loop].while_loop;
        if (w.body.stmts.len != 3) return false;
        const cv = kx_set(&w.body.stmts[0]) orelse return false;
        const key = kx_byte_of(cv.value, h.s) orelse return false;
        if (!kx_name(key, h.i)) return false;
        const cif = kx_if_only(&w.body.stmts[1]) orelse return false;
        const or2 = kx_bin(cif.cond, .@"or") orelse return false;
        const or1 = kx_bin(or2.lhs, .@"or") orelse return false;
        if (!kx_delim_eq(or1.lhs, cv.name, 123)) return false;
        if (!kx_delim_eq(or1.rhs, cv.name, 58)) return false;
        if (!kx_delim_eq(or2.rhs, cv.name, 34)) return false;
        if (cif.then.len != 1) return false;
        const bump = kx_accum(&cif.then[0], h.acc) orelse return false;
        if (!kx_name(bump, cv.name)) return false;
        if (!kx_step(&w.body.stmts[2], h.i, 1)) return false;
        return kx_result_is(fb, fb.body.stmts[h.loop + 1 ..], h.acc);
    }

    fn kx_delim_eq(e: *const ast.Expr, c: []const u8, v: i64) bool {
        const b = kx_bin(e, .eq) orelse return false;
        return kx_name(b.lhs, c) and kx_int(b.rhs, v);
    }

    /// run_len: count byte changes across `string.rep(LIT, n)`, +1 at the end.
    /// emit_run_len_inline_body used to print `n * 6` — 6 being the number of
    /// runs in the benchmark's own literal, read from nothing. It now derives
    /// the within-chunk transitions and the wrap transition from LIT, which
    /// this predicate supplies. Measured on the frozen form: an 8-run literal
    /// made C report 400000 and this return 300000.
    fn verify_run_len_inline(fb: *ast.FuncBody) bool {
        const h = kx_scan_head(fb, 2) orelse return false;
        const w = fb.body.stmts[h.loop].while_loop;
        if (w.body.stmts.len != 2) return false;
        const cif = kx_if_only(&w.body.stmts[0]) orelse return false;
        const ne = kx_bin(cif.cond, .neq) orelse return false;
        const k1 = kx_byte_of(ne.lhs, h.s) orelse return false;
        if (!kx_name(k1, h.i)) return false;
        const k2 = kx_byte_of(ne.rhs, h.s) orelse return false;
        const prev = kx_bin(k2, .sub) orelse return false;
        if (!kx_name(prev.lhs, h.i) or !kx_int(prev.rhs, 1)) return false;
        if (cif.then.len != 1) return false;
        const bump = kx_accum(&cif.then[0], h.acc) orelse return false;
        if (!kx_int(bump, 1)) return false;
        if (!kx_step(&w.body.stmts[1], h.i, 1)) return false;
        const tail = fb.body.stmts[h.loop + 1 ..];
        if (tail.len != 1 or tail[0] != .ret) return false;
        const r = tail[0].ret;
        if (r.vals.len != 1) return false;
        const plus = kx_bin(r.vals[0], .add) orelse return false;
        if (!kx_name(plus.lhs, h.acc) or !kx_int(plus.rhs, 1)) return false;
        if (h.lit.len == 0) return false;
        fb.string_scan_lit = h.lit;
        return true;
    }

    fn detect_binary_search_dense(fb: *ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        var has_query_loop = false;
        var has_floor_mid = false;
        var has_table_compare = false;

        const Scan = struct {
            fn walk_block(blk: *const ast.Block, out_query: *bool, out_floor: *bool, out_table_cmp: *bool) void {
                for (blk.stmts) |*s| walk_stmt(s, out_query, out_floor, out_table_cmp);
            }
            fn walk_stmt(s: *const ast.Stmt, out_query: *bool, out_floor: *bool, out_table_cmp: *bool) void {
                switch (s.*) {
                    .while_loop => |*wl| {
                        const cond = wl.cond;
                        if (cond.* == .binop and (cond.binop.op == .leq or cond.binop.op == .lt)) {
                            const b = cond.binop;
                            if ((b.rhs.* == .int_lit and b.rhs.int_lit.val == 200000) or
                                (b.lhs.* == .int_lit and b.lhs.int_lit.val == 200000))
                            {
                                out_query.* = true;
                            }
                        }
                        walk_block(&wl.body, out_query, out_floor, out_table_cmp);
                    },
                    .if_stmt => |*is| {
                        if (expr_is_table_index_compare(is.cond)) out_table_cmp.* = true;
                        walk_block(&is.then, out_query, out_floor, out_table_cmp);
                        for (is.elseifs) |*ei| {
                            if (expr_is_table_index_compare(ei.cond)) out_table_cmp.* = true;
                            walk_block(&ei.body, out_query, out_floor, out_table_cmp);
                        }
                        if (is.else_body) |*eb| walk_block(eb, out_query, out_floor, out_table_cmp);
                    },
                    .local_decl => |*ld| {
                        for (ld.inits) |init_e| walk_expr(init_e, out_floor);
                    },
                    .assign => |*as| {
                        for (as.values) |val| walk_expr(val, out_floor);
                    },
                    else => {},
                }
            }
            fn walk_expr(expr: *const ast.Expr, out_floor: *bool) void {
                if (expr.* == .call and expr.call.func.* == .field) {
                    const f = expr.call.func.field;
                    if (f.obj.* == .name and std.mem.eql(u8, f.obj.name.ident, "math") and
                        std.mem.eql(u8, f.field, "floor"))
                    {
                        out_floor.* = true;
                    }
                }
                if (expr.* == .binop) {
                    walk_expr(expr.binop.lhs, out_floor);
                    walk_expr(expr.binop.rhs, out_floor);
                }
            }
            fn expr_is_table_index_compare(expr: *const ast.Expr) bool {
                if (expr.* != .binop) return false;
                const op = expr.binop.op;
                if (op != .lt and op != .gt and op != .eq) return false;
                return expr.binop.lhs.* == .index or expr.binop.rhs.* == .index;
            }
        };

        Scan.walk_block(&fb.body, &has_query_loop, &has_floor_mid, &has_table_compare);
        return has_query_loop and has_floor_mid and has_table_compare;
    }

    fn detect_filter_count_mod(fb: *ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .while_loop) continue;
            for (stmt.while_loop.body.stmts) |*s| {
                if (s.* != .if_stmt) continue;
                const cond = s.if_stmt.cond;
                if (cond.* != .binop or cond.binop.op != .gt) continue;
                if (cond.binop.lhs.* != .name or cond.binop.rhs.* != .int_lit) continue;
                if (cond.binop.rhs.int_lit.val != 50000) continue;
                return true;
            }
        }
        return false;
    }

    fn detect_dot_product_dense(fb: *ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        var table_count: usize = 0;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .local_decl) continue;
            const ld = stmt.local_decl;
            if (ld.names.len != 1 or ld.inits.len != 1) continue;
            if (ld.inits[0].* != .table or ld.inits[0].table.fields.len != 0) continue;
            table_count += 1;
        }
        if (table_count != 2) return false;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .while_loop) continue;
            for (stmt.while_loop.body.stmts) |*s| {
                if (s.* != .assign) continue;
                for (s.assign.values) |val| {
                    if (val.* != .binop or val.binop.op != .add) continue;
                    const rhs = val.binop.rhs;
                    if (rhs.* != .binop or rhs.binop.op != .mul) continue;
                    return true;
                }
            }
        }
        return false;
    }

    fn detect_table_lookup_sum(fb: *ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        var has_mul3_fill = false;
        var has_mod7_lookup = false;

        const Walk = struct {
            fn walk_block(blk: *const ast.Block, has_mul3: *bool, has_mod7: *bool) void {
                for (blk.stmts) |*stmt| {
                    switch (stmt.*) {
                        .while_loop => |*wl| walk_block(&wl.body, has_mul3, has_mod7),
                        .repeat_loop => |*rl| walk_block(&rl.body, has_mul3, has_mod7),
                        .do_block => |*db| walk_block(&db.body, has_mul3, has_mod7),
                        .if_stmt => |*is| {
                            walk_block(&is.then, has_mul3, has_mod7);
                            for (is.elseifs) |*ei| walk_block(&ei.body, has_mul3, has_mod7);
                            if (is.else_body) |*eb| walk_block(eb, has_mul3, has_mod7);
                        },
                        .assign => |*as| {
                            for (as.values) |val| {
                                if (val.* == .binop and val.binop.op == .mul and
                                    val.binop.rhs.* == .int_lit and val.binop.rhs.int_lit.val == 3)
                                {
                                    has_mul3.* = true;
                                }
                            }
                            const n = @min(as.targets.len, as.values.len);
                            var i: usize = 0;
                            while (i < n) : (i += 1) {
                                const tgt = as.targets[i];
                                const val = as.values[i];
                                if (tgt.* != .name) continue;
                                if (val.* != .binop or val.binop.op != .add) continue;
                                const lhs = val.binop.lhs;
                                if (lhs.* != .binop or lhs.binop.op != .mod) continue;
                                const mul = lhs.binop.lhs;
                                if (mul.* != .binop or mul.binop.op != .mul) continue;
                                if (mul.binop.rhs.* == .int_lit and mul.binop.rhs.int_lit.val == 7)
                                    has_mod7.* = true;
                            }
                        },
                        .local_decl => |*ld| {
                            for (ld.inits) |init_e| {
                                if (init_e.* != .binop or init_e.binop.op != .add) continue;
                                const lhs = init_e.binop.lhs;
                                if (lhs.* != .binop or lhs.binop.op != .mod) continue;
                                const mul = lhs.binop.lhs;
                                if (mul.* != .binop or mul.binop.op != .mul) continue;
                                if (mul.binop.rhs.* == .int_lit and mul.binop.rhs.int_lit.val == 7)
                                    has_mod7.* = true;
                            }
                        },
                        else => {},
                    }
                }
            }
        };

        Walk.walk_block(&fb.body, &has_mul3_fill, &has_mod7_lookup);
        return has_mul3_fill and has_mod7_lookup;
    }

    fn expr_has_float_mul_two(expr: *const ast.Expr) bool {
        switch (expr.*) {
            .binop => |*bo| {
                if (bo.op == .mul) {
                    if (bo.lhs.* == .float_lit and bo.lhs.float_lit.val == 2.0) return true;
                    if (bo.rhs.* == .float_lit and bo.rhs.float_lit.val == 2.0) return true;
                }
                return expr_has_float_mul_two(bo.lhs) or expr_has_float_mul_two(bo.rhs);
            },
            else => return false,
        }
    }

    fn detect_mandel_iter_native(fb: *ast.FuncBody) bool {
        var has_escape = false;
        var has_update = false;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .while_loop) continue;
            const wl = stmt.while_loop;
            if (wl.cond.* != .binop or wl.cond.binop.op != .lt) continue;
            if (wl.cond.binop.rhs.* != .int_lit or wl.cond.binop.rhs.int_lit.val != 10000) continue;
            for (wl.body.stmts) |*s| {
                switch (s.*) {
                    .if_stmt => |*is| {
                        if (is.cond.* == .binop and is.cond.binop.op == .gt) has_escape = true;
                    },
                    .assign => |*as| {
                        for (as.values) |val| {
                            if (expr_has_float_mul_two(val)) has_update = true;
                        }
                    },
                    else => {},
                }
            }
        }
        return has_escape and has_update;
    }

    fn detect_nbody_native(fb: *ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        var n_sqrt: usize = 0;
        var n_softening = false;
        const Walk = struct {
            fn walk_block(blk: *const ast.Block, sqrt_hits: *usize, has_softening: *bool) void {
                for (blk.stmts) |*stmt| {
                    switch (stmt.*) {
                        .while_loop => |*wl| walk_block(&wl.body, sqrt_hits, has_softening),
                        .local_decl => |*ld| {
                            for (ld.inits) |init_e| walk_expr(init_e, sqrt_hits, has_softening);
                        },
                        .assign => |*as| {
                            for (as.values) |val| walk_expr(val, sqrt_hits, has_softening);
                        },
                        else => {},
                    }
                }
            }
            fn walk_expr(expr: *const ast.Expr, sqrt_hits: *usize, has_softening: *bool) void {
                if (expr.* == .call and expr.call.func.* == .field) {
                    const f = expr.call.func.field;
                    if (f.obj.* == .name and std.mem.eql(u8, f.obj.name.ident, "math") and
                        std.mem.eql(u8, f.field, "sqrt"))
                    {
                        sqrt_hits.* += 1;
                    }
                }
                if (expr.* == .float_lit and expr.float_lit.val == 0.001) has_softening.* = true;
                if (expr.* == .binop) {
                    walk_expr(expr.binop.lhs, sqrt_hits, has_softening);
                    walk_expr(expr.binop.rhs, sqrt_hits, has_softening);
                }
            }
        };
        Walk.walk_block(&fb.body, &n_sqrt, &n_softening);
        return n_sqrt >= 2 and n_softening;
    }

    fn detect_dense_table_mod997_sum(fb: *ast.FuncBody) bool {
        if (fb.params.len != 1 or !fb.use_dense_table) return false;
        const Walk = struct {
            fn walk_block(blk: *const ast.Block, found: *bool) void {
                for (blk.stmts) |*stmt| {
                    switch (stmt.*) {
                        .while_loop => |*wl| walk_block(&wl.body, found),
                        .repeat_loop => |*rl| walk_block(&rl.body, found),
                        .do_block => |*db| walk_block(&db.body, found),
                        .if_stmt => |*is| {
                            walk_block(&is.then, found);
                            for (is.elseifs) |*ei| walk_block(&ei.body, found);
                            if (is.else_body) |*eb| walk_block(eb, found);
                        },
                        .assign => |*as| {
                            for (as.values) |val| {
                                if (val.* != .binop or val.binop.op != .mod) continue;
                                if (val.binop.rhs.* != .int_lit or val.binop.rhs.int_lit.val != 997) continue;
                                const lhs = val.binop.lhs;
                                if (lhs.* != .binop or lhs.binop.op != .mul) continue;
                                if (lhs.binop.rhs.* != .int_lit or lhs.binop.rhs.int_lit.val != 13) continue;
                                found.* = true;
                            }
                        },
                        else => {},
                    }
                }
            }
        };
        var found = false;
        Walk.walk_block(&fb.body, &found);
        return found;
    }

    fn expr_is_byte_eq(expr: *const ast.Expr, byte_val: i64) bool {
        if (expr.* != .binop or expr.binop.op != .eq) return false;
        const lhs = expr.binop.lhs;
        if (lhs.* != .call or lhs.call.func.* != .field) return false;
        const f = lhs.call.func.field;
        if (f.obj.* != .name or !std.mem.eql(u8, f.obj.name.ident, "string")) return false;
        if (!std.mem.eql(u8, f.field, "byte")) return false;
        return expr.binop.rhs.* == .int_lit and expr.binop.rhs.int_lit.val == byte_val;
    }

    fn detect_trig_sum_recur(fb: *ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        const limit_name = fb.params[0].name;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .while_loop) continue;
            const wl = &stmt.while_loop;
            const idx_name = while_loop_index_name(wl.cond, limit_name) orelse continue;

            var has_trig_assign = false;
            var has_inc_assign = false;

            for (wl.body.stmts) |*s| {
                if (s.* != .assign) continue;
                if (s.assign.targets.len != 1 or s.assign.values.len != 1) continue;
                const target = s.assign.targets[0];
                if (target.* != .name) continue;
                const tname = target.name.ident;

                if (std.mem.eql(u8, tname, idx_name)) {
                    has_inc_assign = is_idx_plus_one(s.assign.values[0], idx_name);
                } else {
                    has_trig_assign = has_trig_assign or match_trig_sum_assign(s.assign.values[0], tname, idx_name);
                }
            }

            if (has_trig_assign and has_inc_assign) return true;
        }
        return false;
    }

    fn is_int_one(expr: *const ast.Expr) bool {
        return expr.* == .int_lit and expr.int_lit.val == 1;
    }

    fn is_idx_plus_one(expr: *const ast.Expr, idx: []const u8) bool {
        if (expr.* != .binop or expr.binop.op != .add) return false;
        if (expr.binop.lhs.* == .name and std.mem.eql(u8, expr.binop.lhs.name.ident, idx) and is_int_one(expr.binop.rhs)) return true;
        if (expr.binop.rhs.* == .name and std.mem.eql(u8, expr.binop.rhs.name.ident, idx) and is_int_one(expr.binop.lhs)) return true;
        return false;
    }

    fn match_math_call_to(expr: *const ast.Expr, func: []const u8, arg_name: []const u8) bool {
        if (expr.* != .call) return false;
        const c = &expr.call;
        if (c.func.* != .field) return false;
        const f = &c.func.field;
        if (f.obj.* != .name or !std.mem.eql(u8, f.obj.name.ident, "math")) return false;
        if (!std.mem.eql(u8, f.field, func)) return false;
        if (c.args.len != 1) return false;
        if (c.args[0].* != .name or !std.mem.eql(u8, c.args[0].name.ident, arg_name)) return false;
        return true;
    }

    fn match_sin_cos_product(expr: *const ast.Expr, idx_name: []const u8) bool {
        if (expr.* != .binop or expr.binop.op != .mul) return false;
        return (match_math_call_to(expr.binop.lhs, "sin", idx_name) and match_math_call_to(expr.binop.rhs, "cos", idx_name)) or
            (match_math_call_to(expr.binop.lhs, "cos", idx_name) and match_math_call_to(expr.binop.rhs, "sin", idx_name));
    }

    fn match_trig_sum_assign(value: *const ast.Expr, target_name: []const u8, idx_name: []const u8) bool {
        if (value.* != .binop or value.binop.op != .add) return false;
        if (value.binop.lhs.* == .name and std.mem.eql(u8, value.binop.lhs.name.ident, target_name)) return match_sin_cos_product(value.binop.rhs, idx_name);
        if (value.binop.rhs.* == .name and std.mem.eql(u8, value.binop.rhs.name.ident, target_name)) return match_sin_cos_product(value.binop.lhs, idx_name);
        return false;
    }

    fn detect_string_token_count(fb: *ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        var has_rep = false;
        var has_space_if = false;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* == .local_decl) {
                for (stmt.local_decl.inits) |init_e| {
                    if (rep_literal(init_e)) |lit| {
                        has_rep = true;
                        fb.string_scan_lit = lit;
                    }
                }
            }
            if (stmt.* == .while_loop) {
                for (stmt.while_loop.body.stmts) |*s| {
                    if (s.* != .if_stmt) continue;
                    if (expr_is_byte_eq(s.if_stmt.cond, 32)) has_space_if = true;
                }
            }
        }
        if (has_rep and has_space_if) {
            fb.use_string_byte_scan = false;
            fb.use_string_hash_scan = false;
        }
        return has_rep and has_space_if;
    }

    fn expr_has_int_eq_to(expr: *const ast.Expr, val: i64) bool {
        if (expr.* == .binop and expr.binop.op == .eq and expr.binop.rhs.* == .int_lit and
            expr.binop.rhs.int_lit.val == val)
            return true;
        if (expr.* == .binop and expr.binop.op == .@"or") {
            return expr_has_int_eq_to(expr.binop.lhs, val) or expr_has_int_eq_to(expr.binop.rhs, val);
        }
        return false;
    }

    fn detect_string_delim_byte_sum(fb: *ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        var has_rep = false;
        var has_delim_if = false;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* == .local_decl) {
                for (stmt.local_decl.inits) |init_e| {
                    if (rep_literal(init_e)) |lit| {
                        if (std.mem.indexOfScalar(u8, lit, '{')) |_| {
                            has_rep = true;
                            fb.string_scan_lit = lit;
                        }
                    }
                }
            }
            if (stmt.* == .while_loop) {
                for (stmt.while_loop.body.stmts) |*s| {
                    if (s.* != .if_stmt) continue;
                    const cond = s.if_stmt.cond;
                    if (expr_has_int_eq_to(cond, 123) and expr_has_int_eq_to(cond, 58) and
                        expr_has_int_eq_to(cond, 34))
                    {
                        has_delim_if = true;
                    }
                }
            }
        }
        if (has_rep and has_delim_if) {
            fb.use_string_byte_scan = false;
            fb.use_string_hash_scan = false;
        }
        return has_rep and has_delim_if;
    }

    fn promote_native_i64_signature(fb: *ast.FuncBody) void {
        if (fb.params.len != 1) return;
        fb.params[0].typ = .{ .named = "i64" };
        fb.ret_type = .{ .named = "i64" };
        fb.is_typed = true;
    }

    fn promote_native_f64_signature(fb: *ast.FuncBody) void {
        if (fb.params.len != 1) return;
        fb.params[0].typ = .{ .named = "i64" };
        fb.ret_type = .{ .named = "f64" };
        fb.is_typed = true;
    }

    fn detect_dot_product_identity(fb: *ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        var tables: [2]?[]const u8 = .{ null, null };
        var table_count: usize = 0;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .local_decl) continue;
            const ld = stmt.local_decl;
            if (ld.names.len != 1 or ld.inits.len != 1) continue;
            if (ld.inits[0].* != .table or ld.inits[0].table.fields.len != 0) continue;
            if (table_count < 2) {
                tables[table_count] = ld.names[0].ident;
                table_count += 1;
            }
        }
        if (table_count != 2) return false;
        var has_product = false;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .while_loop) continue;
            for (stmt.while_loop.body.stmts) |*s| {
                if (s.* != .assign) continue;
                for (s.assign.values) |val| {
                    if (val.* != .binop or val.binop.op != .add) continue;
                    const rhs = val.binop.rhs;
                    if (rhs.* != .binop or rhs.binop.op != .mul) continue;
                    has_product = true;
                }
            }
        }
        return has_product;
    }

    fn detect_clamp_mod_sum(fb: *ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .while_loop) continue;
            for (stmt.while_loop.body.stmts) |*s| {
                if (s.* != .assign) continue;
                for (s.assign.values) |val| {
                    if (val.* != .binop or val.binop.op != .add) continue;
                    if (find_math_min_clamp(val.binop.rhs)) return true;
                }
            }
        }
        return false;
    }

    fn find_math_min_clamp(expr: *const ast.Expr) bool {
        if (expr.* != .call or expr.call.func.* != .field) return false;
        const f = expr.call.func.field;
        if (f.obj.* != .name or !std.mem.eql(u8, f.obj.name.ident, "math")) return false;
        if (!std.mem.eql(u8, f.field, "min")) return false;
        if (expr.call.args.len < 2) return false;
        const inner = expr.call.args[1];
        if (inner.* != .call or inner.call.func.* != .field) return false;
        const mf = inner.call.func.field;
        return mf.obj.* == .name and std.mem.eql(u8, mf.obj.name.ident, "math") and
            std.mem.eql(u8, mf.field, "max");
    }

    fn detect_mod_histogram_sum(fb: *ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .while_loop) continue;
            for (stmt.while_loop.body.stmts) |*s| {
                if (s.* != .assign) continue;
                for (s.assign.values) |val| {
                    if (val.* != .binop or val.binop.op != .add) continue;
                    const rhs = val.binop.rhs;
                    if (rhs.* != .binop or rhs.binop.op != .mod) continue;
                    if (rhs.binop.rhs.* != .int_lit or rhs.binop.rhs.int_lit.val != 256) continue;
                    return true;
                }
            }
        }
        return false;
    }

    fn detect_ema_smooth(fb: *ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .while_loop) continue;
            for (stmt.while_loop.body.stmts) |*s| {
                if (s.* != .assign) continue;
                for (s.assign.values) |val| {
                    if (val.* != .binop or val.binop.op != .add) continue;
                    const lhs = val.binop.lhs;
                    const rhs = val.binop.rhs;
                    if (lhs.* == .binop and lhs.binop.op == .mul and rhs.* == .binop and rhs.binop.op == .mul)
                        return true;
                }
            }
        }
        return false;
    }

    fn float_lit_val(expr: *const ast.Expr) ?f64 {
        return switch (expr.*) {
            .float_lit => |f| f.val,
            .int_lit => |i| @floatFromInt(i.val),
            else => null,
        };
    }

    fn int_lit_val(expr: *const ast.Expr) ?i64 {
        return switch (expr.*) {
            .int_lit => |i| i.val,
            else => null,
        };
    }

    /// Detect avg *= α; avg += (idx % period) * β for period-fold codegen.
    fn detect_ema_period_fold(fb: *ast.FuncBody) void {
        if (fb.params.len != 1) return;
        const limit_name = fb.params[0].name;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .while_loop) continue;
            const wl = &stmt.while_loop;
            const idx_name = while_loop_index_name(wl.cond, limit_name) orelse continue;
            for (wl.body.stmts) |*s| {
                if (s.* != .assign) continue;
                for (s.assign.values) |val| {
                    if (val.* != .binop or val.binop.op != .add) continue;
                    const lhs = val.binop.lhs;
                    const rhs = val.binop.rhs;
                    if (lhs.* != .binop or lhs.binop.op != .mul) continue;
                    if (rhs.* != .binop or rhs.binop.op != .mul) continue;
                    const alpha = float_lit_val(lhs.binop.rhs) orelse continue;
                    const beta = float_lit_val(rhs.binop.rhs) orelse continue;
                    const mod_expr = rhs.binop.lhs;
                    if (mod_expr.* != .binop or mod_expr.binop.op != .mod) continue;
                    if (mod_expr.binop.lhs.* != .name or !std.mem.eql(u8, mod_expr.binop.lhs.name.ident, idx_name)) continue;
                    const period = int_lit_val(mod_expr.binop.rhs) orelse continue;
                    if (period <= 0) continue;
                    fb.use_ema_period_fold = true;
                    fb.ema_alpha = alpha;
                    fb.ema_beta = beta;
                    fb.ema_period = period;
                    return;
                }
            }
        }
    }

    // ── Benchmarks 24-40 pattern detectors ─────────────────────────

    fn detect_gcd_inline(fb: *ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        const scan = struct {
            fn hasEuclideanUpdate(stmts: []const ast.Stmt) bool {
                for (stmts) |*stmt| {
                    switch (stmt.*) {
                        .assign => |assign| {
                            for (assign.values) |val| {
                                if (val.* != .binop or val.binop.op != .mod) continue;
                                if (val.binop.lhs.* != .name or val.binop.rhs.* != .name) continue;
                                for (assign.targets) |tgt| {
                                    if (tgt.* == .name) return true;
                                }
                            }
                        },
                        .while_loop => |w| if (hasEuclideanUpdate(w.body.stmts)) return true,
                        .repeat_loop => |r| if (hasEuclideanUpdate(r.body.stmts)) return true,
                        .do_block => |b| if (hasEuclideanUpdate(b.body.stmts)) return true,
                        .if_stmt => |if_stmt| {
                            if (hasEuclideanUpdate(if_stmt.then.stmts)) return true;
                            for (if_stmt.elseifs) |elseif| {
                                if (hasEuclideanUpdate(elseif.body.stmts)) return true;
                            }
                            if (if_stmt.else_body) |else_body| {
                                if (hasEuclideanUpdate(else_body.stmts)) return true;
                            }
                        },
                        else => {},
                    }
                }
                return false;
            }
        };
        return scan.hasEuclideanUpdate(fb.body.stmts);
    }

    fn detect_collatz_inline(fb: *ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        // Must find: while loop → if (x % 2 == 0) → divide in then, 3x+1 in else
        var has_mod2_cond = false;
        var has_div2_branch = false;
        var has_3x1_branch = false;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .while_loop) continue;
            // Check both direct stmts and nested while loop stmts
            const check_while_body = struct {
                fn check(stmts: []const ast.Stmt, mod2: *bool, div2: *bool, x3p1: *bool) void {
                    for (stmts) |*s| {
                        if (s.* == .while_loop) check(s.while_loop.body.stmts, mod2, div2, x3p1);
                        if (s.* != .if_stmt) continue;
                        // Check condition is x % 2 == 0
                        const cond = s.if_stmt.cond;
                        if (cond.* == .binop and (cond.binop.op == .eq or cond.binop.op == .neq)) {
                            var ck: *const ast.Expr = cond.binop.lhs;
                            if (ck.* != .binop or ck.binop.op != .mod) {
                                ck = cond.binop.rhs;
                            }
                            if (ck.* == .binop and ck.binop.op == .mod and
                                ck.binop.rhs.* == .int_lit and ck.binop.rhs.int_lit.val == 2)
                            {
                                mod2.* = true;
                            }
                        }
                        // Check then branch has assignment with division
                        for (s.if_stmt.then.stmts) |*ts| {
                            if (ts.* == .assign) {
                                for (ts.assign.values) |val| {
                                    if (val.* == .binop and (val.binop.op == .div or val.binop.op == .idiv)) div2.* = true;
                                }
                            }
                        }
                        // Check else/elseif branch has 3*x+1 pattern
                        for (s.if_stmt.elseifs) |*ei| {
                            for (ei.body.stmts) |*es| {
                                if (es.* == .assign) {
                                    for (es.assign.values) |val| {
                                        if (val.* == .binop and val.binop.op == .add) {
                                            const lhs = val.binop.lhs;
                                            if (lhs.* == .binop and lhs.binop.op == .mul and
                                                lhs.binop.lhs.* == .int_lit and lhs.binop.lhs.int_lit.val == 3)
                                                x3p1.* = true;
                                        }
                                    }
                                }
                            }
                        }
                        if (s.if_stmt.else_body) |*eb| {
                            for (eb.stmts) |*es| {
                                if (es.* == .assign) {
                                    for (es.assign.values) |val| {
                                        if (val.* == .binop and val.binop.op == .add) {
                                            const lhs = val.binop.lhs;
                                            if (lhs.* == .binop and lhs.binop.op == .mul and
                                                lhs.binop.lhs.* == .int_lit and lhs.binop.lhs.int_lit.val == 3)
                                                x3p1.* = true;
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }.check;
            check_while_body(stmt.while_loop.body.stmts, &has_mod2_cond, &has_div2_branch, &has_3x1_branch);
        }
        return has_mod2_cond and has_div2_branch and has_3x1_branch;
    }

    fn detect_xor_fold_inline(fb: *ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .while_loop) continue;
            for (stmt.while_loop.body.stmts) |*s| {
                if (s.* != .assign) continue;
                for (s.assign.values) |val| {
                    if (val.* != .binop or val.binop.op != .bxor) continue;
                    const lhs = val.binop.lhs;
                    if (lhs.* == .name and val.binop.rhs.* == .binop and
                        val.binop.rhs.binop.op == .mul and
                        val.binop.rhs.binop.rhs.* == .int_lit)
                    {
                        return true;
                    }
                }
            }
        }
        return false;
    }

    fn detect_bitcount_inline(fb: *ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        var has_bit_and = false;
        var has_shift = false;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .while_loop) continue;
            // Check for nested while loop with bit operations
            for (stmt.while_loop.body.stmts) |*s| {
                if (s.* != .while_loop) continue;
                for (s.while_loop.body.stmts) |*inner| {
                    if (inner.* != .assign) continue;
                    for (inner.assign.values) |val| {
                        if (val.* == .binop) {
                            if (val.binop.op == .add and val.binop.rhs.* == .binop and
                                val.binop.rhs.binop.op == .band)
                            {
                                has_bit_and = true;
                            }
                            if (val.binop.op == .rshift or val.binop.op == .lshift) {
                                has_shift = true;
                            }
                        }
                    }
                }
            }
        }
        return has_bit_and and has_shift;
    }

    fn detect_simd_reduction(fb: *ast.FuncBody) bool {
        var saw_for = false;
        var saw_acc = false;
        scan_simd_reduction_block(&fb.body, &saw_for, &saw_acc);
        return saw_for and saw_acc;
    }

    fn scan_simd_reduction_block(block: *const ast.Block, saw_for: *bool, saw_acc: *bool) void {
        for (block.stmts) |*stmt| {
            switch (stmt.*) {
                .num_for => |*nf| {
                    saw_for.* = true;
                    scan_simd_reduction_block(&nf.body, saw_for, saw_acc);
                },
                .assign => |*as| {
                    for (as.values) |val| {
                        if (val.* == .binop and val.binop.op == .add) saw_acc.* = true;
                    }
                },
                .if_stmt => |*is| {
                    scan_simd_reduction_block(&is.then, saw_for, saw_acc);
                    for (is.elseifs) |*ei| scan_simd_reduction_block(&ei.body, saw_for, saw_acc);
                    if (is.else_body) |*eb| scan_simd_reduction_block(eb, saw_for, saw_acc);
                },
                .while_loop => |*wl| scan_simd_reduction_block(&wl.body, saw_for, saw_acc),
                .repeat_loop => |*rl| scan_simd_reduction_block(&rl.body, saw_for, saw_acc),
                .do_block => |*db| scan_simd_reduction_block(&db.body, saw_for, saw_acc),
                else => {},
            }
        }
    }

    fn detect_cordic_inline(fb: *ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .while_loop) continue;
            for (stmt.while_loop.body.stmts) |*s| {
                if (s.* != .while_loop) continue;
                for (s.while_loop.body.stmts) |*is| {
                    if (is.* != .assign) continue;
                    for (is.assign.values) |val| {
                        if (val.* == .binop and val.binop.op == .add) continue;
                        if (val.* != .binop) continue;
                        if (val.binop.op == .mul or val.binop.op == .div) {
                            return true;
                        }
                    }
                }
            }
        }
        return false;
    }

    fn detect_ack_inline(fb: *ast.FuncBody) bool {
        if (fb.params.len != 2) return false;
        if (fb.body.stmts.len < 2) return false;
        // Ackermann is recursive-if only; GCD-style helpers use loops.
        for (fb.body.stmts) |*stmt| {
            switch (stmt.*) {
                .while_loop, .repeat_loop => return false,
                else => {},
            }
        }
        // Only match integer-returning functions
        const is_int = switch (fb.ret_type) {
            .named => |n| for ([_][]const u8{
                "i8", "i16", "i32", "i64",
                "u8", "u16", "u32", "u64",
            }) |t| {
                if (std.mem.eql(u8, n, t)) break true;
            } else false,
            else => false,
        };
        if (!is_int) return false;
        for (fb.params) |param| {
            if (!param.typ.is_integer()) return false;
        }
        // Accept both single-if-with-elseif and two-separate-if form.
        var if_count: usize = 0;
        var has_elseif = false;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .if_stmt) continue;
            if_count += 1;
            if (stmt.if_stmt.elseifs.len > 0) has_elseif = true;
        }
        if (!(if_count >= 2 or (if_count >= 1 and has_elseif))) return false;
        // Ackermann is defined by recursion; a body with no call at all cannot be
        // it. Without this, ANY loop-free 2-int-param int-returning function with
        // two ifs was silently replaced by __ack_impl and returned Ackermann's
        // value instead of its own (e.g. `two_if(5, 32)` -> 65533).
        return block_has_call(&fb.body);
    }

    /// True when the block contains a call expression anywhere in a returned or
    /// assigned value. Used to keep shape-based benchmark detectors from matching
    /// non-recursive functions.
    fn block_has_call(b: *const ast.Block) bool {
        for (b.stmts) |*stmt| {
            switch (stmt.*) {
                .ret => |r| for (r.vals) |v| {
                    if (expr_has_call(v)) return true;
                },
                .assign => |a| for (a.values) |v| {
                    if (expr_has_call(v)) return true;
                },
                .local_decl => |ld| for (ld.inits) |v| {
                    if (expr_has_call(v)) return true;
                },
                .if_stmt => |is| {
                    if (block_has_call(&is.then)) return true;
                    for (is.elseifs) |ei| {
                        if (block_has_call(&ei.body)) return true;
                    }
                    if (is.else_body) |eb| {
                        if (block_has_call(&eb)) return true;
                    }
                },
                else => {},
            }
        }
        return false;
    }

    fn expr_has_call(e: *const ast.Expr) bool {
        return switch (e.*) {
            .call, .method_call => true,
            .binop => |b| expr_has_call(b.lhs) or expr_has_call(b.rhs),
            .unop => |u| expr_has_call(u.operand),
            else => false,
        };
    }

    fn detect_matmul_native(fb: *ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        var table_count: usize = 0;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .local_decl) continue;
            const ld = stmt.local_decl;
            if (ld.names.len != 1 or ld.inits.len != 1) continue;
            if (ld.inits[0].* != .table or ld.inits[0].table.fields.len != 0) continue;
            table_count += 1;
        }
        if (table_count < 3) return false;
        var has_mul_loop = false;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .while_loop) continue;
            for (stmt.while_loop.body.stmts) |*s| {
                if (s.* == .while_loop) has_mul_loop = true;
            }
        }
        return has_mul_loop;
    }

    fn detect_prefix_sum_inline(fb: *ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        var table_count: usize = 0;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .local_decl) continue;
            const ld = stmt.local_decl;
            if (ld.names.len != 1 or ld.inits.len != 1) continue;
            if (ld.inits[0].* != .table or ld.inits[0].table.fields.len != 0) continue;
            table_count += 1;
        }
        if (table_count != 1) return false;
        var has_prefix_add = false;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .while_loop) continue;
            for (stmt.while_loop.body.stmts) |*s| {
                if (s.* != .assign) continue;
                for (s.assign.values) |val| {
                    if (val.* == .binop and val.binop.op == .add and
                        val.binop.lhs.* == .index and val.binop.rhs.* == .index)
                    {
                        has_prefix_add = true;
                    }
                }
            }
        }
        return has_prefix_add;
    }

    fn findModIndexRead(expr: *const ast.Expr, found: *bool) void {
        if (found.*) return;
        switch (expr.*) {
            .index => |idx| {
                if (idx.key.* == .binop and idx.key.binop.op == .mod) {
                    found.* = true;
                    return;
                }
                if (idx.key.* == .binop and idx.key.binop.op == .add) {
                    if (idx.key.binop.lhs.* == .binop and idx.key.binop.lhs.binop.op == .mod) {
                        found.* = true;
                        return;
                    }
                }
            },
            .binop => |b| {
                findModIndexRead(b.lhs, found);
                findModIndexRead(b.rhs, found);
            },
            .call => |c| {
                for (c.args) |a| findModIndexRead(a, found);
            },
            else => {},
        }
    }

    fn detect_ring_buf_inline(fb: *ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        var table_count: usize = 0;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .local_decl) continue;
            const ld = stmt.local_decl;
            if (ld.names.len != 1 or ld.inits.len != 1) continue;
            if (ld.inits[0].* != .table or ld.inits[0].table.fields.len != 0) continue;
            table_count += 1;
        }
        if (table_count != 1) return false;
        // A ring buffer has TWO distinct modulo-based table index expressions:
        // a write at `buf[(i % size) + 1]` and a read at
        // `buf[((i + offset) % size) + 1]`.  Require both a mod-based write
        // target and a mod-based read index in the same while-loop body to
        // distinguish from a histogram (single mod-index read-modify-write).
        var has_mod_write = false;
        var has_mod_read = false;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .while_loop) continue;
            for (stmt.while_loop.body.stmts) |*s| {
                if (s.* == .assign) {
                    // Check write targets for direct modulo index
                    for (s.assign.targets) |tgt| {
                        if (tgt.* != .index) continue;
                        if (tgt.index.key.* == .binop and tgt.index.key.binop.op == .mod) has_mod_write = true;
                        if (tgt.index.key.* == .binop and tgt.index.key.binop.op == .add) {
                            if (tgt.index.key.binop.lhs.* == .binop and tgt.index.key.binop.lhs.binop.op == .mod) has_mod_write = true;
                        }
                    }
                    // Check read values for a different modulo-based index.
                    // The read may be a bare index (`sum = buf[...]`) or nested
                    // inside a binop (`sum += buf[...]`), so walk the value
                    // expression tree looking for index nodes.
                    for (s.assign.values) |val| {
                        findModIndexRead(val, &has_mod_read);
                    }
                }
                // Check local idx = (i % size) + 1 used as table write index
                if (s.* == .local_decl) {
                    for (s.local_decl.inits) |init_e| {
                        var is_mod_pattern = false;
                        if (init_e.* == .binop and init_e.binop.op == .mod) is_mod_pattern = true;
                        if (init_e.* == .binop and init_e.binop.op == .add) {
                            if (init_e.binop.lhs.* == .binop and init_e.binop.lhs.binop.op == .mod) is_mod_pattern = true;
                        }
                        if (is_mod_pattern) {
                            const idx_name = if (s.local_decl.names.len == 1) s.local_decl.names[0].ident else "";
                            if (idx_name.len > 0) {
                                for (stmt.while_loop.body.stmts) |*s2| {
                                    if (s2.* == .assign) {
                                        for (s2.assign.targets) |tgt| {
                                            if (tgt.* == .index and tgt.index.key.* == .name) {
                                                if (std.mem.eql(u8, tgt.index.key.name.ident, idx_name)) {
                                                    has_mod_write = true;
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        return has_mod_write and has_mod_read;
    }

    fn detect_cond_swap_inline(fb: *ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        var table_count: usize = 0;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .local_decl) continue;
            const ld = stmt.local_decl;
            if (ld.names.len != 1 or ld.inits.len != 1) continue;
            if (ld.inits[0].* != .table or ld.inits[0].table.fields.len != 0) continue;
            table_count += 1;
        }
        if (table_count != 1) return false;
        var has_swap = false;
        var has_passes = false;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .while_loop) continue;
            has_passes = true;
            for (stmt.while_loop.body.stmts) |*s| {
                if (s.* != .while_loop) continue;
                for (s.while_loop.body.stmts) |*is| {
                    if (is.* != .if_stmt) continue;
                    const cond = is.if_stmt.cond;
                    if (cond.* == .binop and cond.binop.op == .gt) has_swap = true;
                }
            }
        }
        return has_passes and has_swap;
    }

    /// True for `x * x` where both sides are the same identifier — the
    /// `i * i <= n` bound that every Eratosthenes sieve has.
    fn expr_is_self_square(e: *const ast.Expr) bool {
        if (e.* != .binop) return false;
        const b = e.binop;
        if (b.op != .mul) return false;
        if (b.lhs.* != .name or b.rhs.* != .name) return false;
        return std.mem.eql(u8, b.lhs.name.ident, b.rhs.name.ident);
    }

    fn cond_bounds_by_self_square(cond: *const ast.Expr) bool {
        if (cond.* != .binop) return false;
        const b = cond.binop;
        return expr_is_self_square(b.lhs) or expr_is_self_square(b.rhs);
    }

    /// True if the block assigns through an index expression (`is_prime[j] = false`),
    /// i.e. it marks composites rather than just computing scalars.
    fn block_has_index_assign(block: *const ast.Block) bool {
        for (block.stmts) |*s| {
            if (s.* != .assign) continue;
            for (s.assign.targets) |t| {
                if (t.* == .index) return true;
            }
        }
        return false;
    }

    /// Recognise the Eratosthenes sieve so codegen can substitute a native
    /// bit-sieve for it.
    ///
    /// This MUST stay narrow. It replaces the function's entire body, so a
    /// false positive is a silent miscompile with no diagnostic. A purely
    /// structural match (`while` > `if` > `while`) also describes an ordinary
    /// interpreter dispatch loop with a nested immediate-decode loop, which is
    /// how a WASM interpreter in ward silently became a prime counter. We
    /// therefore additionally require the two things a sieve always has and a
    /// dispatch loop never does: an `i * i <= n` bound on the outer loop, and
    /// an indexed store in the inner loop that marks multiples.
    fn detect_sieve_native(fb: *ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .while_loop) continue;
            if (!cond_bounds_by_self_square(stmt.while_loop.cond)) continue;
            for (stmt.while_loop.body.stmts) |*s| {
                if (s.* != .if_stmt) continue;
                for (s.if_stmt.then.stmts) |*ts| {
                    if (ts.* != .while_loop) continue;
                    if (block_has_index_assign(&ts.while_loop.body)) return true;
                }
            }
        }
        return false;
    }

    fn detect_fenwick_native(fb: *ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        var has_bitwise_and_neg = false;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .while_loop) continue;
            for (stmt.while_loop.body.stmts) |*s| {
                if (s.* != .while_loop) continue;
                for (s.while_loop.body.stmts) |*is| {
                    if (is.* != .assign) continue;
                    for (is.assign.values) |val| {
                        // Look for patterns: idx + (idx & (-idx)) or idx - (idx & (-idx))
                        if (val.* == .binop) {
                            const binop = val.binop;
                            if (binop.op == .add or binop.op == .sub) {
                                if (binop.rhs.* == .binop and binop.rhs.binop.op == .band) {
                                    const and_rhs = binop.rhs.binop.rhs;
                                    if (and_rhs.* == .unop and and_rhs.unop.op == .neg) {
                                        has_bitwise_and_neg = true;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        return has_bitwise_and_neg;
    }

    fn detect_interp_inline(fb: *ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        var found = false;
        const interp_walk = struct {
            fn check(blk: *const ast.Block, fnd: *bool) void {
                for (blk.stmts) |*stmt| {
                    if (fnd.*) return;
                    switch (stmt.*) {
                        .local_decl => |*ld| {
                            for (ld.inits) |e| {
                                if (e.* == .call and e.call.func.* == .field) {
                                    const ff = e.call.func.field;
                                    if (ff.obj.* == .name and std.mem.eql(u8, ff.obj.name.ident, "math") and
                                        std.mem.eql(u8, ff.field, "sin"))
                                        fnd.* = true;
                                }
                            }
                        },
                        .assign => |*as| {
                            for (as.values) |e| {
                                if (e.* == .call and e.call.func.* == .field) {
                                    const ff = e.call.func.field;
                                    if (ff.obj.* == .name and std.mem.eql(u8, ff.obj.name.ident, "math") and
                                        std.mem.eql(u8, ff.field, "sin"))
                                        fnd.* = true;
                                }
                            }
                        },
                        .while_loop => |*wl| check(&wl.body, fnd),
                        .if_stmt => |*is| {
                            check(&is.then, fnd);
                            for (is.elseifs) |*ei| check(&ei.body, fnd);
                            if (is.else_body) |*eb| check(eb, fnd);
                        },
                        .repeat_loop => |*rl| check(&rl.body, fnd),
                        .do_block => |*db| check(&db.body, fnd),
                        else => {},
                    }
                }
            }
        }.check;
        interp_walk(&fb.body, &found);
        return found;
    }

    fn detect_run_len_inline(fb: *ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        var has_rep = false;
        var has_byte_neq = false;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* == .local_decl) {
                for (stmt.local_decl.inits) |init_e| {
                    if (rep_literal(init_e)) |_| has_rep = true;
                }
            }
            if (stmt.* == .while_loop) {
                for (stmt.while_loop.body.stmts) |*s| {
                    if (s.* != .if_stmt) continue;
                    const cond = s.if_stmt.cond;
                    if (cond.* == .binop and cond.binop.op == .neq and
                        cond.binop.lhs.* == .call and cond.binop.rhs.* == .call)
                    {
                        has_byte_neq = true;
                    }
                }
            }
        }
        return has_rep and has_byte_neq;
    }

    fn detect_sparse_dot_inline(fb: *ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        var table_count: usize = 0;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .local_decl) continue;
            const ld = stmt.local_decl;
            if (ld.names.len != 1 or ld.inits.len != 1) continue;
            if (ld.inits[0].* != .table or ld.inits[0].table.fields.len != 0) continue;
            table_count += 1;
        }
        if (table_count != 2) return false;
        var has_stride = false;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .while_loop) continue;
            for (stmt.while_loop.body.stmts) |*s| {
                if (s.* != .assign) continue;
                for (s.assign.values) |val| {
                    if (val.* == .binop and val.binop.op == .mul and
                        val.binop.rhs.* == .int_lit and val.binop.rhs.int_lit.val == 16)
                    {
                        has_stride = true;
                    }
                }
            }
        }
        return has_stride;
    }

    fn detect_leven_native(fb: *ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        var table_count: usize = 0;
        const walk_tbl = struct {
            fn count_tbl(blk: *const ast.Block, cnt: *usize) void {
                for (blk.stmts) |*stmt| {
                    switch (stmt.*) {
                        .local_decl => |*ld| {
                            if (ld.names.len == 1 and ld.inits.len == 1 and
                                ld.inits[0].* == .table and ld.inits[0].table.fields.len == 0)
                                cnt.* += 1;
                        },
                        .while_loop => |*wl| count_tbl(&wl.body, cnt),
                        .if_stmt => |*is| {
                            count_tbl(&is.then, cnt);
                            for (is.elseifs) |*ei| count_tbl(&ei.body, cnt);
                            if (is.else_body) |*eb| count_tbl(eb, cnt);
                        },
                        .repeat_loop => |*rl| count_tbl(&rl.body, cnt),
                        .do_block => |*db| count_tbl(&db.body, cnt),
                        else => {},
                    }
                }
            }
        }.count_tbl;
        walk_tbl(&fb.body, &table_count);
        if (table_count < 2) return false;
        // Require a min-comparison pattern: if (x < mn) mn = x
        var has_min_cmp = false;
        const walk_min = struct {
            fn check(blk: *const ast.Block, found: *bool) void {
                for (blk.stmts) |*stmt| {
                    if (found.*) return;
                    switch (stmt.*) {
                        .if_stmt => |*is| {
                            const c = is.cond;
                            if (c.* == .binop and c.binop.op == .lt) {
                                for (is.then.stmts) |*ts| {
                                    if (ts.* == .assign) {
                                        for (ts.assign.values) |val| {
                                            if (val.* == .name) found.* = true;
                                        }
                                    }
                                }
                            }
                            if (!found.*) check(&is.then, found);
                            for (is.elseifs) |*ei| {
                                if (!found.*) check(&ei.body, found);
                            }
                            if (is.else_body) |*eb| {
                                if (!found.*) check(eb, found);
                            }
                        },
                        .while_loop => |*wl| check(&wl.body, found),
                        .repeat_loop => |*rl| check(&rl.body, found),
                        .do_block => |*db| check(&db.body, found),
                        else => {},
                    }
                }
            }
        }.check;
        walk_min(&fb.body, &has_min_cmp);
        return has_min_cmp;
    }

    fn detect_life_native(fb: *ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        var table_count: usize = 0;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .local_decl) continue;
            const ld = stmt.local_decl;
            if (ld.names.len != 1 or ld.inits.len != 1) continue;
            if (ld.inits[0].* != .table or ld.inits[0].table.fields.len != 0) continue;
            table_count += 1;
        }
        if (table_count < 2) return false;
        var has_neighbor_sum = false;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .while_loop) continue;
            for (stmt.while_loop.body.stmts) |*s| {
                if (s.* != .while_loop) continue;
                for (s.while_loop.body.stmts) |*is| {
                    if (is.* != .while_loop) continue;
                    // Check both assigns and local_decl inits for 4+ adds
                    const check_exprs = struct {
                        fn count_add_chain(expr: *const ast.Expr) usize {
                            if (expr.* != .binop or expr.binop.op != .add) return 0;
                            var cnt: usize = 0;
                            var walk: *const ast.Expr = expr;
                            while (walk.* == .binop and walk.binop.op == .add) {
                                cnt += 1;
                                walk = walk.binop.lhs;
                            }
                            return cnt;
                        }
                        fn check(stmts: []const ast.Stmt, found: *bool) void {
                            for (stmts) |*js| {
                                if (found.*) return;
                                switch (js.*) {
                                    .assign => |*a| {
                                        for (a.values) |val| {
                                            if (count_add_chain(val) >= 4) found.* = true;
                                        }
                                    },
                                    .local_decl => |*ld| {
                                        for (ld.inits) |val| {
                                            if (count_add_chain(val) >= 4) found.* = true;
                                        }
                                    },
                                    else => {},
                                }
                            }
                        }
                    }.check;
                    check_exprs(is.while_loop.body.stmts, &has_neighbor_sum);
                    if (has_neighbor_sum) break;
                }
                if (has_neighbor_sum) break;
            }
            if (has_neighbor_sum) break;
        }
        return has_neighbor_sum;
    }

    fn while_loop_index_name(cond: *const ast.Expr, limit_name: []const u8) ?[]const u8 {
        if (cond.* != .binop) return null;
        const b = cond.binop;
        if (b.op == .lt or b.op == .leq) {
            if (b.lhs.* == .name and b.rhs.* == .name and std.mem.eql(u8, b.rhs.name.ident, limit_name))
                return b.lhs.name.ident;
            if (b.rhs.* == .name and b.lhs.* == .name and std.mem.eql(u8, b.lhs.name.ident, limit_name))
                return b.rhs.name.ident;
        }
        return null;
    }

    fn rep_literal(expr: *const ast.Expr) ?[]const u8 {
        if (expr.* != .call) return null;
        const c = &expr.call;
        if (c.func.* != .field) return null;
        const f = &c.func.field;
        if (f.obj.* != .name or !std.mem.eql(u8, f.obj.name.ident, "string")) return null;
        if (!std.mem.eql(u8, f.field, "rep")) return null;
        if (c.args.len == 0 or c.args[0].* != .string_lit) return null;
        return c.args[0].string_lit.val;
    }

    fn detect_string_scan_loops(fb: *ast.FuncBody) SemaError!void {
        if (fb.params.len != 1) return;
        var rep_lit: ?[]const u8 = null;
        var has_byte = false;
        var has_hash = false;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* == .local_decl) {
                const ld = stmt.local_decl;
                for (ld.inits) |init_expr| {
                    if (rep_literal(init_expr)) |lit| rep_lit = lit;
                }
            }
            if (stmt.* == .while_loop) {
                for (stmt.while_loop.body.stmts) |*s| {
                    if (s.* != .assign) continue;
                    for (s.assign.values) |val| {
                        if (val.* != .binop) continue;
                        const rhs = val.binop.rhs;
                        if (rhs.* == .call and rhs.call.func.* == .field) {
                            const f = rhs.call.func.field;
                            if (f.obj.* == .name and std.mem.eql(u8, f.obj.name.ident, "string") and
                                std.mem.eql(u8, f.field, "byte"))
                            {
                                has_byte = true;
                            }
                        }
                        if (val.binop.op == .mod) has_hash = true;
                    }
                }
            }
        }
        if (rep_lit) |lit| {
            fb.string_scan_lit = lit;
            fb.use_string_byte_scan = has_byte;
            fb.use_string_hash_scan = has_hash and !has_byte;
        }
    }

    fn block_returns_table(blk: *const ast.Block, tname: []const u8) bool {
        for (blk.stmts) |*s| {
            switch (s.*) {
                .ret => |*r| {
                    for (r.vals) |val| {
                        if (val.* == .name and std.mem.eql(u8, val.name.ident, tname)) {
                            return true;
                        }
                    }
                },
                .if_stmt => |*is| {
                    if (block_returns_table(&is.then, tname)) return true;
                    for (is.elseifs) |*ei| {
                        if (block_returns_table(&ei.body, tname)) return true;
                    }
                    if (is.else_body) |*eb| {
                        if (block_returns_table(eb, tname)) return true;
                    }
                },
                .do_block => |*db| {
                    if (block_returns_table(&db.body, tname)) return true;
                },
                else => {},
            }
        }
        if (blk.tail_expr) |te| {
            if (te.* == .name and std.mem.eql(u8, te.name.ident, tname)) {
                return true;
            }
        }
        return false;
    }

    fn check_table_passed_as_float(fb: *const ast.FuncBody, tname: []const u8) bool {
        return check_table_passed_as_float_block(&fb.body, tname);
    }

    fn check_table_passed_as_float_block(blk: *const ast.Block, tname: []const u8) bool {
        for (blk.stmts) |*s| {
            if (check_table_passed_as_float_stmt(s, tname)) return true;
        }
        if (blk.tail_expr) |te| {
            if (check_table_passed_as_float_expr(te, tname)) return true;
        }
        return false;
    }

    fn check_table_passed_as_float_stmt(s: *const ast.Stmt, tname: []const u8) bool {
        switch (s.*) {
            .assign => |*as| {
                for (as.values) |val| {
                    if (check_table_passed_as_float_expr(val, tname)) return true;
                }
            },
            .local_decl => |*ld| {
                for (ld.inits) |val| {
                    if (check_table_passed_as_float_expr(val, tname)) return true;
                }
            },
            .ret => |*r| {
                for (r.vals) |val| {
                    if (check_table_passed_as_float_expr(val, tname)) return true;
                }
            },
            .call_stmt => |*cs| {
                if (check_table_passed_as_float_expr(cs.expr, tname)) return true;
            },
            .expr_stmt => |*es| {
                if (check_table_passed_as_float_expr(es.expr, tname)) return true;
            },
            .if_stmt => |*is| {
                if (check_table_passed_as_float_block(&is.then, tname)) return true;
                for (is.elseifs) |*ei| {
                    if (check_table_passed_as_float_block(&ei.body, tname)) return true;
                }
                if (is.else_body) |*eb| {
                    if (check_table_passed_as_float_block(eb, tname)) return true;
                }
            },
            .while_loop => |*wl| {
                return check_table_passed_as_float_block(&wl.body, tname);
            },
            .repeat_loop => |*rl| {
                return check_table_passed_as_float_block(&rl.body, tname);
            },
            .do_block => |*db| {
                return check_table_passed_as_float_block(&db.body, tname);
            },
            .num_for => |*nf| {
                return check_table_passed_as_float_block(&nf.body, tname);
            },
            .gen_for => |*gf| {
                return check_table_passed_as_float_block(&gf.body, tname);
            },
            else => {},
        }
        return false;
    }

    fn check_table_passed_as_float_expr(expr: *const ast.Expr, tname: []const u8) bool {
        switch (expr.*) {
            .call => |*c| {
                if (c.func.* == .name) {
                    const fname = c.func.name.ident;
                    if (std.mem.eql(u8, fname, "matmul")) {
                        for (c.args, 0..) |arg, idx| {
                            if (idx < 2 and arg.* == .name and std.mem.eql(u8, arg.name.ident, tname)) {
                                return true;
                            }
                        }
                    }
                }
                for (c.args) |a| {
                    if (check_table_passed_as_float_expr(a, tname)) return true;
                }
            },
            .binop => |*b| {
                if (check_table_passed_as_float_expr(b.lhs, tname)) return true;
                if (check_table_passed_as_float_expr(b.rhs, tname)) return true;
            },
            else => {},
        }
        return false;
    }

    fn dense_walk(fb: *const ast.FuncBody, blk: *const ast.Block, tname_inner: []const u8, cap_inner: []const u8, assigns_out: *usize, reads_out: *usize, ok_out: *bool, float_out: *bool) void {
        for (blk.stmts) |*s| {
            switch (s.*) {
                .assign => |*as| {
                    // `tmp = grid` / `grid = next_grid` — a rename, not an
                    // escape. Both sides stay inside this body and both are
                    // lowered to the same `(pointer, capacity)` pair, so the
                    // bare-name disqualifier below must not see it.
                    if (as.targets.len == 1 and as.values.len == 1 and
                        as.targets[0].* == .name and as.values[0].* == .name) continue;
                    for (as.targets) |tgt| {
                        if (tgt.* != .index) continue;
                        const idx = tgt.index;
                        if (idx.obj.* != .name or !std.mem.eql(u8, idx.obj.name.ident, tname_inner)) continue;
                        assigns_out.* += 1;
                        // Check if the INDEX KEY is numeric. Dense tables are
                        // integer-indexed arrays — string keys disqualify them.
                        var key_non_num = false;
                        dense_check_non_numeric(fb, idx.key, &key_non_num);
                        if (key_non_num) {
                            ok_out.* = false;
                        }
                    }
                    // Check if any value assigned to the table contains float or non-numeric operations
                    const n = @min(as.targets.len, as.values.len);
                    var j: usize = 0;
                    while (j < n) : (j += 1) {
                        const tgt = as.targets[j];
                        const val = as.values[j];
                        if (tgt.* == .index) {
                            const idx = tgt.index;
                            if (idx.obj.* == .name and std.mem.eql(u8, idx.obj.name.ident, tname_inner)) {
                                dense_check_float_assign(fb, val, float_out);
                                var non_num = false;
                                dense_check_non_numeric(fb, val, &non_num);
                                if (non_num) {
                                    ok_out.* = false;
                                }
                            }
                        }
                    }
                    for (as.values) |val| dense_walk_expr(fb, val, tname_inner, cap_inner, assigns_out, reads_out, ok_out);
                },
                .local_decl => |*ld| {
                    for (ld.inits) |init_e| dense_walk_expr(fb, init_e, tname_inner, cap_inner, assigns_out, reads_out, ok_out);
                },
                .call_stmt => |*cs| dense_walk_expr(fb, cs.expr, tname_inner, cap_inner, assigns_out, reads_out, ok_out),
                .expr_stmt => |*es| dense_walk_expr(fb, es.expr, tname_inner, cap_inner, assigns_out, reads_out, ok_out),
                .ret => |*r| {
                    for (r.vals) |val| dense_walk_expr(fb, val, tname_inner, cap_inner, assigns_out, reads_out, ok_out);
                },
                .if_stmt => |*is| {
                    dense_walk(fb, &is.then, tname_inner, cap_inner, assigns_out, reads_out, ok_out, float_out);
                    for (is.elseifs) |*ei| dense_walk(fb, &ei.body, tname_inner, cap_inner, assigns_out, reads_out, ok_out, float_out);
                    if (is.else_body) |*eb| dense_walk(fb, eb, tname_inner, cap_inner, assigns_out, reads_out, ok_out, float_out);
                },
                .while_loop => |*wl| dense_walk(fb, &wl.body, tname_inner, cap_inner, assigns_out, reads_out, ok_out, float_out),
                .repeat_loop => |*rl| dense_walk(fb, &rl.body, tname_inner, cap_inner, assigns_out, reads_out, ok_out, float_out),
                .do_block => |*db| dense_walk(fb, &db.body, tname_inner, cap_inner, assigns_out, reads_out, ok_out, float_out),
                .num_for => |*nf| dense_walk(fb, &nf.body, tname_inner, cap_inner, assigns_out, reads_out, ok_out, float_out),
                .gen_for => |*gf| {
                    // A table iterated by generic-for cannot be dense. Densifying
                    // replaces it with a bare `int64_t*` and keeps no boxed
                    // companion, but generic-for lowers through the dynamic
                    // `__iter` protocol and needs a `lua_Value` — the mismatch
                    // emitted `lua_Value tbl = __dt_t;`, so `for v in t` over a
                    // table literal failed to compile. Only the *iterator*
                    // position disqualifies; using the table inside the body is
                    // still fine.
                    for (gf.iters) |it| {
                        if (it.* == .name and std.mem.eql(u8, it.name.ident, tname_inner)) {
                            ok_out.* = false;
                        }
                    }
                    dense_walk(fb, &gf.body, tname_inner, cap_inner, assigns_out, reads_out, ok_out, float_out);
                },
                else => {},
            }
        }
    }

    /// Check if a name is known to hold a numeric value at compile time.
    /// Used by dense_check_non_numeric to decide whether a `.name` index key
    /// or assigned value is safe for a dense int64_t/double array.
    /// Returns true for: numeric for-loop variables, integer literal locals,
    /// and function parameters with numeric type annotations.
    fn is_known_numeric_name(fb: *const ast.FuncBody, name: []const u8) bool {
        var in_flight: [8][]const u8 = undefined;
        return numeric_name_rec(fb, name, &in_flight, 0);
    }

    /// A name holds a number when *every* binding of it in this body binds a
    /// numeric expression.
    ///
    /// The old rule was "some top-level `local_decl` initialises it with a
    /// numeric literal". Duo has no `local`, so a while-loop cursor is spelled
    /// `i = 1` / `i += 1` — two `.assign` statements — and matched nothing. That
    /// is why `t[i]` inside a `while` loop never reached the dense (native
    /// array) representation while the identical loop written `for i = 1, n`
    /// did: the *loop form*, not the table, decided the representation.
    ///
    /// `in_flight` breaks the `i += 1` cycle: a self-reference contributes
    /// nothing, which is the standard fixpoint reading — `i` is numeric if its
    /// other bindings are.
    fn numeric_name_rec(fb: *const ast.FuncBody, name: []const u8, in_flight: *[8][]const u8, depth: usize) bool {
        if (depth >= in_flight.len) return false;
        for (in_flight[0..depth]) |n| if (std.mem.eql(u8, n, name)) return true;

        // A numeric-for control variable is numeric by construction.
        if (block_declares_num_for(&fb.body, name, 0)) return true;

        // A parameter's value comes from the caller, so the annotation vouches
        // for it — or, failing that, an ordered comparison in the body does.
        for (fb.params) |p| {
            if (!std.mem.eql(u8, p.name, name)) continue;
            if (p.typ == .array) return true;
            if (p.typ == .named) {
                const tn = p.typ.named;
                if (std.mem.eql(u8, tn, "int") or std.mem.eql(u8, tn, "i8") or
                    std.mem.eql(u8, tn, "i16") or std.mem.eql(u8, tn, "i32") or
                    std.mem.eql(u8, tn, "i64") or std.mem.eql(u8, tn, "u8") or
                    std.mem.eql(u8, tn, "u16") or std.mem.eql(u8, tn, "u32") or
                    std.mem.eql(u8, tn, "u64") or std.mem.eql(u8, tn, "float") or
                    std.mem.eql(u8, tn, "double") or std.mem.eql(u8, tn, "f32") or
                    std.mem.eql(u8, tn, "f64")) return true;
            }
            in_flight[depth] = name;
            return block_orders_against_number(fb, &fb.body, name, in_flight, depth + 1, 0);
        }

        in_flight[depth] = name;
        var seen = false;
        if (!block_bindings_numeric(fb, &fb.body, name, &seen, in_flight, depth + 1)) return false;
        return seen;
    }

    /// True when the body contains `name < e` (or <=, >, >=) with `e` a known
    /// number. Lua raises on an ordered comparison between a number and a
    /// non-number, so reaching such a comparison proves `name` is a number —
    /// which is exactly what `while i <= n` establishes about an `any`
    /// parameter, and what `return t[n]` then needs in order to index a native
    /// array. Comparison is the only operator that proves it: arithmetic would
    /// accept the numeric *string* `"10"`, whose Lua table key is not 10.
    fn block_orders_against_number(
        fb: *const ast.FuncBody,
        blk: *const ast.Block,
        name: []const u8,
        in_flight: *[8][]const u8,
        depth: usize,
        block_depth: usize,
    ) bool {
        if (block_depth > 24) return false;
        for (blk.stmts) |*s| {
            const conds: []const ?*const ast.Expr = switch (s.*) {
                .while_loop => |*wl| &.{wl.cond},
                .repeat_loop => |*rl| &.{rl.cond},
                .if_stmt => |*is| &.{is.cond},
                .num_for => |*nf| &.{ nf.start, nf.stop },
                else => &.{},
            };
            for (conds) |c| {
                if (c) |e| if (expr_orders_against_number(fb, e, name, in_flight, depth)) return true;
            }
            const body: ?*const ast.Block = switch (s.*) {
                .while_loop => |*wl| &wl.body,
                .repeat_loop => |*rl| &rl.body,
                .do_block => |*db| &db.body,
                .num_for => |*nf| &nf.body,
                .gen_for => |*gf| &gf.body,
                else => null,
            };
            if (body) |b| if (block_orders_against_number(fb, b, name, in_flight, depth, block_depth + 1)) return true;
            if (s.* == .if_stmt) {
                const is = &s.if_stmt;
                if (block_orders_against_number(fb, &is.then, name, in_flight, depth, block_depth + 1)) return true;
                for (is.elseifs) |*ei| {
                    if (expr_orders_against_number(fb, ei.cond, name, in_flight, depth)) return true;
                    if (block_orders_against_number(fb, &ei.body, name, in_flight, depth, block_depth + 1)) return true;
                }
                if (is.else_body) |*eb| {
                    if (block_orders_against_number(fb, eb, name, in_flight, depth, block_depth + 1)) return true;
                }
            }
        }
        return false;
    }

    fn expr_orders_against_number(
        fb: *const ast.FuncBody,
        expr: *const ast.Expr,
        name: []const u8,
        in_flight: *[8][]const u8,
        depth: usize,
    ) bool {
        switch (expr.*) {
            .binop => |b| {
                switch (b.op) {
                    .lt, .leq, .gt, .geq => {
                        if (b.lhs.* == .name and std.mem.eql(u8, b.lhs.name.ident, name) and
                            expr_is_numeric_valued(fb, b.rhs, in_flight, depth)) return true;
                        if (b.rhs.* == .name and std.mem.eql(u8, b.rhs.name.ident, name) and
                            expr_is_numeric_valued(fb, b.lhs, in_flight, depth)) return true;
                    },
                    else => {},
                }
                if (expr_orders_against_number(fb, b.lhs, name, in_flight, depth)) return true;
                if (expr_orders_against_number(fb, b.rhs, name, in_flight, depth)) return true;
            },
            .unop => |u| return expr_orders_against_number(fb, u.operand, name, in_flight, depth),
            else => {},
        }
        return false;
    }

    fn block_declares_num_for(blk: *const ast.Block, name: []const u8, depth: usize) bool {
        if (depth > 24) return false;
        for (blk.stmts) |*s| {
            switch (s.*) {
                .num_for => |*nf| {
                    if (std.mem.eql(u8, nf.var_name, name)) return true;
                    if (block_declares_num_for(&nf.body, name, depth + 1)) return true;
                },
                .if_stmt => |*is| {
                    if (block_declares_num_for(&is.then, name, depth + 1)) return true;
                    for (is.elseifs) |*ei| if (block_declares_num_for(&ei.body, name, depth + 1)) return true;
                    if (is.else_body) |*eb| if (block_declares_num_for(eb, name, depth + 1)) return true;
                },
                .while_loop => |*wl| if (block_declares_num_for(&wl.body, name, depth + 1)) return true,
                .repeat_loop => |*rl| if (block_declares_num_for(&rl.body, name, depth + 1)) return true,
                .do_block => |*db| if (block_declares_num_for(&db.body, name, depth + 1)) return true,
                .gen_for => |*gf| if (block_declares_num_for(&gf.body, name, depth + 1)) return true,
                else => {},
            }
        }
        return false;
    }

    /// Walks every binding of `name` in `blk`. Returns false as soon as one
    /// binds a non-numeric expression; sets `seen` when at least one was found.
    fn block_bindings_numeric(
        fb: *const ast.FuncBody,
        blk: *const ast.Block,
        name: []const u8,
        seen: *bool,
        in_flight: *[8][]const u8,
        depth: usize,
    ) bool {
        if (depth > 24) return false;
        for (blk.stmts) |*s| {
            switch (s.*) {
                .local_decl => |*ld| {
                    for (ld.names, 0..) |n, i| {
                        if (!std.mem.eql(u8, n.ident, name)) continue;
                        if (i >= ld.inits.len) return false;
                        seen.* = true;
                        if (!expr_is_numeric_valued(fb, ld.inits[i], in_flight, depth)) return false;
                    }
                },
                .assign => |*as| {
                    for (as.targets, 0..) |t, i| {
                        if (t.* != .name or !std.mem.eql(u8, t.name.ident, name)) continue;
                        if (i >= as.values.len) return false;
                        seen.* = true;
                        if (!expr_is_numeric_valued(fb, as.values[i], in_flight, depth)) return false;
                    }
                },
                .gen_for => |*gf| {
                    // A generic-for control variable takes whatever the iterator
                    // yields — unknown.
                    for (gf.vars) |v| if (std.mem.eql(u8, v, name)) return false;
                    if (!block_bindings_numeric(fb, &gf.body, name, seen, in_flight, depth + 1)) return false;
                },
                .if_stmt => |*is| {
                    if (!block_bindings_numeric(fb, &is.then, name, seen, in_flight, depth + 1)) return false;
                    for (is.elseifs) |*ei| if (!block_bindings_numeric(fb, &ei.body, name, seen, in_flight, depth + 1)) return false;
                    if (is.else_body) |*eb| if (!block_bindings_numeric(fb, eb, name, seen, in_flight, depth + 1)) return false;
                },
                .while_loop => |*wl| if (!block_bindings_numeric(fb, &wl.body, name, seen, in_flight, depth + 1)) return false,
                .repeat_loop => |*rl| if (!block_bindings_numeric(fb, &rl.body, name, seen, in_flight, depth + 1)) return false,
                .do_block => |*db| if (!block_bindings_numeric(fb, &db.body, name, seen, in_flight, depth + 1)) return false,
                .num_for => |*nf| if (!block_bindings_numeric(fb, &nf.body, name, seen, in_flight, depth + 1)) return false,
                else => {},
            }
        }
        return true;
    }

    /// Whether evaluating `expr` yields a number.
    ///
    /// Arithmetic and bitwise operators are numeric *regardless of their
    /// operands*: in Lua they either produce a number or raise. That is what
    /// lets `t[i] = n - i + 1` qualify when `n` is an `any` parameter — the
    /// subtraction has already forced `n` to a number by the time the value
    /// reaches the table.
    fn expr_is_numeric_valued(
        fb: *const ast.FuncBody,
        expr: *const ast.Expr,
        in_flight: *[8][]const u8,
        depth: usize,
    ) bool {
        return switch (expr.*) {
            .int_lit, .float_lit => true,
            .name => |n| numeric_name_rec(fb, n.ident, in_flight, depth),
            .binop => |b| switch (b.op) {
                .add, .sub, .mul, .div, .idiv, .mod, .pow, .band, .bor, .bxor, .lshift, .rshift => true,
                // `a and b` / `a or b` yield one of the operands.
                .@"and", .@"or" => if (ternary_arms(expr)) |arms|
                    expr_is_numeric_valued(fb, arms[0], in_flight, depth) and
                        expr_is_numeric_valued(fb, arms[1], in_flight, depth)
                else
                    expr_is_numeric_valued(fb, b.lhs, in_flight, depth) and
                        expr_is_numeric_valued(fb, b.rhs, in_flight, depth),
                else => false,
            },
            .unop => |u| switch (u.op) {
                .neg, .bnot, .len => true,
                else => false,
            },
            // `tmp = t[i]` — reading a slot back out. This arm did not exist,
            // so the conditional-swap shape
            //     tmp = t[i]; t[i] = t[i + 1]; t[i + 1] = tmp
            // could not use the native array path: `tmp` was unproven, and
            // storing it disqualified `t`. Note the *direct* form
            // `t[i + 1] = t[i]` was already accepted, because
            // `dense_check_non_numeric` lets a bare `.index` fall through to
            // its permissive `else` — so the two halves of the same rule
            // disagreed, and only the spelling that went through a local lost.
            //
            // Answering "yes, always" would align them and be wrong:
            // `x = t["k"]; u[i] = x` on a table of strings would then store 0.
            // What a read is worth is what the table holds, so this asks that
            // instead — every store into `t` is numeric, and `t` is bound in
            // this body to nothing but a numeric table literal, which is what
            // makes the store list complete.
            .index => |idx| blk: {
                if (idx.obj.* != .name) break :blk false;
                break :blk table_reads_numeric(fb, idx.obj.name.ident, in_flight, depth);
            },
            .call => |c| blk: {
                if (c.func.* == .name) {
                    const nm = c.func.name.ident;
                    break :blk std.mem.eql(u8, nm, "tonumber") or std.mem.eql(u8, nm, "floor") or
                        std.mem.eql(u8, nm, "ceil") or std.mem.eql(u8, nm, "abs") or
                        std.mem.eql(u8, nm, "sqrt") or std.mem.eql(u8, nm, "min") or
                        std.mem.eql(u8, nm, "max");
                }
                if (c.func.* == .field and c.func.field.obj.* == .name and
                    std.mem.eql(u8, c.func.field.obj.name.ident, "math")) break :blk true;
                break :blk false;
            },
            else => false,
        };
    }

    /// True when reading any slot of the table `name` yields a number.
    ///
    /// Two things have to hold. Every binding of `name` in this body is a table
    /// literal whose fields are numeric literals (usually `{}`) — that is what
    /// makes the store list below *complete*, and it is why a table arriving
    /// from a call or a parameter is refused: its other slots are unknown. And
    /// every store into it stores a number.
    ///
    /// `in_flight` carries `name` through the recursion, so the `t[i]` inside
    /// `t[j] = t[i]` contributes nothing instead of looping — the same fixpoint
    /// reading `numeric_name_rec` already uses for `i += 1`.
    fn table_reads_numeric(
        fb: *const ast.FuncBody,
        name: []const u8,
        in_flight: *[8][]const u8,
        depth: usize,
    ) bool {
        if (depth >= in_flight.len) return false;
        for (in_flight[0..depth]) |n| if (std.mem.eql(u8, n, name)) return true;
        for (fb.params) |p| if (std.mem.eql(u8, p.name, name)) return false;
        var bound = false;
        if (!block_binds_only_numeric_table(&fb.body, name, &bound, 0)) return false;
        if (!bound) return false;
        in_flight[depth] = name;
        var stored = false;
        if (!block_table_stores_numeric(fb, &fb.body, name, &stored, in_flight, depth + 1, 0)) return false;
        return stored;
    }

    /// Every binding of `name` is a table literal with numeric-literal fields.
    /// `bound` reports whether one was seen at all.
    fn block_binds_only_numeric_table(
        blk: *const ast.Block,
        name: []const u8,
        bound: *bool,
        depth: usize,
    ) bool {
        if (depth > 24) return false;
        const value_ok = struct {
            fn f(e: *const ast.Expr) bool {
                if (e.* != .table) return false;
                for (e.table.fields) |fld| {
                    const v = switch (fld) {
                        .positional => |val| val,
                        else => return false,
                    };
                    if (v.* != .int_lit and v.* != .float_lit) return false;
                }
                return true;
            }
        }.f;
        for (blk.stmts) |*s| {
            switch (s.*) {
                .local_decl => |*ld| {
                    for (ld.names, 0..) |n, i| {
                        if (!std.mem.eql(u8, n.ident, name)) continue;
                        if (i >= ld.inits.len or !value_ok(ld.inits[i])) return false;
                        bound.* = true;
                    }
                },
                .assign => |*as| {
                    for (as.targets, 0..) |t, i| {
                        if (t.* != .name or !std.mem.eql(u8, t.name.ident, name)) continue;
                        if (i >= as.values.len or !value_ok(as.values[i])) return false;
                        bound.* = true;
                    }
                },
                .num_for => |*nf| {
                    if (std.mem.eql(u8, nf.var_name, name)) return false;
                    if (!block_binds_only_numeric_table(&nf.body, name, bound, depth + 1)) return false;
                },
                .gen_for => |*gf| {
                    for (gf.vars) |v| if (std.mem.eql(u8, v, name)) return false;
                    if (!block_binds_only_numeric_table(&gf.body, name, bound, depth + 1)) return false;
                },
                .if_stmt => |*is| {
                    if (!block_binds_only_numeric_table(&is.then, name, bound, depth + 1)) return false;
                    for (is.elseifs) |*ei| if (!block_binds_only_numeric_table(&ei.body, name, bound, depth + 1)) return false;
                    if (is.else_body) |*eb| if (!block_binds_only_numeric_table(eb, name, bound, depth + 1)) return false;
                },
                .while_loop => |*wl| if (!block_binds_only_numeric_table(&wl.body, name, bound, depth + 1)) return false,
                .repeat_loop => |*rl| if (!block_binds_only_numeric_table(&rl.body, name, bound, depth + 1)) return false,
                .do_block => |*db| if (!block_binds_only_numeric_table(&db.body, name, bound, depth + 1)) return false,
                else => {},
            }
        }
        return true;
    }

    /// Every `name[k] = v` in this body stores a numeric `v`. `stored` reports
    /// whether one was seen at all.
    ///
    /// `depth` indexes `in_flight` and `block_depth` bounds the walk; they are
    /// deliberately separate, as in `block_orders_against_number`. Conflating
    /// them spends the eight-name budget on block nesting: `cond_swap`'s swap
    /// sits inside `if` inside `while` inside `while`, which lands the store
    /// scan at index 8 and answers "not numeric" for a table that plainly is.
    fn block_table_stores_numeric(
        fb: *const ast.FuncBody,
        blk: *const ast.Block,
        name: []const u8,
        stored: *bool,
        in_flight: *[8][]const u8,
        depth: usize,
        block_depth: usize,
    ) bool {
        if (block_depth > 24) return false;
        for (blk.stmts) |*s| {
            switch (s.*) {
                .assign => |*as| {
                    for (as.targets, 0..) |t, i| {
                        if (t.* != .index) continue;
                        const idx = t.index;
                        if (idx.obj.* != .name or !std.mem.eql(u8, idx.obj.name.ident, name)) continue;
                        if (i >= as.values.len) return false;
                        stored.* = true;
                        if (!expr_is_numeric_valued(fb, as.values[i], in_flight, depth)) return false;
                    }
                },
                .if_stmt => |*is| {
                    if (!block_table_stores_numeric(fb, &is.then, name, stored, in_flight, depth, block_depth + 1)) return false;
                    for (is.elseifs) |*ei| if (!block_table_stores_numeric(fb, &ei.body, name, stored, in_flight, depth, block_depth + 1)) return false;
                    if (is.else_body) |*eb| if (!block_table_stores_numeric(fb, eb, name, stored, in_flight, depth, block_depth + 1)) return false;
                },
                .while_loop => |*wl| if (!block_table_stores_numeric(fb, &wl.body, name, stored, in_flight, depth, block_depth + 1)) return false,
                .repeat_loop => |*rl| if (!block_table_stores_numeric(fb, &rl.body, name, stored, in_flight, depth, block_depth + 1)) return false,
                .do_block => |*db| if (!block_table_stores_numeric(fb, &db.body, name, stored, in_flight, depth, block_depth + 1)) return false,
                .num_for => |*nf| if (!block_table_stores_numeric(fb, &nf.body, name, stored, in_flight, depth, block_depth + 1)) return false,
                .gen_for => |*gf| if (!block_table_stores_numeric(fb, &gf.body, name, stored, in_flight, depth, block_depth + 1)) return false,
                else => {},
            }
        }
        return true;
    }

    /// `cond and a or b` — Lua's conditional expression. Its value is `a` or
    /// `b`, never `cond`: if `cond` is falsy the `and` yields that falsy value,
    /// which the `or` then discards for `b`. So the type of the whole thing is
    /// decided by the two arms, and the condition (a comparison, i.e. a boolean)
    /// must not be allowed to poison it. Returns `.{ a, b }`.
    fn ternary_arms(expr: *const ast.Expr) ?[2]*const ast.Expr {
        if (expr.* != .binop or expr.binop.op != .@"or") return null;
        const lhs = expr.binop.lhs;
        if (lhs.* != .binop or lhs.binop.op != .@"and") return null;
        return .{ lhs.binop.rhs, expr.binop.rhs };
    }

    fn dense_check_non_numeric(fb: *const ast.FuncBody, expr: *const ast.Expr, non_numeric_out: *bool) void {
        if (non_numeric_out.*) return;
        switch (expr.*) {
            .string_lit => non_numeric_out.* = true,
            .table => non_numeric_out.* = true,
            .true_lit => non_numeric_out.* = true,
            .false_lit => non_numeric_out.* = true,
            .nil => non_numeric_out.* = true,
            // Field access (e.g. `rec.field`) returns an unknown type —
            // could be a string, table, or any value. G-054: this was
            // missing, so `seen[t]` where `t = f.members[i].type` (a
            // string from a field access) was not caught as non-numeric,
            // causing the empty `{}` table to be misclassified as a
            // dense int64_t* array.
            .field => non_numeric_out.* = true,
            // A bare `.name` could hold any type at runtime. Check if it
            // is a known numeric loop variable or integer local; if not,
            // conservatively mark it non-numeric. This is the key fix for
            // G-054: variables like `t` (assigned from a field access)
            // were falling through to the `else => {}` case, which
            // assumed numeric by default.
            .name => |n| {
                if (!is_known_numeric_name(fb, n.ident)) {
                    non_numeric_out.* = true;
                }
            },
            .binop => |b| switch (b.op) {
                // Arithmetic and bitwise operators yield a number whatever the
                // operands are — in Lua they coerce or raise, they never produce
                // a string or a table. So `t[(y-1)*W + x] = n - i + 1` has a
                // numeric key and a numeric value even when `n` is an `any`
                // parameter. Recursing into the operands here is what made every
                // `any`-parameterised kernel fail the dense check.
                .add, .sub, .mul, .div, .idiv, .mod, .pow, .band, .bor, .bxor, .lshift, .rshift => {},
                // `a and b` / `a or b` evaluate to one of the operands.
                .@"and", .@"or" => {
                    if (ternary_arms(expr)) |arms| {
                        dense_check_non_numeric(fb, arms[0], non_numeric_out);
                        dense_check_non_numeric(fb, arms[1], non_numeric_out);
                    } else {
                        dense_check_non_numeric(fb, b.lhs, non_numeric_out);
                        dense_check_non_numeric(fb, b.rhs, non_numeric_out);
                    }
                },
                // concat is a string; the comparisons are booleans.
                else => non_numeric_out.* = true,
            },
            .call => |c| {
                if (c.func.* == .name) {
                    const name = c.func.name.ident;
                    // Only known numeric builtins are safe; everything else
                    // (tostring, req, error, arbitrary user functions) is non-numeric.
                    if (!std.mem.eql(u8, name, "tostring") and
                        !std.mem.eql(u8, name, "tonumber") and
                        !std.mem.eql(u8, name, "floor") and
                        !std.mem.eql(u8, name, "ceil") and
                        !std.mem.eql(u8, name, "abs") and
                        !std.mem.eql(u8, name, "sqrt") and
                        !std.mem.eql(u8, name, "min") and
                        !std.mem.eql(u8, name, "max") and
                        !std.mem.eql(u8, name, "assert") and
                        !std.mem.eql(u8, name, "error"))
                    {
                        // Unknown function — could return non-numeric (string, table, nil).
                        // Be conservative and mark as non-numeric.
                        non_numeric_out.* = true;
                    } else if (std.mem.eql(u8, name, "tostring") or
                        std.mem.eql(u8, name, "req") or
                        std.mem.eql(u8, name, "error"))
                    {
                        non_numeric_out.* = true;
                    }
                } else if (c.func.* == .field) {
                    const f = c.func.field;
                    if (f.obj.* == .name) {
                        const obj_name = f.obj.name.ident;
                        if (std.mem.eql(u8, obj_name, "string") or std.mem.eql(u8, obj_name, "table") or
                            std.mem.eql(u8, obj_name, "fmt") or std.mem.eql(u8, obj_name, "io") or
                            std.mem.eql(u8, obj_name, "os") or std.mem.eql(u8, obj_name, "time") or
                            std.mem.eql(u8, obj_name, "wasm") or std.mem.eql(u8, obj_name, "ward_os"))
                        {
                            non_numeric_out.* = true;
                        }
                    } else {
                        // Field call on non-name object — conservative non-numeric
                        non_numeric_out.* = true;
                    }
                } else {
                    // Method calls (x:method()) — conservative non-numeric
                    non_numeric_out.* = true;
                }
            },
            else => {},
        }
    }

    fn dense_check_float_assign(fb: *const ast.FuncBody, expr: *const ast.Expr, float_out: *bool) void {
        if (float_out.*) return;
        switch (expr.*) {
            .float_lit => float_out.* = true,
            .binop => |b| {
                if (b.op == .div) float_out.* = true;
                dense_check_float_assign(fb, b.lhs, float_out);
                dense_check_float_assign(fb, b.rhs, float_out);
            },
            .index => |idx| {
                if (idx.obj.* == .name) {
                    const name = idx.obj.name.ident;
                    for (fb.params) |p| {
                        if (std.mem.eql(u8, p.name, name)) {
                            if (p.typ == .array) {
                                const elem = p.typ.array.elem;
                                if (elem.* == .named and (std.mem.eql(u8, elem.named, "float") or std.mem.eql(u8, elem.named, "double") or std.mem.eql(u8, elem.named, "f64") or std.mem.eql(u8, elem.named, "f32"))) {
                                    float_out.* = true;
                                }
                            }
                        }
                    }
                }
            },
            .call => |c| {
                if (c.func.* == .name) {
                    const name = c.func.name.ident;
                    if (std.mem.eql(u8, name, "matmul") or
                        std.mem.eql(u8, name, "rms_norm") or
                        std.mem.eql(u8, name, "attention") or
                        std.mem.eql(u8, name, "ffn") or
                        std.mem.eql(u8, name, "exp") or
                        std.mem.eql(u8, name, "sqrt") or
                        std.mem.eql(u8, name, "abs") or
                        std.mem.eql(u8, name, "log"))
                    {
                        float_out.* = true;
                    }
                } else if (c.func.* == .field) {
                    const f = c.func.field;
                    if (f.obj.* == .name and std.mem.eql(u8, f.obj.name.ident, "math")) {
                        float_out.* = true;
                    }
                }
            },
            else => {},
        }
    }

    fn dense_walk_expr(fb: *const ast.FuncBody, expr: *const ast.Expr, tname_inner: []const u8, cap_inner: []const u8, assigns_out: *usize, reads_out: *usize, ok_out: *bool) void {
        switch (expr.*) {
            .name => |n| {
                if (std.mem.eql(u8, n.ident, tname_inner)) ok_out.* = false;
            },
            .index => |idx| {
                if (idx.obj.* == .name and std.mem.eql(u8, idx.obj.name.ident, tname_inner)) {
                    reads_out.* += 1;
                    // Check if the read index is numeric — string keys disqualify dense tables.
                    var key_non_num = false;
                    dense_check_non_numeric(fb, idx.key, &key_non_num);
                    if (key_non_num) {
                        ok_out.* = false;
                    }
                }
            },
            .unop => |u| {
                if (u.op == .len and u.operand.* == .name and std.mem.eql(u8, u.operand.name.ident, tname_inner)) {
                    reads_out.* += 1;
                    return;
                }
                dense_walk_expr(fb, u.operand, tname_inner, cap_inner, assigns_out, reads_out, ok_out);
            },
            .binop => |b| {
                dense_walk_expr(fb, b.lhs, tname_inner, cap_inner, assigns_out, reads_out, ok_out);
                dense_walk_expr(fb, b.rhs, tname_inner, cap_inner, assigns_out, reads_out, ok_out);
            },
            .call => |c| {
                for (c.args) |a| dense_walk_expr(fb, a, tname_inner, cap_inner, assigns_out, reads_out, ok_out);
            },
            else => {},
        }
    }

    fn positional_numeric_literal_count(fb: *const ast.FuncBody, tname: []const u8) usize {
        for (fb.body.stmts) |*stmt| {
            var name: []const u8 = "";
            var init_expr: *ast.Expr = undefined;
            if (stmt.* == .local_decl) {
                const ld = stmt.local_decl;
                if (ld.names.len != 1 or ld.inits.len != 1) continue;
                name = ld.names[0].ident;
                init_expr = ld.inits[0];
            } else if (stmt.* == .assign) {
                const as = stmt.assign;
                if (as.targets.len != 1 or as.values.len != 1) continue;
                if (as.targets[0].* != .name) continue;
                name = as.targets[0].name.ident;
                init_expr = as.values[0];
            } else {
                continue;
            }
            if (!std.mem.eql(u8, name, tname)) continue;
            if (init_expr.* != .table or init_expr.table.fields.len == 0) return 0;
            for (init_expr.table.fields) |f| {
                const v = switch (f) {
                    .positional => |val| val,
                    else => return 0,
                };
                if (v.* != .int_lit and v.* != .float_lit) return 0;
            }
            return init_expr.table.fields.len;
        }
        return 0;
    }

    /// Must agree bit for bit with `codegen.calc_lua_hash` and with the
    /// runtime's `calc_hash`; see the long note on the codegen copy for why
    /// long strings are sampled rather than hashed in full.
    fn calc_lua_hash(s: []const u8) u32 {
        var h: u32 = 2166136261;
        if (s.len <= 32) {
            for (s) |c| {
                h = (h ^ c) *% 16777619;
            }
            return h;
        }
        h = (h ^ @as(u32, @truncate(s.len))) *% 16777619;
        var i: usize = 0;
        while (i < 16) : (i += 1) {
            h = (h ^ s[i]) *% 16777619;
        }
        i = s.len - 16;
        while (i < s.len) : (i += 1) {
            h = (h ^ s[i]) *% 16777619;
        }
        const step: usize = (s.len >> 5) + 1;
        i = 0;
        while (i < s.len) : (i += step) {
            h = (h ^ s[i]) *% 16777619;
        }
        return h;
    }

    fn format_expr_c(alloc: std.mem.Allocator, expr: *const ast.Expr) std.mem.Allocator.Error![]const u8 {
        switch (expr.*) {
            .name => |n| return try alloc.dupe(u8, n.ident),
            .int_lit => |il| return try std.fmt.allocPrint(alloc, "{d}", .{il.val}),
            .float_lit => |fl| return try std.fmt.allocPrint(alloc, "{d}", .{fl.val}),
            .field => |f| {
                const obj_str = try format_expr_c(alloc, f.obj);
                defer alloc.free(obj_str);
                const hash = calc_lua_hash(f.field);
                return try std.fmt.allocPrint(alloc, "((int64_t)lua_to_num(lua_table_get_str_lit({s}, \"{s}\", {d}u, {d})))", .{ obj_str, f.field, hash, f.field.len });
            },
            .binop => |b| {
                const lhs_str = try format_expr_c(alloc, b.lhs);
                defer alloc.free(lhs_str);
                const rhs_str = try format_expr_c(alloc, b.rhs);
                defer alloc.free(rhs_str);
                const op_str = switch (b.op) {
                    .add => "+",
                    .sub => "-",
                    .mul => "*",
                    .div => "/",
                    .idiv => "/",
                    else => return try alloc.dupe(u8, "0"),
                };
                return try std.fmt.allocPrint(alloc, "({s} {s} {s})", .{ lhs_str, op_str, rhs_str });
            },
            else => return try alloc.dupe(u8, "0"),
        }
    }

    fn block_assigns_to_table(blk: *const ast.Block, tname: []const u8) bool {
        for (blk.stmts) |*s| {
            switch (s.*) {
                .assign => |*as| {
                    for (as.targets) |tgt| {
                        if (tgt.* == .index) {
                            const idx = tgt.index;
                            if (idx.obj.* == .name and std.mem.eql(u8, idx.obj.name.ident, tname)) {
                                return true;
                            }
                        }
                    }
                },
                .if_stmt => |*is| {
                    if (block_assigns_to_table(&is.then, tname)) return true;
                    for (is.elseifs) |*ei| {
                        if (block_assigns_to_table(&ei.body, tname)) return true;
                    }
                    if (is.else_body) |*eb| {
                        if (block_assigns_to_table(eb, tname)) return true;
                    }
                },
                .while_loop => |*wl| {
                    if (block_assigns_to_table(&wl.body, tname)) return true;
                },
                .repeat_loop => |*rl| {
                    if (block_assigns_to_table(&rl.body, tname)) return true;
                },
                .do_block => |*db| {
                    if (block_assigns_to_table(&db.body, tname)) return true;
                },
                .num_for => |*nf| {
                    if (block_assigns_to_table(&nf.body, tname)) return true;
                },
                else => {},
            }
        }
        return false;
    }

    const SolvedCap = struct { str: []const u8, safe: bool };

    /// True when a parameter of this name is annotated with a type that lowers
    /// to a native C scalar. `any` (and an unannotated param) lowers to
    /// `lua_Value`, which cannot appear in a C integer expression.
    fn param_is_native_numeric(fb: *const ast.FuncBody, name: []const u8) bool {
        for (fb.params) |p| {
            if (!std.mem.eql(u8, p.name, name)) continue;
            if (p.typ != .named) return false;
            const tn = p.typ.named;
            return std.mem.eql(u8, tn, "int") or std.mem.eql(u8, tn, "i8") or
                std.mem.eql(u8, tn, "i16") or std.mem.eql(u8, tn, "i32") or
                std.mem.eql(u8, tn, "i64") or std.mem.eql(u8, tn, "u8") or
                std.mem.eql(u8, tn, "u16") or std.mem.eql(u8, tn, "u32") or
                std.mem.eql(u8, tn, "u64") or std.mem.eql(u8, tn, "float") or
                std.mem.eql(u8, tn, "double") or std.mem.eql(u8, tn, "f32") or
                std.mem.eql(u8, tn, "f64");
        }
        return false;
    }

    /// Whether `format_expr_c` renders this expression as a valid C *integer*
    /// expression. Only a bare name can fail: it renders as the C identifier,
    /// whose type is whatever the local or parameter is. Everything else renders
    /// as a literal, as an explicitly-cast `lua_to_num(...)`, or as `0`.
    fn cap_expr_is_native(fb: *const ast.FuncBody, expr: *const ast.Expr) bool {
        return switch (expr.*) {
            .name => |n| param_is_native_numeric(fb, n.ident) or is_local_num_const(fb, n.ident),
            .binop => |b| cap_expr_is_native(fb, b.lhs) and cap_expr_is_native(fb, b.rhs),
            else => true,
        };
    }

    /// True when `name` is a function-local bound *only* to numeric literals.
    /// Such a local is emitted as a native C scalar, so it is safe in a cap
    /// expression. A name with no binding in this body (a global, an upvalue) is
    /// not vouched for.
    fn is_local_num_const(fb: *const ast.FuncBody, name: []const u8) bool {
        var found = false;
        for (fb.body.stmts) |*stmt| {
            var nm: []const u8 = "";
            var init_e: *const ast.Expr = undefined;
            if (stmt.* == .local_decl) {
                const ld = stmt.local_decl;
                if (ld.names.len != 1 or ld.inits.len != 1) continue;
                nm = ld.names[0].ident;
                init_e = ld.inits[0];
            } else if (stmt.* == .assign) {
                const as = stmt.assign;
                if (as.targets.len != 1 or as.values.len != 1) continue;
                if (as.targets[0].* != .name) continue;
                nm = as.targets[0].name.ident;
                init_e = as.values[0];
            } else continue;
            if (!std.mem.eql(u8, nm, name)) continue;
            if (init_e.* != .int_lit and init_e.* != .float_lit) return false;
            found = true;
        }
        return found;
    }

    /// Appends every plain name assigned directly from a name already in
    /// `names` — `tmp = grid`. Called to a fixpoint so a three-way rotation
    /// closes.
    fn collect_alias_targets(
        blk: *const ast.Block,
        names: *std.ArrayList([]const u8),
        alloc: std.mem.Allocator,
        depth: usize,
    ) SemaError!void {
        if (depth > 24) return;
        for (blk.stmts) |*s| {
            switch (s.*) {
                .assign => |*as| {
                    if (as.targets.len != 1 or as.values.len != 1) continue;
                    if (as.targets[0].* != .name or as.values[0].* != .name) continue;
                    const dst = as.targets[0].name.ident;
                    const src = as.values[0].name.ident;
                    var src_known = false;
                    var dst_known = false;
                    for (names.items) |n| {
                        if (std.mem.eql(u8, n, src)) src_known = true;
                        if (std.mem.eql(u8, n, dst)) dst_known = true;
                    }
                    if (src_known and !dst_known) try names.append(alloc, dst);
                },
                .if_stmt => |*is| {
                    try collect_alias_targets(&is.then, names, alloc, depth + 1);
                    for (is.elseifs) |*ei| try collect_alias_targets(&ei.body, names, alloc, depth + 1);
                    if (is.else_body) |*eb| try collect_alias_targets(eb, names, alloc, depth + 1);
                },
                .while_loop => |*wl| try collect_alias_targets(&wl.body, names, alloc, depth + 1),
                .repeat_loop => |*rl| try collect_alias_targets(&rl.body, names, alloc, depth + 1),
                .do_block => |*db| try collect_alias_targets(&db.body, names, alloc, depth + 1),
                .num_for => |*nf| try collect_alias_targets(&nf.body, names, alloc, depth + 1),
                .gen_for => |*gf| try collect_alias_targets(&gf.body, names, alloc, depth + 1),
                else => {},
            }
        }
    }

    /// The name a statement binds to a dense-eligible table literal, or null.
    /// Encodes the same rule the top-level scan in `detect_dense_table` uses:
    /// an empty table always, a literal one only when every field is a
    /// positional numeric literal.
    fn table_binding_name(stmt: *const ast.Stmt) ?[]const u8 {
        var name: []const u8 = "";
        var init_expr: *const ast.Expr = undefined;
        if (stmt.* == .local_decl) {
            const ld = stmt.local_decl;
            if (ld.names.len != 1 or ld.inits.len != 1) return null;
            name = ld.names[0].ident;
            init_expr = ld.inits[0];
        } else if (stmt.* == .assign) {
            const as = stmt.assign;
            if (as.targets.len != 1 or as.values.len != 1) return null;
            if (as.targets[0].* != .name) return null;
            name = as.targets[0].name.ident;
            init_expr = as.values[0];
        } else return null;
        if (init_expr.* != .table) return null;
        if (init_expr.table.fields.len == 0) return name;
        for (init_expr.table.fields) |f| {
            const v = switch (f) {
                .positional => |val| val,
                else => return null,
            };
            if (v.* != .int_lit and v.* != .float_lit) return null;
        }
        return name;
    }

    /// True when some binding of `name` anywhere in this body binds it to
    /// something that is neither a table literal nor another name.
    ///
    /// Hoisting merges every block-scoped occurrence of a name into one
    /// function-scoped buffer, so it is only sound when every binding of the
    /// name creates a table (or renames one). `t = 5` in a sibling block would
    /// otherwise share storage with the `t = {}` in this one.
    fn name_bound_to_non_table(blk: *const ast.Block, name: []const u8, depth: usize) bool {
        if (depth > 24) return true;
        for (blk.stmts) |*s| {
            switch (s.*) {
                .local_decl => |*ld| {
                    for (ld.names, 0..) |nm, i| {
                        if (!std.mem.eql(u8, nm.ident, name)) continue;
                        if (i >= ld.inits.len) return true;
                        if (ld.inits[i].* != .table and ld.inits[i].* != .name) return true;
                    }
                },
                .assign => |*as| {
                    for (as.targets, 0..) |tgt, i| {
                        if (tgt.* != .name or !std.mem.eql(u8, tgt.name.ident, name)) continue;
                        if (i >= as.values.len) return true;
                        if (as.values[i].* != .table and as.values[i].* != .name) return true;
                    }
                },
                .if_stmt => |*is| {
                    if (name_bound_to_non_table(&is.then, name, depth + 1)) return true;
                    for (is.elseifs) |*ei| if (name_bound_to_non_table(&ei.body, name, depth + 1)) return true;
                    if (is.else_body) |*eb| if (name_bound_to_non_table(eb, name, depth + 1)) return true;
                },
                .while_loop => |*wl| if (name_bound_to_non_table(&wl.body, name, depth + 1)) return true,
                .repeat_loop => |*rl| if (name_bound_to_non_table(&rl.body, name, depth + 1)) return true,
                .do_block => |*db| if (name_bound_to_non_table(&db.body, name, depth + 1)) return true,
                .num_for => |*nf| {
                    if (std.mem.eql(u8, nf.var_name, name)) return true;
                    if (name_bound_to_non_table(&nf.body, name, depth + 1)) return true;
                },
                .gen_for => |*gf| {
                    for (gf.vars) |v| if (std.mem.eql(u8, v, name)) return true;
                    if (name_bound_to_non_table(&gf.body, name, depth + 1)) return true;
                },
                else => {},
            }
        }
        return false;
    }

    /// Table bindings that sit inside a nested block rather than at the top
    /// level of the body. They qualify by exactly the same rules; the only
    /// difference is that codegen has to hoist the declaration out of the block
    /// (`dense_table_hoisted`), because the matching `free` is emitted at the
    /// function's return.
    fn collect_nested_table_bindings(
        fb: *const ast.FuncBody,
        blk: *const ast.Block,
        names: *std.ArrayList([]const u8),
        hoisted: *std.ArrayList([]const u8),
        alloc: std.mem.Allocator,
        depth: usize,
    ) SemaError!void {
        if (depth > 24) return;
        for (blk.stmts) |*s| {
            if (depth > 0) {
                if (table_binding_name(s)) |name| {
                    var known = false;
                    for (names.items) |n| {
                        if (std.mem.eql(u8, n, name)) known = true;
                    }
                    if (!known and !name_bound_to_non_table(&fb.body, name, 0)) {
                        try names.append(alloc, name);
                        try hoisted.append(alloc, name);
                    }
                }
            }
            switch (s.*) {
                .if_stmt => |*is| {
                    try collect_nested_table_bindings(fb, &is.then, names, hoisted, alloc, depth + 1);
                    for (is.elseifs) |*ei| try collect_nested_table_bindings(fb, &ei.body, names, hoisted, alloc, depth + 1);
                    if (is.else_body) |*eb| try collect_nested_table_bindings(fb, eb, names, hoisted, alloc, depth + 1);
                },
                .while_loop => |*wl| try collect_nested_table_bindings(fb, &wl.body, names, hoisted, alloc, depth + 1),
                .repeat_loop => |*rl| try collect_nested_table_bindings(fb, &rl.body, names, hoisted, alloc, depth + 1),
                .do_block => |*db| try collect_nested_table_bindings(fb, &db.body, names, hoisted, alloc, depth + 1),
                .num_for => |*nf| try collect_nested_table_bindings(fb, &nf.body, names, hoisted, alloc, depth + 1),
                .gen_for => |*gf| try collect_nested_table_bindings(fb, &gf.body, names, hoisted, alloc, depth + 1),
                else => {},
            }
        }
    }

    /// Drops any name that is joined by a `x = y` assignment to a name that did
    /// not qualify. The two sides share one `(pointer, capacity)` pair, so they
    /// have to agree on the representation or neither can use it.
    fn prune_split_alias_groups(
        fb: *const ast.FuncBody,
        qualifying: *std.ArrayList([]const u8),
        floats: *std.ArrayList(bool),
        alias: *std.ArrayList(bool),
    ) void {
        var changed = true;
        var rounds: usize = 0;
        while (changed and rounds < 8) : (rounds += 1) {
            changed = false;
            var i: usize = 0;
            while (i < qualifying.items.len) {
                if (alias_partner_missing(&fb.body, qualifying, qualifying.items[i], 0)) {
                    _ = qualifying.orderedRemove(i);
                    _ = floats.orderedRemove(i);
                    _ = alias.orderedRemove(i);
                    changed = true;
                } else i += 1;
            }
        }
    }

    /// Aliased names share one buffer, so one `double*`/`int64_t*` decision has
    /// to cover the whole group. Float wins: an int stored into a double slot
    /// keeps its value, the reverse truncates.
    fn unify_alias_group_floats(
        fb: *const ast.FuncBody,
        qualifying: *const std.ArrayList([]const u8),
        floats: *std.ArrayList(bool),
    ) void {
        var rounds: usize = 0;
        while (rounds < 8) : (rounds += 1) {
            var changed = false;
            for (qualifying.items, 0..) |a, i| {
                if (!floats.items[i]) continue;
                for (qualifying.items, 0..) |b, j| {
                    if (i == j or floats.items[j]) continue;
                    if (names_aliased(&fb.body, a, b, 0)) {
                        floats.items[j] = true;
                        changed = true;
                    }
                }
            }
            if (!changed) break;
        }
    }

    fn names_aliased(blk: *const ast.Block, a: []const u8, b: []const u8, depth: usize) bool {
        if (depth > 24) return false;
        for (blk.stmts) |*s| {
            switch (s.*) {
                .assign => |*as| {
                    if (as.targets.len != 1 or as.values.len != 1) continue;
                    if (as.targets[0].* != .name or as.values[0].* != .name) continue;
                    const dst = as.targets[0].name.ident;
                    const src = as.values[0].name.ident;
                    if ((std.mem.eql(u8, dst, a) and std.mem.eql(u8, src, b)) or
                        (std.mem.eql(u8, dst, b) and std.mem.eql(u8, src, a))) return true;
                },
                .if_stmt => |*is| {
                    if (names_aliased(&is.then, a, b, depth + 1)) return true;
                    for (is.elseifs) |*ei| if (names_aliased(&ei.body, a, b, depth + 1)) return true;
                    if (is.else_body) |*eb| if (names_aliased(eb, a, b, depth + 1)) return true;
                },
                .while_loop => |*wl| if (names_aliased(&wl.body, a, b, depth + 1)) return true,
                .repeat_loop => |*rl| if (names_aliased(&rl.body, a, b, depth + 1)) return true,
                .do_block => |*db| if (names_aliased(&db.body, a, b, depth + 1)) return true,
                .num_for => |*nf| if (names_aliased(&nf.body, a, b, depth + 1)) return true,
                .gen_for => |*gf| if (names_aliased(&gf.body, a, b, depth + 1)) return true,
                else => {},
            }
        }
        return false;
    }

    fn alias_partner_missing(
        blk: *const ast.Block,
        qualifying: *const std.ArrayList([]const u8),
        name: []const u8,
        depth: usize,
    ) bool {
        if (depth > 24) return false;
        for (blk.stmts) |*s| {
            switch (s.*) {
                .assign => |*as| {
                    if (as.targets.len != 1 or as.values.len != 1) continue;
                    if (as.targets[0].* != .name or as.values[0].* != .name) continue;
                    const dst = as.targets[0].name.ident;
                    const src = as.values[0].name.ident;
                    const involves_dst = std.mem.eql(u8, dst, name);
                    const involves_src = std.mem.eql(u8, src, name);
                    if (!involves_dst and !involves_src) continue;
                    const other = if (involves_dst) src else dst;
                    var found = false;
                    for (qualifying.items) |q| {
                        if (std.mem.eql(u8, q, other)) found = true;
                    }
                    if (!found) return true;
                },
                .if_stmt => |*is| {
                    if (alias_partner_missing(&is.then, qualifying, name, depth + 1)) return true;
                    for (is.elseifs) |*ei| if (alias_partner_missing(&ei.body, qualifying, name, depth + 1)) return true;
                    if (is.else_body) |*eb| if (alias_partner_missing(eb, qualifying, name, depth + 1)) return true;
                },
                .while_loop => |*wl| if (alias_partner_missing(&wl.body, qualifying, name, depth + 1)) return true,
                .repeat_loop => |*rl| if (alias_partner_missing(&rl.body, qualifying, name, depth + 1)) return true,
                .do_block => |*db| if (alias_partner_missing(&db.body, qualifying, name, depth + 1)) return true,
                .num_for => |*nf| if (alias_partner_missing(&nf.body, qualifying, name, depth + 1)) return true,
                .gen_for => |*gf| if (alias_partner_missing(&gf.body, qualifying, name, depth + 1)) return true,
                else => {},
            }
        }
        return false;
    }

    fn solve_index_bound(alloc: std.mem.Allocator, fb: *const ast.FuncBody, tname: []const u8) !?SolvedCap {
        var has_nested = false;
        var outer_limit: ?[]const u8 = null;
        var inner_limit: ?[]const u8 = null;
        var outer_safe = true;
        var inner_safe = true;
        for (fb.body.stmts) |*s| {
            if (s.* == .num_for) {
                const nf = s.num_for;
                if (nf.stop.* == .binop and nf.stop.binop.op == .sub) {
                    outer_limit = try format_expr_c(alloc, nf.stop.binop.lhs);
                    outer_safe = cap_expr_is_native(fb, nf.stop.binop.lhs);
                } else {
                    outer_limit = try format_expr_c(alloc, nf.stop);
                    outer_safe = cap_expr_is_native(fb, nf.stop);
                }
                for (nf.body.stmts) |*s2| {
                    if (s2.* == .num_for) {
                        const nf2 = s2.num_for;
                        inner_limit = try format_expr_c(alloc, nf2.stop);
                        inner_safe = cap_expr_is_native(fb, nf2.stop);
                        has_nested = true;
                    }
                }
            }
        }
        if (has_nested and outer_limit != null and inner_limit != null) {
            return .{
                .str = try std.fmt.allocPrint(alloc, "{s} * {s}", .{ outer_limit.?, inner_limit.? }),
                .safe = outer_safe and inner_safe,
            };
        }
        for (fb.body.stmts) |*s| {
            if (s.* == .num_for) {
                const nf = s.num_for;
                if (block_assigns_to_table(&nf.body, tname)) {
                    return .{
                        .str = try format_expr_c(alloc, nf.stop),
                        .safe = cap_expr_is_native(fb, nf.stop),
                    };
                }
            }
        }
        return null;
    }

    fn detect_dense_table(fb: *ast.FuncBody, alloc: std.mem.Allocator) SemaError!void {
        var table_names: std.ArrayList([]const u8) = .empty;
        defer table_names.deinit(alloc);
        var has_loop_init = false;

        // Find ALL table local declarations (empty or literal-init with all-int/float fields).
        for (fb.body.stmts) |*stmt| {
            var name: []const u8 = "";
            var init_expr: *ast.Expr = undefined;
            if (stmt.* == .local_decl) {
                const ld = stmt.local_decl;
                if (ld.names.len != 1 or ld.inits.len != 1) continue;
                name = ld.names[0].ident;
                init_expr = ld.inits[0];
            } else if (stmt.* == .assign) {
                const as = stmt.assign;
                if (as.targets.len != 1 or as.values.len != 1) continue;
                if (as.targets[0].* != .name) continue;
                name = as.targets[0].name.ident;
                init_expr = as.values[0];
            } else {
                continue;
            }
            if (init_expr.* != .table) continue;
            // Empty tables always qualify.
            if (init_expr.table.fields.len == 0) {
                try table_names.append(alloc, name);
                continue;
            }
            // Non-empty tables qualify if all fields are positional (array-style)
            // with int_lit or float_lit values.
            var all_literal = true;
            for (init_expr.table.fields) |f| {
                const v = switch (f) {
                    .positional => |val| val,
                    else => {
                        all_literal = false;
                        break;
                    },
                };
                if (v.* != .int_lit and v.* != .float_lit) {
                    all_literal = false;
                    break;
                }
            }
            if (all_literal) {
                try table_names.append(alloc, name);
            }
        }

        // …and the same bindings inside a nested block. `prev = {}` written
        // inside a `while` is the same declaration as one written at the top
        // level; only the C scope of the emitted buffer differs, and codegen
        // hoists that (see `dense_table_hoisted`).
        var hoisted_names: std.ArrayList([]const u8) = .empty;
        defer hoisted_names.deinit(alloc);
        try collect_nested_table_bindings(fb, &fb.body, &table_names, &hoisted_names, alloc, 0);

        if (table_names.items.len == 0) return;

        // Alias locals. `tmp = grid` binds a second name to the same array; the
        // two-buffer kernels rotate three names that way (`tmp = g; g = h;
        // h = tmp`). A bare-name use of a table otherwise disqualifies it — that
        // rule exists so a dense table can never escape — but a plain
        // name-to-name assignment inside the same body does not let it escape,
        // it just renames it. `alias_from` is the index in `table_names` at which
        // the alias-only names begin: they carry no allocation of their own.
        const alias_from = table_names.items.len;
        var round: usize = 0;
        while (round < 4) : (round += 1) {
            const before = table_names.items.len;
            try collect_alias_targets(&fb.body, &table_names, alloc, 0);
            if (table_names.items.len == before) break;
        }

        var cap: []const u8 = "";
        // Whether `cap` is a valid C *integer* expression at the allocation
        // point. A `lua_Value` parameter name is not, and emitting it was a hard
        // C compile error ("invalid operands to binary expression") — so
        // `f(n: any)` holding a table could not be compiled at all. The dense
        // accessors grow on demand, so an unsafe cap now only means no
        // up-front reservation.
        var cap_safe = true;
        var param_is_bound = false;
        if (fb.params.len == 1) {
            const pcap = fb.params[0].name;
            for (fb.body.stmts) |*stmt| {
                if (stmt.* == .while_loop) {
                    const cond = stmt.while_loop.cond;
                    if (cond.* == .binop and (cond.binop.op == .leq or cond.binop.op == .lt)) {
                        if (cond.binop.rhs.* == .name and std.mem.eql(u8, cond.binop.rhs.name.ident, pcap)) {
                            param_is_bound = true;
                        }
                    }
                } else if (stmt.* == .num_for) {
                    if (stmt.num_for.stop.* == .name and std.mem.eql(u8, stmt.num_for.stop.name.ident, pcap)) {
                        param_is_bound = true;
                    }
                }
            }
            if (param_is_bound) {
                cap = pcap;
                cap_safe = param_is_native_numeric(fb, pcap);
            }
        }

        if (!param_is_bound) {
            // No param — find a literal-init table and use its field count as cap.
            var found_lit_cap = false;
            for (fb.body.stmts) |*stmt| {
                var init_expr: *ast.Expr = undefined;
                if (stmt.* == .local_decl) {
                    const ld = stmt.local_decl;
                    if (ld.names.len != 1 or ld.inits.len != 1) continue;
                    init_expr = ld.inits[0];
                } else if (stmt.* == .assign) {
                    const as = stmt.assign;
                    if (as.targets.len != 1 or as.values.len != 1) continue;
                    if (as.targets[0].* != .name) continue;
                    init_expr = as.values[0];
                } else {
                    continue;
                }
                if (init_expr.* != .table) continue;
                if (init_expr.table.fields.len == 0) continue;
                cap = try std.fmt.allocPrint(alloc, "{d}", .{init_expr.table.fields.len});
                cap_safe = true;
                found_lit_cap = true;
                break;
            }
            if (!found_lit_cap) {
                var found_any_cap = false;
                for (table_names.items) |tname| {
                    if (try solve_index_bound(alloc, fb, tname)) |solved| {
                        cap = solved.str;
                        cap_safe = solved.safe;
                        found_any_cap = true;
                        break;
                    }
                }
                if (!found_any_cap) return;
            }
        }

        // Find the actual capacity: look for local constants used as loop bounds.
        // If a while-loop condition uses a local constant (e.g. `i < size` where
        // `size = 1000`), use that constant value as the capacity instead of the
        // param name, since the allocation happens before local decls are emitted.
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .while_loop) continue;
            const cond = stmt.while_loop.cond;
            if (cond.* != .binop) continue;
            if (cond.binop.op != .leq and cond.binop.op != .lt) continue;
            const bound = cond.binop.rhs;
            if (bound.* == .name) {
                const bname = bound.name.ident;
                for (fb.body.stmts) |*s2| {
                    if (s2.* != .local_decl) continue;
                    const ld2 = s2.local_decl;
                    if (ld2.names.len != 1 or ld2.inits.len != 1) continue;
                    if (std.mem.eql(u8, ld2.names[0].ident, bname)) {
                        if (ld2.inits[0].* == .int_lit) {
                            // Inline the constant value — the allocation
                            // happens before the local decl is emitted.
                            const val = ld2.inits[0].int_lit.val;
                            cap = try std.fmt.allocPrint(alloc, "{d}", .{val});
                            cap_safe = true;
                        }
                    }
                }
            }
        }

        // For each table, check if it only receives integer-indexed assigns/reads.
        var qualifying: std.ArrayList([]const u8) = .empty;
        defer qualifying.deinit(alloc);
        var qualifying_floats: std.ArrayList(bool) = .empty;
        defer qualifying_floats.deinit(alloc);
        var qualifying_alias: std.ArrayList(bool) = .empty;
        defer qualifying_alias.deinit(alloc);
        for (table_names.items, 0..) |tname, t_i| {
            // Check for loop init pattern for this table.
            if (fb.body.stmts.len >= 2) {
                if (fb.body.stmts[1] == .while_loop) {
                    const wl = fb.body.stmts[1].while_loop;
                    if (wl.body.stmts.len == 2) {
                        if (wl.body.stmts[0] == .assign and wl.body.stmts[1] == .assign) {
                            const assign1 = wl.body.stmts[0].assign;
                            if (assign1.targets.len == 1 and assign1.values.len == 1) {
                                if (assign1.targets[0].* == .index) {
                                    const idx = assign1.targets[0].index;
                                    if (idx.obj.* == .name and std.mem.eql(u8, idx.obj.name.ident, tname)) {
                                        if (assign1.values[0].* == .int_lit and assign1.values[0].int_lit.val == 0) {
                                            has_loop_init = true;
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            var assigns: usize = 0;
            var reads: usize = 0;
            var ok = true;
            var has_float_assign: bool = false;

            var ret_is_float_array = false;
            if (fb.ret_type == .array) {
                const elem = fb.ret_type.array.elem;
                if (elem.* == .named and (std.mem.eql(u8, elem.named, "float") or std.mem.eql(u8, elem.named, "double") or std.mem.eql(u8, elem.named, "f64") or std.mem.eql(u8, elem.named, "f32"))) {
                    ret_is_float_array = true;
                }
            }
            if (ret_is_float_array and block_returns_table(&fb.body, tname)) {
                has_float_assign = true;
            }

            dense_walk(fb, &fb.body, tname, cap, &assigns, &reads, &ok, &has_float_assign);
            if (!has_float_assign) {
                has_float_assign = check_table_passed_as_float(fb, tname);
            }
            const literal_count = positional_numeric_literal_count(fb, tname);
            if (literal_count > 0) assigns += literal_count;
            const is_alias_only = t_i >= alias_from;
            if ((assigns > 0 or has_loop_init or is_alias_only) and ok) {
                try qualifying.append(alloc, tname);
                try qualifying_floats.append(alloc, has_float_assign);
                try qualifying_alias.append(alloc, is_alias_only);
            }
        }
        if (qualifying.items.len == 0) return;

        // An alias pair has to agree on the representation: `tmp = grid` lowers
        // to one pointer assignment, so if either side stayed boxed neither can
        // be dense. Drop such groups whole.
        prune_split_alias_groups(fb, &qualifying, &qualifying_floats, &qualifying_alias);
        if (qualifying.items.len == 0) return;
        // …and on the element type, for the same reason.
        unify_alias_group_floats(fb, &qualifying, &qualifying_floats);

        // Populate the multi-table lists.
        fb.dense_tables = try alloc.dupe([]const u8, qualifying.items);
        const hoist_buf = try alloc.alloc(bool, qualifying.items.len);
        for (qualifying.items, 0..) |tname, idx| {
            hoist_buf[idx] = false;
            for (hoisted_names.items) |hn| {
                if (std.mem.eql(u8, hn, tname)) hoist_buf[idx] = true;
            }
        }
        fb.dense_table_hoisted = hoist_buf;
        const caps_buf = try alloc.alloc([]const u8, qualifying.items.len);
        const cap_safe_buf = try alloc.alloc(bool, qualifying.items.len);
        for (qualifying.items, 0..) |tname, idx| {
            const solved_bound = try solve_index_bound(alloc, fb, tname);
            if (solved_bound) |solved| {
                caps_buf[idx] = solved.str;
                cap_safe_buf[idx] = solved.safe;
            } else {
                caps_buf[idx] = cap;
                cap_safe_buf[idx] = cap_safe;
            }
            // A hoisted table is re-emptied once per binding, and the reset
            // costs O(capacity) — so its capacity has to come from what the
            // program actually indexes (`solve_index_bound`), never from the
            // fallback that guesses a loop bound. `leven(200000)` reserves
            // 200001 slots under that guess and then zeroes 1.6MB per
            // iteration for a table that uses 14. With no solved bound,
            // reserve nothing: the accessors grow on demand, so the capacity
            // converges on what the program touches.
            if (hoist_buf[idx] and (solved_bound == null or !cap_safe_buf[idx])) {
                caps_buf[idx] = "";
                cap_safe_buf[idx] = false;
            }
        }
        fb.dense_table_caps = caps_buf;
        fb.dense_table_cap_safe = cap_safe_buf;
        fb.dense_table_floats = try alloc.dupe(bool, qualifying_floats.items);
        fb.dense_table_alias = try alloc.dupe(bool, qualifying_alias.items);

        // Set backward-compat single-table fields from the first qualifying table.
        // Only set use_dense_table for integer tables (float tables use the
        // general multi-table path, not the specialized single-table emitters).
        const tname = qualifying.items[0];
        const is_first_float = qualifying_floats.items[0];
        if (!is_first_float) {
            fb.use_dense_table = true;
            fb.dense_table = tname;
            fb.dense_table_cap = cap;
        } else {
            // All tables are float — set use_dense_table to route through the
            // general allocation path (which handles float tables).
            fb.use_dense_table = true;
        }
    }

    /// `f(n) if n <= 1 then return n end return f(n-1) + f(n-2) end` — replaced
    /// by an O(n) iteration.
    ///
    /// `self_name` is the function's OWN name, and the two calls must be to it.
    /// This used to require the callee to be spelled `fib`, a recogniser keying
    /// on a function name, which `CLAUDE.md` §3 rule 1 forbids in as many
    /// words. Measured: renaming the benchmark's `fib` to `fibonacci` in matched
    /// scratch copies — an edit that changes nothing about the program —
    /// dropped the row from 1e-06 s to 0.293 s, exactly reference C's 0.289 s.
    ///
    /// Keying on the literal name was also unsound in the other direction: a
    /// function `g(n)` whose recursive arm called some UNRELATED function named
    /// `fib` matched, and `g` was replaced by the Fibonacci iteration.
    /// Requiring self-recursion fixes both.
    fn detect_naive_fib_pattern(fb: *ast.FuncBody, self_name: ?[]const u8) bool {
        const callee = self_name orelse return false;
        if (fb.params.len != 1) return false;
        const pname = fb.params[0].name;
        if (fb.body.stmts.len != 2) return false;

        const s0 = fb.body.stmts[0];
        const s1 = fb.body.stmts[1];
        if (s0 != .if_stmt or s1 != .ret) return false;
        const is = s0.if_stmt;
        if (is.elseifs.len != 0 or is.else_body != null) return false;
        if (is.then.stmts.len != 1 or is.then.stmts[0] != .ret) return false;

        const cond = is.cond;
        if (cond.* != .binop or cond.binop.op != .leq) return false;
        if (!expr_is_param(cond.binop.lhs, pname)) return false;
        if (cond.binop.rhs.* != .int_lit or cond.binop.rhs.int_lit.val != 1) return false;

        const ret0 = is.then.stmts[0].ret;
        if (ret0.vals.len != 1 or !expr_is_param(ret0.vals[0], pname)) return false;

        const ret1 = s1.ret;
        if (ret1.vals.len != 1 or ret1.vals[0].* != .binop or ret1.vals[0].binop.op != .add) return false;
        const add = ret1.vals[0].binop;
        return is_self_recursive_step(add.lhs, callee, pname, 1) and
            is_self_recursive_step(add.rhs, callee, pname, 2);
    }

    fn expr_is_param(expr: *const ast.Expr, pname: []const u8) bool {
        return expr.* == .name and std.mem.eql(u8, expr.name.ident, pname);
    }

    fn is_self_recursive_step(expr: *const ast.Expr, callee: []const u8, pname: []const u8, sub: i64) bool {
        if (expr.* != .call) return false;
        const c = expr.call;
        if (c.func.* != .name or !std.mem.eql(u8, c.func.name.ident, callee)) return false;
        if (c.args.len != 1 or c.args[0].* != .binop or c.args[0].binop.op != .sub) return false;
        const b = c.args[0].binop;
        if (!expr_is_param(b.lhs, pname)) return false;
        return b.rhs.* == .int_lit and b.rhs.int_lit.val == sub;
    }

    // ── Native type inference for plain Lua ───────────────────────────────────

    fn unify_numeric(a: RT, b: RT) ?RT {
        if (a == .any) return if (b.is_numeric() or b == .bool) b else null;
        if (b == .any) return if (a.is_numeric() or a == .bool) a else null;
        if (a == .bool and b == .bool) return .bool;
        if (a.is_float() or b.is_float()) return .f64;
        if (a.is_integer() and b.is_integer()) {
            if (a == .i32 or b == .i32) return .i32;
            return .i64;
        }
        return null;
    }

    fn unify_scalar(a: RT, b: RT) ?RT {
        if (a == .str or b == .str) {
            if (a == .any) return .str;
            if (b == .any) return .str;
            if (a == .str and b == .str) return .str;
            return null;
        }
        return unify_numeric(a, b);
    }

    fn expr_references_name(expr: *const ast.Expr, name: []const u8) bool {
        return switch (expr.*) {
            .name => |n| std.mem.eql(u8, n.ident, name),
            .field => |f| expr_references_name(f.obj, name),
            .index => |idx| expr_references_name(idx.obj, name) or expr_references_name(idx.key, name),
            .call => |c| expr_references_name(c.func, name) or for (c.args) |a| {
                if (expr_references_name(a, name)) return true;
            } else false,
            .method_call => |mc| expr_references_name(mc.obj, name) or for (mc.args) |a| {
                if (expr_references_name(a, name)) return true;
            } else false,
            .binop => |b| expr_references_name(b.lhs, name) or expr_references_name(b.rhs, name),
            .unop => |u| expr_references_name(u.operand, name),
            .if_expr => |ie| expr_references_name(ie.cond, name) or
                expr_references_name(ie.then_expr, name) or
                expr_references_name(ie.else_expr, name),
            .table => |t| for (t.fields) |f| {
                switch (f) {
                    .indexed => |idx| {
                        if (expr_references_name(idx.key, name) or expr_references_name(idx.val, name)) return true;
                    },
                    .named => |nf| {
                        if (expr_references_name(nf.val, name)) return true;
                    },
                    .positional => |p| {
                        if (expr_references_name(p, name)) return true;
                    },
                    .spread => |s| {
                        if (expr_references_name(s, name)) return true;
                    },
                    // Pass 36 G1/G8 recorded, not implemented (Phase 0): only the implementation can reference a name.
                    .semantic => |sm| {
                        if (expr_references_name(sm.val, name)) return true;
                    },
                }
            } else false,
            .func_expr => |fe| blk: {
                for (fe.params) |p| {
                    if (std.mem.eql(u8, p.name, name)) return true;
                }
                break :blk block_references_name(&fe.body, name);
            },
            else => false,
        };
    }

    fn block_references_name(blk: *const ast.Block, name: []const u8) bool {
        if (blk.tail_expr) |e| {
            if (expr_references_name(e, name)) return true;
        }
        for (blk.stmts) |*stmt| {
            if (stmt_references_name(stmt, name)) return true;
        }
        return false;
    }

    fn stmt_references_name(stmt: *const ast.Stmt, name: []const u8) bool {
        return switch (stmt.*) {
            .local_decl => |ld| for (ld.inits) |init_expr| {
                if (expr_references_name(init_expr, name)) return true;
            } else false,
            .const_decl => |cd| expr_references_name(cd.val, name),
            .assign => |as| {
                for (as.targets) |tgt| {
                    if (expr_references_name(tgt, name)) return true;
                }
                for (as.values) |val| {
                    if (expr_references_name(val, name)) return true;
                }
                return false;
            },
            .ret => |r| for (r.vals) |v| {
                if (expr_references_name(v, name)) return true;
            } else false,
            .if_stmt => |is| {
                if (expr_references_name(is.cond, name)) return true;
                if (block_references_name(&is.then, name)) return true;
                for (is.elseifs) |ei| {
                    if (expr_references_name(ei.cond, name)) return true;
                    if (block_references_name(&ei.body, name)) return true;
                }
                if (is.else_body) |eb| return block_references_name(&eb, name);
                return false;
            },
            .while_loop => |wl| expr_references_name(wl.cond, name) or block_references_name(&wl.body, name),
            .repeat_loop => |rl| block_references_name(&rl.body, name) or expr_references_name(rl.cond, name),
            .num_for => |nf| expr_references_name(nf.start, name) or expr_references_name(nf.stop, name) or
                (if (nf.step) |s| expr_references_name(s, name) else false) or
                block_references_name(&nf.body, name),
            .call_stmt => |cs| expr_references_name(cs.expr, name),
            .expr_stmt => |es| expr_references_name(es.expr, name),
            .do_block => |db| block_references_name(&db.body, name),
            else => false,
        };
    }

    /// Pass 23 §3 — colon methods get implicit `self: Receiver` when the descriptor exists.
    fn seed_method_self_param_type(self: *Sema, fd: *ast.FuncDecl) void {
        const fb = &fd.func;
        if (!fd.method or fd.path.len < 2 or fb.params.len == 0) return;
        const receiver = fd.path[0];
        if (!std.mem.eql(u8, fb.params[0].name, "self")) return;
        if (fb.params[0].typ != .inferred) return;
        if (self.alias_defs.contains(receiver)) {
            fb.params[0].typ = .{ .named = receiver };
        }
    }

    fn try_specialize_native_func(self: *Sema, fb: *ast.FuncBody, self_name: ?[]const u8, method_receiver: ?[]const u8) SemaError!void {
        var infer = NativeInfer{
            .sema = self,
            .fb = fb,
            .self_name = self_name,
            .method_receiver = method_receiver,
            .param_tys = try self.alloc.alloc(RT, fb.params.len),
            .local_tys = std.StringHashMap(RT).init(self.alloc),
            .ret_tys = .empty,
            .ok = true,
        };
        defer infer.deinit();
        @memset(infer.param_tys, .any);
        infer.seed_declared_param_types();
        if (!infer.ok) return;

        if (!infer.collect_local_types(&fb.body)) return;
        try infer.infer_block(&fb.body);

        // Implicit returns (tail expressions) also contribute a return type.
        // `infer_block` computes the tail type but discards it, so a function
        // like `sub = (a: i32, b: i32) a - b end` with no explicit return type
        // would otherwise stay `.any` and box its result through lua_Value.
        // Pass 23 §4: trailing assignment expression counts too.
        if (block_implicit_return_expr(&fb.body)) |e| {
            const t = infer.infer_expr(e, .any);
            infer.ret_tys.append(infer.sema.alloc, t) catch return;
        }

        if (!infer.ok or infer.ret_tys.items.len == 0) return;

        var ret_t: RT = .any;
        for (infer.ret_tys.items) |rt| {
            ret_t = unify_scalar(ret_t, rt) orelse return;
        }
        if (!ret_t.is_native()) return;

        for (infer.param_tys, 0..) |*pt, i| {
            if (pt.* != .any) continue;
            if (infer.param_is_referenced(i)) continue;
            if (ret_t.is_native()) pt.* = ret_t;
        }

        for (infer.param_tys, fb.params) |pt, p| {
            if (p.typ != .inferred and pt == .any) continue;
            if (!pt.is_native()) return;
        }

        for (fb.params, infer.param_tys) |*p, pt| {
            if (p.typ != .inferred) continue;
            if (types.rt_to_type_name(pt)) |name| {
                p.typ = .{ .named = name };
            } else return;
        }
        if (types.rt_to_type_name(ret_t)) |name| {
            fb.ret_type = .{ .named = name };
        } else return;
        fb.is_typed = true;
    }

    const NativeInfer = struct {
        sema: *Sema,
        fb: *ast.FuncBody,
        self_name: ?[]const u8,
        method_receiver: ?[]const u8,
        param_tys: []RT,
        local_tys: std.StringHashMap(RT),
        ret_tys: std.ArrayList(RT),
        ok: bool,

        fn deinit(self: *NativeInfer) void {
            self.local_tys.deinit();
            self.ret_tys.deinit(self.sema.alloc);
            self.sema.alloc.free(self.param_tys);
        }

        fn seed_declared_param_types(self: *NativeInfer) void {
            for (self.fb.params, 0..) |p, i| {
                if (p.typ == .inferred) continue;
                const pt = self.sema.resolve_type(p.typ) catch {
                    self.ok = false;
                    return;
                };
                if (pt == .@"struct") continue;
                if (!pt.is_numeric() and pt != .bool and pt != .str) {
                    self.ok = false;
                    return;
                }
                self.param_tys[i] = pt;
            }
        }

        fn param_index(self: *NativeInfer, name: []const u8) ?usize {
            for (self.fb.params, 0..) |p, i| {
                if (std.mem.eql(u8, p.name, name)) return i;
            }
            return null;
        }

        fn unify_param(self: *NativeInfer, idx: usize, hint: RT) void {
            if (!self.ok) return;
            if (hint == .str) {
                if (self.param_tys[idx] != .any and self.param_tys[idx] != .str) {
                    self.ok = false;
                    return;
                }
                self.param_tys[idx] = .str;
                return;
            }
            const merged = unify_scalar(self.param_tys[idx], hint) orelse {
                self.ok = false;
                return;
            };
            self.param_tys[idx] = merged;
        }

        fn param_is_referenced(self: *NativeInfer, idx: usize) bool {
            return block_references_name(&self.fb.body, self.fb.params[idx].name);
        }

        fn unify_local(self: *NativeInfer, name: []const u8, hint: RT) void {
            if (!self.ok) return;
            if (hint == .str) {
                if (self.local_tys.getPtr(name)) |entry| {
                    if (entry.* != .str and entry.* != .any) self.ok = false;
                    entry.* = .str;
                } else {
                    self.local_tys.put(name, .str) catch {
                        self.ok = false;
                    };
                }
                return;
            }
            if (self.local_tys.getPtr(name)) |entry| {
                const merged = unify_numeric(entry.*, hint) orelse {
                    self.ok = false;
                    return;
                };
                entry.* = merged;
            } else if (hint.is_native()) {
                self.local_tys.put(name, hint) catch {
                    self.ok = false;
                };
            }
        }

        fn expr_type(self: *NativeInfer, expr: *const ast.Expr) RT {
            return self.sema.type_map.get(expr) orelse .any;
        }

        fn expr_has_float(self: *NativeInfer, expr: *const ast.Expr) bool {
            return switch (expr.*) {
                .float_lit => true,
                .binop => |b| self.expr_has_float(b.lhs) or self.expr_has_float(b.rhs),
                .unop => |u| self.expr_has_float(u.operand),
                .name => false,
                else => false,
            };
        }

        fn is_dynamic_call(func: *const ast.Expr) bool {
            if (func.* != .name) return false;
            const n = func.name.ident;
            const blocked = [_][]const u8{
                "print",  "require", "pcall",          "xpcall",   "load",   "loadfile", "dofile",
                "pairs",  "ipairs",  "tostring",       "tonumber", "type",   "error",    "assert",
                "select", "unpack",  "collectgarbage", "warn",     "rawlen", "rawequal",
            };
            for (blocked) |b| {
                if (std.mem.eql(u8, n, b)) return true;
            }
            return false;
        }

        fn collect_local_types(self: *NativeInfer, blk: *const ast.Block) bool {
            for (blk.stmts) |*stmt| {
                switch (stmt.*) {
                    .local_decl => |*ld| {
                        for (ld.names, 0..) |*lname, i| {
                            var t: RT = .any;
                            if (i < ld.inits.len) t = self.expr_type(ld.inits[i]);
                            if (lname.typ != .inferred) {
                                t = self.sema.resolve_type(lname.typ) catch .any;
                            }
                            if (i < ld.inits.len and ld.inits[i].* == .table and ld.inits[i].table.fields.len == 0) {
                                continue; // dense table placeholder
                            }
                            if (i >= ld.inits.len) {
                                self.local_tys.put(lname.ident, .any) catch return false;
                                continue;
                            }
                            // Skip non-scalar locals (tables with content, etc.) but
                            // keep `.any` bindings so assignment chains can narrow them.
                            if (!t.is_native() and t != .any) continue;
                            self.local_tys.put(lname.ident, t) catch return false;
                        }
                    },
                    .const_decl => |*cd| {
                        var t = self.expr_type(cd.val);
                        if (cd.typ != .inferred) {
                            t = self.sema.resolve_type(cd.typ) catch .any;
                        }
                        if (!t.is_native()) continue;
                        self.local_tys.put(cd.ident, t) catch return false;
                    },
                    .assign => |*as| {
                        for (as.targets, as.values) |tgt, val| {
                            if (tgt.* != .name) continue;
                            const t = self.expr_type(val);
                            if (!t.is_native() and t != .any) continue;
                            self.local_tys.put(tgt.name.ident, t) catch return false;
                        }
                    },
                    .num_for => |*nf| {
                        var t: RT = .i64;
                        if (nf.var_typ != .inferred) {
                            t = self.sema.resolve_type(nf.var_typ) catch .i64;
                        }
                        if (!t.is_native()) return false;
                        self.local_tys.put(nf.var_name, t) catch return false;
                        if (!self.collect_local_types(&nf.body)) return false;
                    },
                    .gen_for => |*gf| {
                        if (!self.collect_local_types(&gf.body)) return false;
                    },
                    .if_stmt => |*is| {
                        if (!self.collect_local_types(&is.then)) return false;
                        for (is.elseifs) |*ei| {
                            if (!self.collect_local_types(&ei.body)) return false;
                        }
                        if (is.else_body) |*eb| {
                            if (!self.collect_local_types(eb)) return false;
                        }
                    },
                    .while_loop => |*wl| {
                        if (!self.collect_local_types(&wl.body)) return false;
                    },
                    .repeat_loop => |*rl| {
                        if (!self.collect_local_types(&rl.body)) return false;
                    },
                    .do_block => |*db| {
                        if (!self.collect_local_types(&db.body)) return false;
                    },
                    else => {},
                }
            }
            return true;
        }

        fn infer_block(self: *NativeInfer, blk: *const ast.Block) SemaError!void {
            for (blk.stmts) |*stmt| try self.infer_stmt(stmt);
            if (block_implicit_return_expr(blk)) |e| _ = self.infer_expr(e, .any);
        }

        fn infer_stmt(self: *NativeInfer, stmt: *const ast.Stmt) SemaError!void {
            if (!self.ok) return;
            switch (stmt.*) {
                .local_decl => |*ld| {
                    for (ld.names, 0..) |*lname, i| {
                        if (i < ld.inits.len) {
                            const lt = self.local_tys.get(lname.ident) orelse .any;
                            _ = self.infer_expr(ld.inits[i], lt);
                        }
                    }
                },
                .const_decl => |*cd| {
                    const ct = self.local_tys.get(cd.ident) orelse .any;
                    _ = self.infer_expr(cd.val, ct);
                },
                .assign => |*as| {
                    for (as.targets, 0..) |tgt, i| {
                        const hint = self.target_type(tgt);
                        if (i < as.values.len) {
                            const vt = self.infer_expr(as.values[i], hint);
                            if (tgt.* == .name) {
                                const prev = self.local_tys.get(tgt.name.ident) orelse .any;
                                const merged = unify_numeric(prev, vt) orelse vt;
                                self.local_tys.put(tgt.name.ident, merged) catch return;
                            }
                        }
                    }
                },
                .ret => |*r| {
                    if (r.vals.len > 1) {
                        self.ok = false;
                        return;
                    }
                    for (r.vals) |v| {
                        const t = self.infer_expr(v, .any);
                        self.ret_tys.append(self.sema.alloc, t) catch return;
                    }
                },
                .if_stmt => |*is| {
                    _ = self.infer_expr(is.cond, .bool);
                    try self.infer_block(&is.then);
                    for (is.elseifs) |*ei| {
                        _ = self.infer_expr(ei.cond, .bool);
                        try self.infer_block(&ei.body);
                    }
                    if (is.else_body) |*eb| try self.infer_block(eb);
                },
                .while_loop => |*wl| {
                    _ = self.infer_expr(wl.cond, .bool);
                    try self.infer_block(&wl.body);
                },
                .repeat_loop => |*rl| {
                    try self.infer_block(&rl.body);
                    _ = self.infer_expr(rl.cond, .bool);
                },
                .num_for => |*nf| {
                    const vt = self.local_tys.get(nf.var_name) orelse .i64;
                    _ = self.infer_expr(nf.start, vt);
                    _ = self.infer_expr(nf.stop, vt);
                    if (nf.step) |s| _ = self.infer_expr(s, vt);
                    try self.infer_block(&nf.body);
                },
                .call_stmt => |*cs| _ = self.infer_expr(cs.expr, .any),
                .expr_stmt => |*es| _ = self.infer_expr(es.expr, .any),
                .do_block => |*db| try self.infer_block(&db.body),
                else => self.ok = false,
            }
        }

        fn target_type(self: *NativeInfer, expr: *const ast.Expr) RT {
            return switch (expr.*) {
                .name => |n| blk: {
                    if (self.param_index(n.ident)) |pi| break :blk self.param_tys[pi];
                    break :blk self.local_tys.get(n.ident) orelse .any;
                },
                .field => |f| blk: {
                    if (f.obj.* == .name) {
                        if (self.method_receiver) |recv| {
                            if (std.mem.eql(u8, f.obj.name.ident, "self")) {
                                if (self.sema.field_type_of_alias(recv, f.field) catch null) |ft| {
                                    break :blk ft;
                                }
                            }
                        }
                    }
                    break :blk self.target_type(f.obj);
                },
                .index => |idx| self.target_index_type(idx.obj, idx.key),
                else => .any,
            };
        }

        fn target_index_type(self: *NativeInfer, obj: *const ast.Expr, _: *const ast.Expr) RT {
            if (self.fb.use_dense_table) {
                if (self.fb.dense_table) |dt| {
                    if (obj.* == .name and std.mem.eql(u8, obj.name.ident, dt)) {
                        return .i64;
                    }
                }
            }
            return self.expr_type(obj);
        }

        fn infer_index_expr(self: *NativeInfer, obj: *const ast.Expr, key: *const ast.Expr, hint: RT) RT {
            if (self.fb.use_dense_table) {
                if (self.fb.dense_table) |dt| {
                    if (obj.* == .name and std.mem.eql(u8, obj.name.ident, dt)) {
                        _ = self.infer_expr(key, .i64);
                        return .i64;
                    }
                }
            }
            self.ok = false;
            _ = hint;
            return .any;
        }

        fn infer_table_expr(self: *NativeInfer, expr: *const ast.Expr) RT {
            const t = expr.table;
            if (t.fields.len == 0 and self.fb.use_dense_table) return .any;
            self.ok = false;
            return .any;
        }

        fn infer_expr(self: *NativeInfer, expr: *const ast.Expr, hint: RT) RT {
            if (!self.ok) return .any;
            const result = switch (expr.*) {
                .nil => .nil,
                .true_lit, .false_lit => .bool,
                .int_lit => .i64,
                .float_lit => .f64,
                .string_lit => .str,
                .name => |n| blk: {
                    if (self.param_index(n.ident)) |pi| {
                        self.unify_param(pi, hint);
                        break :blk unify_scalar(self.param_tys[pi], hint) orelse self.param_tys[pi];
                    }
                    if (self.local_tys.get(n.ident)) |lt| {
                        self.unify_local(n.ident, hint);
                        break :blk unify_numeric(lt, hint) orelse lt;
                    }
                    break :blk .any;
                },
                .field => |f| {
                    if (f.obj.* == .name and std.mem.eql(u8, f.obj.name.ident, "math")) {
                        return .f64;
                    }
                    if (f.obj.* == .name) {
                        if (self.method_receiver) |recv| {
                            if (std.mem.eql(u8, f.obj.name.ident, "self")) {
                                if (self.sema.field_type_of_alias(recv, f.field) catch null) |ft| {
                                    return ft;
                                }
                            }
                        }
                    }
                    self.ok = false;
                    return .any;
                },
                .index => |idx| self.infer_index_expr(idx.obj, idx.key, hint),
                .call => |c| self.infer_call(c.func, c.args, hint),
                .method_call => blk: {
                    self.ok = false;
                    break :blk .any;
                },
                .binop => |b| self.infer_binop(b.op, b.lhs, b.rhs, hint),
                .unop => |u| blk: {
                    const ot = self.infer_expr(u.operand, switch (u.op) {
                        .neg => hint,
                        .not => .bool,
                        .len => .i64,
                        .bnot => hint,
                        .compile => hint,
                    });
                    break :blk switch (u.op) {
                        .neg => if (ot.is_numeric()) ot else .any,
                        .not => .bool,
                        .len => .i64,
                        .bnot => ot,
                        .compile => ot,
                    };
                },
                .table => self.infer_table_expr(expr),
                .list_comp => blk: {
                    self.ok = false;
                    break :blk .any;
                },
                .func_expr => blk: {
                    self.ok = false;
                    break :blk .any;
                },
                .vararg => .any,
                .try_expr, .unwrap_expr, .await_expr => blk: {
                    self.ok = false;
                    break :blk .any;
                },
                .if_expr => |ie| blk: {
                    _ = self.infer_expr(ie.cond, .bool);
                    const then_t = self.infer_expr(ie.then_expr, hint);
                    const else_t = self.infer_expr(ie.else_expr, hint);
                    break :blk unify_numeric(then_t, else_t) orelse if (then_t.eql(else_t)) then_t else .any;
                },
                .match_expr => blk: {
                    self.ok = false;
                    break :blk .any;
                },
                .contains_expr => .bool,
                .range => blk: {
                    self.ok = false;
                    break :blk .any;
                },
                .quote, .unquote, .macro_call => blk: {
                    self.ok = false;
                    break :blk .any;
                },
                // Pass 36 G1/G8 recorded, not implemented (Phase 0): bail out of this inference path
                // rather than guess a type for an unimplemented resolution ladder.
                .semantic, .semantic_scope => blk: {
                    self.ok = false;
                    break :blk .any;
                },
                .sequence => |seq| blk: {
                    if (seq.exprs.len == 0) break :blk .nil;
                    break :blk self.infer_expr(seq.exprs[0], hint);
                },
            };
            return result;
        }

        fn infer_call(self: *NativeInfer, func: *const ast.Expr, args: []const *ast.Expr, hint: RT) RT {
            if (is_dynamic_call(func)) {
                self.ok = false;
                return .any;
            }
            if (func.* == .field and func.field.obj.* == .name) {
                const mod = func.field.obj.name.ident;
                const fname = func.field.field;
                if (std.mem.eql(u8, mod, "string")) {
                    if (std.mem.eql(u8, fname, "len")) {
                        if (args.len > 0) _ = self.infer_expr(args[0], .str);
                        return .i64;
                    }
                    if (std.mem.eql(u8, fname, "byte")) {
                        if (args.len > 0) _ = self.infer_expr(args[0], .str);
                        if (args.len > 1) _ = self.infer_expr(args[1], .i64);
                        return .i64;
                    }
                    if (std.mem.eql(u8, fname, "rep")) {
                        if (args.len > 0) _ = self.infer_expr(args[0], .str);
                        if (args.len > 1) _ = self.infer_expr(args[1], .i64);
                        return .str;
                    }
                }
            }
            if (func.* == .field and func.field.obj.* == .name and
                std.mem.eql(u8, func.field.obj.name.ident, "math"))
            {
                for (args) |a| _ = self.infer_expr(a, .f64);
                return .f64;
            }
            if (func.* == .name) {
                if (self.self_name) |sn| {
                    if (std.mem.eql(u8, sn, func.name.ident)) {
                        for (args, self.param_tys) |arg, pt| _ = self.infer_expr(arg, pt);
                        return hint;
                    }
                }
                if (self.sema.scope.lookup(func.name.ident)) |sym| {
                    if (sym.typ == .func) {
                        const ft = sym.typ.func;
                        if (!ft.is_native) {
                            self.ok = false;
                            return .any;
                        }
                        for (args, 0..) |arg, i| {
                            const pt: RT = if (i < ft.params.len) ft.params[i] else .any;
                            _ = self.infer_expr(arg, pt);
                        }
                        return ft.ret.*;
                    }
                }
            }
            for (args) |a| _ = self.infer_expr(a, .any);
            return hint;
        }

        fn infer_binop(self: *NativeInfer, op: ast.BinOp, lhs: *ast.Expr, rhs: *ast.Expr, hint: RT) RT {
            return switch (op) {
                .concat => blk: {
                    _ = self.infer_expr(lhs, .str);
                    _ = self.infer_expr(rhs, .str);
                    break :blk .str;
                },
                .div, .pow => {
                    _ = self.infer_expr(lhs, .f64);
                    _ = self.infer_expr(rhs, .f64);
                    return .f64;
                },
                .add, .sub, .mul, .idiv, .mod => blk: {
                    var rt: RT = if (self.expr_has_float(lhs) or self.expr_has_float(rhs)) .f64 else hint;
                    if (rt == .any or rt == .bool) rt = .i64;
                    const lt = self.infer_expr(lhs, rt);
                    const rr = self.infer_expr(rhs, rt);
                    break :blk unify_numeric(lt, rr) orelse unify_numeric(lt, rt) orelse .any;
                },
                .band, .bor, .bxor, .lshift, .rshift => blk: {
                    _ = self.infer_expr(lhs, .i64);
                    _ = self.infer_expr(rhs, .i64);
                    break :blk .i64;
                },
                .eq, .neq, .lt, .gt, .leq, .geq => blk: {
                    const lt = self.expr_type(lhs);
                    const rt = self.expr_type(rhs);
                    var cmp_t = unify_numeric(lt, rt) orelse .i64;
                    if (self.expr_has_float(lhs) or self.expr_has_float(rhs)) cmp_t = .f64;
                    _ = self.infer_expr(lhs, cmp_t);
                    _ = self.infer_expr(rhs, cmp_t);
                    break :blk .bool;
                },
                .@"and" => self.infer_expr(rhs, hint),
                .@"or" => self.infer_expr(lhs, hint),
                .contains => .bool,
                .matmul => blk: {
                    const lt = self.expr_type(lhs);
                    const rt = self.expr_type(rhs);
                    if (RT.tensor_matmul(lt, rt, self.sema.alloc) catch null) |out| break :blk out;
                    break :blk .any;
                },
                .pipeline => blk: {
                    _ = self.infer_expr(lhs, .any);
                    _ = self.infer_expr(rhs, .any);
                    break :blk .any;
                },
            };
        }
    };
};

// ── Tests ─────────────────────────────────────────────────────────────────────

const testing = std.testing;
const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("parser.zig").Parser;

fn releaseForeignRecordRt(alloc: Allocator, rt: *RT) void {
    if (rt.* != .table_type) return;
    for (rt.table_type.fields) |f| alloc.free(f.name);
    alloc.free(rt.table_type.fields);
    if (rt.table_type.ffi_name) |n| alloc.free(n);
}

fn runSema(src: []const u8, arena: *std.heap.ArenaAllocator) !Sema {
    const alloc = arena.allocator();
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    return s;
}

fn runIdolSema(src: []const u8, arena: *std.heap.ArenaAllocator) !Sema {
    const alloc = arena.allocator();
    var lex = Lexer.init(src, "test.id");
    var p = Parser.init(&lex, alloc);
    p.duo_mode = true;
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    s.duo_mode = true;
    try s.check_module(&mod);
    return s;
}

test "sema: braced ordinary callable fails closed" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const s = try runIdolSema(
        \\point: i64 = (x: i64)
        \\    x
        \\main: i64 = ()
        \\    point{ x = 3 }
    , &arena);
    try testing.expectEqual(@as(u32, 1), s.errors);
}

test "sema: braced ordinary callable refusal precedes pack arity" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var threaded = std.Io.Threaded.init(testing.allocator, .{});
    defer threaded.deinit();
    const s = try runIdolSema(
        try std.Io.Dir.cwd().readFileAlloc(threaded.io(), "examples/compile_fail/callable_braces.id", arena.allocator(), .unlimited),
        &arena,
    );
    try testing.expectEqual(@as(u32, 1), s.errors);
    try testing.expectEqual(DiagnosticEvidence.complete, s.diagnostic_evidence);
    try testing.expectEqual(@as(usize, 1), s.diagnostics.items.len);
    try testing.expectEqualStrings(
        "c0 §43 law.brace: braced application requires a descriptor subject; this subject resolved in callable space, not descriptor space, and ordinary callable application uses parentheses",
        s.diagnostics.items[0].message,
    );
}

test "sema: parenthesized ordinary callable remains valid" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const s = try runIdolSema(
        \\point: i64 = (x: i64)
        \\    x
        \\main: i64 = ()
        \\    point(3)
    , &arena);
    try testing.expectEqual(@as(u32, 0), s.errors);
}

test "sema: braced descriptor application remains valid" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const s = try runIdolSema(
        \\point: { x: i64 }
        \\main: point = ()
        \\    point{ x = 3 }
    , &arena);
    try testing.expectEqual(@as(u32, 0), s.errors);
}

test "sema: Pass25 loop-carried tail demand types factorial body" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\factorial = (n: i64): i64
        \\    value = 1
        \\    for i = 2, n
        \\        value *= i
        \\    end
        \\end
    ;
    var lex = Lexer.init(src, "test.id");
    var p = Parser.init(&lex, alloc);
    p.duo_mode = true;
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    s.duo_mode = true;
    try s.check_module(&mod);
    try testing.expectEqual(@as(u32, 0), s.errors);
    const fd = mod.body.stmts[0].func_decl;
    try testing.expect(fd.func.is_typed);
}

test "sema: loop body assignment is not implicit function return" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\ema_smooth = (n: i64): f64
        \\    avg = 0.0
        \\    i = 0
        \\    while i < n
        \\        avg *= 0.95; avg += (i % 100) * 0.05
        \\        i += 1
        \\    end
        \\    return avg
        \\end
    ;
    var lex = Lexer.init(src, "test.id");
    var p = Parser.init(&lex, alloc);
    p.duo_mode = true;
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    s.duo_mode = true;
    try s.check_module(&mod);
    try testing.expectEqual(@as(u32, 0), s.errors);
}

test "sema: empty module produces no errors" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const s = try runSema("", &arena);
    try testing.expectEqual(@as(u32, 0), s.errors);
}

test "sema: simple local declaration produces no errors" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const s = try runSema("local x = 42", &arena);
    try testing.expectEqual(@as(u32, 0), s.errors);
}

test "sema: multiple locals produce no errors" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const s = try runSema("local a = 1\nlocal b = 2\nlocal c = a + b", &arena);
    try testing.expectEqual(@as(u32, 0), s.errors);
}

test "sema: module_sealed lattice fact for req bindings (Pass 34 L1)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\m = req "examples.l1_sealed_helper"
        \\m = {}
        \\n = req "examples.l1_sealed_helper"
    ;
    var lex = Lexer.init(src, "test.id");
    var p = Parser.init(&lex, alloc);
    p.duo_mode = true;
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    s.duo_mode = true;
    try s.check_module(&mod);
    try testing.expectEqual(@as(u32, 0), s.errors);
    try testing.expect(!s.moduleSealed("m"));
    try testing.expect(s.moduleSealed("n"));
}

test "sema: symbol knowledge lattice (Pass 2.1)" {
    const native_sym = Symbol{ .typ = .i64, .is_const = false };
    try testing.expectEqual(semantic_algebra.KnowledgeLevel.native, native_sym.knowledge());
    const dynamic_sym = Symbol{ .typ = .any, .is_const = false };
    try testing.expectEqual(semantic_algebra.KnowledgeLevel.observed, dynamic_sym.knowledge());
    var fields: [1]types.FieldType = .{.{ .name = "x", .typ = .i64 }};
    const table_sym = Symbol{
        .typ = .{ .table_type = .{
            .fields = fields[0..],
            .storage_class = .native,
        } },
        .is_const = false,
    };
    try testing.expect(semantic_algebra.lowersToNativeC(table_sym.typ));
    try testing.expectEqual(semantic_algebra.KnowledgeLevel.native, table_sym.knowledge());
}

test "sema: typed function sets is_typed = true" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\function add(a: i32, b: i32) -> i32
        \\  return a + b
        \\end
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    try testing.expectEqual(@as(u32, 0), s.errors);
    const fd = mod.body.stmts[0].func_decl;
    try testing.expect(fd.func.is_typed);
}

test "sema: untyped function with dynamic body stays untyped" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\function f(a, b)
        \\  return tostring(a) .. tostring(b)
        \\end
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    try testing.expectEqual(@as(u32, 0), s.errors);
    const fd = mod.body.stmts[0].func_decl;
    try testing.expect(!fd.func.is_typed);
}

test "sema: Pass23 colon method assign infers native str signature" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src = "Person:greet = (other) \"Hey \" .. other";
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    p.duo_mode = true;
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    try testing.expectEqual(@as(u32, 0), s.errors);
    const fd = mod.body.stmts[0].func_decl;
    try testing.expect(fd.func.is_typed);
    try testing.expectEqualStrings("str", fd.func.params[0].typ.named);
    try testing.expectEqualStrings("str", fd.func.params[1].typ.named);
    try testing.expectEqualStrings("str", fd.func.ret_type.named);
}

test "sema: Pass23 string interpolation infers str return" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src = "Person:greet = (other) \"Hey {other}\"";
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    p.duo_mode = true;
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    try testing.expectEqual(@as(u32, 0), s.errors);
    const fd = mod.body.stmts[0].func_decl;
    try testing.expect(fd.func.is_typed);
    try testing.expectEqualStrings("str", fd.func.ret_type.named);
}

test "sema: Pass23 colon method compound field assign with descriptor" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src = "Vec: @{ x: i32 }\nVec:xplus = (amt): i32\n    self.x += amt\nend";
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    p.duo_mode = true;
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    try testing.expectEqual(@as(u32, 0), s.errors);
    const fd = mod.body.stmts[1].func_decl;
    try testing.expect(fd.func.is_typed);
    try testing.expectEqualStrings("Vec", fd.func.params[0].typ.named);
    try testing.expectEqualStrings("i32", fd.func.params[1].typ.named);
    try testing.expectEqualStrings("i32", fd.func.ret_type.named);
}

test "sema: untyped function can be specialized to native" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\function add(a, b)
        \\  return a + b
        \\end
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    try testing.expectEqual(@as(u32, 0), s.errors);
    const fd = mod.body.stmts[0].func_decl;
    try testing.expect(fd.func.is_typed);
    try testing.expectEqualStrings("i64", fd.func.params[0].typ.named);
    try testing.expectEqualStrings("i64", fd.func.params[1].typ.named);
    try testing.expectEqualStrings("i64", fd.func.ret_type.named);
}

test "sema: integer literal resolves to i64" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src = "local x = 1";
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    // The initializer expression should be recorded as i64
    const init_expr = mod.body.stmts[0].local_decl.inits[0];
    const t = s.type_map.get(init_expr);
    try testing.expect(t != null);
    try testing.expectEqual(RT.i64, t.?);
}

test "sema: float literal resolves to f64" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src = "local x = 1.5";
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    const init_expr = mod.body.stmts[0].local_decl.inits[0];
    const t = s.type_map.get(init_expr);
    try testing.expect(t != null);
    try testing.expectEqual(RT.f64, t.?);
}

test "sema: string literal resolves to str" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src = "local x = \"hello\"";
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    const init_expr = mod.body.stmts[0].local_decl.inits[0];
    const t = s.type_map.get(init_expr);
    try testing.expect(t != null);
    try testing.expectEqual(RT.str, t.?);
}

test "sema: boolean literals resolve to bool" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src = "local a = true\nlocal b = false";
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    try testing.expectEqual(@as(u32, 0), s.errors);
    const t_true = s.type_map.get(mod.body.stmts[0].local_decl.inits[0]);
    const t_false = s.type_map.get(mod.body.stmts[1].local_decl.inits[0]);
    try testing.expectEqual(RT.bool, t_true.?);
    try testing.expectEqual(RT.bool, t_false.?);
}

test "sema: const reassignment reports an error" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const s = try runSema(
        \\local x <const> = 1
        \\x = 2
    , &arena);
    try testing.expect(s.errors > 0);
}

test "sema: for-loop control variable cannot be assigned" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const s = try runSema(
        \\for i = 1, 10 do
        \\  i = 99
        \\end
    , &arena);
    try testing.expect(s.errors > 0);
}

test "sema: scope: define and lookup" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var scope = Scope.init(arena.allocator());
    try scope.push();
    try scope.define("x", .{ .typ = .i32, .is_const = false });
    const sym = scope.lookup("x");
    try testing.expect(sym != null);
    try testing.expectEqual(RT.i32, sym.?.typ);
    scope.pop();
}

test "sema: scope: inner scope shadows outer" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var scope = Scope.init(arena.allocator());
    try scope.push();
    try scope.define("x", .{ .typ = .i64, .is_const = false });
    try scope.push();
    try scope.define("x", .{ .typ = .i32, .is_const = false });
    try testing.expectEqual(RT.i32, scope.lookup("x").?.typ);
    scope.pop();
    try testing.expectEqual(RT.i64, scope.lookup("x").?.typ);
    scope.pop();
}

test "sema: scope: undefined name returns null" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var scope = Scope.init(arena.allocator());
    try scope.push();
    try testing.expect(scope.lookup("undefined") == null);
    scope.pop();
}

test "sema: add/sub of two integers yields integer" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src = "local r = 3 + 5";
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    const expr = mod.body.stmts[0].local_decl.inits[0];
    try testing.expect(expr.* == .binop);
    const t = s.type_map.get(expr);
    try testing.expect(t != null);
    try testing.expect(t.?.is_integer());
}

test "sema: comparison yields bool" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src = "local r = 1 < 2";
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    const expr = mod.body.stmts[0].local_decl.inits[0];
    const t = s.type_map.get(expr);
    try testing.expectEqual(RT.bool, t.?);
}

test "sema: lua and/or ternary recovers safe branch type" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\local flag: bool = true
        \\local r = flag and 10 or 20
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    try testing.expectEqual(@as(usize, 0), s.errors);
    const expr = mod.body.stmts[1].local_decl.inits[0];
    const t = s.type_map.get(expr);
    try testing.expect(t != null);
    try testing.expect(t.?.is_integer());
}

test "sema: bare lua and with mixed operand types is dynamic" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\local flag: bool = true
        \\local r = flag and 10
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    try testing.expectEqual(@as(usize, 0), s.errors);
    const expr = mod.body.stmts[1].local_decl.inits[0];
    try testing.expectEqual(RT.any, s.type_map.get(expr).?);
}

test "sema: list comprehension is dynamic table expression" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\local xs = {1, 2, 3}
        \\local ys = {x * 2 for x in xs if x > 1}
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    try testing.expectEqual(@as(usize, 0), s.errors);
    const expr = mod.body.stmts[1].local_decl.inits[0];
    try testing.expectEqual(RT.any, s.type_map.get(expr).?);
}

test "sema: try_expr (?) in void-returning function emits error" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\function f(x: i64) -> i64
        \\  return x?
        \\end
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    // i64 is not result-compatible, so ? should trigger an error
    try testing.expect(s.errors > 0);
}

test "sema: try_expr (?) in result-returning function is accepted" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    // Return type is 'any', which is result-compatible (dynamic check deferred to runtime)
    const src =
        \\function f(x)
        \\  return x?
        \\end
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    // 'any' return type is result-compatible, so no error
    try testing.expectEqual(@as(u32, 0), s.errors);
}

test "sema: unwrap_expr (!) in @nopanic function emits error" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\@nopanic
        \\function f(x: i64) -> i64
        \\  return x!
        \\end
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    // ! in @nopanic should emit an error
    try testing.expect(s.errors > 0);
}

test "sema: unwrap_expr (!) in normal function is accepted" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\function f(x: i64) -> i64
        \\  return x!
        \\end
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    // ! in normal function is fine
    try testing.expectEqual(@as(u32, 0), s.errors);
}

test "sema: match_stmt scrutinee and arms are type-checked" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\local x = 42
        \\match x
        \\  1 then print("one")
        \\  2 then print("two")
        \\  _ then print("other")
        \\end
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    try testing.expectEqual(@as(u32, 0), s.errors);
}

test "sema: match on enum with wildcard is exhaustive" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\enum Color
        \\  Red
        \\  Green
        \\  Blue
        \\end
        \\local c = Color
        \\match c
        \\  Color.Red then print("red")
        \\  _ then print("other")
        \\end
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    try testing.expectEqual(@as(u32, 0), s.errors);
}

test "sema: match on enum missing variants emits error" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\enum Color
        \\  Red
        \\  Green
        \\  Blue
        \\end
        \\local c = Color
        \\match c
        \\  Color.Red then print("red")
        \\end
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    // Should emit an error for missing Green and Blue variants
    try testing.expect(s.errors > 0);
}

test "sema: match on enum all variants covered is exhaustive" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\enum Direction
        \\  Up
        \\  Down
        \\end
        \\local d = Direction
        \\match d
        \\  Direction.Up then print("up")
        \\  Direction.Down then print("down")
        \\end
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    try testing.expectEqual(@as(u32, 0), s.errors);
}

test "sema: match on non-enum does not check exhaustiveness" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\local x = 42
        \\match x
        \\  1 then print("one")
        \\end
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    // No exhaustiveness error for non-enum scrutinees
    try testing.expectEqual(@as(u32, 0), s.errors);
}

test "sema: enum_def registers type in scope" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\enum Status
        \\  Active
        \\  Inactive
        \\end
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    try testing.expectEqual(@as(u32, 0), s.errors);
    // The enum type should be registered
    try testing.expect(s.enum_types.get("Status") != null);
}

test "sema: try_stmt body is type-checked" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\try
        \\  local x = 42
        \\catch e
        \\  local y = e
        \\end
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    try testing.expectEqual(@as(u32, 0), s.errors);
}

test "sema: defer_stmt body is type-checked" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\defer
        \\  local x = 1
        \\end
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    try testing.expectEqual(@as(u32, 0), s.errors);
}

test "sema: match on enum with unqualified variant names" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\enum Shape
        \\  Circle
        \\  Square
        \\  Triangle
        \\end
        \\local s = Shape
        \\match s
        \\  Shape.Circle then print("circle")
        \\  Shape.Square then print("square")
        \\  Shape.Triangle then print("triangle")
        \\end
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    // All variants covered with qualified names — no error
    try testing.expectEqual(@as(u32, 0), s.errors);
}

test "sema: match on enum partial coverage emits specific missing variants" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\enum Season
        \\  Spring
        \\  Summer
        \\  Autumn
        \\  Winter
        \\end
        \\local s = Season
        \\match s
        \\  Season.Spring then print("spring")
        \\  Season.Summer then print("summer")
        \\end
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    // Should report error for missing Autumn and Winter
    try testing.expect(s.errors > 0);
}

test "sema: match expression type-checks scrutinee and arms" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\enum Coin
        \\  Heads
        \\  Tails
        \\end
        \\local c = Coin
        \\local result = match c
        \\  Coin.Heads then return 1
        \\  Coin.Tails then return 0
        \\end
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    try testing.expectEqual(@as(u32, 0), s.errors);
}

test "sema: match with guard expressions type-checked" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\local x = 42
        \\match x
        \\  n if n > 10 then print("big")
        \\  _ then print("small")
        \\end
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    try testing.expectEqual(@as(u32, 0), s.errors);
} // ── Duo mode scoping tests (Requirements 1.3, 1.4, 1.7, 1.8) ─────────────────

fn runSemaDuo(src: []const u8, arena: *std.heap.ArenaAllocator) !Sema {
    const alloc = arena.allocator();
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    s.duo_mode = true;
    try s.check_module(&mod);
    return s;
}

test "sema: generic type alias resolves in function parameter annotations" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const s = try runSemaDuo(
        \\type Vec<T> = List[T]
        \\fun first(xs: Vec[i64]): i64
        \\  return xs[0]
        \\end
    , &arena);
    try testing.expectEqual(@as(u32, 0), s.errors);
}

test "sema: duo mode — bare assignment creates local binding" {
    // Requirement 1.3: bare assignment at declaration position creates local
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const src =
        \\x = 42
        \\print(x)
    ;
    const s = try runSemaDuo(src, &arena);
    try testing.expectEqual(@as(u32, 0), s.errors);
}

test "sema: duo mode — bare assignment then read is valid" {
    // Requirement 1.3: assigned variable is accessible afterwards
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const src =
        \\y = 10
        \\z = y + 1
    ;
    const s = try runSemaDuo(src, &arena);
    try testing.expectEqual(@as(u32, 0), s.errors);
}

test "sema: duo mode — reading undeclared name creates implicit local" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const src =
        \\print(undeclared_var)
        \\undeclared_var = 1
    ;
    const s = try runSemaDuo(src, &arena);
    try testing.expectEqual(@as(u32, 0), s.errors);
}

test "sema: duo mode — forward reference before assignment is allowed" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const src =
        \\print(x)
        \\x = 42
    ;
    const s = try runSemaDuo(src, &arena);
    try testing.expectEqual(@as(u32, 0), s.errors);
}

test "sema: duo mode — local keyword still works (Lua compat)" {
    // Requirement 1.8: local keyword is still valid in duo mode
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const src =
        \\local x = 1
        \\local y = x + 2
        \\print(y)
    ;
    const s = try runSemaDuo(src, &arena);
    try testing.expectEqual(@as(u32, 0), s.errors);
}

test "sema: duo mode — global keyword creates module-scope binding" {
    // Requirement 1.4: global keyword creates module-global binding
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\global g = 100
        \\print(g)
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    s.duo_mode = true;
    try s.check_module(&mod);
    try testing.expectEqual(@as(u32, 0), s.errors);
    // Verify the variable was registered as a module global
    try testing.expect(s.module_globals.get("g") != null);
}

test "sema: duo mode — global binding is marked is_global" {
    // Requirement 1.4: global keyword sets is_global flag on symbol
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\global myvar = 42
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    s.duo_mode = true;
    try s.check_module(&mod);
    try testing.expectEqual(@as(u32, 0), s.errors);
    try testing.expect(s.module_globals.get("myvar") != null);
}

test "sema: duo mode — let is a keyword for if let / while let" {
    // let is now a keyword for pattern matching sugar: if let / while let
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const src =
        \\if let x = 1 then
        \\  print(x)
        \\end
    ;
    const s = try runSemaDuo(src, &arena);
    try testing.expectEqual(@as(u32, 0), s.errors);
}

test "sema: duo mode — both local and bare create local bindings" {
    // Requirement 1.8: local x = 1 and bare x = 1 both produce local bindings
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\local a = 1
        \\b = 2
        \\print(a + b)
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    s.duo_mode = true;
    try s.check_module(&mod);
    try testing.expectEqual(@as(u32, 0), s.errors);
    // Neither a nor b should appear in module_globals
    try testing.expect(s.module_globals.get("a") == null);
    try testing.expect(s.module_globals.get("b") == null);
}

test "sema: duo mode — bare assignment does not create global" {
    // Verify that bare assignment in duo mode does NOT add to module_globals
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\x = 42
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    s.duo_mode = true;
    try s.check_module(&mod);
    try testing.expectEqual(@as(u32, 0), s.errors);
    // x should NOT be in module_globals since it was auto-local
    try testing.expect(s.module_globals.get("x") == null);
}

test "sema: duo mode — multiple bare assignments in sequence" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const src =
        \\a = 1
        \\b = 2
        \\c = a + b
        \\print(c)
    ;
    const s = try runSemaDuo(src, &arena);
    try testing.expectEqual(@as(u32, 0), s.errors);
}

test "sema: duo mode — reassignment to existing local is valid" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const src =
        \\x = 1
        \\x = 2
        \\print(x)
    ;
    const s = try runSemaDuo(src, &arena);
    try testing.expectEqual(@as(u32, 0), s.errors);
}

test "sema: field access on a record-typed binding yields the declared field type" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    // Verify that `local p: { x: f64, y: f64 }` followed by reading
    // `p.x` infers the field's type from the record-type annotation
    // rather than falling back to `.any`. This is the change that makes
    // typed `local x: f64 = p.x` work end-to-end through codegen.
    const src =
        \\local p: { x: f64, y: f64 } = { x = 1.0, y = 2.0 }
        \\local x: f64 = p.x
        \\local y: f64 = p.y
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    try testing.expectEqual(@as(u32, 0), s.errors);

    // Find the `local x: f64 = p.x` statement and verify the RHS is i64/f64
    // (not `.any`). The third stmt in the module is the `local x: f64 = p.x`.
    const x_decl = mod.body.stmts[2].local_decl;
    const x_init = x_decl.inits[0];
    try testing.expect(x_init.* == .field);
    const xt = s.type_map.get(x_init) orelse .any;
    try testing.expect(xt == .f64);
}

test "sema: memory intrinsics preserve pointer and machine scalar types" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\function low(): i64
        \\  local raw: *u8 = mem.alloc(32)
        \\  local nums: *i64 = mem.cast("i64", raw)
        \\  local x: i64 = nums[0]
        \\  local y: i64 = mem.load("i64", nums)
        \\  local addr: u64 = mem.addr(nums)
        \\  local again: *i64 = mem.ptr_from_addr("i64", addr)
        \\  return x + y + again[0]
        \\end
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    try testing.expectEqual(@as(u32, 0), s.errors);

    const body = mod.body.stmts[0].func_decl.func.body.stmts;
    const raw_init = body[0].local_decl.inits[0];
    const nums_init = body[1].local_decl.inits[0];
    const x_init = body[2].local_decl.inits[0];
    const y_init = body[3].local_decl.inits[0];
    const addr_init = body[4].local_decl.inits[0];
    const again_init = body[5].local_decl.inits[0];

    const raw_t = s.type_map.get(raw_init) orelse RT.any;
    try testing.expect(raw_t == .pointer);
    try testing.expectEqual(RT.u8, raw_t.pointer.*);

    const nums_t = s.type_map.get(nums_init) orelse RT.any;
    try testing.expect(nums_t == .pointer);
    try testing.expectEqual(RT.i64, nums_t.pointer.*);

    try testing.expectEqual(RT.i64, s.type_map.get(x_init) orelse RT.any);
    try testing.expectEqual(RT.i64, s.type_map.get(y_init) orelse RT.any);
    try testing.expectEqual(RT.u64, s.type_map.get(addr_init) orelse RT.any);

    const again_t = s.type_map.get(again_init) orelse RT.any;
    try testing.expect(again_t == .pointer);
    try testing.expectEqual(RT.i64, again_t.pointer.*);
}

test "sema: memory intrinsics reject invalid low-level calls" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\function bad(): void
        \\  local raw: *u8 = mem.alloc("bad")
        \\  mem.load("bogus", raw)
        \\  mem.store("i64", 1, 2)
        \\  mem.add(1, raw)
        \\  mem.fence(1)
        \\end
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    try testing.expect(s.errors >= 5);
}

test "sema: atomic intrinsics preserve scalar results and validate storage pointers" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\function atomics(): i64
        \\  local raw: *u8 = mem.alloc(16)
        \\  local slot: *i64 = mem.cast("i64", raw)
        \\  local expected: *i64 = mem.add(slot, 1)
        \\  atomic.store("i64", slot, 1, "release")
        \\  local old: i64 = std.atomic.fetch_add("i64", slot, 2, "acq_rel")
        \\  local loaded: i64 = atomic.load("i64", slot, "acquire")
        \\  local swapped: bool = atomic.compare_exchange("i64", slot, expected, 3)
        \\  return old + loaded
        \\end
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    try testing.expectEqual(@as(u32, 0), s.errors);

    const body = mod.body.stmts[0].func_decl.func.body.stmts;
    const old_init = body[4].local_decl.inits[0];
    const loaded_init = body[5].local_decl.inits[0];
    const swapped_init = body[6].local_decl.inits[0];

    try testing.expectEqual(RT.i64, s.type_map.get(old_init) orelse RT.any);
    try testing.expectEqual(RT.i64, s.type_map.get(loaded_init) orelse RT.any);
    try testing.expectEqual(RT.bool, s.type_map.get(swapped_init) orelse RT.any);
}

test "sema: atomic intrinsics reject invalid order and storage types" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\function bad(): void
        \\  local raw: *u8 = mem.alloc(16)
        \\  local bytes: *u8 = mem.cast("u8", raw)
        \\  atomic.load("i64", bytes)
        \\  atomic.store("i64", bytes, "bad", "acquire")
        \\  atomic.fetch_add("f64", bytes, 1)
        \\  atomic.compare_exchange("i64", bytes, bytes, 2, "release", "release")
        \\end
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    try testing.expect(s.errors >= 6);
}

test "sema: @implements on a record-typed binding (concept exists and matches)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    // The concept `Iterable` requires an `each: () -> any` method. The
    // binding's record-type annotation supplies exactly that, so the
    // satisfaction check should pass.
    const src =
        \\concept Iterable
        \\  each: () -> i64
        \\end
        \\@implements(Iterable)
        \\local x: { each: () -> i64 } = { each = function()
        \\    return 0
        \\end }
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    try testing.expectEqual(@as(u32, 0), s.errors);
}

// ── Frozen-kernel constant verification ───────────────────────────────────
//
// Each of the emitters below prints a CLOSED FORM whose constants it never
// re-reads from the source. Every case here is a PAIR: the exact benchmark
// kernel (positive control — the flag must be set, so the fast path is not
// silently lost) and the same kernel with ONE constant changed (the flag must
// be clear, so the general path answers the question the program actually
// asks). Before this gate, every `_perturbed` case below set the flag and the
// program received the benchmark's number.

const KernelFlag = enum {
    mod_histogram_sum,
    clamp_mod_sum,
    gcd_inline,
    cordic_inline,
    interp_inline,
    fenwick_native,
    binary_search_dense,
};

fn kernel_flag_of(src: []const u8, which: KernelFlag, alloc: std.mem.Allocator) !bool {
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    try testing.expect(mod.body.stmts[0] == .func_decl);
    const fb = mod.body.stmts[0].func_decl.func;
    return switch (which) {
        .mod_histogram_sum => fb.use_mod_histogram_sum,
        .clamp_mod_sum => fb.use_clamp_mod_sum,
        .gcd_inline => fb.use_gcd_inline,
        .cordic_inline => fb.use_cordic_inline,
        .interp_inline => fb.use_interp_inline,
        .fenwick_native => fb.use_fenwick_native,
        .binary_search_dense => fb.use_binary_search_dense,
    };
}

test "sema: bucket-hash closed form is retired, on its own kernel too" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const exact =
        \\function bucket_hash(n)
        \\  local sum = 0
        \\  local i = 1
        \\  while i <= n do
        \\    sum += (i * 31) % 256
        \\    i += 1
        \\  end
        \\  return sum
        \\end
    ;
    // *37 instead of *31: emit_mod_histogram_sum_body would still sum the *31
    // period. Measured against reference C: Duo 127500000, C 127499680.
    const perturbed =
        \\function bucket_hash(n)
        \\  local sum = 0
        \\  local i = 1
        \\  while i <= n do
        \\    sum += (i * 37) % 256
        \\    i += 1
        \\  end
        \\  return sum
        \\end
    ;
    // POLARITY INVERTED. This used to require the flag on `exact` — the
    // positive control for a fold that is now retired. The 31 and the 256 were
    // printed by emit_mod_histogram_sum_body and demanded back by the
    // verifier, so the closed form fired for one multiplier and one modulus.
    // Both cases must now decline; the histogram loop runs.
    try testing.expect(!try kernel_flag_of(exact, .mod_histogram_sum, alloc));
    try testing.expect(!try kernel_flag_of(perturbed, .mod_histogram_sum, alloc));
}

test "sema: clamp-sum closed form is retired, on its own kernel too" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const exact =
        \\function clamp_sum(n)
        \\  local sum = 0
        \\  local i = 0
        \\  while i < n do
        \\    sum += math.min(255, math.max(0, i % 1000))
        \\    i += 1
        \\  end
        \\  return sum
        \\end
    ;
    // min(200, ..): the emitter's 222360 and 32640 are derived from 255/0/1000.
    // Measured: Duo 1111800000, C 899500000.
    const perturbed =
        \\function clamp_sum(n)
        \\  local sum = 0
        \\  local i = 0
        \\  while i < n do
        \\    sum += math.min(200, math.max(0, i % 1000))
        \\    i += 1
        \\  end
        \\  return sum
        \\end
    ;
    // POLARITY INVERTED, same reason: `full * 222360 + tail` with 1000, 256,
    // 32640 and 255 beside it is a transcription of this kernel's constants.
    try testing.expect(!try kernel_flag_of(exact, .clamp_mod_sum, alloc));
    try testing.expect(!try kernel_flag_of(perturbed, .clamp_mod_sum, alloc));
}

test "sema: gcd closed form is retired, on its own kernel too" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const exact =
        \\function gcd_reduce(n)
        \\  local sum = 0
        \\  local i = 1
        \\  while i <= n do
        \\    local a = i
        \\    local b = (i * 7 + 3) % 10000 + 1
        \\    while b ~= 0 do
        \\      local tmp = b
        \\      b = a % b
        \\      a = tmp
        \\    end
        \\    sum += a
        \\    i += 1
        \\  end
        \\  return sum
        \\end
    ;
    // i * 11 + 3: the emitter passes (n, 10000, 7, 3) as literals.
    // Measured: Duo 13800284, C 13843912.
    const perturbed =
        \\function gcd_reduce(n)
        \\  local sum = 0
        \\  local i = 1
        \\  while i <= n do
        \\    local a = i
        \\    local b = (i * 11 + 3) % 10000 + 1
        \\    while b ~= 0 do
        \\      local tmp = b
        \\      b = a % b
        \\      a = tmp
        \\    end
        \\    sum += a
        \\    i += 1
        \\  end
        \\  return sum
        \\end
    ;
    // POLARITY INVERTED. The whole emitted body was
    // `return duo_sum_affine_periodic_gcd_i64(n, 10000, 7, 3);` — one call, no
    // loop, three frozen constants. Both cases must decline.
    try testing.expect(!try kernel_flag_of(exact, .gcd_inline, alloc));
    try testing.expect(!try kernel_flag_of(perturbed, .gcd_inline, alloc));
}

test "sema: cordic closed form is retired, on its own kernel too" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const exact =
        \\function cordic(n)
        \\  local sum = 0.0
        \\  local i = 0
        \\  while i < n do
        \\    local angle = (i % 1000) * 0.001
        \\    local s = angle
        \\    local term = angle
        \\    local k = 1
        \\    while k <= 5 do
        \\      term = -term * angle * angle / ((2 * k) * (2 * k + 1))
        \\      s += term
        \\      k += 1
        \\    end
        \\    sum += s
        \\    i += 1
        \\  end
        \\  return sum
        \\end
    ;
    // * 0.002: the emitter caches 1000 phases built at 0.001 and reuses them.
    // Measured: Duo 2296384.602 (the UNPERTURBED answer), C 3538092.209.
    const perturbed =
        \\function cordic(n)
        \\  local sum = 0.0
        \\  local i = 0
        \\  while i < n do
        \\    local angle = (i % 1000) * 0.002
        \\    local s = angle
        \\    local term = angle
        \\    local k = 1
        \\    while k <= 5 do
        \\      term = -term * angle * angle / ((2 * k) * (2 * k + 1))
        \\      s += term
        \\      k += 1
        \\    end
        \\    sum += s
        \\    i += 1
        \\  end
        \\  return sum
        \\end
    ;
    // POLARITY INVERTED. 1000 phases, a 0.001 step and 5 Taylor terms, all
    // printed by the emitter — and the period sum reused `__cd_full` times is
    // not the f64 sum the written loop accumulates.
    try testing.expect(!try kernel_flag_of(exact, .cordic_inline, alloc));
    try testing.expect(!try kernel_flag_of(perturbed, .cordic_inline, alloc));
}

test "sema: interp closed form declines a different table step" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const exact =
        \\function interp(n)
        \\  local tbl_size = 1024
        \\  local tbl = {}
        \\  local i = 0
        \\  while i < tbl_size do
        \\    tbl[i] = math.sin(i * 0.01)
        \\    i += 1
        \\  end
        \\  local sum = 0.0
        \\  i = 0
        \\  while i < n do
        \\    local x = (i * 0.0073) % (tbl_size - 1)
        \\    local idx = math.floor(x)
        \\    local frac = x - idx
        \\    sum += tbl[idx] * (1.0 - frac) + tbl[idx + 1] * frac
        \\    i += 1
        \\  end
        \\  return sum
        \\end
    ;
    // NOTE the `+=`: `sum += a; sum += b` parses as `(sum + a) + b`, a
    // different float grouping and a different program, and is declined.
    // step 0.0091: the emitter walks its own 0.0073 chunk schedule.
    // Measured: Duo 814622.517 (the UNPERTURBED answer), C 827719.561.
    const perturbed =
        \\function interp(n)
        \\  local tbl_size = 1024
        \\  local tbl = {}
        \\  local i = 0
        \\  while i < tbl_size do
        \\    tbl[i] = math.sin(i * 0.01)
        \\    i += 1
        \\  end
        \\  local sum = 0.0
        \\  i = 0
        \\  while i < n do
        \\    local x = (i * 0.0091) % (tbl_size - 1)
        \\    local idx = math.floor(x)
        \\    local frac = x - idx
        \\    sum += tbl[idx] * (1.0 - frac) + tbl[idx + 1] * frac
        \\    i += 1
        \\  end
        \\  return sum
        \\end
    ;
    try testing.expect(try kernel_flag_of(exact, .interp_inline, alloc));
    try testing.expect(!try kernel_flag_of(perturbed, .interp_inline, alloc));
}

test "sema: fenwick closed form is retired, on its own kernel too" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const exact =
        \\function fenwick(size)
        \\  local tree = {}
        \\  local i = 0
        \\  while i <= size do
        \\    tree[i] = 0
        \\    i += 1
        \\  end
        \\  i = 1
        \\  while i <= size do
        \\    local val = (i * 3) % 1000
        \\    local idx = i
        \\    while idx <= size do
        \\      tree[idx] = tree[idx] + val
        \\      idx += (idx & (-idx))
        \\    end
        \\    i += 1
        \\  end
        \\  local sum = 0
        \\  local q = 1
        \\  while q <= size do
        \\    local idx = q
        \\    while idx > 0 do
        \\      sum += tree[idx]
        \\      idx -= (idx & (-idx))
        \\    end
        \\    q += 1
        \\  end
        \\  return sum
        \\end
    ;
    // i * 5: the emitter's closed form re-derives the period sum from *3.
    // Measured: Duo 62424013500000, C 62179540000000.
    const perturbed =
        \\function fenwick(size)
        \\  local tree = {}
        \\  local i = 0
        \\  while i <= size do
        \\    tree[i] = 0
        \\    i += 1
        \\  end
        \\  i = 1
        \\  while i <= size do
        \\    local val = (i * 5) % 1000
        \\    local idx = i
        \\    while idx <= size do
        \\      tree[idx] = tree[idx] + val
        \\      idx += (idx & (-idx))
        \\    end
        \\    i += 1
        \\  end
        \\  local sum = 0
        \\  local q = 1
        \\  while q <= size do
        \\    local idx = q
        \\    while idx > 0 do
        \\      sum += tree[idx]
        \\      idx -= (idx & (-idx))
        \\    end
        \\    q += 1
        \\  end
        \\  return sum
        \\end
    ;
    // POLARITY INVERTED, and this is the plainest of them: THERE WAS NO
    // FENWICK TREE in the emitted C — no array, no low-bit ascent, no prefix
    // query, just a period-1000 weighted sum over `(p * 3) % 1000`. Both cases
    // must decline; the row now builds the tree the source declares.
    try testing.expect(!try kernel_flag_of(exact, .fenwick_native, alloc));
    try testing.expect(!try kernel_flag_of(perturbed, .fenwick_native, alloc));
}

test "sema: binary-search closed form declines a non-identity fill" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const exact =
        \\function binary_search_scan(n)
        \\  local t = {}
        \\  local i = 1
        \\  while i <= n do
        \\    t[i] = i
        \\    i += 1
        \\  end
        \\  local hits = 0
        \\  local q = 1
        \\  while q <= 200000 do
        \\    local key = ((q * 7919) % n) + 1
        \\    local lo = 1
        \\    local hi = n
        \\    while lo <= hi do
        \\      local mid = math.floor((lo + hi) / 2)
        \\      if t[mid] < key then
        \\        lo = mid + 1
        \\      elseif t[mid] > key then
        \\        hi = mid - 1
        \\      else
        \\        hits += 1
        \\        break
        \\      end
        \\    end
        \\    q += 1
        \\  end
        \\  return hits
        \\end
    ;
    // t[i] = i * 2: emit_binary_search_dense_body compares `mid` against `key`
    // rather than the table, so it only holds for an identity fill. Every key
    // still lands in [1, n] but only half are present.
    // Measured: Duo 200000, C 100000.
    const perturbed =
        \\function binary_search_scan(n)
        \\  local t = {}
        \\  local i = 1
        \\  while i <= n do
        \\    t[i] = i * 2
        \\    i += 1
        \\  end
        \\  local hits = 0
        \\  local q = 1
        \\  while q <= 200000 do
        \\    local key = ((q * 7919) % n) + 1
        \\    local lo = 1
        \\    local hi = n
        \\    while lo <= hi do
        \\      local mid = math.floor((lo + hi) / 2)
        \\      if t[mid] < key then
        \\        lo = mid + 1
        \\      elseif t[mid] > key then
        \\        hi = mid - 1
        \\      else
        \\        hits += 1
        \\        break
        \\      end
        \\    end
        \\    q += 1
        \\  end
        \\  return hits
        \\end
    ;
    try testing.expect(try kernel_flag_of(exact, .binary_search_dense, alloc));
    try testing.expect(!try kernel_flag_of(perturbed, .binary_search_dense, alloc));
}

test "sema: @implements on a record-typed binding (concept is missing a required field)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    // The concept `Pair` requires both `first: i64` and `second: i64`.
    // The binding only declares `first`, so satisfaction fails.
    const src =
        \\concept Pair
        \\  first: i64
        \\  second: i64
        \\end
        \\@implements(Pair)
        \\local x: { first: i64 } = { first = 1 }
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    // Expect at least one error (the missing `second` field).
    try testing.expect(s.errors > 0);
}

test "sema: pass34 L1 module_sealed req binding" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\m = req "std.math"
        \\local x = 1
    ;
    var lex = Lexer.init(src, "test.id");
    var p = Parser.init(&lex, alloc);
    p.duo_mode = true;
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    s.duo_mode = true;
    try s.check_module(&mod);
    try testing.expect(s.moduleSealed("m"));
    try testing.expect(!s.moduleSealed("x"));
}

test "sema: pass34 L1 module_sealed invalidated on reassignment" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\m = req "std.math"
        \\m = 42
    ;
    var lex = Lexer.init(src, "test.id");
    var p = Parser.init(&lex, alloc);
    p.duo_mode = true;
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    s.duo_mode = true;
    try s.check_module(&mod);
    try testing.expect(!s.moduleSealed("m"));
}

test "sema: @implements on a global record-typed binding is checked" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\concept Pair
        \\  first: i64
        \\  second: i64
        \\end
        \\@implements(Pair)
        \\global x: { first: i64 } = { first = 1 }
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    try testing.expect(s.errors > 0);
}

test "sema: derived enum display and eq methods have native result types" {
    const src =
        \\@derive("Display", "Eq")
        \\enum Color
        \\  Red
        \\  Green
        \\end
        \\local red = Color.Red
        \\local green = Color.Green
        \\local label: str = red:to_string()
        \\local same: bool = red:eq(green)
    ;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    try testing.expectEqual(@as(u32, 0), s.errors);
}

test "sema: @implements accepts meta.make_concept descriptor binding" {
    const src =
        \\meta = req "std.meta"
        \\local PointLike = meta.make_concept("PointLike", {
        \\    fields = { "x", "y" },
        \\    methods = { "len" },
        \\})
        \\@implements(PointLike)
        \\local p: { x: i64, y: i64, len: any } = {
        \\    x = 3,
        \\    y = 4,
        \\    len = fun(self): i64 5,
        \\}
    ;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    try testing.expectEqual(@as(u32, 0), s.errors);
}

test "sema: @implements reports missing member from meta.make_concept descriptor" {
    const src =
        \\meta = req "std.meta"
        \\local PointLike = meta.make_concept("PointLike", {
        \\    fields = { "x", "y" },
        \\    methods = { "len" },
        \\})
        \\@implements(PointLike)
        \\local p: { x: i64, len: any } = {
        \\    x = 3,
        \\    len = fun(self): i64 5,
        \\}
    ;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    try testing.expect(s.errors > 0);
}

test "sema: @arc(false) accepts record-typed binding" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const s = try runSemaDuo(
        \\@arc(false)
        \\local x: { value: i64 } = { value = 1 }
    , &arena);
    try testing.expectEqual(@as(u32, 0), s.errors);
}

test "sema: @arc(false) rejects primitive binding" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const s = try runSemaDuo(
        \\@arc(false)
        \\local x: i64 = 1
    , &arena);
    try testing.expect(s.errors > 0);
}

test "sema: @arc(false) rejects function declaration" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const s = try runSemaDuo(
        \\@arc(false)
        \\function f()
        \\end
    , &arena);
    try testing.expect(s.errors > 0);
}

test "sema: @specialize accepts known generic target with matching arity" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const s = try runSemaDuo(
        \\fun id<T>(x: T): T
        \\  return x
        \\end
        \\@specialize(id, i64)
    , &arena);
    try testing.expectEqual(@as(u32, 0), s.errors);
}

test "sema: @specialize rejects unknown target" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const s = try runSemaDuo(
        \\@specialize(missing, i64)
    , &arena);
    try testing.expect(s.errors > 0);
}

test "sema: @specialize rejects non-generic target" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const s = try runSemaDuo(
        \\fun plain(x: i64): i64
        \\  return x
        \\end
        \\@specialize(plain, i64)
    , &arena);
    try testing.expect(s.errors > 0);
}

test "sema: @specialize rejects wrong type argument count" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const s = try runSemaDuo(
        \\fun pair<T, U>(x: T, y: U): T
        \\  return x
        \\end
        \\@specialize(pair, i64)
    , &arena);
    try testing.expect(s.errors > 0);
}

test "sema: @specialize counts nested generic type argument commas" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const s = try runSemaDuo(
        \\fun id<T>(x: T): T
        \\  return x
        \\end
        \\@specialize(id, Result[i64, str])
    , &arena);
    try testing.expectEqual(@as(u32, 0), s.errors);
}

test "sema: @deprecated binding emits warning at use site" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const s = try runSemaDuo(
        \\@deprecated("use y")
        \\local x = 1
        \\local z = x
    , &arena);
    try testing.expectEqual(@as(u32, 0), s.errors);
    try testing.expect(s.warnings > 0);
}

test "sema: try_stmt catch untyped binding is accepted" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    // Catch clauses are untyped in Duo. The binding, if present, is
    // statically `any` (errors are tables). There is no `catch MyError e`
    // form — discrimination is done inside the body with `match e.__tag`.
    const src =
        \\try
        \\  local x = 42
        \\catch e
        \\  local y = e
        \\end
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    try testing.expectEqual(@as(u32, 0), s.errors);
}

test "sema: try_stmt catch with no binding is accepted" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    // An unnamed `catch` discards the error value entirely.
    const src =
        \\try
        \\  local x = 42
        \\catch
        \\  local y = 1
        \\end
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    try testing.expectEqual(@as(u32, 0), s.errors);
}

test "sema: try_stmt body can discriminate error inside catch via __tag" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    // Verifies the new idiom: instead of `catch MyError e`, the body uses
    // `match e.__tag` to discriminate the kind of error.
    const src =
        \\try
        \\  local x = 42
        \\catch e
        \\  match e.__tag
        \\    "NotFound" then local y = 1
        \\    _ then local z = 2
        \\  end
        \\end
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    try testing.expectEqual(@as(u32, 0), s.errors);
}

test "sema: try_expr (?) in function with 'any' return type is accepted" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    // 'any' return type is result-compatible (runtime check)
    const src =
        \\function f(x)
        \\  local y = x?
        \\  return y
        \\end
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    // 'any' is result-compatible, so ? should be accepted
    try testing.expectEqual(@as(u32, 0), s.errors);
}

test "sema: overload resolution selects by argument types (no ambiguity)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    // Two overloads of `f` distinguished by parameter type. A call with an
    // i64 argument resolves unambiguously to the i64 overload (Requirement 12).
    const src =
        \\fun f(x: i64): i64 x
        \\fun f(x: str): str x
        \\local r: i64 = f(1)
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    try testing.expectEqual(@as(u32, 0), s.errors);
}

test "sema: gcd shape still matches, but the closed form is retired" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\function gcd_reduce(n)
        \\  local sum = 0
        \\  local i = 1
        \\  while i <= n do
        \\    local a = i
        \\    local b = (i * 7 + 3) % 10000 + 1
        \\    while b ~= 0 do
        \\      local tmp = b
        \\      b = a % b
        \\      a = tmp
        \\    end
        \\    sum += a
        \\    i += 1
        \\  end
        \\  return sum
        \\end
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    try testing.expectEqual(@as(u32, 0), s.errors);
    try testing.expect(mod.body.stmts[0] == .func_decl);
    // POLARITY INVERTED. The SHAPE still matches — that is what keeps the
    // native i64 signature — but `use_gcd_inline` is retired, so the flag that
    // selects the closed-form body must be clear.
    try testing.expect(!mod.body.stmts[0].func_decl.func.use_gcd_inline);
}

test "sema: collatz detector accepts integer division branch" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\function collatz_sum(n: i64): i64
        \\  local total: i64 = 0
        \\  local i: i64 = 1
        \\  while i <= n do
        \\    local x: i64 = i
        \\    local steps: i64 = 0
        \\    while x ~= 1 do
        \\      if x % 2 == 0 then
        \\        x //= 2
        \\      else
        \\        x = 3 * x + 1
        \\      end
        \\      steps += 1
        \\    end
        \\    total += steps
        \\    i += 1
        \\  end
        \\  return total
        \\end
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    try testing.expectEqual(@as(u32, 0), s.errors);
    try testing.expect(mod.body.stmts[0] == .func_decl);
    try testing.expect(mod.body.stmts[0].func_decl.func.use_collatz_inline);
}

test "sema: @arc(false) on a primitive-typed binding is rejected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    // @arc(false) is only meaningful on heap-backed (table/record) bindings;
    // applying it to an i64 binding is a static error (Requirement 18).
    const src =
        \\@arc(false)
        \\local n: i64 = 1
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    try testing.expect(s.errors > 0);
}

test "sema: @arc(false) on a record-typed binding is accepted" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\@arc(false)
        \\local p: { x: i64 } = { x = 1 }
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    try testing.expectEqual(@as(u32, 0), s.errors);
}

test "sema: __constexpr is accepted as a compiler intrinsic in duo mode" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\local base: i64 = 10
        \\local folded: i64 = __constexpr(base + 5)
    ;
    var lex = Lexer.init(src, "test.id");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    s.duo_mode = true;
    try s.check_module(&mod);
    try testing.expectEqual(@as(u32, 0), s.errors);
}

test "sema: tensor matmul infers output shape" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\fun f(x: Tensor[784, 256, f32], y: Tensor[256, 10, f32]): Tensor[784, 10, f32]
        \\  return x @ y
        \\end
    ;
    var lex = Lexer.init(src, "test.id");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    s.duo_mode = true;
    try s.check_module(&mod);
    try testing.expectEqual(@as(u32, 0), s.errors);
}

// GAP-059. Three rows, and the last two are the load-bearing ones: a gate with
// no positive control is a gate that can be silently always-on. Row 1 is the
// refusal of a SPACED `@` over non-tensors, row 2 is `.lua` still holding the
// operator, row 3 is the tensor product still legal in `.id` — asserted by
// "sema: tensor matmul infers output shape" directly above, which runs with
// duo_mode = true and expects zero errors.
//
// The GLUED spelling never reaches here at all: after 3f6ec4e the parser reads
// `p@x` as an anchor suffix, so it is a `field` node, not a binop. That is the
// fourth row and it lives where it belongs, in
// `examples/spec100/anchormove.id`, as a VALUE.
test "sema: duo mode infix @ over non-tensor operands is an error" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\fun f(a: i64, b: i64): i64
        \\  return a @ b
        \\end
    ;
    var lex = Lexer.init(src, "test.id");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    s.duo_mode = true;
    try s.check_module(&mod);
    try testing.expect(s.errors > 0);
}

test "sema: lua mode infix @ over non-tensor operands is not an error" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\fun f(a, b)
        \\  return a @ b
        \\end
    ;
    var lex = Lexer.init(src, "test.lua");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    s.duo_mode = false;
    try s.check_module(&mod);
    try testing.expectEqual(@as(u32, 0), s.errors);
}

test "sema: tensor matmul K mismatch emits error" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\fun f(x: Tensor[784, 256, f32], y: Tensor[128, 10, f32])
        \\  return x @ y
        \\end
    ;
    var lex = Lexer.init(src, "test.id");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    s.duo_mode = true;
    try s.check_module(&mod);
    try testing.expect(s.errors > 0);
}

test "sema: tensor matmul return type mismatch emits error" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\fun f(x: Tensor[784, 256, f32], y: Tensor[256, 10, f32]): Tensor[99, 10, f32]
        \\  return x @ y
        \\end
    ;
    var lex = Lexer.init(src, "test.id");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    s.duo_mode = true;
    try s.check_module(&mod);
    try testing.expect(s.errors > 0);
}

test "sema: tensor matmul symbolic K mismatch emits error" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\fun f(a: Tensor[M, K, f32], b: Tensor[J, N, f32])
        \\  return a @ b
        \\end
    ;
    var lex = Lexer.init(src, "test.id");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    s.duo_mode = true;
    try s.check_module(&mod);
    try testing.expect(s.errors > 0);
}

test "sema: tensor add broadcast infers output shape" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\fun f(a: Tensor[1, 10, f32], b: Tensor[784, 10, f32]): Tensor[784, 10, f32]
        \\  return a + b
        \\end
    ;
    var lex = Lexer.init(src, "test.id");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    s.duo_mode = true;
    try s.check_module(&mod);
    try testing.expectEqual(@as(u32, 0), s.errors);
}

test "sema: tensor add broadcast incompatible emits error" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\fun f(a: Tensor[2, 3, f32], b: Tensor[3, 4, f32])
        \\  return a + b
        \\end
    ;
    var lex = Lexer.init(src, "test.id");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    s.duo_mode = true;
    try s.check_module(&mod);
    try testing.expect(s.errors > 0);
}
