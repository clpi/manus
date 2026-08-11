pub const DescriptorState = enum {
    frozen_snapshot,
    open_semantic,
    sealed,
    derived,
    mutable_builder,

    pub fn name(self: DescriptorState) []const u8 {
        return @tagName(self);
    }
};

pub const InterningPolicy = enum {
    canonicalize_pure,
    defer_until_sealed,
    foreign_fingerprint,
    preserve_declaration,

    pub fn name(self: InterningPolicy) []const u8 {
        return @tagName(self);
    }
};
