import os
import re

def process_file(path):
    with open(path, 'r') as f:
        lines = f.readlines()
    
    out = []
    in_main = False
    main_indent = ""
    
    for i, line in enumerate(lines):
        original_line = line
        
        # Replace 'not' with '!' (but only as a whole word)
        # Avoid things like 'cannot', or strings if possible, but regex \bnot\b is decent.
        # Actually in Idol 'not' -> '!'
        line = re.sub(r'\bnot\b\s*', '!', line)
        
        # Replace string.char(10) with "\n"
        line = line.replace('string.char(10)', '"\\n"')
        
        # Check if this line is a main-like function definition at root level
        # Matches: main: i64 = (), main = (), etc.
        if not in_main:
            match = re.match(r'^(main|entry|init|runmain)(:\s*\w+)?\s*=\s*\(\)\s*$', original_line.strip())
            if match and not original_line.startswith(' ') and not original_line.startswith('\t'):
                in_main = True
                continue
        else:
            # We are inside the main wrapper
            # If we hit an 'end' at root level, we finish main
            if original_line.strip() == 'end' and not original_line.startswith('    ') and not original_line.startswith('\t'):
                in_main = False
                continue
            
            # If we hit a non-empty line that has NO indentation, it means the block ended
            # (assuming offside rule)
            if original_line.strip() and not original_line.startswith(' ') and not original_line.startswith('\t') and not original_line.startswith('#'):
                in_main = False
            else:
                # Un-indent by 4 spaces
                if line.startswith('    '):
                    line = line[4:]
                elif line.startswith('\t'):
                    line = line[1:]
        
        out.append(line)
        
    with open(path, 'w') as f:
        f.writelines(out)

for root, _, files in os.walk('.'):
    for name in files:
        if name.endswith('.id'):
            process_file(os.path.join(root, name))
print("Refactoring complete.")
