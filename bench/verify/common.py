#!/usr/bin/env python3
"""Shared build/run/compare primitives for bench/verify.

Builds go through the platform shim interface (bench/platforms/lib.sh),
so this suite works on any host whose shim reports plat_status=supported.
The compiler under test is always built fresh from lib/compiler/native.id
into verify/.work/ — never the sibling workstream's bench/.work/.
"""
import os
import shlex
import shutil
import subprocess
import sys

THIS = os.path.dirname(os.path.abspath(__file__))
BENCH = os.path.dirname(THIS)
REPO = os.path.dirname(BENCH)
PLATFORMS = os.path.join(BENCH, "platforms")


class InfraError(RuntimeError):
    pass


def host_triple():
    import platform as _p
    m = _p.machine().lower()
    s = _p.system()
    arch = {"arm64": "arm64", "aarch64": "arm64",
            "x86_64": "x86_64", "amd64": "x86_64"}.get(m, m)
    ops = {"darwin": "macos", "linux": "linux", "windows": "windows"}.get(
        s.lower(), s.lower())
    return f"{arch}-{ops}"


def load_shim():
    """Return (shim_path, triple); raise InfraError if host unsupported."""
    path = os.path.join(PLATFORMS, host_triple() + ".sh")
    if not os.path.isfile(path):
        raise InfraError(f"no platform shim for {host_triple()}")
    out = subprocess.run(
        ["bash", "-c", f'source {shlex.quote(path)}; echo "$plat_status"'],
        capture_output=True, text=True, timeout=30)
    if out.stdout.strip() != "supported":
        raise InfraError(f"platform {host_triple()} shim status is not "
                         f"'supported' (see bench/platforms/)")
    return path


def ensure_native(work):
    """Build nativebench from lib/compiler/native.id into work/."""
    os.makedirs(work, exist_ok=True)
    nb = os.path.join(work, "nativeverify")
    if os.path.isfile(nb) and os.access(nb, os.X_OK):
        return nb
    idol_bin = os.path.join(REPO, "zig-out", "bin", "idol")
    if not (os.path.isfile(idol_bin) and os.access(idol_bin, os.X_OK)):
        raise InfraError(f"idol binary missing: {idol_bin} "
                         "(run 'zig build' in the repo first)")
    src = os.path.join(REPO, "lib", "compiler", "native.id")
    r = subprocess.run([idol_bin, "compile", src, "--backend", "native",
                        "-o", nb],
                       capture_output=True, text=True, timeout=600)
    if r.returncode != 0 or not os.access(nb, os.X_OK):
        raise InfraError("nativeverify build failed:\n" + r.stderr[-3000:])
    return nb


def _shim_fn(shim, native, fn, *args):
    q = " ".join(shlex.quote(a) for a in args)
    script = ("set -e; IDOL_NATIVE={nb}; source {sh}; {fn} {args}"
              .format(nb=shlex.quote(native), sh=shlex.quote(shim),
                      fn=fn, args=q))
    return subprocess.run(["bash", "-c", script],
                          capture_output=True, text=True, timeout=180)


def build_idol(shim, native, work, tag, idol_src):
    """Compile Idol source -> executable. Returns (exe_path, log)."""
    src = os.path.join(work, tag + ".id")
    obj = os.path.join(work, tag + ".o")
    exe = os.path.join(work, tag + ".idol")
    with open(src, "w") as f:
        f.write(idol_src)
    r = _shim_fn(shim, native, "plat_idol_object", src, obj)
    if r.returncode != 0:
        return None, f"plat_idol_object failed:\n{r.stderr[-2000:]}"
    r = _shim_fn(shim, native, "plat_link", obj, exe)
    if r.returncode != 0:
        return None, f"plat_link failed:\n{r.stderr[-2000:]}"
    if not os.access(exe, os.X_OK):
        return None, "link produced no executable"
    return exe, ""


def build_c(shim, native, work, tag, c_src):
    """Compile C source -> executable. Returns (exe_path, log)."""
    src = os.path.join(work, tag + ".c")
    exe = os.path.join(work, tag + ".clang")
    with open(src, "w") as f:
        f.write(c_src)
    r = _shim_fn(shim, native, "plat_c_exe", src, exe)
    if r.returncode != 0:
        return None, f"plat_c_exe failed:\n{r.stderr[-2000:]}"
    if not os.access(exe, os.X_OK):
        return None, "C compile produced no executable"
    return exe, ""


def run_exe(path, timeout=30):
    """Run executable. Returns ('ok', rc) | ('timeout', None) | ('signal', n)."""
    try:
        p = subprocess.run([path], capture_output=True, timeout=timeout)
        if p.returncode < 0:
            return ("signal", -p.returncode)
        return ("ok", p.returncode)
    except subprocess.TimeoutExpired:
        return ("timeout", None)


# --- full-observability transforms ---------------------------------------
# The harness observes only the process exit code (low 8 bits of x0).
# For full 64-bit observability, a case whose Idol source ends in a bare
# variable R is re-run 8 times, each returning (R / 256^k) so the exit
# code exposes byte k. Division is truncating on both sides (ARM64 sdiv
# and C signed /), so byte slices agree even for negative R.
# Reserved: generators must not use the variable name `q`.

def idol_byte_variants(idol_src, ret_var, max_byte=7):
    lines = idol_src.strip().split("\n")
    if lines[-1].strip() != ret_var:
        raise InfraError(f"generator contract broken: last line "
                         f"{lines[-1]!r} != ret var {ret_var!r}")
    base = lines[:-1]
    out = {}
    for k in range(max_byte + 1):
        v = base + [f"q = {ret_var}"] + ["q = q / 256"] * k + ["q"]
        out[k] = "\n".join(v) + "\n"
    return out


def c_byte_variants(c_body, ret_expr, signed, max_byte=7):
    out = {}
    for k in range(max_byte + 1):
        if signed:
            decl = f"long long __s = ({ret_expr});" + "__s = __s / 256;" * k
            tail = "return (int)((unsigned long long)__s & 255);"
        else:
            decl = (f"unsigned long long __q = "
                    f"(unsigned long long)({ret_expr});"
                    + "__q = __q / 256ULL;" * k)
            tail = "return (int)(__q & 255);"
        out[k] = f"int main(void){{{c_body}{decl}{tail}}}"
    return out


def c_plain(c_body, ret_expr, signed):
    return c_byte_variants(c_body, ret_expr, signed, max_byte=0)[0]
