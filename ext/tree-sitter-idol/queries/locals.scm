; Locals for Duo

(function_declaration) @local.scope
(function_expression) @local.scope
(do_block) @local.scope
(if_statement) @local.scope
(while_loop) @local.scope
(repeat_loop) @local.scope
(numeric_for) @local.scope
(generic_for) @local.scope
(try_statement) @local.scope
(match_statement) @local.scope

(local_declaration
  (binding_name
    (identifier) @local.definition))

(const_declaration
  (identifier) @local.definition)

(parameter
  (identifier) @local.definition)

(numeric_for
  (identifier) @local.definition)

(generic_for
  (identifier) @local.definition)

(identifier) @local.reference
