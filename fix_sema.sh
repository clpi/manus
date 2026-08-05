sed -i '' 's/fn check_stmt/fn check_stmt(self: \*Sema, stmt: \*ast.Stmt) SemaError!void {\\n    std.debug.print("CHECK STMT {any}\\n", .{stmt.*});/g' src/sema.zig
