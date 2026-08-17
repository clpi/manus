// Root test aggregator.
// Importing each module causes the test runner to discover and execute all
// `test` blocks declared inside that module.
const std = @import("std");

test {
    _ = @import("conversion_law.zig");
    _ = @import("lexer.zig");
    _ = @import("lexer_bridge.zig");
    _ = @import("lexical_identity.zig");
    _ = @import("lexer_dispatch.zig");
    _ = @import("launch_role.zig");
    _ = @import("ast.zig");
    _ = @import("types.zig");
    _ = @import("parser.zig");
    _ = @import("grammar_roles.zig");
    _ = @import("token_view.zig");
    _ = @import("sema.zig");
    _ = @import("comptime.zig");
    _ = @import("macro_expand.zig");
    _ = @import("derive_eval.zig");
    _ = @import("mono.zig");
    _ = @import("arc.zig");
    _ = @import("async_lower.zig");
    _ = @import("escape.zig");
    _ = @import("table_facts.zig");
    _ = @import("collection_relation.zig");
    _ = @import("property_tests.zig");
    _ = @import("pretty.zig");
    _ = @import("meta_module.zig");
    _ = @import("transform_engine.zig");
    _ = @import("meta_dispatch.zig");
    _ = @import("semantic_graph.zig");
    _ = @import("semantic_algebra.zig");
    _ = @import("sim.zig");
    _ = @import("c_frontend.zig");
    _ = @import("c_sim_import.zig");
    _ = @import("c_layout_verify.zig");
    _ = @import("foreign_adapter.zig");
    _ = @import("abi_specialize.zig");
    _ = @import("knowledge_snapshot.zig");
    _ = @import("optimization_outcome.zig");
    _ = @import("explain_pipeline.zig");
    _ = @import("assumption_guard.zig");
    _ = @import("repair_candidate.zig");
    _ = @import("semantic_fingerprint.zig");
    _ = @import("evidence_record.zig");
    _ = @import("place.zig");
    _ = @import("region.zig");
    _ = @import("eqspace.zig");
    _ = @import("observation.zig");
    _ = @import("observer_demand.zig");
    _ = @import("wasm_semantic.zig");
    _ = @import("wasm_semantic_gen.zig");
    _ = @import("wasm_decode_differential.zig");
    _ = @import("tail_result_demand.zig");
    _ = @import("tail_result_model.zig");
    _ = @import("wiring.zig");
    _ = @import("benchmark_evidence.zig");
    _ = @import("lua_metamethod.zig");
    _ = @import("graph_query.zig");
    _ = @import("region_graph.zig");
    _ = @import("native_ir.zig");
    _ = @import("dnir_lower.zig");
    _ = @import("module_names.zig");
    _ = @import("source_cursor.zig");
    _ = @import("lexer_differential.zig");
    _ = @import("shell_session.zig");
    _ = @import("shell_host.zig");
    _ = @import("git_preservation.zig");
    _ = @import("proof_carrying.zig");
    _ = @import("token_semantic.zig");
    _ = @import("token_classify_gen.zig");
    _ = @import("backend_identity.zig");
    _ = @import("native_barrier_checks.zig");
    _ = @import("target_model.zig");
    _ = @import("sim_pipeline.zig");
    _ = @import("meta_codegen.zig");
    _ = @import("directives.zig");
    _ = @import("term.zig");
    _ = @import("debug_trace.zig");
    _ = @import("build_framework.zig");
    _ = @import("ml_kernels.zig");
    _ = @import("jit.zig");
    _ = @import("c_backend.zig");
    _ = @import("native_backend.zig");
    // `wasm_backend.zig` — 3,429 lines with ZERO IMPORTERS until this line.
    //
    // MEASURED at `015ded1a`: `git grep wasm_backend` over `src/`, `tools/` and
    // `build.zig` returns nothing outside the file itself, and it was absent
    // from this list — so nothing had ever COMPILED it, let alone run it. It is
    // the "second realizer off the same facts" that `AGENTS.md`'s host-removal
    // test 3 asks for, and the evidence for that test did not exist.
    //
    // One import is the cheapest thing that makes `consumers = 0` false (HPLS
    // §7/§8) and it costs nothing: it type-checks the file on every `zig build
    // test`, which is what caught that adding `.idiv` to `native_ir.BinOpTag`
    // needed an arm here. Wiring it to a driver is a larger job and is NOT this;
    // this is the line that stops it decaying unnoticed in the meantime.
    _ = @import("wasm_backend.zig");
    _ = @import("demand.zig");
    _ = @import("demand_projection.zig");
    _ = @import("quotient_synth.zig");
    _ = @import("obseq.zig");
    _ = @import("loop_closure.zig");
}
