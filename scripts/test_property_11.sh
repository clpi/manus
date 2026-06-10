#!/usr/bin/env bash
set -e

echo "[Property 11] Testing C codegen..."
cat << 'DUO' > tests/.tmp_prop11.duo
function add(a: i64, b: i64) -> i64
  return a + b
end

function get_f64() -> f64
  return 3.14
end

function do_stuff(x: i64, y: i64) -> i64
  local z: i64 = add(x, y)
  local f: f64 = get_f64()
  if z > 0 then
    return z
  end
  return 0
end
DUO

./zig-out/bin/duo dump-c tests/.tmp_prop11.duo > tests/.tmp_prop11.c
if [[ "$(uname)" == "Darwin" ]]; then
    xcrun clang -Wall -Wextra -pedantic -std=c11 -Wno-unused-variable -Wno-strict-prototypes -fsyntax-only tests/.tmp_prop11.c
else
    clang -Wall -Wextra -pedantic -std=c11 -Wno-unused-variable -Wno-strict-prototypes -fsyntax-only tests/.tmp_prop11.c
fi
echo "[Property 11] SUCCESS"
rm -f tests/.tmp_prop11.*
