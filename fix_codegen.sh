sed -i '' 's/try self.emit_arg_for_param(default_val, pt);/try self.emit_arg_for_param(default_val, pt, false);/' src/codegen.zig
sed -i '' 's/try self.emit_arg_for_param(ld.inits\[i\], rt);/try self.emit_arg_for_param(ld.inits\[i\], rt, false);/' src/codegen.zig
sed -i '' 's/try self.emit_arg_for_param(c.args\[1\], target);/try self.emit_arg_for_param(c.args\[1\], target, false);/' src/codegen.zig
