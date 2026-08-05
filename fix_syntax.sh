sed -i '' 's/if (has_literal_arg) return false;/if (has_literal_arg and !typed_or_vararg) return false;/' src/parser.zig
