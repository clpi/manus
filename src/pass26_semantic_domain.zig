//! Pass 26 §52 — semantic domains (second unifier after boundaries).
//!
//! Every value, call, descriptor, resource, effect, and transformation operates
//! within one or more domains. A boundary connects domains; a transformation
//! changes or removes a boundary; a proof justifies movement; a realization
//! selects concrete domains.
const std = @import("std");

pub const SCHEMA_VERSION = "pass26-semantic-domain-v0";

pub const DomainKind = enum {
    language,
    stage,
    ownership,
    execution,
    trust,
    target,
    failure,
    representation,
    authority,

    pub fn name(self: DomainKind) []const u8 {
        return @tagName(self);
    }

    pub fn dottedPath(self: DomainKind) []const u8 {
        return switch (self) {
            .language => "Domain.Language",
            .stage => "Domain.Stage",
            .ownership => "Domain.Ownership",
            .execution => "Domain.Execution",
            .trust => "Domain.Trust",
            .target => "Domain.Target",
            .failure => "Domain.Failure",
            .representation => "Domain.Representation",
            .authority => "Domain.Authority",
        };
    }
};

/// A value or entity may inhabit multiple domains simultaneously (product, not scalar).
pub const DomainMembership = struct {
    kind: DomainKind,
    /// Stable domain-specific identity (not surface spelling).
    domain_id: []const u8,
};

pub const DomainRelation = enum {
    /// Boundary connects source domain to destination domain.
    boundary_crossing,
    /// Transformation removes or weakens a boundary between domains.
    boundary_elimination,
    /// Proof justifies movement between domains.
    justified_transfer,
    /// Realization selects a concrete domain assignment.
    realization_selection,

    pub fn name(self: DomainRelation) []const u8 {
        return @tagName(self);
    }
};

pub const Invariant = struct {
    id: []const u8,
    rule: []const u8,
};

pub const invariants: []const Invariant = &.{
    .{ .id = "P26-SD01", .rule = "nine domain kinds cover all semantic placement" },
    .{ .id = "P26-SD02", .rule = "membership is product lattice; not one scalar rank" },
    .{ .id = "P26-SD03", .rule = "boundaries connect domains; not separate ad hoc systems" },
    .{ .id = "P26-SD04", .rule = "proofs justify cross-domain movement with evidence" },
    .{ .id = "P26-SD05", .rule = "domain is internal structure; not required user syntax" },
};

pub fn domainKindCount() usize {
    return @typeInfo(DomainKind).@"enum".field_names.len;
}

test "pass26_semantic_domain: nine kinds" {
    try std.testing.expect(domainKindCount() == 9);
    try std.testing.expectEqualStrings("Domain.Trust", DomainKind.trust.dottedPath());
}
