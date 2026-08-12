import glob

# Files to process
files_to_check = glob.glob("src/*.zig") + glob.glob("src/*.c") + ["build.zig"]

for path in files_to_check:
    with open(path, 'r') as f:
        content = f.read()
    
    new_content = content
    
    # Fix missed `duo_` imports variables
    new_content = new_content.replace('duo_lexer_bridge', 'lexer_bridge')
    new_content = new_content.replace('duo_lexer_dispatch', 'lexer_dispatch')
    new_content = new_content.replace('duo_native_ir', 'native_ir')
    new_content = new_content.replace('duo_module_names', 'module_names')
    new_content = new_content.replace('duo_keyword_bridge', 'keyword_bridge')
    
    # Remove `.duo` acceptance from `lexer_bridge.zig`
    if path == "src/lexer_bridge.zig":
        new_content = new_content.replace('pub const HISTORICAL_SOURCE_SUFFIX = ".duo";\n', '')
        new_content = new_content.replace('    historical,\n', '')
        new_content = new_content.replace('    if (std.mem.endsWith(u8, path, HISTORICAL_SOURCE_SUFFIX)) {\n        return .{ .law = .idol, .provenance = .historical };\n    }\n', '')
        new_content = new_content.replace('    try std.testing.expectEqual(SourceProvenance.historical, historical.provenance);\n', '')
        new_content = new_content.replace('    const historical = sourceFacts("test.duo");\n', '')

    # Remove `SourceProvenance.historical` usages
    if path == "src/lexical_identity.zig":
        new_content = new_content.replace('pub fn classifyHistoricalSingleQuote(provenance: SourceProvenance) LiteralKind {\n    return if (provenance == .canonical) .bytes else .compat_text;\n}\n', '')
        new_content = new_content.replace('    try std.testing.expect(backtickAllowed(sourceFacts("x.duo")));\n', '')
        new_content = new_content.replace('test "lexical identity: historical single quote is compatibility text" {\n    try std.testing.expectEqual(\n        LiteralKind.compat_text.tokenKind(),\n        classifyHistoricalSingleQuote(.historical).tokenKind(),\n    );\n}\n\n', '')
        new_content = new_content.replace('test "lexical identity: historical single quote stays compatibility text" {\n    const facts = sourceFacts("x.duo");\n    try std.testing.expectEqual(\n        LiteralKind.compat_text.tokenKind(),\n        classifyQuote(facts, \'\\\'\', false).?.tokenKind(),\n    );\n}\n\n', '')
        new_content = new_content.replace('    try std.testing.expect(hashOperatorAllowed(sourceFacts("x.duo")));\n', '')

    if path == "src/build_framework.zig":
        new_content = new_content.replace('const historical = family.HISTORICAL_SOURCE_SUFFIX;\n', '')
        new_content = new_content.replace('    "build" ++ historical,\n', '')
        new_content = new_content.replace('    "src/build" ++ historical,\n', '')

    if path == "src/codegen.zig":
        new_content = new_content.replace('            "{s}/{s}" ++ lexer_bridge.HISTORICAL_SOURCE_SUFFIX,\n', '')
        new_content = new_content.replace('            "{s}/{s}/init" ++ lexer_bridge.HISTORICAL_SOURCE_SUFFIX,\n', '')

    if path == "src/native_req_support.zig":
        new_content = new_content.replace('    source_family.HISTORICAL_SOURCE_SUFFIX,\n', '')
        new_content = new_content.replace('    try std.testing.expectEqual(source_family.SourceProvenance.historical, source_family.sourceFacts("module.duo").provenance);\n', '')

    if new_content != content:
        with open(path, 'w') as f:
            f.write(new_content)
        print(f"Updated {path}")
