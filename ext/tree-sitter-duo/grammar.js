/**
 * @file Tree-sitter grammar for the Duo programming language.
 *
 * Duo is a Lua-like language with optional static typing that compiles to
 * native C and WebAssembly.
 *
 * Based on the lexer tokens from src/lexer.zig and AST from src/ast.zig.
 *
 * ── STATUS: AUTHORED. It is not supposed to be. ──────────────────────────────
 *
 * Pass 100 §19 lists tree-sitter as "a generated grammar projection (output,
 * never authored)". These 106 rules are hand-written, so this file is a live
 * violation of the spec it describes, and it is the largest non-Duo authored
 * source in the repository.
 *
 * It is NOT converted, and not deleted, because the surface it would be
 * generated FROM does not exist: there is no declarative production registry
 * in Duo. `lib/std/compiler/parser.duo` is an imperative recursive-descent
 * parser over a bounded subset (~12 productions), `docs/GRAMMAR_SPEC.md` is
 * prose, and `duo token-tables emit` is lexical only. See gaps/GAP-049 for the
 * three missing pieces and the order they have to land in.
 *
 * The rules below still spell a PRE-PASS-100 surface alongside the Pass 100
 * one — match / enum / try / catch / concept / local / const / function are all
 * still here, and CLAUDE.md §1 denies every one of them by name. They are kept
 * because the CORPUS still uses them (8 statement-initial `match`, 9 `enum`,
 * 59 `concept`, 23 `local`, 348 `fun`), and because `try`/`catch`/`defer`, with
 * no statement uses left, are still assigned token numbers by the GENERATED
 * `lib/std/token/classify.duo`. Dropping a rule here alone desynchronises the
 * front-ends; retiring one is a language decision, not a grammar edit.
 *
 * It BUILDS as of 2026-08-08. It did not before: `tree-sitter generate`
 * exited 1 on an unresolved conflict on `return_statement` ('return' • '(' —
 * an argument list versus a bare `return` followed by a parenthesised
 * statement), and the tracked `src/grammar.json` beside this file was NOT a
 * usable fallback: regenerating from that JSON alone fails with the identical
 * conflict, so no editor on this tree had a working parser at all. The repair
 * is `prec.right` on `return_statement` plus the `conflicts:` entries below,
 * each one proven necessary by dropping it and re-running the generator — all
 * 46 of them, re-proved after every change in this pass.
 *
 * What it recognises, MEASURED over the 748 tracked `.duo` files with
 * `tree-sitter parse --paths`, counting a file as recognised only when its
 * tree has no ERROR / MISSING / UNEXPECTED node:
 *
 *   75  (10.0 %)  before this pass
 *  226  (30.2 %)  + `bare_function_declaration`         — GR-001
 *  422  (56.4 %)  + `!=` `&` `~` `|>` and `+= -= *= /= %= ^=`
 *  494  (66.0 %)  + `function_value_expression`         — `f = (x: i64): i64 … end`
 *  599  (80.0 %)  + N-segment `@` directives, `@{ … }`, expression args
 *  635  (84.8 %)  + shebang, `;`, long strings containing `]`
 *  656  (87.7 %)  + `->` results, default parameters, `.field` projection
 *  670  (89.5 %)  + bodyless `@ffi` declarations, `alias N = T`, `M:name()`
 *  697  (93.1 %)  + function values as directive arguments, `<T: Bound>`
 *  702  (93.8 %)  + `[T]` / `Tensor[a, b, c]`, and Lua's `f "s"` / `f { … }`
 *
 * The 46 files still failing are a long tail of one to four files each: the
 * expression-body lambda (`(v) return v * 2`, 11), `type` used as both a
 * keyword and a function name (5, and the two spellings are mutually
 * exclusive), `macro … \`do`, and the `#` / `//` comment openers.
 *
 * A file with no ERROR node is not the same as a CORRECT tree, and this count
 * does not claim it is. `require "x"` parsed as two unrelated statements in 95
 * files without ever producing an error node; it is fixed here, and the
 * recognition number could not see either the defect or the repair.
 *
 * Counted, until then, as one of three tracked `.js` files in the G11 debt
 * line (`scripts/language_census.duo`, ratchet `CENSUS_JS_FLOOR`). Editing
 * this comment does not make the file generated.
 */

module.exports = grammar({
  name: 'duo',

  extras: $ => [
    /\s/,
    $.comment,
  ],

  supertypes: $ => [
    $.statement,
    $.expression,
    $.type,
    $.pattern,
  ],

  // Duo statements are not separated by a terminator and an expression is a
  // statement, so the LR(1) item set genuinely cannot decide these without
  // lookahead past the conflict point. Each entry below was proven NECESSARY:
  // a script drops one at a time and re-runs `tree-sitter generate`, and all
  // 46 are still required for it to exit 0. See gaps/GAP-049.
  conflicts: $ => [
    // statement head vs expression statement
    [$.struct_definition, $.expression],
    [$.typed_binding, $.call_expression],
    [$.assignment, $.call_expression],
    [$.compound_assignment, $.call_expression],
    [$.local_declaration, $.call_expression],
    [$.const_declaration, $.call_expression],
    [$.global_declaration, $.call_expression],
    [$.return_statement, $.call_expression],
    [$.repeat_loop, $.call_expression],
    [$.expression_statement, $.call_expression],
    // `f "s"` / `f { … }` — the sugar call, or two adjacent expressions. The
    // dynamic precedence on `call_expression` attaches it.
    [$.expression, $.call_expression],
    [$.match_arm, $.expression_statement, $.call_expression],
    [$.call_expression, $.parenthesized_expression],
    // GR-001: `f(` is a declaration head or a call, decided only at the `:`
    // that annotates a parameter or the result — past the conflict point.
    // `f(): i64 … end` — a NAMED declaration, or the expression `f` followed
    // by an anonymous function value. Both are structurally valid; the
    // dynamic precedence on `bare_function_declaration` picks the declaration.
    // `@name` — an attribute BINDING to the next declaration, or a directive
    // standing alone as a statement. The dynamic precedence on
    // `_attribute_list` decides; both readings are in the corpus.
    [$._attribute_list, $.expression],
    // `M:hash(` / `pkg.fn(` — a declaration NAME or an expression that is
    // about to be called. Same tokens; the `:` inside the parameter list or
    // after the `)` is what decides.
    [$.function_name, $.expression],
    [$.function_name, $.jai_type_definition, $.typed_binding, $.expression],
    [$.function_name, $.catch_clause, $.expression],
    // A signature with a body, or a bodyless declaration whose statements
    // happen to follow. `bare_function_declaration` carries the dynamic
    // precedence, so a body wins wherever one closes with `end`.
    [$.bare_function_declaration, $.foreign_declaration],
    // `f(...)` — a vararg PARAMETER (`zip(...): any`) or a call forwarding the
    // enclosing vararg. Only the `): type` after the paren tells them apart.
    [$.vararg_parameter, $.vararg],
    // `f(a, b)` — an unannotated PARAMETER list awaiting `): type`, or an
    // argument list of bare identifiers. Same token, decided after the `)`.
    [$._plain_parameter, $.expression],
    // `f(a: …)` — an annotated PARAMETER or the receiver of a method call
    // argument, `f(a:greet())`. The `:` is shared; the type is not.
    [$._typed_parameter, $.expression],
    // `f()` immediately followed by `(): i64 … end` — a call, or a call whose
    // argument is a function VALUE. Only the token after the `)` decides.
    [$._annotated_signature, $.call_expression],
    // unterminated statement lists — where does the body stop
    [$.do_block, $.while_loop],
    [$.do_block, $.numeric_for],
    [$.do_block, $.generic_for],
    [$.statement, $.try_statement],
    [$.catch_clause],
    [$.catch_clause, $.expression],
    [$.binding_name],
    // pattern position overlaps expression position
    [$.literal_pattern, $.expression],
    [$.literal_pattern, $.nil],
    [$.literal_pattern, $.boolean],
    [$.binding_pattern, $.expression],
    [$.variant_pattern, $.expression],
    [$.table_pattern, $.table_constructor],
    [$.match_statement, $.match_expression],
    [$.expression_statement, $.match_arm],
    [$.match_arm, $.index_expression],
    // prefix operators bind before the LR item is decided
    [$.binary_expression, $.unary_expression],
    [$.binary_expression, $.contains_expression],
    [$.binary_expression, $.unary_expression, $.contains_expression],
    [$.call_expression, $.await_expression],
    [$.index_expression, $.await_expression],
    [$.method_call_expression, $.await_expression],
    [$.try_expression, $.await_expression],
    [$.unwrap_expression, $.await_expression],
  ],

  // ── Rules ──────────────────────────────────────────────────────────────────

  rules: {
    // ── Top-level ───────────────────────────────────────────────────────────

    module: $ => seq(
      optional($.shebang),
      repeat($.statement),
    ),

    // `#!/usr/bin/env duo`. src/lexer.zig recognises `#!` only at index 0 and
    // so does this: `#` is the length operator everywhere else.
    shebang: $ => token(seq('#!', /[^\n]*/)),

    // ── Statements ──────────────────────────────────────────────────────────

    statement: $ => choice(
      $.local_declaration,
      $.const_declaration,
      $.global_declaration,
      $.assignment,
      $.compound_assignment,
      $.typed_binding,
      $.jai_type_definition,
      $.type_definition,
      $.struct_definition,
      $.do_block,
      $.if_statement,
      $.while_loop,
      $.repeat_loop,
      $.numeric_for,
      $.generic_for,
      $.function_declaration,
      $.bare_function_declaration,
      $.foreign_declaration,
      $.return_statement,
      $.break_statement,
      $.goto_statement,
      $.label_statement,
      $.expression_statement,
      $.match_statement,
      $.try_statement,
      $.defer_statement,
      $.enum_definition,
      $.concept_definition,
      $.alias_definition,
      $.empty_statement,
    ),

    // Duo has no statement terminator, but `;` is a token (`semi`) and 16
    // tracked files use it to put two statements on one line.
    empty_statement: $ => ';',

    // ── Attributes ──────────────────────────────────────────────────────────

    // `@export`, `@ffi("puts")`, `@c.emit("code")`, `@comp.define.derive(…)`,
    // `@(expr)`.
    //
    // Two things were wrong here. The path was capped at TWO segments, so
    // `@comp.define.derive` and `@comp.embed.json` had no rule; and the
    // argument list was the raw regex `/[^)]*/`, which stops at the first `)`
    // it sees — so `@comp.assert(@comp.satisfies(Point, "HasXY"), "…")` ended
    // mid-argument and every nested call was an error. Arguments are ordinary
    // expressions, which is what they are in the compiler too.
    attribute: $ => prec.right(choice(
      seq('@', $.attribute_path, optional(seq(
        '(',
        // A directive argument may be a whole function: 22 tracked files write
        // `@comp.define.derive("Name", generate(meta) -> str … end)`, where the
        // second argument is a NAMED declaration, not an expression.
        commaSep(choice($.expression, $.bare_function_declaration)),
        ')',
      ))),
      // @(expr) — compile-time evaluation
      seq('@', '(', $.expression, ')'),
    )),

    // Right-associative so the path is GREEDY: `@comp.type.name(x)` is one
    // three-segment directive, not `@comp` with a field access hanging off it.
    attribute_path: $ => prec.right(seq(
      $.identifier,
      repeat(seq('.', $.identifier)),
    )),

    // An attribute BINDS to the declaration it precedes wherever one follows;
    // where none does (`@c.emit("code")` on its own line) the same syntax is a
    // statement. Both readings exist in the corpus, so the list carries a
    // dynamic precedence and attachment wins when it is available at all.
    _attribute_list: $ => prec.dynamic(1, repeat1($.attribute)),

    // ── Local declaration ───────────────────────────────────────────────────

    local_declaration: $ => seq(
      optional($._attribute_list),
      'local',
      commaSep1($.binding_name),
      optional(seq(
        ':',
        $.type,
      )),
      optional(seq(
        '=',
        commaSep1($.expression),
      )),
    ),

    binding_name: $ => seq(
      optional($._attribute_list),
      $.identifier,
      optional(seq(':', field('type', $.type))),
    ),

    // ── Const declaration ───────────────────────────────────────────────────

    const_declaration: $ => seq(
      'const',
      $.identifier,
      optional(seq(':', $.type)),
      '=',
      $.expression,
    ),

    // ── Global declaration ──────────────────────────────────────────────────

    global_declaration: $ => seq(
      'global',
      choice(
        '*',
        commaSep1($.binding_name),
      ),
      optional(seq(
        '=',
        commaSep1($.expression),
      )),
    ),

    // ── Assignment ──────────────────────────────────────────────────────────

    assignment: $ => seq(
      commaSep1($.expression),
      '=',
      commaSep1($.expression),
    ),

    // ── Compound assignment ─────────────────────────────────────────────────
    //
    // `+= -= *= /= %= ^=` are six distinct token kinds in src/lexer.zig
    // (`plus_assign` … `caret_assign`) and this grammar had none of them, so
    // `sub -= 1` parsed as `sub -` followed by `= 1`.
    compound_assignment: $ => seq(
      $.expression,
      choice('+=', '-=', '*=', '/=', '%=', '^='),
      $.expression,
    ),

    // ── Do block ────────────────────────────────────────────────────────────

    do_block: $ => seq(
      'do',
      repeat($.statement),
      'end',
    ),

    // ── If statement ────────────────────────────────────────────────────────

    if_statement: $ => seq(
      'if',
      $.expression,
      optional('then'),
      repeat($.statement),
      repeat($.elseif_clause),
      optional($.else_clause),
      'end',
    ),

    elseif_clause: $ => seq(
      'elseif',
      $.expression,
      optional('then'),
      repeat($.statement),
    ),

    else_clause: $ => seq(
      'else',
      repeat($.statement),
    ),

    // ── While loop ──────────────────────────────────────────────────────────

    while_loop: $ => seq(
      'while',
      $.expression,
      optional('do'),
      repeat($.statement),
      'end',
    ),

    // ── Repeat loop ─────────────────────────────────────────────────────────

    repeat_loop: $ => seq(
      'repeat',
      repeat($.statement),
      'until',
      $.expression,
    ),

    // ── Numeric for ─────────────────────────────────────────────────────────

    numeric_for: $ => seq(
      'for',
      $.identifier,
      optional(seq(':', $.type)),
      '=',
      $.expression,
      ',',
      $.expression,
      optional(seq(',', $.expression)),
      optional('do'),
      repeat($.statement),
      'end',
    ),

    // ── Generic for ─────────────────────────────────────────────────────────

    generic_for: $ => seq(
      'for',
      commaSep1($.identifier),
      'in',
      commaSep1($.expression),
      optional('do'),
      repeat($.statement),
      'end',
    ),

    // ── Function declaration ────────────────────────────────────────────────

    function_declaration: $ => seq(
      optional($._attribute_list),
      optional('local'),
      choice('function', 'fun'),
      field('name', $.function_name),
      optional($.type_parameters),
      '(',
      commaSep($.parameter),
      optional(seq(',', '...')),
      ')',
      optional(seq($._result_arrow, $.type)),
      repeat($.statement),
      'end',
    ),

    // `<T>`, and `<T: Hashable>` / `<T: Hashable + Counter>` — a type
    // parameter may carry constraints, which `commaSep1($.type)` could not
    // express because `T: Hashable` is not a type.
    type_parameters: $ => seq(
      '<',
      commaSep1($.type_parameter),
      '>',
    ),

    type_parameter: $ => seq(
      $.identifier,
      optional(seq(':', $.type, repeat(seq('+', $.type)))),
    ),

    function_name: $ => seq(
      $.identifier,
      repeat(seq('.', $.identifier)),
      optional(seq(':', $.identifier)),
    ),

    // `step: i64 = default_step` — a default value. It is part of the
    // parameter, not an assignment smuggled into the list.
    parameter: $ => seq(
      optional($._attribute_list),
      $.identifier,
      optional(seq(':', field('type', $.type))),
      optional(seq('=', $.expression)),
    ),

    // ── Bare function declaration (GR-001) ──────────────────────────────────
    //
    // `fib(n: any)` / `_env_or(n: str, d: str): str` — no `fun`, no
    // `function`. This is Pass 100's canonical declaration form and it is 63 %
    // of what this grammar used to fail on.
    //
    // The two arms below are GR-001's disambiguation, not a stylistic choice.
    // `main()` followed by statements and an `end` is a CALL in this language,
    // not a declaration, so a bare head is only a declaration when it carries
    // AT LEAST ONE type annotation:
    //
    //   arm (a)  NO parameter is annotated, so a return type is REQUIRED —
    //            `f(a, b): i64`, `main(): i64`. `): i64` cannot follow a call.
    //   arm (b)  some parameter IS annotated, so the return type is optional —
    //            `fib(n: any)`, `arena_alloc(self, bytes: i64)`,
    //            `_env_or(n: str, d: str): str`. `x: T` is not an expression,
    //            so this cannot be an argument list either.
    //
    // The split is by the PARAMETERS, not by the return type, and that is what
    // keeps it LR(1): both arms open with the same unannotated-parameter
    // symbol, so nothing forks at `(`. The arms separate at the first `:`
    // inside the list — one token of lookahead after a parameter name, which
    // arm (a) cannot follow and arm (b) must.
    //
    // Corpus evidence for the exclusion (statement-initial heads, 748 tracked
    // files): 4645 have a return type, 230 have an annotated parameter and no
    // return type, 48 are `main()`-shaped with neither, and 791 are ordinary
    // calls like `print(out)`. Accepting the 48 would make every one of the
    // 791 a candidate declaration.
    // The precedence is against `function_value_expression`, not against the
    // call: `f(): i64 … end` is either this rule, or the bare expression `f`
    // followed by an anonymous function value. Both are structurally valid and
    // only one is ever meant, so it is settled statically rather than left to
    // GLR to pick a tree by size.
    bare_function_declaration: $ => prec.dynamic(3, seq(
      optional($._attribute_list),
      // `function_name` rather than a bare identifier: `M:hash(): i64` and
      // `pkg.fn(x: i64): i64` are declarations too.
      field('name', $.function_name),
      $._annotated_signature,
      repeat($.statement),
      'end',
    )),

    // ── Foreign / bodyless declaration ──────────────────────────────────────
    //
    // `@ffi("llabs")` then `llabs(n: i64): i64` — a signature with no body and
    // no `end`. 43 tracked files declare something this way (`@ffi`, `@export`,
    // `@native`, `@hot`, `@device(.cuda)`, `@test.unit`).
    //
    // An attribute list is REQUIRED, and that is what keeps the rule safe: a
    // bare signature with no body is otherwise indistinguishable from one whose
    // body follows, and the dynamic precedence on `bare_function_declaration`
    // is what settles the case where an `end` does turn up.
    foreign_declaration: $ => seq(
      $._attribute_list,
      field('name', $.function_name),
      $._annotated_signature,
    ),

    // The signature carrying GR-001's annotation requirement. Shared with
    // `function_value_expression` so the two spellings of a Duo function
    // cannot drift apart.
    _annotated_signature: $ => choice(
      seq(
        '(',
        optional(seq(
          optional($._plain_parameter_prefix),
          choice(alias($._plain_parameter, $.parameter), $.vararg_parameter),
        )),
        ')',
        $._result_arrow,
        field('result', $.type),
      ),
      seq(
        '(',
        optional($._plain_parameter_prefix),
        alias($._typed_parameter, $.parameter),
        repeat(seq(',', choice($.parameter, $.vararg_parameter))),
        ')',
        optional(seq($._result_arrow, field('result', $.type))),
      ),
    ),

    // `:` and `->` are the same thing here — `hash(self) -> i64` in a concept
    // body, `generate(meta) -> str` as a derive argument, `f(n: i64): i64`
    // everywhere else. `arrow` is its own token in src/lexer.zig.
    _result_arrow: $ => choice(':', '->'),

    // Both arms open on THIS symbol, which is why nothing forks at `(`. One
    // token of lookahead after a parameter name settles it: `,` continues the
    // prefix, `)` ends arm (a), `:` starts arm (b)'s pivot.
    _plain_parameter_prefix: $ => repeat1(
      seq(alias($._plain_parameter, $.parameter), ','),
    ),

    _plain_parameter: $ => seq(
      optional($._attribute_list),
      $.identifier,
    ),

    _typed_parameter: $ => seq(
      optional($._attribute_list),
      $.identifier,
      ':',
      field('type', $.type),
      optional(seq('=', $.expression)),
    ),

    vararg_parameter: $ => seq(
      '...',
      optional($.identifier),
    ),

    // ── Return ──────────────────────────────────────────────────────────────

    return_statement: $ => prec.right(seq(
      'return',
      optional(commaSep1($.expression)),
    )),

    // ── Break ───────────────────────────────────────────────────────────────

    break_statement: $ => 'break',

    // ── Goto ────────────────────────────────────────────────────────────────

    goto_statement: $ => seq(
      'goto',
      $.identifier,
    ),

    label_statement: $ => seq(
      '::',
      $.identifier,
      '::',
    ),

    // ── Expression statement ────────────────────────────────────────────────

    expression_statement: $ => $.expression,

    // ── Match statement ─────────────────────────────────────────────────────

    match_statement: $ => seq(
      'match',
      $.expression,
      repeat($.match_arm),
      'end',
    ),

    match_arm: $ => choice(
      seq(
        'case',
        $.pattern,
        optional($.guard),
        choice('then', 'do'),
        choice(
          $.expression,
          seq(repeat($.statement), 'end'),
        ),
      ),
      seq(
        $.pattern,
        optional($.guard),
        '=>',
        choice(
          $.expression,
          seq(repeat($.statement), 'end'),
        ),
      ),
    ),

    guard: $ => seq(
      'if',
      $.expression,
    ),

    // ── Pattern ─────────────────────────────────────────────────────────────

    pattern: $ => choice(
      $.literal_pattern,
      $.binding_pattern,
      $.variant_pattern,
      $.table_pattern,
      $.array_pattern,
      $.rest_pattern,
      '_',
    ),

    literal_pattern: $ => choice(
      $.number,
      $.string,
      'true',
      'false',
      'nil',
    ),

    binding_pattern: $ => seq(
      $.identifier,
      optional(seq(':', $.type)),
    ),

    variant_pattern: $ => seq(
      $.identifier,
      '(',
      commaSep($.pattern),
      ')',
    ),

    table_pattern: $ => seq(
      '{',
      commaSep($.table_pattern_entry),
      '}',
    ),

    table_pattern_entry: $ => seq(
      $.identifier,
      '=',
      $.pattern,
    ),

    array_pattern: $ => seq(
      '[',
      commaSep($.pattern),
      ']',
    ),

    rest_pattern: $ => seq(
      '...',
      $.identifier,
    ),

    // ── Try statement ───────────────────────────────────────────────────────

    try_statement: $ => seq(
      'try',
      repeat($.statement),
      repeat($.catch_clause),
      optional($.defer_statement),
      'end',
    ),

    catch_clause: $ => seq(
      'catch',
      optional($.identifier),
      repeat($.statement),
    ),

    // ── Defer statement ─────────────────────────────────────────────────────

    defer_statement: $ => seq(
      'defer',
      repeat($.statement),
      'end',
    ),

    // ── Enum definition ─────────────────────────────────────────────────────

    enum_definition: $ => seq(
      optional($._attribute_list),
      'enum',
      $.identifier,
      optional($.type_parameters),
      repeat($.enum_variant),
      'end',
    ),

    enum_variant: $ => seq(
      $.identifier,
      optional(seq(
        '(',
        commaSep1($.enum_field),
        ')',
      )),
    ),

    enum_field: $ => seq(
      optional(seq($.identifier, ':')),
      $.type,
    ),

    // ── Concept definition ──────────────────────────────────────────────────

    concept_definition: $ => seq(
      optional($._attribute_list),
      'concept',
      $.identifier,
      optional($.type_parameters),
      repeat(choice(
        $.concept_method,
        $.concept_field,
      )),
      'end',
    ),

    concept_method: $ => seq(
      $.identifier,
      '(',
      commaSep($.parameter),
      ')',
      $._result_arrow,
      $.type,
    ),

    concept_field: $ => seq(
      $.identifier,
      ':',
      $.type,
    ),

    // ── Alias definition ────────────────────────────────────────────────────

    // Two forms. The block form (`alias Name extends Base … end`) was here;
    // `alias Point = { x: f64, y: f64 }`, which 7 tracked files open with, was
    // not, so those files failed on their first line.
    alias_definition: $ => seq(
      optional($._attribute_list),
      'alias',
      $.identifier,
      choice(
        seq('=', $.type),
        seq(
          optional(seq('extends', $.identifier)),
          repeat($.alias_member),
          'end',
        ),
      ),
    ),

    // ── Type definition (type Name = Type) ──────────────────────────────────

    type_definition: $ => seq(
      optional($._attribute_list),
      'type',
      $.identifier,
      '=',
      $.type,
    ),

    // ── Jai-like type definition (Name: { fields }) ─────────────────────────

    jai_type_definition: $ => seq(
      optional($._attribute_list),
      $.identifier,
      ':',
      $.record_type,
    ),

    // ── Typed binding (name: Type = expr) ───────────────────────────────────

    typed_binding: $ => seq(
      optional($._attribute_list),
      $.identifier,
      ':',
      $.type,
      '=',
      $.expression,
    ),

    // ── Struct definition (Name = struct ... end) ────────────────────────────

    struct_definition: $ => seq(
      optional($._attribute_list),
      $.identifier,
      '=',
      'struct',
      repeat($.struct_field),
      'end',
    ),

    struct_field: $ => seq(
      $.identifier,
      optional(seq(':', $.type)),
      optional(seq('=', $.expression)),
    ),

    alias_member: $ => choice(
      $.alias_field,
      $.function_declaration,
    ),

    alias_field: $ => seq(
      optional('private'),
      $.identifier,
      ':',
      $.type,
      optional(seq('=', $.expression)),
    ),

    // ── Types ───────────────────────────────────────────────────────────────

    type: $ => choice(
      $.named_type,
      $.array_type,
      $.pointer_type,
      $.optional_type,
      $.generic_type,
      $.function_type,
      $.record_type,
    ),

    named_type: $ => $.identifier,

    // `[4]i32` (Jai-style, element type after the brackets) and `[string]` /
    // `[float]` (element type INSIDE them). Both are in the corpus; only the
    // first was in this grammar.
    array_type: $ => choice(
      seq('[', optional($.number), ']', $.type),
      seq('[', $.type, ']'),
    ),

    pointer_type: $ => seq(
      '*',
      $.type,
    ),

    optional_type: $ => seq(
      '?',
      $.type,
    ),

    // `Map<K, V>` and `Tensor[784, 256, f32]` — the bracket form takes shape
    // arguments, so a dimension is a NUMBER where a type would otherwise be.
    generic_type: $ => choice(
      seq($.identifier, '<', commaSep1($.type), '>'),
      seq($.identifier, '[', commaSep1(choice($.type, $.number)), ']'),
    ),

    function_type: $ => seq(
      '(',
      commaSep($.type),
      ')',
      '->',
      $.type,
    ),

    // `{ x: f64, y: f64 }` and its Pass 100 spelling `@{ x: f64, y: f64 }`.
    // CLAUDE.md §0.4 names `@{ … }` as the descriptor form; 25 tracked files
    // open a record with it and this grammar had no `@` here at all.
    record_type: $ => seq(
      optional('@'),
      '{',
      commaSep1($.record_field),
      '}',
    ),

    record_field: $ => seq(
      $.identifier,
      ':',
      $.type,
    ),

    // ── Expressions ─────────────────────────────────────────────────────────

    expression: $ => choice(
      $.nil,
      $.boolean,
      $.number,
      $.string,
      $.vararg,
      $.identifier,
      $.binary_expression,
      $.unary_expression,
      $.function_expression,
      $.function_value_expression,
      $.table_constructor,
      $.descriptor_constructor,
      $.attribute,
      $.field_projection,
      $.index_expression,
      $.field_expression,
      $.call_expression,
      $.method_call_expression,
      $.try_expression,
      $.unwrap_expression,
      $.match_expression,
      $.await_expression,
      $.contains_expression,
      $.parenthesized_expression,
    ),

    nil: $ => 'nil',

    boolean: $ => choice('true', 'false'),

    number: $ => choice(
      $.integer,
      $.float,
    ),

    integer: $ => token(choice(
      /[0-9]+/,
      /0x[0-9a-fA-F]+/,
    )),

    float: $ => token(choice(
      /[0-9]+\.[0-9]+([eE][+-]?[0-9]+)?/,
      /[0-9]+[eE][+-]?[0-9]+/,
    )),

    string: $ => choice(
      $.double_quoted_string,
      $.single_quoted_string,
      $.long_string,
    ),

    double_quoted_string: $ => token(seq(
      '"',
      repeat(choice(
        /[^"\\]+/,
        /\\./,
      )),
      '"',
    )),

    single_quoted_string: $ => token(seq(
      "'",
      repeat(choice(
        /[^'\\]+/,
        /\\./,
      )),
      "'",
    )),

    // The body was `/[^]]*/` — "no `]` at all" — so a long string containing
    // an index expression (`a[i]`) or a C statement ended at the first `]` and
    // took the rest of the file with it. A `]` is body text unless the NEXT
    // character is also `]`, which is the closing delimiter. Stated as an
    // alternation rather than a lookahead because tree-sitter's token DFA has
    // none; it stays non-greedy across two long strings in one file precisely
    // because `]]` can never be consumed as body.
    long_string: $ => token(seq(
      '[',
      repeat('='),
      '[',
      repeat(choice(/[^\]]/, seq(']', /[^\]]/))),
      ']',
      repeat('='),
      ']',
    )),

    vararg: $ => '...',

    identifier: $ => /[a-zA-Z_][a-zA-Z0-9_]*/,

    // ── Binary operators ────────────────────────────────────────────────────

    binary_expression: $ => choice(
      prec.left(11, seq($.expression, 'or', $.expression)),
      prec.left(10, seq($.expression, 'and', $.expression)),
      prec.left(9, seq($.expression, '<', $.expression)),
      prec.left(9, seq($.expression, '>', $.expression)),
      prec.left(9, seq($.expression, '<=', $.expression)),
      prec.left(9, seq($.expression, '>=', $.expression)),
      prec.left(9, seq($.expression, '~=', $.expression)),
      // `!=` is the SAME token as `~=` in src/lexer.zig (both lex to `.neq`),
      // and it is the spelling 271 tracked files actually use. Without it
      // `a != nil` lexed as an unwrap_expression `a!` followed by `= nil`.
      prec.left(9, seq($.expression, '!=', $.expression)),
      prec.left(9, seq($.expression, '==', $.expression)),
      prec.left(9, seq($.expression, 'in', $.expression)),
      prec.left(8, seq($.expression, '|', $.expression)),
      // `&` (amp) and binary `~` (xor) are in the lexer's token table and were
      // not in this one; `|` alone was.
      prec.left(8, seq($.expression, '&', $.expression)),
      prec.left(8, seq($.expression, '~', $.expression)),
      prec.left(8, seq($.expression, '<<', $.expression)),
      prec.left(8, seq($.expression, '>>', $.expression)),
      prec.left(3, seq($.expression, '|>', $.expression)),
      prec.left(7, seq($.expression, '..', $.expression)),
      prec.left(6, seq($.expression, '+', $.expression)),
      prec.left(6, seq($.expression, '-', $.expression)),
      prec.left(5, seq($.expression, '*', $.expression)),
      prec.left(5, seq($.expression, '/', $.expression)),
      prec.left(5, seq($.expression, '//', $.expression)),
      prec.left(5, seq($.expression, '%', $.expression)),
      prec.right(4, seq($.expression, '^', $.expression)),
    ),

    // ── Unary operators ─────────────────────────────────────────────────────

    unary_expression: $ => choice(
      prec(7, seq('not', $.expression)),
      prec(7, seq('#', $.expression)),
      prec(7, seq('##', $.expression)),
      prec(7, seq('comptime', $.expression)),
      prec(7, seq('-', $.expression)),
      prec(7, seq('~', $.expression)),
    ),

    // ── Function expression ─────────────────────────────────────────────────

    function_expression: $ => seq(
      choice('function', 'fun'),
      '(',
      commaSep($.parameter),
      optional(seq(',', '...')),
      ')',
      optional(seq($._result_arrow, $.type)),
      repeat($.statement),
      'end',
    ),

    // ── Function value (the VALUE form of GR-001) ───────────────────────────
    //
    // `main = (): i64 … end`, `sum = (a: i64, b: i64): i64 … end`. Same
    // annotation requirement as the bare declaration, and for the same reason:
    // without it `x = (a) f() end` is indistinguishable from a parenthesised
    // expression followed by two more statements.
    function_value_expression: $ => seq(
      $._annotated_signature,
      repeat($.statement),
      'end',
    ),

    // ── Table constructor ───────────────────────────────────────────────────

    table_constructor: $ => seq(
      '{',
      commaSep(choice(
        seq($.identifier, '=', $.expression),
        seq('[', $.expression, ']', '=', $.expression),
        $.expression,
      )),
      optional(','),
      '}',
    ),

    // ── Field projection / method reference ─────────────────────────────────
    //
    // `has(.err)(r)`, `map(users, .name)`, `t:sort(.key)`,. A leading `.` in VALUE
    // position names a field of whatever the receiver turns out to be —
    // CLAUDE.md §0 spells `t:sort(.key)` as canonical. 35 tracked files use it
    // and this grammar could only see `.` as a field access on a preceding
    // expression.
    // Lowest precedence of anything that can consume a `.`: wherever the dot
    // could extend a dotted NAME or attach to the expression on its left, it
    // does, and a projection is only what is left over in value position.
    field_projection: $ => prec(-1, seq('.', $.identifier)),

    // ── Descriptor constructor ──────────────────────────────────────────────
    //
    // `@{ eof = 0, ident = 1 }` and the update form `@{ ..self, x = nx }`.
    // Field TYPES (`@{ kind: i64 }`) are not here: that spelling only occurs
    // in type position, where `record_type` now carries the same `@`.
    descriptor_constructor: $ => seq(
      '@',
      '{',
      commaSep(choice(
        seq($.identifier, '=', $.expression),
        seq('[', $.expression, ']', '=', $.expression),
        seq('..', $.expression),
        $.expression,
      )),
      optional(','),
      '}',
    ),

    // ── Postfix expressions ─────────────────────────────────────────────────

    index_expression: $ => seq(
      $.expression,
      '[',
      $.expression,
      ']',
    ),

    // Higher precedence than starting a new statement with a
    // `field_projection`: a `.` that CAN attach to the expression on its left
    // always does. `f(x)\n.y` is a field access, not two statements.
    field_expression: $ => prec(1, seq(
      $.expression,
      '.',
      $.identifier,
    )),

    // The dynamic precedence is what makes a `(` following an expression
    // ATTACH as a call. Without it `if f(x) …` read its condition as the bare
    // `f` and made `(x)` a separate statement — a wrong tree with no ERROR
    // node, so nothing counted it. Pre-existing; fixed here because the same
    // ambiguity governs the two sugar forms below.
    //
    // `req "std.os"` and `nn { … }` are Lua's argument sugar: a single string
    // or table literal may be passed without parentheses. 95 tracked files use
    // the string form, and every one of them was parsing as two unrelated
    // statements rather than as an error, so this is a correctness repair that
    // the recognition count could not see.
    call_expression: $ => prec.dynamic(1, seq(
      $.expression,
      choice(
        seq('(', commaSep($.expression), ')'),
        $.string,
        $.table_constructor,
      ),
    )),

    method_call_expression: $ => seq(
      $.expression,
      ':',
      $.identifier,
      '(',
      commaSep($.expression),
      ')',
    ),

    // ── Try/unwrap expressions ──────────────────────────────────────────────

    try_expression: $ => seq(
      $.expression,
      '?',
    ),

    unwrap_expression: $ => seq(
      $.expression,
      '!',
    ),

    // ── Match expression ────────────────────────────────────────────────────

    match_expression: $ => seq(
      'match',
      $.expression,
      repeat($.match_arm),
      'end',
    ),

    // ── Await expression ────────────────────────────────────────────────────

    await_expression: $ => seq(
      'await',
      $.expression,
    ),

    // ── Contains expression ─────────────────────────────────────────────────

    contains_expression: $ => seq(
      $.expression,
      'in',
      $.expression,
    ),

    // ── Parenthesized ───────────────────────────────────────────────────────

    parenthesized_expression: $ => seq(
      '(',
      $.expression,
      ')',
    ),

    // ── Comments ────────────────────────────────────────────────────────────

    comment: $ => token(choice(
      seq('--', /[^\n]*/),
      seq('--', '[', repeat('='), '[',
          repeat(choice(/[^\]]/, seq(']', /[^\]]/))),
          ']', repeat('='), ']'),
    )),
  },
});

// ── Helpers ──────────────────────────────────────────────────────────────────

function commaSep(rule) {
  return optional(commaSep1(rule));
}

function commaSep1(rule) {
  return seq(rule, repeat(seq(',', rule)));
}
