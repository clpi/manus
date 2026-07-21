#!/usr/bin/env bash
# run_gpu_benchmark.sh — Build and run GPU (Metal) vs CPU matmul benchmark
#
# Requirements:
#   - macOS with Apple Silicon (or any Metal-capable GPU)
#   - Xcode Command Line Tools (clang with Metal framework)
#   - Duo compiler built (zig build)
#
# This benchmark is OPT-IN and not part of the CI gate.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
EXAMPLES_DIR="$PROJECT_DIR/examples"
DUO="$PROJECT_DIR/zig-out/bin/duo"
OUT_DIR="/tmp/duo_gpu_bench"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}=== Duo GPU (Metal) Benchmark ===${NC}"
echo ""

# Check prerequisites
if [[ "$(uname)" != "Darwin" ]]; then
    echo -e "${CYAN}SKIP: This benchmark requires macOS with Metal support. Skipping gracefully.${NC}"
    exit 0
fi

if [[ ! -f "$DUO" ]]; then
    echo -e "${RED}ERROR: Duo compiler not found at $DUO${NC}"
    echo "  Run 'zig build' first"
    exit 1
fi

mkdir -p "$OUT_DIR"

# Step 1: Compile Metal helper (Objective-C)
echo -e "${CYAN}[1/3] Compiling Metal helper (metal_compute.m)...${NC}"
SDK_PATH="$(xcrun --show-sdk-path)"
clang -c "$EXAMPLES_DIR/metal_compute.m" \
    -o "$OUT_DIR/metal_compute.o" \
    -isysroot "$SDK_PATH" \
    -O2 \
    -fobjc-arc

echo "      → $OUT_DIR/metal_compute.o"

# Step 2: Compile Duo benchmark to C, then to native binary linked with Metal helper
echo -e "${CYAN}[2/3] Compiling bench_gpu_metal.duo...${NC}"

# First, generate C from Duo
"$DUO" dump-c "$EXAMPLES_DIR/bench_gpu_metal.duo" > "$OUT_DIR/bench_gpu_metal.c"
echo "      → Generated C: $OUT_DIR/bench_gpu_metal.c"

# Compile C + link with Metal helper
clang "$OUT_DIR/bench_gpu_metal.c" \
    "$OUT_DIR/metal_compute.o" \
    -o "$OUT_DIR/bench_gpu_metal" \
    -isysroot "$SDK_PATH" \
    -framework Metal \
    -framework Foundation \
    -O3 -ffast-math \
    -lm

echo "      → Binary: $OUT_DIR/bench_gpu_metal"

# Step 3: Run benchmark
echo ""
echo -e "${CYAN}[3/3] Running benchmark...${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
"$OUT_DIR/bench_gpu_metal"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo -e "${GREEN}Done.${NC}"
