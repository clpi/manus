; Tags for Duo (used by code navigation)

(function_declaration
  name: (function_name) @definition.function)

; GR-001 — the form most Duo functions are actually written in.
(bare_function_declaration
  name: (function_name) @definition.function)

(foreign_declaration
  name: (function_name) @definition.function)

(function_expression
  ) @definition.function

(local_declaration
  (binding_name
    (identifier) @definition.var))

(const_declaration
  (identifier) @definition.var)

(parameter
  (identifier) @definition.parameter)

(enum_definition
  (identifier) @definition.type)

(concept_definition
  (identifier) @definition.type)

(alias_definition
  (identifier) @definition.type)

(call_expression
  (expression
    (identifier) @reference.function))

(field_expression
  (identifier) @reference.property)
