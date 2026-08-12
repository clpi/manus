import os
import subprocess
import glob

# Files to rename
renames = {
    "src/duo_lexer_bridge.zig": "src/lexer_bridge.zig",
    "src/duo_keyword_bridge.zig": "src/keyword_bridge.zig",
    "src/duo_lexer_dispatch.zig": "src/lexer_dispatch.zig",
    "src/duo_native_ir.zig": "src/native_ir.zig",
    "src/duo_module_names.zig": "src/module_names.zig",
    "src/duo_lexer_tokenize.c": "src/lexer_tokenize.c",
    "src/duo_keyword_classify.c": "src/keyword_classify.c"
}

# Perform mv
for old, new in renames.items():
    if os.path.exists(old):
        try:
            subprocess.run(["git", "mv", old, new], check=True, capture_output=True)
        except subprocess.CalledProcessError:
            subprocess.run(["mv", old, new], check=True)

# Replace in files
files_to_check = glob.glob("src/*.zig") + glob.glob("src/*.c") + ["build.zig"]

for path in files_to_check:
    with open(path, 'r') as f:
        content = f.read()
    
    new_content = content
    for old, new in renames.items():
        old_name = os.path.basename(old)
        new_name = os.path.basename(new)
        new_content = new_content.replace(old_name, new_name)
        # also replace without extension for imports
        old_stem = os.path.splitext(old_name)[0]
        new_stem = os.path.splitext(new_name)[0]
        # Only replace if surrounded by quotes or similar to avoid partial matches
        new_content = new_content.replace(f'"{old_stem}"', f'"{new_stem}"')
        new_content = new_content.replace(f'@{old_stem}', f'@{new_stem}')
        
    if new_content != content:
        with open(path, 'w') as f:
            f.write(new_content)
        print(f"Updated {path}")
