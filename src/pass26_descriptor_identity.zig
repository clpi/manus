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
