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
 * never authored)". These 90 rules are hand-written, so this file is a live
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
 * Second reason it cannot simply be regenerated: the rules below still spell a
 * PRE-PASS-100 surface — match / enum / try / catch / concept / optional types
 * / local / const / function — every one of which CLAUDE.md §1 denies by name.
 * Projecting this file from Pass 100 descriptors would change which programs
 * the editors recognise, which is a language decision downstream of GAP-025.
 *
 * It BUILDS again as of 2026-08-08. It did not before: `tree-sitter generate`
 * exited 1 on an unresolved conflict on `return_statement` ('return' • '(' —
 * an argument list versus a bare `return` followed by a parenthesised
 * statement), and the tracked `src/grammar.json` beside this file was NOT a
 * usable fallback: regenerating from that JSON alone fails with the identical
 * conflict, so no editor on this tree had a working parser at all. The repair
 * is `prec.right` on `return_statement` plus the 36 `conflicts:` entries
 * below, each one proven necessary by dropping it and re-running the generator.
 *
 * What it recognises, MEASURED rather than assumed, now that a parser exists:
 * 75 of 748 tracked `.duo` files parse without an ERROR node — 10 %. 423 of
 * the 673 failures are one rule this file does not have: the BARE function
 * declaration `fib(n: any)` / `_env_or(n: str, d: str): str` (GR-001), which
 * is the canonical Pass 100 form. Adding it is the language decision GAP-049
 * defers to the descriptor work, not a bug fix, so it is recorded rather than
 * patched here.
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
  // 36 are still required for it to exit 0. See gaps/GAP-049.
  conflicts: $ => [
    // statement head vs expression statement
    [$.jai_type_definition, $.typed_binding, $.expression],
    [$.struct_definition, $.expression],
    [$.typed_binding, $.call_expression],
    [$.assignment, $.call_expression],
    [$.local_declaration, $.call_expression],
    [$.const_declaration, $.call_expression],
    [$.global_declaration, $.call_expression],
    [$.return_statement, $.call_expression],
    [$.repeat_loop, $.call_expression],
    [$.expression_statement, $.call_expression],
    [$.call_expression, $.parenthesized_expression],
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
    [$.field_expression, $.await_expression],
    [$.index_expression, $.await_expression],
    [$.method_call_expression, $.await_expression],
    [$.try_expression, $.await_expression],
    [$.unwrap_expression, $.await_expression],
  ],

  // ── Rules ──────────────────────────────────────────────────────────────────

  rules: {
    // ── Top-level ───────────────────────────────────────────────────────────

    module: $ => seq(
      repeat($.statement),
    ),

    // ── Statements ──────────────────────────────────────────────────────────

    statement: $ => choice(
      $.local_declaration,
      $.const_declaration,
      $.global_declaration,
      $.assignment,
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
    ),

    // ── Attributes ──────────────────────────────────────────────────────────

    attribute: $ => choice(
      // @name or @name(args)
      seq('@', $.identifier, optional(seq('(', $.attribute_args, ')'))),
      // @c.include("header.h"), @c.emit("code"), @c.export("name")
      seq('@', $.identifier, '.', $.identifier, optional(seq('(', $.attribute_args, ')'))),
      // @(expr) — compile-time evaluation
      seq('@', '(', $.expression, ')'),
    ),

    attribute_args: $ => /[^)]*/,

    _attribute_list: $ => repeat1($.attribute),

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
      optional(seq(':', $.type)),
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
      $.function_name,
      optional(seq('<', commaSep1($.type), '>')),
      '(',
      commaSep($.parameter),
      optional(seq(',', '...')),
      ')',
      optional(seq(':', $.type)),
      repeat($.statement),
      'end',
    ),

    function_name: $ => seq(
      $.identifier,
      repeat(seq('.', $.identifier)),
      optional(seq(':', $.identifier)),
    ),

    parameter: $ => seq(
      optional($._attribute_list),
      $.identifier,
      optional(seq(':', $.type)),
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
      optional(seq('<', commaSep1($.type), '>')),
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
      optional(seq('<', commaSep1($.type), '>')),
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
      ':',
      $.type,
    ),

    concept_field: $ => seq(
      $.identifier,
      ':',
      $.type,
    ),

    // ── Alias definition ────────────────────────────────────────────────────

    alias_definition: $ => seq(
      optional($._attribute_list),
      'alias',
      $.identifier,
      optional(seq('extends', $.identifier)),
      repeat($.alias_member),
      'end',
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

    array_type: $ => seq(
      '[',
      optional($.number),
      ']',
      $.type,
    ),

    pointer_type: $ => seq(
      '*',
      $.type,
    ),

    optional_type: $ => seq(
      '?',
      $.type,
    ),

    generic_type: $ => seq(
      $.identifier,
      '<',
      commaSep1($.type),
      '>',
    ),

    function_type: $ => seq(
      '(',
      commaSep($.type),
      ')',
      '->',
      $.type,
    ),

    record_type: $ => seq(
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
      $.table_constructor,
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

    long_string: $ => token(seq(
      '[',
      repeat('='),
      '[',
      /[^]]*/,
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
      prec.left(9, seq($.expression, '==', $.expression)),
      prec.left(9, seq($.expression, 'in', $.expression)),
      prec.left(8, seq($.expression, '|', $.expression)),
      prec.left(8, seq($.expression, '<<', $.expression)),
      prec.left(8, seq($.expression, '>>', $.expression)),
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
      optional(seq(':', $.type)),
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

    // ── Postfix expressions ─────────────────────────────────────────────────

    index_expression: $ => seq(
      $.expression,
      '[',
      $.expression,
      ']',
    ),

    field_expression: $ => seq(
      $.expression,
      '.',
      $.identifier,
    ),

    call_expression: $ => seq(
      $.expression,
      '(',
      commaSep($.expression),
      ')',
    ),

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
      seq('--', '[', repeat('='), '[', /[^]]*/, ']', repeat('='), ']'),
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
