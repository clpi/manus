#!/usr/bin/env python3
"""Structural validation for the Idol x86_64 PE/COFF backend.

Builds lib/compiler/pecoffx86.id with the repo idol binary, runs the
emitter, and parses the emitted bytes as PE/COFF, asserting every header
field. No Windows execution target exists on the build machine, so this
validates structure, not runtime behavior.

Usage: python3 test/pecoffx86/check.py   (from repo root)
"""
import os
import struct
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
IDOL = os.path.join(REPO, "zig-out", "bin", "idol")
SRC = os.path.join(REPO, "lib", "compiler", "pecoffx86.id")
WORK = "/tmp/pecoffx86-test"

fails = []


def check(name, got, want):
    if got != want:
        fails.append("%s: got %r want %r" % (name, got, want))
    else:
        print("ok %s = %r" % (name, got))


def main():
    os.makedirs(WORK, exist_ok=True)
    emit = os.path.join(WORK, "peemit")
    r = subprocess.run([IDOL, "compile", SRC, "--backend", "native", "-o", emit],
                       capture_output=True, text=True)
    if r.returncode != 0:
        print(r.stderr)
        sys.exit("emitter build failed")
    hexout = subprocess.run([emit], capture_output=True, text=True).stdout.strip()
    data = bytes.fromhex(hexout)

    check("file size", len(data), 1536)

    # DOS header
    check("dos magic", data[0:2], b"MZ")
    elfanew = struct.unpack_from("<I", data, 0x3C)[0]
    check("e_lfanew", elfanew, 0x80)

    # DOS stub: real-mode code then the message
    check("stub code", data[0x40:0x4E].hex(),
          "0e1fba0e00b409cd21b8014ccd21")
    check("stub msg", data[0x4E:0x79],
          b"This program cannot be run in DOS mode.\r\r\n$")

    # PE signature + COFF header
    check("pe sig", data[elfanew:elfanew + 4], b"PE\0\0")
    coff = elfanew + 4
    machine, nsect, tds, psym, nsym, optsz, chars = struct.unpack_from(
        "<HHIIIHH", data, coff)
    check("machine", hex(machine), "0x8664")
    check("num sections", nsect, 2)
    check("timestamp", tds, 0)
    check("symtab ptr", psym, 0)
    check("num symbols", nsym, 0)
    check("opt header size", optsz, 240)
    check("characteristics", hex(chars), "0x2f")

    # Optional header (PE32+)
    opt = coff + 20
    magic = struct.unpack_from("<H", data, opt)[0]
    check("opt magic", hex(magic), "0x20b")
    (size_code, size_idata, size_udata, entry, base_code,
     image_base, sect_align, file_align) = struct.unpack_from(
        "<IIIIIQII", data, opt + 4)
    check("size of code", size_code, 0x200)
    check("size of idata", size_idata, 0x200)
    check("size of udata", size_udata, 0)
    check("entry rva", hex(entry), "0x1000")
    check("base of code", hex(base_code), "0x1000")
    check("image base", hex(image_base), "0x140000000")
    check("section align", hex(sect_align), "0x1000")
    check("file align", hex(file_align), "0x200")
    (os_maj, os_min, img_maj, img_min, sub_maj, sub_min,
     win32ver, size_image, size_headers, checksum,
     subsystem, dllchars) = struct.unpack_from(
        "<HHHHHHIIIIHH", data, opt + 40)
    check("os version", (os_maj, os_min), (6, 0))
    check("subsystem version", (sub_maj, sub_min), (6, 0))
    check("size of image", hex(size_image), "0x3000")
    check("size of headers", hex(size_headers), "0x200")
    check("checksum", checksum, 0)
    check("subsystem", subsystem, 3)
    check("dll characteristics", hex(dllchars), "0x8160")
    (stack_res, stack_com, heap_res, heap_com,
     loader_flags, nrva) = struct.unpack_from("<QQQQII", data, opt + 72)
    check("stack reserve", hex(stack_res), "0x100000")
    check("num rva sizes", nrva, 16)
    dirs = struct.unpack_from("<" + "II" * 16, data, opt + 112)
    check("export dir", (dirs[0], dirs[1]), (0, 0))
    check("import dir rva", hex(dirs[2]), "0x2000")
    check("import dir size", dirs[3], 40)
    for i in range(2, 16):
        check("datadir[%d] zero" % i, (dirs[i * 2], dirs[i * 2 + 1]), (0, 0))

    # Section headers
    sec = opt + 240
    n1 = data[sec:sec + 8].rstrip(b"\0")
    (vsize1, vaddr1, rawsize1, rawptr1) = struct.unpack_from("<IIII", data, sec + 8)
    flags1 = struct.unpack_from("<I", data, sec + 36)[0]
    check("sect1 name", n1, b".text")
    check("sect1 vsize", vsize1, 54)
    check("sect1 vaddr", hex(vaddr1), "0x1000")
    check("sect1 rawsize", hex(rawsize1), "0x200")
    check("sect1 rawptr", hex(rawptr1), "0x200")
    check("sect1 flags", hex(flags1), "0x60000020")
    n2 = data[sec + 40:sec + 48].rstrip(b"\0")
    (vsize2, vaddr2, rawsize2, rawptr2) = struct.unpack_from(
        "<IIII", data, sec + 48)
    flags2 = struct.unpack_from("<I", data, sec + 76)[0]
    check("sect2 name", n2, b".idata")
    check("sect2 vsize", vsize2, 99)
    check("sect2 vaddr", hex(vaddr2), "0x2000")
    check("sect2 rawsize", hex(rawsize2), "0x200")
    check("sect2 rawptr", hex(rawptr2), "0x400")
    check("sect2 flags", hex(flags2), "0xc0000040")

    # .text: entry code
    text = data[0x200:0x200 + 54]
    check("sub rsp,40", text[0:4].hex(), "4883ec28")
    check("mov rax,6", text[4:14].hex(), "48b80600000000000000")
    check("mov rcx,7", text[14:24].hex(), "48b90700000000000000")
    check("imul rax,rcx", text[24:28].hex(), "480fafc1")
    check("mov rcx,2", text[28:38].hex(), "48b90200000000000000")
    check("add rax,rcx", text[38:41].hex(), "4801c8")
    check("sub rax,rcx", text[41:44].hex(), "4829c8")
    check("mov rcx,rax", text[44:47].hex(), "4889c1")
    check("call opcode", text[47:49].hex(), "ff15")
    disp = struct.unpack_from("<i", text, 49)[0]
    iat_rva = 0x2000 + 56
    call_rva = 0x1000 + 47
    check("call disp32 target", hex(call_rva + 6 + disp), hex(iat_rva))
    check("ret", text[53:54].hex(), "c3")
    check("text padding zero", data[0x200 + 54:0x400], b"\0" * (0x200 - 54))

    # .idata: import directory
    idata = data[0x400:0x400 + 99]
    (ilt, tds2, fwd, name_rva, iat) = struct.unpack_from("<IIIII", idata, 0)
    check("import ilt rva", hex(ilt), "0x2028")
    check("import dll name rva", hex(name_rva), "0x2056")
    check("import iat rva", hex(iat), "0x2038")
    check("null descriptor", idata[20:40], b"\0" * 20)
    (ilt_e,) = struct.unpack_from("<Q", idata, 40)
    check("ilt entry", hex(ilt_e), "0x2048")
    check("ilt null", idata[48:56], b"\0" * 8)
    (iat_e,) = struct.unpack_from("<Q", idata, 56)
    check("iat entry", hex(iat_e), "0x2048")
    check("iat null", idata[64:72], b"\0" * 8)
    (hint,) = struct.unpack_from("<H", idata, 72)
    check("hint", hint, 0)
    check("import name", idata[74:86], b"ExitProcess\0")
    check("dll name", idata[86:99], b"kernel32.dll\0")

    if fails:
        print("\nFAILURES:")
        for f in fails:
            print("FAIL", f)
        sys.exit(1)
    print("\nall structural checks passed")

    # Optional second oracle: pefile, if installed
    try:
        import pefile
        pe = pefile.PE(data=data)
        check("pefile machine", hex(pe.FILE_HEADER.Machine), "0x8664")
        check("pefile entry", hex(pe.OPTIONAL_HEADER.AddressOfEntryPoint), "0x1000")
        check("pefile sections", len(pe.sections), 2)
        imports = getattr(pe, "DIRECTORY_ENTRY_IMPORT", [])
        if imports:
            imp = imports[0]
            check("pefile dll", imp.dll, b"kernel32.dll")
            check("pefile sym", imp.imports[0].name, b"ExitProcess")
        print("ok pefile oracle parsed")
    except ImportError:
        print("skip pefile oracle (not installed)")

    if fails:
        print("\nFAILURES:")
        for f in fails:
            print("FAIL", f)
        sys.exit(1)
    print("pefile oracle checks passed")


if __name__ == "__main__":
    main()
