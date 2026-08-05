#!/usr/bin/env bash
# run_alloc_churn_benchmark.sh — Compare Duo dynamic table churn to native C arrays.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
EXAMPLES_DIR="$PROJECT_DIR/examples"
DUO="$PROJECT_DIR/zig-out/bin/duo"
OUT_DIR="/tmp/duo_alloc_churn_bench"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}=== Duo Alloc Churn Benchmark ===${NC}"
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

clang -O3 -flto -march=native $SYSROOT_FLAG "$EXAMPLES_DIR/bench_alloc_churn_c.c" -o "$OUT_DIR/bench_alloc_c"
echo "      → $OUT_DIR/bench_alloc_c"

# Step 2: Compile Duo benchmark
echo -e "${CYAN}[2/3] Compiling bench_alloc_churn.duo...${NC}"
"$DUO" compile "$EXAMPLES_DIR/bench_alloc_churn.duo" -o "$OUT_DIR/bench_alloc_churn_duo" -O3
echo "      → $OUT_DIR/bench_alloc_churn_duo"

# Step 3: Run benchmark
echo ""
echo -e "${CYAN}[3/3] Running benchmark...${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Running Duo..."
DUO_OUT=$("$OUT_DIR/bench_alloc_churn_duo" | tail -n 1)
echo "Duo Time: $DUO_OUT s"

echo "Running C..."
C_OUT=$("$OUT_DIR/bench_alloc_c" | tail -n 1)
echo "C Time:   $C_OUT s"

RATIO=$(awk -v d="$DUO_OUT" -v c="$C_OUT" 'BEGIN{printf "%.2f", d/c}')
echo "Ratio (Duo/C): ${RATIO}x"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo -e "${GREEN}Done.${NC}"
