/**
 * @file Tree-sitter grammar for the Duo programming language.
 *
 * Duo is a Lua-like language with optional static typing that compiles to
 * native C and WebAssembly.
 *
 * Based on the lexer tokens from src/lexer.zig and AST from src/ast.zig.
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

    attribute: $ => seq(
      '@',
      $.identifier,
      optional(seq('(', $.attribute_args, ')')),
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
      'then',
      repeat($.statement),
      repeat($.elseif_clause),
      optional($.else_clause),
      'end',
    ),

    elseif_clause: $ => seq(
      'elseif',
      $.expression,
      'then',
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
      'do',
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
      'do',
      repeat($.statement),
      'end',
    ),

    // ── Generic for ─────────────────────────────────────────────────────────

    generic_for: $ => seq(
      'for',
      commaSep1($.identifier),
      'in',
      commaSep1($.expression),
      'do',
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

    return_statement: $ => seq(
      'return',
      optional(commaSep1($.expression)),
    ),

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
