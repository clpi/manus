//! Exact semantic graph identity and fact cardinality.
//!
//! Kept below the graph/region dependency seam so every producer and consumer
//! uses one id and one unknown/absent/one algebra without creating an import
//! cycle or a second nullable identity representation.

pub const id = u32;

/// FACT-CARDINALITY-ONE: unknown, known-absent, or one exact graph id.
pub const Card = union(enum) {
    unknown,
    none,
    one: id,

    pub fn name(self: Card) []const u8 {
        return switch (self) {
            .unknown => "unknown",
            .none => "none",
            .one => "one",
        };
    }
};
