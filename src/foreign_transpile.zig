//! Cross-language snippet transpilation for `@foreign("lang", "code")`.
const std = @import("std");

pub const ForeignArgs = struct {
    lang: []const u8,
    code_raw: []const u8,
};

/// Parse `@foreign("lang", "code")` or `@foreign("lang", @run(...))` args text.
pub fn parseForeignArgs(raw: []const u8) ?ForeignArgs {
    if (findStringPair(raw)) |pair| {
        return .{ .lang = pair[0], .code_raw = pair[1] };
    }
    const trimmed = std.mem.trim(u8, raw, " \t\r\n()");
    if (trimmed.len < 3) return null;

    var i: usize = 0;
    while (i < trimmed.len and trimmed[i] != '"' and trimmed[i] != '\'') : (i += 1) {}
    if (i >= trimmed.len) return null;
    const quote = trimmed[i];
    i += 1;
    const lang_start = i;
    while (i < trimmed.len and trimmed[i] != quote) : (i += 1) {}
    if (i >= trimmed.len) return null;
    const lang = trimmed[lang_start..i];
    i += 1;
    while (i < trimmed.len and (trimmed[i] == ',' or trimmed[i] == ' ' or trimmed[i] == '\t')) : (i += 1) {}
    if (i >= trimmed.len) return null;
    return .{ .lang = lang, .code_raw = std.mem.trim(u8, trimmed[i..], " \t\r\n") };
}

pub fn findStringPair(raw: []const u8) ?[2][]const u8 {
    const trimmed = std.mem.trim(u8, raw, " \t\r\n()");
    if (trimmed.len < 5) return null;
    var i: usize = 0;
    while (i < trimmed.len and trimmed[i] != '"' and trimmed[i] != '\'') : (i += 1) {}
    if (i >= trimmed.len) return null;
    const quote = trimmed[i];
    i += 1;
    const lang_start = i;
    while (i < trimmed.len and trimmed[i] != quote) : (i += 1) {}
    if (i >= trimmed.len) return null;
    const lang = trimmed[lang_start..i];
    i += 1;
    while (i < trimmed.len and (trimmed[i] == ',' or trimmed[i] == ' ' or trimmed[i] == '\t')) : (i += 1) {}
    if (i >= trimmed.len or (trimmed[i] != '"' and trimmed[i] != '\'')) return null;
    const code_quote = trimmed[i];
    i += 1;
    const code_start = i;
    while (i < trimmed.len and trimmed[i] != code_quote) : (i += 1) {}
    if (i >= trimmed.len) return null;
    return .{ lang, trimmed[code_start..i] };
}

/// Expand `\n`, `\t`, `\r` escapes in foreign snippet text extracted from raw args.
pub fn unescapeSnippet(alloc: std.mem.Allocator, raw: []const u8) ![]const u8 {
    if (std.mem.indexOfScalar(u8, raw, '\\') == null) return try alloc.dupe(u8, raw);
    var buf = try alloc.alloc(u8, raw.len);
    var j: usize = 0;
    var i: usize = 0;
    while (i < raw.len) {
        if (raw[i] == '\\' and i + 1 < raw.len) {
            switch (raw[i + 1]) {
                'n' => {
                    buf[j] = '\n';
                    i += 2;
                    j += 1;
                },
                't' => {
                    buf[j] = '\t';
                    i += 2;
                    j += 1;
                },
                'r' => {
                    buf[j] = '\r';
                    i += 2;
                    j += 1;
                },
                '\\', '"' => {
                    buf[j] = raw[i + 1];
                    i += 2;
                    j += 1;
                },
                else => {
                    buf[j] = raw[i];
                    i += 1;
                    j += 1;
                },
            }
        } else {
            buf[j] = raw[i];
            i += 1;
            j += 1;
        }
    }
    return buf[0..j];
}

pub fn transpileForeign(alloc: std.mem.Allocator, lang: []const u8, code: []const u8) ![]const u8 {
    if (std.mem.eql(u8, lang, "python") or std.mem.eql(u8, lang, "py")) {
        return transpilePythonToC(alloc, code);
    }
    if (std.mem.eql(u8, lang, "zig")) {
        return transpileZigToC(alloc, code);
    }
    if (std.mem.eql(u8, lang, "rust") or std.mem.eql(u8, lang, "rs")) {
        return transpileRustToC(alloc, code);
    }
    if (std.mem.eql(u8, lang, "c") or std.mem.eql(u8, lang, "cpp")) {
        return alloc.dupe(u8, code);
    }
    if (std.mem.eql(u8, lang, "go") or std.mem.eql(u8, lang, "golang")) {
        return transpileGoToC(alloc, code);
    }
    if (std.mem.eql(u8, lang, "mojo")) {
        return transpileMojoToC(alloc, code);
    }
    if (std.mem.eql(u8, lang, "kotlin") or std.mem.eql(u8, lang, "kt")) {
        return transpileKotlinToC(alloc, code);
    }
    return error.UnsupportedLanguage;
}

fn zigTypeToC(t: []const u8) []const u8 {
    const trimmed = std.mem.trim(u8, t, " \t");
    if (std.mem.eql(u8, trimmed, "u8")) return "uint8_t";
    if (std.mem.eql(u8, trimmed, "u16")) return "uint16_t";
    if (std.mem.eql(u8, trimmed, "u32")) return "uint32_t";
    if (std.mem.eql(u8, trimmed, "u64")) return "uint64_t";
    if (std.mem.eql(u8, trimmed, "i8")) return "int8_t";
    if (std.mem.eql(u8, trimmed, "i16")) return "int16_t";
    if (std.mem.eql(u8, trimmed, "i32")) return "int32_t";
    if (std.mem.eql(u8, trimmed, "i64")) return "int64_t";
    if (std.mem.eql(u8, trimmed, "f32")) return "float";
    if (std.mem.eql(u8, trimmed, "f64")) return "double";
    if (std.mem.eql(u8, trimmed, "bool")) return "int";
    if (std.mem.eql(u8, trimmed, "void")) return "void";
    return trimmed;
}

fn rustTypeToC(t: []const u8) []const u8 {
    const trimmed = std.mem.trim(u8, t, " \t");
    if (std.mem.eql(u8, trimmed, "u8")) return "uint8_t";
    if (std.mem.eql(u8, trimmed, "u16")) return "uint16_t";
    if (std.mem.eql(u8, trimmed, "u32")) return "uint32_t";
    if (std.mem.eql(u8, trimmed, "u64")) return "uint64_t";
    if (std.mem.eql(u8, trimmed, "i8")) return "int8_t";
    if (std.mem.eql(u8, trimmed, "i16")) return "int16_t";
    if (std.mem.eql(u8, trimmed, "i32")) return "int32_t";
    if (std.mem.eql(u8, trimmed, "i64")) return "int64_t";
    if (std.mem.eql(u8, trimmed, "f32")) return "float";
    if (std.mem.eql(u8, trimmed, "f64")) return "double";
    if (std.mem.eql(u8, trimmed, "bool")) return "int";
    if (std.mem.eql(u8, trimmed, "usize")) return "size_t";
    if (std.mem.eql(u8, trimmed, "isize")) return "ssize_t";
    if (std.mem.startsWith(u8, trimmed, "&str")) return "const char*";
    return trimmed;
}

fn convertZigParams(params: []const u8, out: *std.ArrayListUnmanaged(u8), alloc: std.mem.Allocator) !void {
    if (params.len == 0) return;
    var first = true;
    var parts = std.mem.tokenizeScalar(u8, params, ',');
    while (parts.next()) |part| {
        const p = std.mem.trim(u8, part, " \t\n");
        if (p.len == 0) continue;
        if (!first) try out.appendSlice(alloc, ", ");
        if (std.mem.indexOfScalar(u8, p, ':')) |colon| {
            const name = std.mem.trim(u8, p[0..colon], " \t");
            const ty = std.mem.trim(u8, p[colon + 1 ..], " \t");
            try out.appendSlice(alloc, zigTypeToC(ty));
            try out.appendSlice(alloc, " ");
            try out.appendSlice(alloc, name);
        } else {
            try out.appendSlice(alloc, p);
        }
        first = false;
    }
}

/// Transform Zig body lines to C equivalents.
fn convertRustParams(params: []const u8, out: *std.ArrayListUnmanaged(u8), alloc: std.mem.Allocator) !void {
    if (params.len == 0) return;
    var first = true;
    var parts = std.mem.tokenizeScalar(u8, params, ',');
    while (parts.next()) |part| {
        const p = std.mem.trim(u8, part, " \t\n");
        if (p.len == 0) continue;
        if (!first) try out.appendSlice(alloc, ", ");
        if (std.mem.indexOfScalar(u8, p, ':')) |colon| {
            const name = std.mem.trim(u8, p[0..colon], " \t");
            const ty = std.mem.trim(u8, p[colon + 1 ..], " \t");
            try out.appendSlice(alloc, rustTypeToC(ty));
            try out.appendSlice(alloc, " ");
            try out.appendSlice(alloc, name);
        } else {
            try out.appendSlice(alloc, p);
        }
        first = false;
    }
}

fn zigBodyToC(body: []const u8, out: *std.ArrayListUnmanaged(u8), alloc: std.mem.Allocator) !void {
    var lines = std.mem.splitScalar(u8, body, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        const trimmed = std.mem.trim(u8, line, " \t");
        // `var x: type = expr;` → `type x = expr;`
        if (std.mem.startsWith(u8, trimmed, "var ")) {
            const rest = trimmed[4..];
            if (std.mem.indexOfScalar(u8, rest, ':')) |colon_pos| {
                const vname = std.mem.trim(u8, rest[0..colon_pos], " \t");
                const after_colon = std.mem.trim(u8, rest[colon_pos + 1 ..], " \t");
                if (std.mem.indexOfScalar(u8, after_colon, '=')) |eq_pos| {
                    const vtype = std.mem.trim(u8, after_colon[0..eq_pos], " \t");
                    const init = std.mem.trim(u8, after_colon[eq_pos + 1 ..], " \t");
                    const indent = line[0 .. line.len - trimmed.len];
                    try out.appendSlice(alloc, indent);
                    try out.appendSlice(alloc, zigTypeToC(vtype));
                    try out.append(alloc, ' ');
                    try out.appendSlice(alloc, vname);
                    try out.appendSlice(alloc, " = ");
                    try out.appendSlice(alloc, init);
                    try out.append(alloc, '\n');
                    continue;
                }
            }
        }
        // `const x: type = expr;` → `type x = expr;`
        if (std.mem.startsWith(u8, trimmed, "const ")) {
            if (std.mem.indexOfScalar(u8, trimmed[6..], ':')) |colon_rel| {
                const rest = trimmed[6..];
                const colon_pos = colon_rel;
                if (std.mem.indexOfScalar(u8, rest[colon_pos + 1 ..], '=')) |eq_rel| {
                    const eq_pos = colon_pos + 1 + eq_rel;
                    const vname = std.mem.trim(u8, rest[0..colon_pos], " \t");
                    const vtype = std.mem.trim(u8, rest[colon_pos + 1 .. eq_pos], " \t");
                    const init = std.mem.trim(u8, rest[eq_pos + 1 ..], " \t");
                    const indent = line[0 .. line.len - trimmed.len];
                    try out.appendSlice(alloc, indent);
                    try out.appendSlice(alloc, zigTypeToC(vtype));
                    try out.append(alloc, ' ');
                    try out.appendSlice(alloc, vname);
                    try out.appendSlice(alloc, " = ");
                    try out.appendSlice(alloc, init);
                    try out.append(alloc, '\n');
                    continue;
                }
            }
        }
        // Everything else: pass through
        try out.appendSlice(alloc, line);
        try out.append(alloc, '\n');
    }
}

fn transpileZigToC(alloc: std.mem.Allocator, code: []const u8) ![]const u8 {
    var result: std.ArrayListUnmanaged(u8) = .empty;
    errdefer result.deinit(alloc);
    try result.appendSlice(alloc, "/* [foreign.zig] */\n");

    var remaining: []const u8 = code;
    while (remaining.len > 0) {
        if (std.mem.indexOf(u8, remaining, "fn ")) |fn_pos| {
            if (fn_pos > 0) try result.appendSlice(alloc, remaining[0..fn_pos]);
            remaining = remaining[fn_pos + 3 ..];
            if (std.mem.indexOf(u8, remaining, "(")) |paren_pos| {
                const fname = std.mem.trim(u8, remaining[0..paren_pos], " \t\n");
                var depth: usize = 1;
                var i: usize = paren_pos + 1;
                while (i < remaining.len and depth > 0) {
                    if (remaining[i] == '(') depth += 1;
                    if (remaining[i] == ')') depth -= 1;
                    i += 1;
                }
                const after_params = std.mem.trim(u8, remaining[i..], " \t\n");
                if (std.mem.indexOf(u8, after_params, "{")) |brace_pos| {
                    const ret_type = std.mem.trim(u8, after_params[0..brace_pos], " \t\n");
                    try result.appendSlice(alloc, zigTypeToC(ret_type));
                    try result.appendSlice(alloc, " ");
                    try result.appendSlice(alloc, fname);
                    try result.appendSlice(alloc, "(");
                    try convertZigParams(std.mem.trim(u8, remaining[paren_pos + 1 .. i - 1], " \t\n"), &result, alloc);
                    try result.appendSlice(alloc, ") {\n");
                    remaining = after_params[brace_pos + 1 ..];
                    depth = 1;
                    i = 0;
                    while (i < remaining.len and depth > 0) {
                        if (remaining[i] == '{') depth += 1;
                        if (remaining[i] == '}') depth -= 1;
                        i += 1;
                    }
                    // Collect raw body, transform Zig→C, append
                    const raw_body = remaining[1 .. i - 1];
                    var body_buf: std.ArrayListUnmanaged(u8) = .empty;
                    try zigBodyToC(raw_body, &body_buf, alloc);
                    try result.appendSlice(alloc, body_buf.items);
                    body_buf.deinit(alloc);
                    remaining = remaining[i..];
                    try result.appendSlice(alloc, "}\n");
                } else break;
            } else break;
        } else {
            try result.appendSlice(alloc, remaining);
            break;
        }
    }
    return result.toOwnedSlice(alloc);
}

/// Transform Rust body lines to C equivalents.
fn rustBodyToC(body: []const u8, out: *std.ArrayListUnmanaged(u8), alloc: std.mem.Allocator) !void {
    var lines = std.mem.splitScalar(u8, body, '\n');
    var last_trimmed: []const u8 = "";
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        const trimmed = std.mem.trim(u8, line, " \t");
        // `let mut x: type = expr;` → `type x = expr;`
        if (std.mem.startsWith(u8, trimmed, "let mut ")) {
            const rest = trimmed[8..];
            if (std.mem.indexOfScalar(u8, rest, ':')) |colon_pos| {
                const vname = std.mem.trim(u8, rest[0..colon_pos], " \t");
                const after_colon = std.mem.trim(u8, rest[colon_pos + 1 ..], " \t");
                if (std.mem.indexOfScalar(u8, after_colon, '=')) |eq_pos| {
                    const vtype = std.mem.trim(u8, after_colon[0..eq_pos], " \t");
                    const init = std.mem.trim(u8, after_colon[eq_pos + 1 ..], " \t");
                    const indent = line[0 .. line.len - trimmed.len];
                    try out.appendSlice(alloc, indent);
                    try out.appendSlice(alloc, rustTypeToC(vtype));
                    try out.append(alloc, ' ');
                    try out.appendSlice(alloc, vname);
                    try out.appendSlice(alloc, " = ");
                    try out.appendSlice(alloc, init);
                    try out.append(alloc, '\n');
                    continue;
                }
            }
        }
        // `let x: type = expr;` → `type x = expr;`
        if (std.mem.startsWith(u8, trimmed, "let ")) {
            const rest = trimmed[4..];
            if (std.mem.indexOfScalar(u8, rest, ':')) |colon_pos| {
                const vname = std.mem.trim(u8, rest[0..colon_pos], " \t");
                const after_colon = std.mem.trim(u8, rest[colon_pos + 1 ..], " \t");
                if (std.mem.indexOfScalar(u8, after_colon, '=')) |eq_pos| {
                    const vtype = std.mem.trim(u8, after_colon[0..eq_pos], " \t");
                    const init = std.mem.trim(u8, after_colon[eq_pos + 1 ..], " \t");
                    const indent = line[0 .. line.len - trimmed.len];
                    try out.appendSlice(alloc, indent);
                    try out.appendSlice(alloc, rustTypeToC(vtype));
                    try out.append(alloc, ' ');
                    try out.appendSlice(alloc, vname);
                    try out.appendSlice(alloc, " = ");
                    try out.appendSlice(alloc, init);
                    try out.append(alloc, '\n');
                    continue;
                }
            }
        }
        // `let mut x = expr;` (no type annotation) → `auto x = expr;`
        if (std.mem.startsWith(u8, trimmed, "let mut ") and std.mem.indexOfScalar(u8, trimmed[8..], ':') == null) {
            // `let mut x = expr;` (no type) → pass through
            try out.appendSlice(alloc, line);
            try out.append(alloc, '\n');
            last_trimmed = trimmed;
            continue;
        }
        if (std.mem.startsWith(u8, trimmed, "let ") and std.mem.indexOfScalar(u8, trimmed[4..], ':') == null) {
            // `let x = expr;` (no type) → pass through
            try out.appendSlice(alloc, line);
            try out.append(alloc, '\n');
            last_trimmed = trimmed;
            continue;
        }
        // Rust `while cond {` → C `while (cond) {`
        if (std.mem.startsWith(u8, trimmed, "while ") and !std.mem.startsWith(u8, trimmed, "while (")) {
            if (std.mem.indexOf(u8, trimmed[6..], " {")) |brace_rel| {
                const cond = std.mem.trim(u8, trimmed[6 .. 6 + brace_rel], " \t");
                const indent = line[0 .. line.len - trimmed.len];
                try out.appendSlice(alloc, indent);
                try out.appendSlice(alloc, "while (");
                try out.appendSlice(alloc, cond);
                try out.appendSlice(alloc, ") {");
                try out.append(alloc, '\n');
                last_trimmed = trimmed;
                continue;
            }
        }
        // Bare expression (no keyword) before closing `}` → `return expr;`
        if (trimmed.len > 0 and trimmed[trimmed.len - 1] != ';' and trimmed[trimmed.len - 1] != '{' and trimmed[trimmed.len - 1] != '}' and
            !std.mem.startsWith(u8, trimmed, "if ") and !std.mem.startsWith(u8, trimmed, "while ") and
            !std.mem.startsWith(u8, trimmed, "for ") and !std.mem.startsWith(u8, trimmed, "let ") and
            !std.mem.startsWith(u8, trimmed, "auto ") and !std.mem.startsWith(u8, trimmed, "return ") and
            !std.mem.startsWith(u8, trimmed, "int") and !std.mem.startsWith(u8, trimmed, "void") and
            !std.mem.startsWith(u8, trimmed, "uint") and !std.mem.startsWith(u8, trimmed, "/*") and
            std.mem.indexOfScalar(u8, trimmed, '=') == null and std.mem.indexOfScalar(u8, trimmed, '+') == null and
            std.mem.indexOfScalar(u8, trimmed, '-') == null and std.mem.indexOfScalar(u8, trimmed, '*') == null and
            std.mem.indexOfScalar(u8, trimmed, '%') == null)
        {
            // Likely a bare return expression like Rust's trailing `a`
            const indent = line[0 .. line.len - trimmed.len];
            try out.appendSlice(alloc, indent);
            try out.appendSlice(alloc, "return ");
            try out.appendSlice(alloc, trimmed);
            try out.appendSlice(alloc, ";");
            try out.append(alloc, '\n');
            last_trimmed = trimmed;
            continue;
        }
        // Everything else: pass through
        try out.appendSlice(alloc, line);
        try out.append(alloc, '\n');
        last_trimmed = trimmed;
    }
}

fn transpileRustToC(alloc: std.mem.Allocator, code: []const u8) ![]const u8 {
    var result: std.ArrayListUnmanaged(u8) = .empty;
    errdefer result.deinit(alloc);
    try result.appendSlice(alloc, "/* [foreign.rust] */\n");

    var remaining: []const u8 = code;
    while (remaining.len > 0) {
        if (std.mem.indexOf(u8, remaining, "fn ")) |fn_pos| {
            if (fn_pos > 0) try result.appendSlice(alloc, remaining[0..fn_pos]);
            remaining = remaining[fn_pos + 3 ..];
            if (std.mem.indexOf(u8, remaining, "(")) |paren_pos| {
                const fname = std.mem.trim(u8, remaining[0..paren_pos], " \t\n");
                var depth: usize = 1;
                var i: usize = paren_pos + 1;
                while (i < remaining.len and depth > 0) {
                    if (remaining[i] == '(') depth += 1;
                    if (remaining[i] == ')') depth -= 1;
                    i += 1;
                }
                const after_params = std.mem.trim(u8, remaining[i..], " \t\n");
                if (std.mem.startsWith(u8, after_params, "->")) {
                    const rest = std.mem.trim(u8, after_params[2..], " \t");
                    if (std.mem.indexOf(u8, rest, "{")) |brace_pos| {
                        const ret_type = std.mem.trim(u8, rest[0..brace_pos], " \t\n");
                        try result.appendSlice(alloc, rustTypeToC(ret_type));
                        try result.appendSlice(alloc, " ");
                        try result.appendSlice(alloc, fname);
                        try result.appendSlice(alloc, "(");
                        try convertRustParams(std.mem.trim(u8, remaining[paren_pos + 1 .. i - 1], " \t\n"), &result, alloc);
                        try result.appendSlice(alloc, ") {\n");
                        remaining = rest[brace_pos + 1 ..];
                        depth = 1;
                        i = 0;
                        while (i < remaining.len and depth > 0) {
                            if (remaining[i] == '{') depth += 1;
                            if (remaining[i] == '}') depth -= 1;
                            i += 1;
                        }
                        const raw_body = remaining[0..i];
                        var body_buf: std.ArrayListUnmanaged(u8) = .empty;
                        try rustBodyToC(raw_body, &body_buf, alloc);
                        try result.appendSlice(alloc, body_buf.items);
                        body_buf.deinit(alloc);
                        remaining = remaining[i..];
                    } else break;
                } else break;
            } else break;
        } else {
            try result.appendSlice(alloc, remaining);
            break;
        }
    }
    return result.toOwnedSlice(alloc);
}

fn pythonIdentToC(name: []const u8) []const u8 {
    if (std.mem.eql(u8, name, "self")) return "self_";
    return name;
}

fn transpilePythonToC(alloc: std.mem.Allocator, code: []const u8) ![]const u8 {
    var result: std.ArrayListUnmanaged(u8) = .empty;
    errdefer result.deinit(alloc);
    try result.appendSlice(alloc, "/* [foreign.python] */\n");

    var remaining: []const u8 = code;
    while (std.mem.indexOf(u8, remaining, "def ")) |def_pos| {
        remaining = remaining[def_pos + 4 ..];
        const line_end = std.mem.indexOfScalar(u8, remaining, '\n') orelse remaining.len;
        const header = std.mem.trim(u8, remaining[0..line_end], " \t\r");
        remaining = if (line_end < remaining.len) remaining[line_end + 1 ..] else "";

        if (std.mem.indexOf(u8, header, "(")) |paren_pos| {
            const fname = pythonIdentToC(std.mem.trim(u8, header[0..paren_pos], " \t"));
            var depth: usize = 1;
            var i: usize = paren_pos + 1;
            while (i < header.len and depth > 0) {
                if (header[i] == '(') depth += 1;
                if (header[i] == ')') depth -= 1;
                i += 1;
            }
            const params_raw = std.mem.trim(u8, header[paren_pos + 1 .. i - 1], " \t");
            try result.appendSlice(alloc, "int64_t ");
            try result.appendSlice(alloc, fname);
            try result.appendSlice(alloc, "(");
            if (params_raw.len > 0) {
                var params = std.mem.tokenizeScalar(u8, params_raw, ',');
                var first = true;
                while (params.next()) |p| {
                    const param = std.mem.trim(u8, p, " \t");
                    if (param.len == 0) continue;
                    const name_end = std.mem.indexOfScalar(u8, param, ':') orelse param.len;
                    const pname = pythonIdentToC(std.mem.trim(u8, param[0..name_end], " \t"));
                    if (!first) try result.appendSlice(alloc, ", ");
                    try result.appendSlice(alloc, "int64_t ");
                    try result.appendSlice(alloc, pname);
                    first = false;
                }
            }
            try result.appendSlice(alloc, ") {\n");

            const body_end = std.mem.indexOf(u8, remaining, "\ndef ") orelse remaining.len;
            const body = remaining[0..body_end];
            remaining = remaining[body_end..];

            if (std.mem.indexOf(u8, body, "return ")) |ret_pos| {
                var expr = std.mem.trim(u8, body[ret_pos + 7 ..], " \t\r\n");
                if (std.mem.indexOfScalar(u8, expr, '\n')) |nl| expr = std.mem.trim(u8, expr[0..nl], " \t\r");
                try result.appendSlice(alloc, "    return ");
                try result.appendSlice(alloc, expr);
                try result.appendSlice(alloc, ";\n");
            }
            try result.appendSlice(alloc, "}\n");
        }
    }

    if (result.items.len == "/* [foreign.python] */\n".len) {
        try result.appendSlice(alloc, "/* no transpilable def/return found */\n");
    }
    return result.toOwnedSlice(alloc);
}

// transpileGoToC, transpileMojoToC, transpileKotlinToC are implemented
// below (full implementations).

// ── Go transpilation ──────────────────────────────────────────────────────────

fn goTypeToC(t: []const u8) []const u8 {
    const trimmed = std.mem.trim(u8, t, " \t");
    if (std.mem.eql(u8, trimmed, "int8")) return "int8_t";
    if (std.mem.eql(u8, trimmed, "int16")) return "int16_t";
    if (std.mem.eql(u8, trimmed, "int32")) return "int32_t";
    if (std.mem.eql(u8, trimmed, "int64")) return "int64_t";
    if (std.mem.eql(u8, trimmed, "uint8")) return "uint8_t";
    if (std.mem.eql(u8, trimmed, "uint16")) return "uint16_t";
    if (std.mem.eql(u8, trimmed, "uint32")) return "uint32_t";
    if (std.mem.eql(u8, trimmed, "uint64")) return "uint64_t";
    if (std.mem.eql(u8, trimmed, "float32")) return "float";
    if (std.mem.eql(u8, trimmed, "float64")) return "double";
    if (std.mem.eql(u8, trimmed, "bool")) return "int";
    if (std.mem.eql(u8, trimmed, "string")) return "const char*";
    if (std.mem.eql(u8, trimmed, "byte")) return "uint8_t";
    if (std.mem.eql(u8, trimmed, "rune")) return "int32_t";
    if (std.mem.eql(u8, trimmed, "uintptr")) return "uintptr_t";
    return trimmed;
}

fn convertGoParams(params: []const u8, out: *std.ArrayListUnmanaged(u8), alloc: std.mem.Allocator) !void {
    if (params.len == 0) return;
    var first = true;
    var parts = std.mem.splitScalar(u8, params, ',');
    while (parts.next()) |part| {
        const p = std.mem.trim(u8, part, " \t\n");
        if (p.len == 0) continue;
        if (!first) try out.appendSlice(alloc, ", ");
        // Go params can be: "name type" or "name1, name2 type"
        if (std.mem.indexOfScalar(u8, p, ' ')) |space_pos| {
            const before_space = std.mem.trim(u8, p[0..space_pos], " \t");
            const after_space = std.mem.trim(u8, p[space_pos + 1 ..], " \t");
            // Check if before_space contains commas (multiple names)
            if (std.mem.indexOfScalar(u8, before_space, ',') != null) {
                var names = std.mem.splitScalar(u8, before_space, ',');
                while (names.next()) |n| {
                    const name = std.mem.trim(u8, n, " \t");
                    if (name.len == 0) continue;
                    try out.appendSlice(alloc, goTypeToC(after_space));
                    try out.appendSlice(alloc, " ");
                    try out.appendSlice(alloc, name);
                    try out.appendSlice(alloc, ", ");
                }
                // Remove trailing ", "
                if (out.items.len >= 2) {
                    out.items.len -= 2;
                }
            } else {
                try out.appendSlice(alloc, goTypeToC(after_space));
                try out.appendSlice(alloc, " ");
                try out.appendSlice(alloc, before_space);
            }
        } else {
            try out.appendSlice(alloc, "int64_t ");
            try out.appendSlice(alloc, p);
        }
        first = false;
    }
}

fn goBodyToC(body: []const u8, out: *std.ArrayListUnmanaged(u8), alloc: std.mem.Allocator) !void {
    var lines = std.mem.splitScalar(u8, body, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        const trimmed = std.mem.trim(u8, line, " \t");
        // `var x type = expr` → `type x = expr;`
        if (std.mem.startsWith(u8, trimmed, "var ")) {
            const rest = trimmed[4..];
            if (std.mem.indexOfScalar(u8, rest, ' ')) |space_pos| {
                const vname = std.mem.trim(u8, rest[0..space_pos], " \t");
                const after_space = std.mem.trim(u8, rest[space_pos + 1 ..], " \t");
                if (std.mem.indexOfScalar(u8, after_space, '=')) |eq_pos| {
                    const vtype = std.mem.trim(u8, after_space[0..eq_pos], " \t");
                    const init = std.mem.trim(u8, after_space[eq_pos + 1 ..], " \t");
                    const indent = line[0 .. line.len - trimmed.len];
                    try out.appendSlice(alloc, indent);
                    try out.appendSlice(alloc, goTypeToC(vtype));
                    try out.append(alloc, ' ');
                    try out.appendSlice(alloc, vname);
                    try out.appendSlice(alloc, " = ");
                    try out.appendSlice(alloc, init);
                    try out.appendSlice(alloc, ";\n");
                    continue;
                }
            }
        }
        // `func name(params) type {` → `type name(params) {` — nested function
        // declarations within a body. We emit a C prototype-style line and recurse
        // into the body. Since this is line-oriented, we only handle single-line
        // `func ... { ... }` forms; multi-line nested funcs are passed through.
        if (std.mem.startsWith(u8, trimmed, "func ")) {
            const rest = trimmed[5..];
            if (std.mem.indexOfScalar(u8, rest, '(')) |paren_pos| {
                const fname = std.mem.trim(u8, rest[0..paren_pos], " \t");
                var depth: usize = 1;
                var i: usize = paren_pos + 1;
                while (i < rest.len and depth > 0) {
                    if (rest[i] == '(') depth += 1;
                    if (rest[i] == ')') depth -= 1;
                    i += 1;
                }
                const after_params = std.mem.trim(u8, rest[i..], " \t");
                if (after_params.len > 0 and after_params[0] == '{') {
                    // No return type — void
                    try out.appendSlice(alloc, "void ");
                    try out.appendSlice(alloc, fname);
                    try out.appendSlice(alloc, "(");
                    try convertGoParams(std.mem.trim(u8, rest[paren_pos + 1 .. i - 1], " \t\n"), out, alloc);
                    try out.appendSlice(alloc, ") {\n");
                    // Parse body until closing }
                    var bd: usize = 1;
                    var j: usize = 1;
                    while (j < after_params.len and bd > 0) {
                        if (after_params[j] == '{') bd += 1;
                        if (after_params[j] == '}') bd -= 1;
                        j += 1;
                    }
                    if (j > 1 and j - 1 < after_params.len) {
                        const raw_body = after_params[1 .. j - 1];
                        var body_buf: std.ArrayListUnmanaged(u8) = .empty;
                        try goBodyToC(raw_body, &body_buf, alloc);
                        try out.appendSlice(alloc, body_buf.items);
                        body_buf.deinit(alloc);
                    }
                    try out.appendSlice(alloc, "}\n");
                    continue;
                }
                // Has return type
                if (std.mem.indexOfScalar(u8, after_params, '{')) |brace_pos| {
                    const ret_type = std.mem.trim(u8, after_params[0..brace_pos], " \t");
                    try out.appendSlice(alloc, goTypeToC(ret_type));
                    try out.appendSlice(alloc, " ");
                    try out.appendSlice(alloc, fname);
                    try out.appendSlice(alloc, "(");
                    try convertGoParams(std.mem.trim(u8, rest[paren_pos + 1 .. i - 1], " \t\n"), out, alloc);
                    try out.appendSlice(alloc, ") {\n");
                    // Parse body until closing }
                    const body_start = brace_pos + 1;
                    var bd: usize = 1;
                    var j: usize = body_start;
                    while (j < after_params.len and bd > 0) {
                        if (after_params[j] == '{') bd += 1;
                        if (after_params[j] == '}') bd -= 1;
                        j += 1;
                    }
                    if (j > body_start and j - 1 < after_params.len) {
                        const raw_body = after_params[body_start .. j - 1];
                        var body_buf: std.ArrayListUnmanaged(u8) = .empty;
                        try goBodyToC(raw_body, &body_buf, alloc);
                        try out.appendSlice(alloc, body_buf.items);
                        body_buf.deinit(alloc);
                    }
                    try out.appendSlice(alloc, "}\n");
                    continue;
                }
            }
        }
        // `return expr` → `return expr;`
        if (std.mem.startsWith(u8, trimmed, "return ") or std.mem.eql(u8, trimmed, "return")) {
            try out.appendSlice(alloc, line);
            try out.appendSlice(alloc, ";\n");
            continue;
        }
        // Everything else: pass through
        try out.appendSlice(alloc, line);
        try out.appendSlice(alloc, "\n");
    }
}

fn transpileGoToC(alloc: std.mem.Allocator, code: []const u8) ![]const u8 {
    var result: std.ArrayListUnmanaged(u8) = .empty;
    errdefer result.deinit(alloc);
    try result.appendSlice(alloc, "/* [foreign.go] */\n");

    var remaining: []const u8 = code;
    while (remaining.len > 0) {
        if (std.mem.indexOf(u8, remaining, "func ")) |func_pos| {
            if (func_pos > 0) try result.appendSlice(alloc, remaining[0..func_pos]);
            remaining = remaining[func_pos + 5 ..];
            if (std.mem.indexOf(u8, remaining, "(")) |paren_pos| {
                const fname = std.mem.trim(u8, remaining[0..paren_pos], " \t\n");
                var depth: usize = 1;
                var i: usize = paren_pos + 1;
                while (i < remaining.len and depth > 0) {
                    if (remaining[i] == '(') depth += 1;
                    if (remaining[i] == ')') depth -= 1;
                    i += 1;
                }
                const after_params = std.mem.trim(u8, remaining[i..], " \t\n");
                // Handle receiver: func (r *Type) Method(...) → skip
                if (fname.len > 0 and fname[0] == '(') {
                    remaining = remaining[i..];
                    continue;
                }
                if (std.mem.indexOfScalar(u8, after_params, '{')) |brace_pos| {
                    const ret_type = std.mem.trim(u8, after_params[0..brace_pos], " \t\n");
                    if (ret_type.len > 0) {
                        try result.appendSlice(alloc, goTypeToC(ret_type));
                    } else {
                        try result.appendSlice(alloc, "void");
                    }
                    try result.appendSlice(alloc, " ");
                    try result.appendSlice(alloc, fname);
                    try result.appendSlice(alloc, "(");
                    try convertGoParams(std.mem.trim(u8, remaining[paren_pos + 1 .. i - 1], " \t\n"), &result, alloc);
                    try result.appendSlice(alloc, ") {\n");
                    remaining = after_params[brace_pos + 1 ..];
                    depth = 1;
                    i = 0;
                    while (i < remaining.len and depth > 0) {
                        if (remaining[i] == '{') depth += 1;
                        if (remaining[i] == '}') depth -= 1;
                        i += 1;
                    }
                    const raw_body = remaining[0..i];
                    var body_buf: std.ArrayListUnmanaged(u8) = .empty;
                    try goBodyToC(raw_body, &body_buf, alloc);
                    try result.appendSlice(alloc, body_buf.items);
                    body_buf.deinit(alloc);
                    remaining = remaining[i..];
                    try result.appendSlice(alloc, "}\n");
                } else break;
            } else break;
        } else {
            try result.appendSlice(alloc, remaining);
            break;
        }
    }
    return result.toOwnedSlice(alloc);
}

// ── Mojo transpilation ────────────────────────────────────────────────────────

fn mojoTypeToC(t: []const u8) []const u8 {
    const trimmed = std.mem.trim(u8, t, " \t");
    if (std.mem.eql(u8, trimmed, "Int8")) return "int8_t";
    if (std.mem.eql(u8, trimmed, "Int16")) return "int16_t";
    if (std.mem.eql(u8, trimmed, "Int32")) return "int32_t";
    if (std.mem.eql(u8, trimmed, "Int64")) return "int64_t";
    if (std.mem.eql(u8, trimmed, "UInt8")) return "uint8_t";
    if (std.mem.eql(u8, trimmed, "UInt16")) return "uint16_t";
    if (std.mem.eql(u8, trimmed, "UInt32")) return "uint32_t";
    if (std.mem.eql(u8, trimmed, "UInt64")) return "uint64_t";
    if (std.mem.eql(u8, trimmed, "Float32")) return "float";
    if (std.mem.eql(u8, trimmed, "Float64")) return "double";
    if (std.mem.eql(u8, trimmed, "Bool")) return "int";
    if (std.mem.eql(u8, trimmed, "String")) return "const char*";
    if (std.mem.eql(u8, trimmed, "SIMD")) return "double"; // fallback
    if (std.mem.eql(u8, trimmed, "DType")) return "int"; // enum fallback
    return trimmed;
}

fn convertMojoParams(params: []const u8, out: *std.ArrayListUnmanaged(u8), alloc: std.mem.Allocator) !void {
    if (params.len == 0) return;
    var first = true;
    var parts = std.mem.splitScalar(u8, params, ',');
    while (parts.next()) |part| {
        const p = std.mem.trim(u8, part, " \t\n");
        if (p.len == 0) continue;
        if (!first) try out.appendSlice(alloc, ", ");
        if (std.mem.indexOfScalar(u8, p, ':')) |colon_pos| {
            const name = std.mem.trim(u8, p[0..colon_pos], " \t");
            const ty = std.mem.trim(u8, p[colon_pos + 1 ..], " \t");
            try out.appendSlice(alloc, mojoTypeToC(ty));
            try out.appendSlice(alloc, " ");
            try out.appendSlice(alloc, name);
        } else {
            try out.appendSlice(alloc, p);
        }
        first = false;
    }
}

fn transpileMojoToC(alloc: std.mem.Allocator, code: []const u8) ![]const u8 {
    var result: std.ArrayListUnmanaged(u8) = .empty;
    errdefer result.deinit(alloc);
    try result.appendSlice(alloc, "/* [foreign.mojo] */\n");

    var remaining: []const u8 = code;
    while (remaining.len > 0) {
        // `fn name(params) -> type:` or `fn name(params):`
        if (std.mem.indexOf(u8, remaining, "fn ")) |fn_pos| {
            if (fn_pos > 0) try result.appendSlice(alloc, remaining[0..fn_pos]);
            remaining = remaining[fn_pos + 3 ..];
            if (std.mem.indexOf(u8, remaining, "(")) |paren_pos| {
                const fname = std.mem.trim(u8, remaining[0..paren_pos], " \t\n");
                var depth: usize = 1;
                var i: usize = paren_pos + 1;
                while (i < remaining.len and depth > 0) {
                    if (remaining[i] == '(') depth += 1;
                    if (remaining[i] == ')') depth -= 1;
                    i += 1;
                }
                const after_params = std.mem.trim(u8, remaining[i..], " \t\n");
                if (std.mem.startsWith(u8, after_params, "->")) {
                    const rest = std.mem.trim(u8, after_params[2..], " \t");
                    if (std.mem.indexOfScalar(u8, rest, ':')) |colon_pos| {
                        const ret_type = std.mem.trim(u8, rest[0..colon_pos], " \t");
                        try result.appendSlice(alloc, mojoTypeToC(ret_type));
                        try result.appendSlice(alloc, " ");
                        try result.appendSlice(alloc, fname);
                        try result.appendSlice(alloc, "(");
                        try convertMojoParams(std.mem.trim(u8, remaining[paren_pos + 1 .. i - 1], " \t\n"), &result, alloc);
                        try result.appendSlice(alloc, ") {\n");
                        remaining = rest[colon_pos + 1 ..];
                        var bd: usize = 1;
                        var j: usize = 0;
                        while (j < remaining.len) {
                            if (remaining[j] == '{') bd += 1;
                            if (remaining[j] == '}') {
                                bd -= 1;
                                if (bd == 0) {
                                    j += 1;
                                    break;
                                }
                            }
                            j += 1;
                        }
                        if (j > 1) {
                            const raw_body = remaining[0 .. j - 1];
                            var body_buf: std.ArrayListUnmanaged(u8) = .empty;
                            try mojoBodyToC(raw_body, &body_buf, alloc);
                            try result.appendSlice(alloc, body_buf.items);
                            body_buf.deinit(alloc);
                        }
                        remaining = remaining[j..];
                        try result.appendSlice(alloc, "}\n");
                    } else break;
                } else if (std.mem.indexOfScalar(u8, after_params, ':')) |colon_pos| {
                    try result.appendSlice(alloc, "void ");
                    try result.appendSlice(alloc, fname);
                    try result.appendSlice(alloc, "(");
                    try convertMojoParams(std.mem.trim(u8, remaining[paren_pos + 1 .. i - 1], " \t\n"), &result, alloc);
                    try result.appendSlice(alloc, ") {\n");
                    remaining = after_params[colon_pos + 1 ..];
                    var bd: usize = 1;
                    var j: usize = 0;
                    while (j < remaining.len) {
                        if (remaining[j] == '{') bd += 1;
                        if (remaining[j] == '}') {
                            bd -= 1;
                            if (bd == 0) {
                                j += 1;
                                break;
                            }
                        }
                        j += 1;
                    }
                    if (j > 1) {
                        const raw_body = remaining[0 .. j - 1];
                        var body_buf: std.ArrayListUnmanaged(u8) = .empty;
                        try mojoBodyToC(raw_body, &body_buf, alloc);
                        try result.appendSlice(alloc, body_buf.items);
                        body_buf.deinit(alloc);
                    }
                    remaining = remaining[j..];
                    try result.appendSlice(alloc, "}\n");
                } else break;
            } else break;
        } else {
            try result.appendSlice(alloc, remaining);
            break;
        }
    }
    return result.toOwnedSlice(alloc);
}

fn mojoBodyToC(body: []const u8, out: *std.ArrayListUnmanaged(u8), alloc: std.mem.Allocator) !void {
    var lines = std.mem.splitScalar(u8, body, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        const trimmed = std.mem.trim(u8, line, " \t");
        // `let x: type = expr` → `type x = expr;`
        if (std.mem.startsWith(u8, trimmed, "let ")) {
            const rest = trimmed[4..];
            if (std.mem.indexOfScalar(u8, rest, ':')) |colon_pos| {
                const vname = std.mem.trim(u8, rest[0..colon_pos], " \t");
                const after_colon = std.mem.trim(u8, rest[colon_pos + 1 ..], " \t");
                if (std.mem.indexOfScalar(u8, after_colon, '=')) |eq_pos| {
                    const vtype = std.mem.trim(u8, after_colon[0..eq_pos], " \t");
                    const init = std.mem.trim(u8, after_colon[eq_pos + 1 ..], " \t");
                    const indent = line[0 .. line.len - trimmed.len];
                    try out.appendSlice(alloc, indent);
                    try out.appendSlice(alloc, mojoTypeToC(vtype));
                    try out.append(alloc, ' ');
                    try out.appendSlice(alloc, vname);
                    try out.appendSlice(alloc, " = ");
                    try out.appendSlice(alloc, init);
                    try out.appendSlice(alloc, ";\n");
                    continue;
                }
            }
        }
        // `var x: type = expr` → `type x = expr;`
        if (std.mem.startsWith(u8, trimmed, "var ")) {
            const rest = trimmed[4..];
            if (std.mem.indexOfScalar(u8, rest, ':')) |colon_pos| {
                const vname = std.mem.trim(u8, rest[0..colon_pos], " \t");
                const after_colon = std.mem.trim(u8, rest[colon_pos + 1 ..], " \t");
                if (std.mem.indexOfScalar(u8, after_colon, '=')) |eq_pos| {
                    const vtype = std.mem.trim(u8, after_colon[0..eq_pos], " \t");
                    const init = std.mem.trim(u8, after_colon[eq_pos + 1 ..], " \t");
                    const indent = line[0 .. line.len - trimmed.len];
                    try out.appendSlice(alloc, indent);
                    try out.appendSlice(alloc, mojoTypeToC(vtype));
                    try out.append(alloc, ' ');
                    try out.appendSlice(alloc, vname);
                    try out.appendSlice(alloc, " = ");
                    try out.appendSlice(alloc, init);
                    try out.appendSlice(alloc, ";\n");
                    continue;
                }
            }
        }
        // `return expr` → `return expr;`
        if (std.mem.startsWith(u8, trimmed, "return ") or std.mem.eql(u8, trimmed, "return")) {
            try out.appendSlice(alloc, line);
            try out.appendSlice(alloc, ";\n");
            continue;
        }
        // `for i in range(...)` → `for (int64_t i = ...; ...)`
        if (std.mem.startsWith(u8, trimmed, "for ")) {
            const rest = trimmed[4..];
            if (std.mem.indexOf(u8, rest, " in range(")) |range_pos| {
                const var_name = std.mem.trim(u8, rest[0..range_pos], " \t");
                const range_args = std.mem.trim(u8, rest[range_pos + 10 ..], " \t)");
                const indent = line[0 .. line.len - trimmed.len];
                var args = std.mem.splitScalar(u8, range_args, ',');
                const start = std.mem.trim(u8, args.next() orelse "0", " \t");
                const stop = std.mem.trim(u8, args.next() orelse start, " \t");
                const step = std.mem.trim(u8, args.next() orelse "1", " \t");
                try out.appendSlice(alloc, indent);
                try out.appendSlice(alloc, "for (int64_t ");
                try out.appendSlice(alloc, var_name);
                try out.appendSlice(alloc, " = ");
                try out.appendSlice(alloc, start);
                try out.appendSlice(alloc, "; ");
                try out.appendSlice(alloc, var_name);
                try out.appendSlice(alloc, " < ");
                try out.appendSlice(alloc, stop);
                try out.appendSlice(alloc, "; ");
                try out.appendSlice(alloc, var_name);
                try out.appendSlice(alloc, " += ");
                try out.appendSlice(alloc, step);
                try out.appendSlice(alloc, ") {\n");
                continue;
            }
        }
        // `if cond:` → `if (cond) {`
        if (std.mem.startsWith(u8, trimmed, "if ")) {
            const rest = std.mem.trim(u8, trimmed[3..], " \t");
            if (std.mem.endsWith(u8, rest, ":")) {
                const cond = std.mem.trim(u8, rest[0 .. rest.len - 1], " \t");
                const indent = line[0 .. line.len - trimmed.len];
                try out.appendSlice(alloc, indent);
                try out.appendSlice(alloc, "if (");
                try out.appendSlice(alloc, cond);
                try out.appendSlice(alloc, ") {\n");
                continue;
            }
        }
        // `elif cond:` → `} else if (cond) {`
        if (std.mem.startsWith(u8, trimmed, "elif ")) {
            const rest = std.mem.trim(u8, trimmed[5..], " \t");
            if (std.mem.endsWith(u8, rest, ":")) {
                const cond = std.mem.trim(u8, rest[0 .. rest.len - 1], " \t");
                const indent = line[0 .. line.len - trimmed.len];
                try out.appendSlice(alloc, indent);
                try out.appendSlice(alloc, "} else if (");
                try out.appendSlice(alloc, cond);
                try out.appendSlice(alloc, ") {\n");
                continue;
            }
        }
        // `else:` → `} else {`
        if (std.mem.eql(u8, trimmed, "else:")) {
            const indent = line[0 .. line.len - trimmed.len];
            try out.appendSlice(alloc, indent);
            try out.appendSlice(alloc, "} else {\n");
            continue;
        }
        // `pass` → skip
        if (std.mem.eql(u8, trimmed, "pass")) continue;
        // Everything else: pass through
        try out.appendSlice(alloc, line);
        try out.appendSlice(alloc, "\n");
    }
}

// ── Kotlin transpilation ──────────────────────────────────────────────────────

fn kotlinTypeToC(t: []const u8) []const u8 {
    const trimmed = std.mem.trim(u8, t, " \t");
    if (std.mem.eql(u8, trimmed, "Byte") or std.mem.eql(u8, trimmed, "UByte")) return "int8_t";
    if (std.mem.eql(u8, trimmed, "Short") or std.mem.eql(u8, trimmed, "UShort")) return "int16_t";
    if (std.mem.eql(u8, trimmed, "Int") or std.mem.eql(u8, trimmed, "UInt")) return "int32_t";
    if (std.mem.eql(u8, trimmed, "Long") or std.mem.eql(u8, trimmed, "ULong")) return "int64_t";
    if (std.mem.eql(u8, trimmed, "Float")) return "float";
    if (std.mem.eql(u8, trimmed, "Double")) return "double";
    if (std.mem.eql(u8, trimmed, "Boolean")) return "int";
    if (std.mem.eql(u8, trimmed, "String")) return "const char*";
    if (std.mem.eql(u8, trimmed, "Char")) return "char";
    if (std.mem.eql(u8, trimmed, "Unit")) return "void";
    return trimmed;
}

fn convertKotlinParams(params: []const u8, out: *std.ArrayListUnmanaged(u8), alloc: std.mem.Allocator) !void {
    if (params.len == 0) return;
    var first = true;
    var parts = std.mem.splitScalar(u8, params, ',');
    while (parts.next()) |part| {
        const p = std.mem.trim(u8, part, " \t\n");
        if (p.len == 0) continue;
        if (!first) try out.appendSlice(alloc, ", ");
        if (std.mem.indexOfScalar(u8, p, ':')) |colon_pos| {
            const name = std.mem.trim(u8, p[0..colon_pos], " \t");
            const ty = std.mem.trim(u8, p[colon_pos + 1 ..], " \t");
            // Strip default value
            const type_str = if (std.mem.indexOfScalar(u8, ty, '=')) |eq_pos|
                std.mem.trim(u8, ty[0..eq_pos], " \t")
            else
                ty;
            try out.appendSlice(alloc, kotlinTypeToC(type_str));
            try out.appendSlice(alloc, " ");
            try out.appendSlice(alloc, name);
        } else {
            try out.appendSlice(alloc, p);
        }
        first = false;
    }
}

fn transpileKotlinToC(alloc: std.mem.Allocator, code: []const u8) ![]const u8 {
    var result: std.ArrayListUnmanaged(u8) = .empty;
    errdefer result.deinit(alloc);
    try result.appendSlice(alloc, "/* [foreign.kotlin] */\n");

    var remaining: []const u8 = code;
    while (remaining.len > 0) {
        // `fun name(params): type {` or `fun name(params) {`
        if (std.mem.indexOf(u8, remaining, "fun ")) |fn_pos| {
            if (fn_pos > 0) try result.appendSlice(alloc, remaining[0..fn_pos]);
            remaining = remaining[fn_pos + 4 ..];
            if (std.mem.indexOf(u8, remaining, "(")) |paren_pos| {
                const fname = std.mem.trim(u8, remaining[0..paren_pos], " \t\n");
                var depth: usize = 1;
                var i: usize = paren_pos + 1;
                while (i < remaining.len and depth > 0) {
                    if (remaining[i] == '(') depth += 1;
                    if (remaining[i] == ')') depth -= 1;
                    i += 1;
                }
                const after_params = std.mem.trim(u8, remaining[i..], " \t\n");
                if (std.mem.startsWith(u8, after_params, ":")) {
                    const rest = std.mem.trim(u8, after_params[1..], " \t");
                    if (std.mem.indexOfScalar(u8, rest, '{')) |brace_pos| {
                        const ret_type = std.mem.trim(u8, rest[0..brace_pos], " \t");
                        try result.appendSlice(alloc, kotlinTypeToC(ret_type));
                        try result.appendSlice(alloc, " ");
                        try result.appendSlice(alloc, fname);
                        try result.appendSlice(alloc, "(");
                        try convertKotlinParams(std.mem.trim(u8, remaining[paren_pos + 1 .. i - 1], " \t\n"), &result, alloc);
                        try result.appendSlice(alloc, ") {\n");
                        remaining = rest[brace_pos + 1 ..];
                        depth = 1;
                        i = 0;
                        while (i < remaining.len and depth > 0) {
                            if (remaining[i] == '{') depth += 1;
                            if (remaining[i] == '}') depth -= 1;
                            i += 1;
                        }
                        const raw_body = remaining[0..i];
                        var body_buf: std.ArrayListUnmanaged(u8) = .empty;
                        try kotlinBodyToC(raw_body, &body_buf, alloc);
                        try result.appendSlice(alloc, body_buf.items);
                        body_buf.deinit(alloc);
                        remaining = remaining[i..];
                        try result.appendSlice(alloc, "}\n");
                    } else break;
                } else if (std.mem.indexOfScalar(u8, after_params, '{')) |brace_pos| {
                    try result.appendSlice(alloc, "void ");
                    try result.appendSlice(alloc, fname);
                    try result.appendSlice(alloc, "(");
                    try convertKotlinParams(std.mem.trim(u8, remaining[paren_pos + 1 .. i - 1], " \t\n"), &result, alloc);
                    try result.appendSlice(alloc, ") {\n");
                    remaining = after_params[brace_pos + 1 ..];
                    depth = 1;
                    i = 0;
                    while (i < remaining.len and depth > 0) {
                        if (remaining[i] == '{') depth += 1;
                        if (remaining[i] == '}') depth -= 1;
                        i += 1;
                    }
                    const raw_body = remaining[0..i];
                    var body_buf: std.ArrayListUnmanaged(u8) = .empty;
                    try kotlinBodyToC(raw_body, &body_buf, alloc);
                    try result.appendSlice(alloc, body_buf.items);
                    body_buf.deinit(alloc);
                    remaining = remaining[i..];
                    try result.appendSlice(alloc, "}\n");
                } else break;
            } else break;
        } else {
            try result.appendSlice(alloc, remaining);
            break;
        }
    }
    return result.toOwnedSlice(alloc);
}

fn kotlinBodyToC(body: []const u8, out: *std.ArrayListUnmanaged(u8), alloc: std.mem.Allocator) !void {
    var lines = std.mem.splitScalar(u8, body, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        const trimmed = std.mem.trim(u8, line, " \t");
        // `val x: type = expr` or `var x: type = expr` → `type x = expr;`
        if (std.mem.startsWith(u8, trimmed, "val ") or std.mem.startsWith(u8, trimmed, "var ")) {
            const kw_len: usize = if (trimmed[0] == 'v') 4 else 4; // both "val " and "var " are 4 chars
            const rest = trimmed[kw_len..];
            if (std.mem.indexOfScalar(u8, rest, ':')) |colon_pos| {
                const vname = std.mem.trim(u8, rest[0..colon_pos], " \t");
                const after_colon = std.mem.trim(u8, rest[colon_pos + 1 ..], " \t");
                if (std.mem.indexOfScalar(u8, after_colon, '=')) |eq_pos| {
                    const vtype = std.mem.trim(u8, after_colon[0..eq_pos], " \t");
                    const init = std.mem.trim(u8, after_colon[eq_pos + 1 ..], " \t");
                    const indent = line[0 .. line.len - trimmed.len];
                    try out.appendSlice(alloc, indent);
                    try out.appendSlice(alloc, kotlinTypeToC(vtype));
                    try out.append(alloc, ' ');
                    try out.appendSlice(alloc, vname);
                    try out.appendSlice(alloc, " = ");
                    try out.appendSlice(alloc, init);
                    try out.appendSlice(alloc, ";\n");
                    continue;
                }
            }
        }
        // `return expr` → `return expr;`
        if (std.mem.startsWith(u8, trimmed, "return ") or std.mem.eql(u8, trimmed, "return")) {
            try out.appendSlice(alloc, line);
            try out.appendSlice(alloc, ";\n");
            continue;
        }
        // `println(...)` → `printf("...\\n", ...);`
        if (std.mem.startsWith(u8, trimmed, "println(")) {
            const args = std.mem.trim(u8, trimmed[8 .. trimmed.len - 1], " \t");
            const indent = line[0 .. line.len - trimmed.len];
            try out.appendSlice(alloc, indent);
            try out.appendSlice(alloc, "printf(\"%s\\n\", ");
            try out.appendSlice(alloc, args);
            try out.appendSlice(alloc, ");\n");
            continue;
        }
        // Everything else: pass through
        try out.appendSlice(alloc, line);
        try out.appendSlice(alloc, "\n");
    }
}

/// Parse function declarations from a transpiled `@foreign` snippet.
pub fn declsFromForeignSnippet(alloc: std.mem.Allocator, lang: []const u8, code: []const u8) ![]@import("c_header_parse.zig").CDecl {
    const c_header_parse = @import("c_header_parse.zig");
    const c_code = try transpileForeign(alloc, lang, code);
    defer alloc.free(c_code);
    return c_header_parse.parseFunctionDecls(alloc, c_code);
}

test "foreign_transpile: decl extraction" {
    const alloc = std.testing.allocator;
    const code = "fn add(a: i64, b: i64) i64 { return a + b; }";
    const decls = try declsFromForeignSnippet(alloc, "zig", code);
    defer {
        for (decls) |d| {
            alloc.free(d.name);
            alloc.free(d.ret_type);
            alloc.free(d.params);
        }
        alloc.free(decls);
    }
    try std.testing.expectEqual(@as(usize, 1), decls.len);
    try std.testing.expectEqualStrings("add", decls[0].name);
}

test "foreign_transpile: zig fn" {
    const alloc = std.testing.allocator;
    const code =
        \\fn add(a: i64, b: i64) i64 {
        \\    return a + b;
        \\}
    ;
    const out = try transpileForeign(alloc, "zig", code);
    defer alloc.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "int64_t add") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "return a + b") != null);
}

test "foreign_transpile: showcase snippets" {
    const alloc = std.testing.allocator;
    const cases = [_]struct { []const u8, []const u8, []const u8 }{
        .{ "zig", "fn add(a: i64, b: i64) i64 { return a + b; }", "add" },
        .{ "python", "def mul(a, b):\n    return a * b", "mul" },
        .{ "c", "static inline int64_t sub(int64_t a, int64_t b) { return a - b; }", "sub" },
    };
    for (cases) |c| {
        const decls = try declsFromForeignSnippet(alloc, c[0], c[1]);
        defer {
            for (decls) |d| {
                alloc.free(d.name);
                alloc.free(d.ret_type);
                alloc.free(d.params);
            }
            alloc.free(decls);
        }
        try std.testing.expectEqual(@as(usize, 1), decls.len);
        try std.testing.expectEqualStrings(c[2], decls[0].name);
    }
}

test "foreign_transpile: python def" {
    const alloc = std.testing.allocator;
    const code =
        \\def mul(a, b):
        \\    return a * b
    ;
    const out = try transpileForeign(alloc, "python", code);
    defer alloc.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "int64_t mul") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "return a * b") != null);
}
