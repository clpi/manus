pub const CallingConventionKind = enum {
    c_abi,

    pub fn name(self: CallingConventionKind) []const u8 {
        return @tagName(self);
    }
};
