#!/usr/bin/env python3
"""Check or patch an isolated mitmproxy 12.2.3 copy for grpc-exp HTTP/2.

This does not start a proxy, install trust, or access a phone or network.
Only exact known source files inside this repository's .private directory are
accepted. Use --apply to make changes; the default is verification only.
"""
import argparse
import hashlib
import os
from pathlib import Path
import tempfile


PATCHES = (
    (
        "mitmproxy/proxy/layers/http/__init__.py",
        "0e7b3474f7febddcf81cb69685f3cd9a3b7af9c849ae47925add565e9ed67d4c",
        "976c3c5f49f6eb8e3f0ef9a2ccb47537296934e9efb9ff0844d0c73327ba78c9",
        (
            (b'== b"h2"', b'in (b"h2", b"grpc-exp")', 5),
            (b'!= b"h2"', b'not in (b"h2", b"grpc-exp")', 2),
        ),
    ),
    (
        "mitmproxy/proxy/layers/tls.py",
        "76e315d8e64355a757183d3f4dbace43550ce4092d1907547ed9ddf40c6a2c39",
        "e82564ae533e4ff62bb595f33e4fbb19435c139521556f7f22e460c86424d018",
        (
            (
                b"HTTP_ALPNS = (HTTP3_ALPN, HTTP2_ALPN, *HTTP1_ALPNS)",
                b'HTTP_ALPNS = (HTTP3_ALPN, HTTP2_ALPN, b"grpc-exp", *HTTP1_ALPNS)',
                1,
            ),
        ),
    ),
)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def inspect_runtime(runtime, private_root):
    runtime = runtime.resolve()
    if not runtime.is_relative_to(private_root.resolve()):
        raise ValueError("Runtime must be an isolated copy inside .private")
    candidates = list(runtime.glob("lib/python*/site-packages"))
    if len(candidates) != 1:
        raise ValueError("Expected exactly one Python site-packages directory")
    planned = []
    for relative, original_hash, patched_hash, replacements in PATCHES:
        path = candidates[0] / relative
        if not path.resolve().is_relative_to(runtime) or path.stat().st_nlink != 1:
            raise ValueError("Refusing a symlink or shared package-cache hard link")
        original = path.read_bytes()
        if digest(original) == patched_hash:
            continue
        if digest(original) != original_hash:
            raise ValueError(f"Unexpected source hash: {relative}")
        patched = original
        for old, new, count in replacements:
            if patched.count(old) != count:
                raise ValueError(f"Unexpected replacement count: {relative}")
            patched = patched.replace(old, new)
        if digest(patched) != patched_hash:
            raise ValueError(f"Unexpected patched hash: {relative}")
        backup = path.with_suffix(path.suffix + ".unmodified")
        if backup.exists() and backup.read_bytes() != original:
            raise ValueError(f"Conflicting source backup: {relative}")
        planned.append((path, backup, original, patched))
    return planned


def main():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime", type=Path,
                        default=root / ".private/tools/mitmproxy-grpc")
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    try:
        planned = inspect_runtime(args.runtime, root / ".private")
        if planned and not args.apply:
            parser.exit(1, f"{len(planned)} source file(s) need the grpc-exp fix; use --apply.\n")
        for path, backup, original, patched in planned:
            if not backup.exists():
                with backup.open("xb") as output:
                    output.write(original)
            # Replace each verified file atomically. Stop the runtime first.
            with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as output:
                temporary = Path(output.name)
                output.write(patched)
            try:
                temporary.chmod(path.stat().st_mode & 0o777)
                os.replace(temporary, path)
            finally:
                temporary.unlink(missing_ok=True)
        assert not inspect_runtime(args.runtime, root / ".private")
    except (OSError, ValueError) as error:
        parser.exit(1, f"Runtime preparation failed: {error}\n")
    print("Both grpc-exp fixes match the verified source hashes.")


if __name__ == "__main__":
    main()
