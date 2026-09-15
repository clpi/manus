#!/usr/bin/env python3
"""Compile-time evidence producer for bench/run.sh.

Measures source->executable compile time with HARD validation.

Usage:
    ctime.py <native> <benchdir> <prog> <sdk> <workdir> <out-json> <compilers>
             [route] [idol_bin]

    <compilers> is a space-separated list drawn from run.sh's discovered set,
    e.g. "idol clang gcc". "idol" takes the nativebench pipeline route;
    every other name is invoked as "<cc> -O3 <prog>.c -o <artifact>".
    [route] is "restricted" (default) or "production"; on the production
    route "idol" compiles via <idol_bin> (zig-out/bin/idol)
    `compile <prog>.id --backend native --no-cache -o <artifact>`.

Measurement-integrity contract (the point of this file):
  - A duration qualifies as a SUCCESSFUL compilation ONLY when every required
    stage succeeds AND the artifact is validated:
        idol : produce (nativebench rc 0) -> decode (valid nonempty hex) ->
               link (ld rc 0) -> validate (executable exists, size > 0)
        idol (production route): compile
               (zig-out/bin/idol compile --backend native --no-cache rc 0) ->
               validate (executable exists, size > 0)
        clang/gcc: compile (cc rc 0) -> validate (executable exists, size > 0)
  - Failed attempts are recorded as FAILED work (stage, rc, stderr tail,
    stdout tail, and the wall-clock cost of the failed attempt). They stay
    visible in the output but are NEVER mixed into the success median.
  - The producer exits 0 even when every attempt fails: a failed compilation
    is data, not a harness crash. It exits nonzero only on harness errors
    (bad arguments, missing inputs).
  - Attempts are INTERLEAVED round-robin across compilers (idol, clang, gcc,
    idol, clang, gcc, ...) so thermal drift and background load affect every
    compiler's attempts equally.
"""
import hashlib
import json
import os
import subprocess
import sys
import time

ATTEMPTS = 5
LD_FLAGS = ["-arch", "arm64", "-e", "_idolmain",
            "-platform_version", "macos", "14.0", "14.0"]


def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, **kw)


def validate_artifact(path):
    """Return None when the artifact is acceptable, else a reason string."""
    try:
        st = os.stat(path)
    except OSError:
        return "missing"
    if st.st_size == 0:
        return "empty"
    return None


def failed(stage, rc, t0, stderr, stdout=b""):
    # stdout_tail: compilers may report the rejection on stdout (e.g. the
    # native backend's "indexed array memory unsupported" goes to stdout);
    # a failure record that cannot show the reason is failed evidence.
    return {
        "status": "failed",
        "stage": stage,
        "rc": rc,
        "duration_s": time.perf_counter() - t0,
        "stderr_tail": (stderr or b"")[-300:].decode("utf-8", "replace"),
        "stdout_tail": (stdout or b"")[-300:].decode("utf-8", "replace"),
    }


def succeeded(t0, artifact):
    return {
        "status": "success",
        "duration_s": time.perf_counter() - t0,
        "artifact_bytes": os.stat(artifact).st_size,
    }


def attempt_idol(native, prog_id, sdk, workdir, tag):
    """One idol compile attempt: produce -> decode -> link -> validate."""
    t0 = time.perf_counter()
    obj = os.path.join(workdir, tag + ".cto.o")
    exe = os.path.join(workdir, tag + ".cto")
    with open(prog_id, "rb") as fh:
        p1 = run([native], stdin=fh)
    if p1.returncode != 0:
        return failed("produce", p1.returncode, t0, p1.stderr, p1.stdout)
    try:
        code = bytes.fromhex(p1.stdout.decode("ascii"))
    except Exception as e:  # noqa: BLE001 - any decode failure is failed work
        return failed("decode", "bad-hex", t0, str(e)[:200].encode())
    if not code:
        return failed("decode", "empty-object", t0, b"producer emitted no bytes")
    with open(obj, "wb") as fh:
        fh.write(code)
    p3 = run(["ld"] + LD_FLAGS + ["-syslibroot", sdk, obj, "-lSystem", "-o", exe])
    if p3.returncode != 0:
        return failed("link", p3.returncode, t0, p3.stderr, p3.stdout)
    why = validate_artifact(exe)
    if why is not None:
        return failed("validate", why, t0, b"")
    return succeeded(t0, exe)


def attempt_idol_prod(idol_bin, prog_id, workdir, tag):
    """One production-route idol compile attempt: compile -> validate."""
    t0 = time.perf_counter()
    exe = os.path.join(workdir, tag + ".cto")
    p = run([idol_bin, "compile", prog_id, "--backend", "native",
             "--no-cache", "-o", exe])
    if p.returncode != 0:
        return failed("compile", p.returncode, t0, p.stderr, p.stdout)
    why = validate_artifact(exe)
    if why is not None:
        return failed("validate", why, t0, b"")
    return succeeded(t0, exe)


def attempt_cc(cc, prog_c, workdir, tag):
    """One C-compiler attempt: compile -> validate."""
    t0 = time.perf_counter()
    exe = os.path.join(workdir, tag + ".cto-" + cc)
    p = run([cc, "-O3", prog_c, "-o", exe])
    if p.returncode != 0:
        return failed("compile", p.returncode, t0, p.stderr, p.stdout)
    why = validate_artifact(exe)
    if why is not None:
        return failed("validate", why, t0, b"")
    return succeeded(t0, exe)


def median(xs):
    s = sorted(xs)
    return s[len(s) // 2]

def sha256_of(path):
    """Hex SHA-256 of the file's exact bytes; None when unreadable."""
    try:
        h = hashlib.sha256()
        with open(path, "rb") as fh:
            for chunk in iter(lambda: fh.read(65536), b""):
                h.update(chunk)
        return h.hexdigest()
    except OSError:
        return None


def main():
    if len(sys.argv) not in (8, 10):
        print("usage: ctime.py <native> <benchdir> <prog> <sdk> "
              "<workdir> <out-json> <compilers> [route] [idol_bin]",
              file=sys.stderr)
        return 2
    native, benchdir, prog, sdk, workdir, out_json, compilers = sys.argv[1:8]
    route = sys.argv[8] if len(sys.argv) > 8 else "restricted"
    idol_bin = sys.argv[9] if len(sys.argv) > 9 else None
    if route not in ("restricted", "production"):
        print("ctime: bad route: " + route, file=sys.stderr)
        return 2
    if route == "production" and not idol_bin:
        print("ctime: production route needs idol_bin", file=sys.stderr)
        return 2
    compilers = compilers.split()
    if "idol" not in compilers:
        print("ctime: compilers must include idol", file=sys.stderr)
        return 2
    prog_id = os.path.join(benchdir, "programs", prog + ".id")
    prog_c = os.path.join(benchdir, "programs", prog + ".c")
    reqs = [prog_id, prog_c, workdir]
    # The macOS SDK path is consumed only by the restricted route's macOS-ld
    # link step; the production route never references it (and no SDK exists
    # on Linux hosts).
    if route == "restricted":
        reqs.append(sdk)
    reqs.append(idol_bin if route == "production" else native)
    for req in reqs:
        if not os.path.exists(req):
            print("ctime: missing input: " + req, file=sys.stderr)
            return 2

    attempts = {cc: [] for cc in compilers}
    for _ in range(ATTEMPTS):  # interleaved round-robin across compilers
        for cc in compilers:
            tag = "%s.%s" % (prog, cc)
            if cc == "idol":
                if route == "production":
                    attempts[cc].append(
                        attempt_idol_prod(idol_bin, prog_id, workdir, tag))
                else:
                    attempts[cc].append(
                        attempt_idol(native, prog_id, sdk, workdir, tag))
            else:
                attempts[cc].append(attempt_cc(cc, prog_c, workdir, tag))

    results = {}
    for cc in compilers:
        atts = attempts[cc]
        ok_ds = [a["duration_s"] for a in atts if a["status"] == "success"]
        fails = [a for a in atts if a["status"] != "success"]
        entry = {
            "attempts": ATTEMPTS,
            "succeeded": len(ok_ds),
            "failed": len(fails),
            "failures": fails,  # FAILED work: visible, never in the median
        }
        if ok_ds:
            entry["status"] = "success"
            entry["median_s"] = median(ok_ds)
            entry["success_durations_s"] = ok_ds
        else:
            entry["status"] = "failed"
            entry["median_s"] = None
        results[cc] = entry

    # Producer binding: hash the exact idol compiler binary whose attempts
    # are measured here, so the compile-time record names its subject.
    producer_bin = idol_bin if route == "production" else native
    producer = {"idol_compiler": producer_bin,
                "sha256": sha256_of(producer_bin),
                "route": route}
    if producer["sha256"] is None:
        print("ctime: FATAL: cannot hash producer binary " + str(producer_bin),
              file=sys.stderr)
        return 2

    with open(out_json, "w") as fh:
        json.dump({"compilers": results,
                   "attempts_per_compiler": ATTEMPTS,
                   "producer": producer}, fh, indent=2)
    return 0


if __name__ == "__main__":
    sys.exit(main())
