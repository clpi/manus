import re
with open("src/main.zig", "r") as f:
    main_zig = f.read()

pattern = r'    var req = native_req_support\.collectFromModule.*?return inputs\.toOwnedSlice\(alloc\);\n\}'
main_zig = re.sub(pattern, '    return inputs.toOwnedSlice(alloc);\n}', main_zig, flags=re.DOTALL)

with open("src/main.zig", "w") as f:
    f.write(main_zig)

print("Cleaned main.zig")
