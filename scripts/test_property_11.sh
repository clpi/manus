#!/usr/bin/env bash
set -euo pipefail

echo "[Property 11] Testing C codegen..."

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/duo-prop11.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

if [[ "$(uname)" == "Darwin" ]]; then
    CLANG=(xcrun clang)
else
    CLANG=(clang)
fi

check_module() {
    local name="$1"
    local duo_file="$TMP_DIR/$name.duo"
    local c_file="$TMP_DIR/$name.c"
    local clang_log="$TMP_DIR/$name.clang.log"
    cat > "$duo_file"
    "$ROOT/zig-out/bin/duo" dump-c "$duo_file" > "$c_file"
    if ! "${CLANG[@]}" -Wall -Wextra -pedantic -std=c11 \
        -Wno-unused-variable -Wno-strict-prototypes \
        -fsyntax-only "$c_file" > "$clang_log" 2>&1; then
        cat "$clang_log"
        return 1
    fi
}

check_module arithmetic <<'DUO'
function add(a: i64, b: i64) -> i64
  return a + b
end

function mix(a: i64, b: i64) -> i64
  local x: i64 = add(a, b)
  local y: i64 = (x * 3) - (b // 2)
  return y % 97
end

local result: i64 = mix(40, 2)
DUO

check_module floats_and_branches <<'DUO'
function scale(x: f64, n: i64) -> f64
  if n > 10 then
    return x * 2.5
  elseif n == 10 then
    return x + 1.25
  end
  return x / 2.0
end

local a: f64 = scale(3.0, 12)
local b: bool = a > 1.0
DUO

check_module loops <<'DUO'
function sum_to(n: i64) -> i64
  local acc: i64 = 0
  local i: i64 = 1
  while i <= n do
    acc = acc + i
    i = i + 1
  end
  return acc
end

local total: i64 = sum_to(16)
DUO

check_module strings <<'DUO'
function middle(s: str): str
  return string.sub(s, 2, 4)
end

function label(n: i64): str
  local s: str = tostring(n)
  return middle("abcdef") .. s
end

local out: str = label(42)
DUO

check_module records_and_globals <<'DUO'
@packed
@align(16)
global gp: { x: i8, y: i64 } = { x = 1, y = 2 }

function sum_point(): i64
  @packed
  @align(8)
  local p: { x: i8, y: i64 } = { x = 3, y = 4 }
  return gp.y + p.y
end

local n: i64 = sum_point()
DUO

check_module record_alias_params <<'DUO'
type Point = { x: i64, y: i64 }

function get_y(p: { x: i64, y: i64 }) -> i64
  return p.y
end

function sum_point(p: Point) -> i64
  return p.x + p.y
end

local p: Point = { x = 5, y = 7 }
local a: i64 = get_y({ x = 3, y = 4 })
local b: i64 = sum_point(p)
DUO

check_module bitwise <<'DUO'
function bits(a: i64, b: i64, s: i64) -> i64
  local x: i64 = (a & b) | (a ~ b)
  local y: i64 = (a & 65535) << s
  local z: i64 = y >> s
  return x + z + (~b)
end

local n: i64 = bits(123456, 7890, 3)
DUO

check_module native_indexing <<'DUO'
function pointer_read(xs: *i32, i: i64) -> i32
  return xs[i]
end
DUO
if ! grep -Fq 'return xs[i];' "$TMP_DIR/native_indexing.c"; then
    echo "native pointer indexing did not remain a direct typed C index" >&2
    exit 1
fi

check_module typed_function_values <<'DUO'
function increment(x: i32) -> i32
  return x + 1
end

function apply(f: (i32) -> i32, x: i32) -> i32
  return f(x)
end

local result: i32 = apply(increment, 41)
DUO
if ! grep -Fq 'int32_t (*f)(int32_t)' "$TMP_DIR/typed_function_values.c" ||
   ! grep -Fq 'return f(x);' "$TMP_DIR/typed_function_values.c"; then
    echo "typed function parameter/call did not remain direct native C" >&2
    exit 1
fi

echo "[Property 11] SUCCESS"
