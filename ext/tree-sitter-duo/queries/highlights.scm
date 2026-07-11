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
  "break"
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
  "async"
  "await"
  "enum"
  "concept"
  "alias"
  "extends"
  "private"
  "comptime"
  "type"
] @keyword

; ── Type keywords ─────────────────────────────────────────────────────────────

[
  "i8" "i16" "i32" "i64"
  "u8" "u16" "u32" "u64"
  "f32" "f64"
  "bool" "void" "str"
] @type.builtin

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
  "," "." ":" "::" ";"
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
    "<<" ">>" "|" "~" "in"
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
