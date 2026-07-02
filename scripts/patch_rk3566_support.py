#!/usr/bin/env python3
"""Enable RK3566/RK3568 in RKLLM v1.3.0 binaries.

v1.3.0 already ships RKNN Lite / RK3566/RK3568 kernels, but the API blocks them.
This script patches the runtime and toolkit modules in-place.
"""

from __future__ import annotations

import argparse
import shutil
import struct
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]

BASE_ERROR_OLD = b"target_platform must be rk3588, rk3576, rk3562, rv1126b, cuda!"
BASE_ERROR_NEW = b"target_platform must be rk3588, rk3576, rk3566, rv1126b, cuda!"


def patch_bytes(path: Path, offset: int, new: bytes, expected: bytes | None, backup: bool) -> None:
    data = bytearray(path.read_bytes())
    if expected is not None:
        old = data[offset : offset + len(expected)]
        if old != expected:
            raise ValueError(f"{path}@{offset:#x}: expected {expected!r}, got {bytes(old)!r}")
    if backup:
        bak = path.with_suffix(path.suffix + ".bak")
        if not bak.exists():
            shutil.copy2(path, bak)
    data[offset : offset + len(new)] = new
    path.write_bytes(data)
    print(f"patched {path.name} @ {offset:#x}")


def patch_u32(path: Path, offset: int, insn: int, backup: bool) -> None:
    patch_bytes(path, offset, struct.pack("<I", insn), None, backup)


def patch_librkllmrt(path: Path, backup: bool) -> None:
    # hw type w1==1 ("lite" / RK3566): use init path at 0xe4aa8 instead of error
    patch_u32(path, 0xE3BA0, 0x54006300, backup)  # b.eq 0xe4aa8
    # platform id stored for RK3566 models
    patch_u32(path, 0xE4AB0, 0x52800081, backup)  # movz w1, #4
    # accept model platform id 4
    patch_u32(path, 0xE4B8C, 0x7100103F, backup)  # cmp w1, #4

    err_old = b"Platform error, must be either RK3588, RK3576, RV1126B or RK3562. Your platform is %s"
    err_new = b"Platform error, must be RK3588, RK3576, RV1126B, RK3562 or RK3566. Your platform is %s"
    patch_bytes(path, path.read_bytes().find(err_old), err_new, err_old, backup)


def patch_rkllm_base(path: Path, backup: bool) -> None:
    patch_bytes(path, 0x1361C0, BASE_ERROR_NEW, BASE_ERROR_OLD, backup)
    # validation table entry (was rk3562; RK3568 uses the same target string)
    patch_bytes(path, 0x13962E, b"rk3566\x00", b"rk3562\x00", backup)


def patch_converter(path: Path, backup: bool) -> None:
    patch_bytes(path, 0x349E28, b"rk3566\x00", b"rk3562\x00", backup)


def patch_toolkit(site_packages: Path, backup: bool) -> None:
    base = next(site_packages.glob("rkllm/api/rkllm_base.cpython-*.so"))
    conv = next(site_packages.glob("rkllm/base/converter.cpython-*.so"))
    patch_rkllm_base(base, backup)
    patch_converter(conv, backup)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--runtime",
        type=Path,
        default=REPO_ROOT / "rkllm-runtime/Linux/librkllm_api/aarch64/librkllmrt.so",
    )
    parser.add_argument("--site-packages", type=Path, default=None)
    parser.add_argument("--backup", action="store_true")
    args = parser.parse_args()

    if not args.runtime.is_file():
        print(f"missing runtime: {args.runtime}", file=sys.stderr)
        return 1

    site = args.site_packages
    if site is None:
        for root in (REPO_ROOT / ".venv/lib", REPO_ROOT / ".venv/lib64"):
            hits = list(root.glob("python*/site-packages"))
            if hits:
                site = hits[0]
                break
    if site is None or not site.is_dir():
        print("site-packages not found; use --site-packages", file=sys.stderr)
        return 1

    patch_librkllmrt(args.runtime, args.backup)
    patch_toolkit(site, args.backup)
    print("RK3566 support patches applied.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
