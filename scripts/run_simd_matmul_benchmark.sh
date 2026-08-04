#!/usr/bin/env bash
# run_simd_matmul_benchmark.sh — Compare Duo builtin simd.matmul_f32 to native C.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
EXAMPLES_DIR="$PROJECT_DIR/examples"
DUO="$PROJECT_DIR/zig-out/bin/duo"
OUT_DIR="/tmp/duo_simd_matmul_bench"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}=== Duo SIMD Matmul Benchmark (512x512) ===${NC}"
echo ""

if [[ ! -f "$DUO" ]]; then
    echo -e "${RED}ERROR: Duo compiler not found at $DUO${NC}"
    echo "  Run 'zig build' first"
    exit 1
fi

mkdir -p "$OUT_DIR"

# Step 1: Compile C reference
echo -e "${CYAN}[1/3] Compiling C reference...${NC}"
SDK_PATH="$(xcrun --show-sdk-path 2>/dev/null || echo '')"
if [[ -n "$SDK_PATH" ]]; then
    SYSROOT_FLAG="-isysroot $SDK_PATH"
else
    SYSROOT_FLAG=""
fi

clang -O3 -flto -ffast-math -march=native $SYSROOT_FLAG "$EXAMPLES_DIR/bench_simd_matmul_c.c" -o "$OUT_DIR/bench_simd_matmul_c"
echo "      → $OUT_DIR/bench_simd_matmul_c"

# Step 2: Compile Duo benchmark
echo -e "${CYAN}[2/3] Compiling bench_simd_matmul.duo...${NC}"
"$DUO" compile "$EXAMPLES_DIR/bench_simd_matmul.duo" -o "$OUT_DIR/bench_simd_matmul_duo" -O3
echo "      → $OUT_DIR/bench_simd_matmul_duo"

# Step 3: Run benchmark
echo ""
echo -e "${CYAN}[3/3] Running benchmark (10 iterations)...${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Running Duo..."
# Use awk to parse output. The output has: RESULT simd_matmul\n<time>\nChecksum: <csum>
DUO_OUT=$("$OUT_DIR/bench_simd_matmul_duo" | grep -A 1 "RESULT simd_matmul" | tail -n 1)
echo "Duo Time: $DUO_OUT s"

echo "Running C..."
C_OUT=$("$OUT_DIR/bench_simd_matmul_c" | grep -A 1 "RESULT simd_matmul" | tail -n 1)
echo "C Time:   $C_OUT s"

RATIO=$(awk -v d="$DUO_OUT" -v c="$C_OUT" 'BEGIN{printf "%.2f", d/c}')
echo "Ratio (Duo/C): ${RATIO}x"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo -e "${GREEN}Done.${NC}"
