import os
import re

# 1. codegen.zig
with open("src/codegen.zig", "r") as f:
    codegen = f.read()

# Remove import
codegen = re.sub(r'const native_req_support = @import\("native_req_support\.zig"\);\n', '', codegen)
# Remove req_ctx field
codegen = re.sub(r'    req_ctx: \?native_req_support\.Context = null,\n', '', codegen)
# Remove init logic
codegen = re.sub(r'        const old_req_ctx = self\.req_ctx;\n', '', codegen)
codegen = re.sub(r'        self\.req_ctx = native_req_support\.collectFromModule\(self\.alloc, mod\) catch null;\n', '', codegen)
codegen = re.sub(r'            if \(self\.req_ctx\) \|\*rc\| rc\.deinit\(self\.alloc\);\n', '', codegen)
codegen = re.sub(r'            self\.req_ctx = old_req_ctx;\n', '', codegen)

# Remove emitReqQualifiedCall
emitReq_pattern = r'    /// Emit `Alias\.fn\(args\)`.*?fn emitReqQualifiedCall.*?return true;\n    }\n'
codegen = re.sub(emitReq_pattern, '', codegen, flags=re.DOTALL)
# Remove call to emitReqQualifiedCall
codegen = re.sub(r'            if \(try self\.emitReqQualifiedCall\(c\)\) return;\n', '', codegen)

with open("src/codegen.zig", "w") as f:
    f.write(codegen)
    
# 2. dnir_lower.zig
with open("src/dnir_lower.zig", "r") as f:
    dnir = f.read()

dnir = re.sub(r'const native_req_support = @import\("native_req_support\.zig"\);\n', '', dnir)
dnir = re.sub(r'    var req = try native_req_support\.collectFromModule\(alloc, mod\);\n    defer req\.deinit\(alloc\);\n', '', dnir)
dnir = re.sub(r'    req: \*const native_req_support\.Context,\n', '', dnir)
dnir = re.sub(r'            &req,\n', '', dnir)
dnir = re.sub(r'        \.req = req,\n', '', dnir)
dnir = re.sub(r'                if \(ctx\.req\.exportSymbolByPath\(ctx\.alloc, pbuf\.items, f\.field\)\) \|sym\| {\n                    return emitForeignCall\(ctx, f\.field, sym, c\.args, res\);\n                }\n', '', dnir)
dnir = re.sub(r'            if \(ctx\.req\.exportSymbol\(f\.obj\.name\.ident, f\.field\)\) \|sym\| {\n                return emitForeignCall\(ctx, f\.field, sym, c\.args, res\);\n            }\n', '', dnir)
dnir = re.sub(r'        if \(ctx\.req\.constant\(fld\.obj\.name\.ident, fld\.field\)\) \|val\| {\n            return emitConstScalar\(ctx, val, dnir\.ResolvedType\.i64, res\);\n        }\n', '', dnir)

with open("src/dnir_lower.zig", "w") as f:
    f.write(dnir)

# 3. main.zig
with open("src/main.zig", "r") as f:
    main_zig = f.read()

main_zig = re.sub(r'const native_req_support = @import\("native_req_support\.zig"\);\n', '', main_zig)

# Remove spliceReqModules
spliceReq_pattern = r'/// `double\(\)` by bare name,.*?fn spliceReqModules.*?return added\.items\.len;\n}\n'
main_zig = re.sub(spliceReq_pattern, '', main_zig, flags=re.DOTALL)
# Remove usage of spliceReqModules
main_zig = re.sub(r'                    const spliced = spliceReqModules\(alloc, io, &ps\.mod\) catch 0;\n', '                    const spliced: usize = 0;\n', main_zig)
main_zig = re.sub(r'    var req = native_req_support\.collectFromModule\(alloc, mod\) catch return inputs\.toOwnedSlice\(alloc\);\n    defer req\.deinit\(alloc\);\n    req\.exportingModuleSources\(alloc, &sources\) catch return inputs\.toOwnedSlice\(alloc\);\n', '', main_zig)

with open("src/main.zig", "w") as f:
    f.write(main_zig)

print("Removed native_req_support from codegen.zig, dnir_lower.zig, main.zig")
