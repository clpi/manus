import sys
p = "/tmp/wt-callclobber/src/native.zig"
src = open(p).read()
def rep(old, new, count=1):
    global src
    n = src.count(old)
    assert n == count, f"expected {count}, found {n} for: {old[:80]!r}"
    src = src.replace(old, new)

# 1. Field: replace spill_exclude with held_regs bitmask
rep("""    spilled_regs: std.AutoHashMapUnmanaged(u5, u16) = .empty,
    spill_exclude: [4]?u5 = .{ null, null, null, null },""",
"""    spilled_regs: std.AutoHashMapUnmanaged(u5, u16) = .empty,
    /// Registers currently handed to emitter code, which may still name them
    /// in a local and read them raw without re-deriving through
    /// `evalDnirValue`. `spillTempVictim` never chooses one: spilling it
    /// would leave the emitter's register number stale. Set at every
    /// hand-out (`evalDnirValue` family, `allocRegExcluding`,
    /// `allocRegOutsideSaveSet`), cleared at every free (`releaseReg`,
    /// `sweepGpLive`, the direct free sites). A missed clear over-protects
    /// toward honest refusal; the set points are complete by construction,
    /// so no emitter can be missed the way a per-site list can be.
    held_regs: u32 = 0,""")

# 2. Helpers after claimReg
rep("""    fn claimReg(self: *Arm64Compiler, reg: u5) void {
        self.used_regs[reg] = true;
        if (reg >= callee_save_first and reg <= callee_save_last) {
            self.callee_touched |= @as(u32, 1) << reg;
        }
    }""",
"""    fn claimReg(self: *Arm64Compiler, reg: u5) void {
        self.used_regs[reg] = true;
        if (reg >= callee_save_first and reg <= callee_save_last) {
            self.callee_touched |= @as(u32, 1) << reg;
        }
    }

    fn holdReg(self: *Arm64Compiler, reg: u5) void {
        self.held_regs |= @as(u32, 1) << reg;
    }

    fn unholdReg(self: *Arm64Compiler, reg: u5) void {
        self.held_regs &= ~(@as(u32, 1) << reg);
    }""")

# 3. evalDnirValue wrapper
rep("""    fn evalDnirValue(self: *Arm64Compiler, temps: *std.AutoHashMapUnmanaged(u32, u5), v: dnir.Value) Error!u5 {
        // FP temp on GP path: convert via fmov instead of refusing.""",
"""    fn evalDnirValue(self: *Arm64Compiler, temps: *std.AutoHashMapUnmanaged(u32, u5), v: dnir.Value) Error!u5 {
        const r = try self.evalDnirValueUnheld(temps, v);
        self.holdReg(r);
        return r;
    }

    fn evalDnirValueUnheld(self: *Arm64Compiler, temps: *std.AutoHashMapUnmanaged(u32, u5), v: dnir.Value) Error!u5 {
        // FP temp on GP path: convert via fmov instead of refusing.""")

# 4. evalDnirValueBits wrapper
rep("""    fn evalDnirValueBits(self: *Arm64Compiler, temps: *std.AutoHashMapUnmanaged(u32, u5), v: dnir.Value) Error!u5 {
        if (!self.valueIsFp(v)) return self.evalDnirValue(temps, v);""",
"""    fn evalDnirValueBits(self: *Arm64Compiler, temps: *std.AutoHashMapUnmanaged(u32, u5), v: dnir.Value) Error!u5 {
        const r = try self.evalDnirValueBitsUnheld(temps, v);
        self.holdReg(r);
        return r;
    }

    fn evalDnirValueBitsUnheld(self: *Arm64Compiler, temps: *std.AutoHashMapUnmanaged(u32, u5), v: dnir.Value) Error!u5 {
        if (!self.valueIsFp(v)) return self.evalDnirValue(temps, v);""")

# 5. evalDnirValueFp wrapper
rep("""    fn evalDnirValueFp(self: *Arm64Compiler, temps: *std.AutoHashMapUnmanaged(u32, u5), v: dnir.Value) Error!u5 {""",
"""    fn evalDnirValueFp(self: *Arm64Compiler, temps: *std.AutoHashMapUnmanaged(u32, u5), v: dnir.Value) Error!u5 {
        const r = try self.evalDnirValueFpUnheld(temps, v);
        self.holdReg(r);
        return r;
    }

    fn evalDnirValueFpUnheld(self: *Arm64Compiler, temps: *std.AutoHashMapUnmanaged(u32, u5), v: dnir.Value) Error!u5 {""")

# 6. allocRegExcluding wrapper
rep("""    fn allocRegExcluding(self: *Arm64Compiler, exclude: ?u5) Error!u5 {
        var reg: u5 = 9;""",
"""    fn allocRegExcluding(self: *Arm64Compiler, exclude: ?u5) Error!u5 {
        const reg = try self.allocRegExcludingUnheld(exclude);
        self.holdReg(reg);
        return reg;
    }

    fn allocRegExcludingUnheld(self: *Arm64Compiler, exclude: ?u5) Error!u5 {
        var reg: u5 = 9;""")
rep("""            try self.spillReg(victim);
            return self.allocRegExcluding(exclude);""",
"""            try self.spillReg(victim);
            return self.allocRegExcludingUnheld(exclude);""", count=3)

# 7. allocRegOutsideSaveSet: hold the result reg
rep("""    fn allocRegOutsideSaveSet(self: *Arm64Compiler, save: SaveSet) Error!u5 {
        const reg = self.resultReg(save) orelse return error.RegisterExhausted;
        self.claimReg(reg);
        return reg;
    }""",
"""    fn allocRegOutsideSaveSet(self: *Arm64Compiler, save: SaveSet) Error!u5 {
        const reg = self.resultReg(save) orelse return error.RegisterExhausted;
        self.claimReg(reg);
        self.holdReg(reg);
        return reg;
    }""")

# 8. releaseReg: clear at top
rep("""    fn releaseReg(self: *Arm64Compiler, reg: u5) void {
        if (reg >= 29) return;""",
"""    fn releaseReg(self: *Arm64Compiler, reg: u5) void {
        self.unholdReg(reg);
        if (reg >= 29) return;""")

# 9. sweepGpLive: per-instruction scope reset
rep("""    fn sweepGpLive(self: *Arm64Compiler, idx: u32) void {
        var reg: u5 = 0;""",
"""    fn sweepGpLive(self: *Arm64Compiler, idx: u32) void {
        // Per-instruction scope: no emitter local survives past this point,
        // so every hand-out is re-derived (and re-held) by the next emitter.
        // A live temp's register is therefore spillable again here exactly
        // when no emitter holds it raw, which is the benign case.
        self.held_regs = 0;
        var reg: u5 = 0;""")

# 10. spillReg: value leaves the register
rep("""        try self.spilled_regs.put(self.alloc, victim, off);
        self.used_regs[victim] = false;""",
"""        try self.spilled_regs.put(self.alloc, victim, off);
        self.unholdReg(victim);
        self.used_regs[victim] = false;""")

# 11. hoist teardown
rep("""                self.gp_home_regs[r] = false;
                self.gp_reg_owner[r] = null;
                self.used_regs[r] = false;""",
"""                self.gp_home_regs[r] = false;
                self.gp_reg_owner[r] = null;
                self.unholdReg(r);
                self.used_regs[r] = false;""")

# 12. call arg release
rep("""                                        self.gp_reg_owner[arg_reg] = null;
                                        self.used_regs[arg_reg] = false;""",
"""                                        self.gp_reg_owner[arg_reg] = null;
                                        self.unholdReg(arg_reg);
                                        self.used_regs[arg_reg] = false;""")

# 13. call restore loop
rep("""            if (self.stagedRegHoldsLiveValue(temps, r, at)) continue;
            self.used_regs[r] = false;""",
"""            if (self.stagedRegHoldsLiveValue(temps, r, at)) continue;
            self.unholdReg(r);
            self.used_regs[r] = false;""")

# 14. spillTempVictim: check held bit instead of manual list
rep("""        for (self.spill_exclude) |ex| if (ex) |x| if (reg == x) return null;""",
"""        if ((self.held_regs >> reg) & 1 != 0) return null;""")

# 15. i64 store_index: remove manual excludes
rep("""                        self.spill_exclude[0] = base;
                        self.spill_exclude[1] = idx;
                        self.spill_exclude[2] = biased;
                        const val = try self.evalDnirValueBits(temps, ins.third);
                        self.spill_exclude[0] = null;
                        self.spill_exclude[1] = null;
                        self.spill_exclude[2] = null;
                        try self.emitStrScaled(val, base, biased);""",
"""                        const val = try self.evalDnirValueBits(temps, ins.third);
                        try self.emitStrScaled(val, base, biased);""")

# 16. byte store_index: remove manual excludes
rep("""                        self.spill_exclude[0] = sbase;
                        self.spill_exclude[1] = sidx;
                        const sval = try self.evalDnirValue(temps, ins.third);
                        self.spill_exclude[0] = null;
                        self.spill_exclude[1] = null;""",
"""                        const sval = try self.evalDnirValue(temps, ins.third);""")

# 17. function entry / exit hygiene
rep("""        self.eval_pinned = &pinned;
        self.eval_temps = &temps;""",
"""        self.eval_pinned = &pinned;
        self.eval_temps = &temps;
        self.held_regs = 0;""")
rep("""        self.eval_pinned = null;
        self.eval_temps = null;
        self.cur_func_has_call = false;""",
"""        self.eval_pinned = null;
        self.eval_temps = null;
        self.held_regs = 0;
        self.cur_func_has_call = false;""", count=2)

open(p, "w").write(src)
print("all edits applied")
