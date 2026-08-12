import glob
import re

files = [
    "src/emit_grammar_role.zig",
    "src/lexer_differential.zig",
    "src/main.zig",
    "src/semantic_context.zig",
    "src/wasm_decode_semantic.zig"
]

for file in files:
    with open(file, "r") as f:
        content = f.read()
    
    # Replace lib/std/ with lib/
    new_content = content.replace('"lib/std/', '"lib/')
    
    if new_content != content:
        with open(file, "w") as f:
            f.write(new_content)
        print(f"Updated {file}")
