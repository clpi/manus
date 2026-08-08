; Highlights for Duo

; ── Keywords ──────────────────────────────────────────────────────────────────

[
  "local"
  "global"
  "const"
  "function"
  "fun"
  "end"
  "return"
  "goto"
  "do"
  "if"
  "then"
  "else"
  "elseif"
  "while"
  "repeat"
  "until"
  "for"
  "in"
] @keyword

[
  "and"
  "or"
  "not"
  "in"
] @keyword.operator

[
  "match"
  "case"
  "catch"
  "try"
  "defer"
  "await"
  "enum"
  "concept"
  "alias"
  "extends"
  "private"
  "comptime"
  "type"
] @keyword

; ── Types ─────────────────────────────────────────────────────────────────────
;
; `i64` / `str` / `void` are not tokens in this grammar — they are ordinary
; identifiers reaching `named_type`, which the rule below already covers.

(named_type) @type
(generic_type) @type
(array_type) @type
(pointer_type) @type
(optional_type) @type
(function_type) @type
(record_type) @type

; ── Literals ──────────────────────────────────────────────────────────────────

(nil) @constant.builtin
(boolean) @boolean
(integer) @number
(float) @float

(double_quoted_string) @string
(single_quoted_string) @string
(long_string) @string

(vararg) @punctuation.special

; ── Identifiers ───────────────────────────────────────────────────────────────

(identifier) @variable

; ── Function definitions ─────────────────────────────────────────────────────

(function_declaration
  name: (function_name) @function)

(function_expression) @function

; GR-001, the canonical declaration form, and its value and bodyless spellings.
(bare_function_declaration
  name: (function_name) @function)

(foreign_declaration
  name: (function_name) @function)

(function_value_expression) @function

(break_statement) @keyword
(empty_statement) @punctuation.delimiter
(shebang) @comment
(field_projection
  "." @punctuation.special
  (identifier) @property)
(descriptor_constructor
  "@" @punctuation.special)
(type_parameter
  (identifier) @type)

; ── Parameters ────────────────────────────────────────────────────────────────

(parameter
  (identifier) @parameter)

; ── Types in annotations ─────────────────────────────────────────────────────

(binding_name
  type: (type) @type)

(parameter
  type: (type) @type)

; ── Attributes ────────────────────────────────────────────────────────────────

(attribute
  "@" @punctuation.special
  (identifier) @attribute)

; ── Punctuation ───────────────────────────────────────────────────────────────

[
  "(" ")" "[" "]" "{" "}"
] @punctuation.bracket

[
  "," "." ":" "::"
] @punctuation.delimiter

; ── Operators ─────────────────────────────────────────────────────────────────

[
  "+" "-" "*" "/" "%" "^" "#"
  "&" "~" "|" "<<" ">>"
  "=="
] @operator

(binary_expression
  [
    "and" "or" "<" ">" "<=" ">=" "~=" "=="
    "+" "-" "*" "/" "//" "%" "^" ".."
    "<<" ">>" "|" "&" "~" "!=" "|>" "in"
  ] @operator)

(compound_assignment
  [
    "+=" "-=" "*=" "/=" "%=" "^="
  ] @operator)

(unary_expression
  [
    "not" "#" "-" "~"
  ] @operator)

; ── Field access ──────────────────────────────────────────────────────────────

(field_expression
  "."
  (identifier) @property)

(table_constructor
  (identifier) @property)

(table_pattern_entry
  (identifier) @property)

; ── Enum / Concept names ─────────────────────────────────────────────────────

(enum_definition
  (identifier) @type)

(enum_variant
  (identifier) @constant)

(concept_definition
  (identifier) @type)

(alias_definition
  (identifier) @type)

; ── Labels ────────────────────────────────────────────────────────────────────

(label_statement
  (identifier) @label)

(goto_statement
  (identifier) @label)

; ── Patterns ──────────────────────────────────────────────────────────────────

(binding_pattern
  (identifier) @variable)

(rest_pattern
  (identifier) @variable)

"_" @variable.builtin

; ── Comments ──────────────────────────────────────────────────────────────────

(comment) @comment @spell

; ── Compile-time / Metaprogramming ───────────────────────────────────────────

; @(expr) — compile-time evaluation
; @inline, @hot, @cold, @raw, @packed — compiler directives
; @derive(...) — type attributes
; @c.include, @c.emit, @c.export — C interface
; @device, @autodiff — ML/hardware directives
(attribute) @attribute

; ## prefix for comptime (legacy, still supported)
"##" @keyword.operator

; `@name(...)` needs no separate pattern: it IS an `attribute`, captured above.
