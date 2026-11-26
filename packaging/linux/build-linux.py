"""Assemble a portable Linux Inkrail bundle from the shared desk.

Usage:
    python3 packaging/linux/build-linux.py
    python3 packaging/linux/build-linux.py --output dist/Inkrail-Linux.tar.gz
"""

from __future__ import annotations

import argparse
import hashlib
import os
import platform
import shutil
import stat
import tarfile
from pathlib import Path

from inkrail_linux.assets import prepare_ui

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
DESKTOP = """[Desktop Entry]
Type=Application
Version=1.0
Name=Inkrail
GenericName=Writing Desk
Comment=A quiet place to write letters
Exec=inkrail
Icon=inkrail
Terminal=false
Categories=Office;Writer;
StartupWMClass=Inkrail
Keywords=writing;typewriter;letters;markdown;
"""


def package_files(bundle: Path):
    for path in sorted(bundle.rglob("*")):
        if path.is_file():
            yield path.relative_to(bundle).as_posix(), path


def write_manifest(bundle: Path) -> int:
    hashes = []
    for name, path in package_files(bundle):
        if name == "files.sha256":
            continue
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        hashes.append(f"{digest}  {name}\n")
    (bundle / "files.sha256").write_text("".join(hashes), encoding="utf-8")
    return len(hashes)


def check_manifest(bundle: Path) -> None:
    expected = {}
    for line in (bundle / "files.sha256").read_text(encoding="utf-8").splitlines():
        digest, name = line.split("  ", 1)
        expected[name] = digest
    actual = {name: hashlib.sha256(path.read_bytes()).hexdigest()
              for name, path in package_files(bundle) if name != "files.sha256"}
    if expected != actual:
        missing = sorted(set(expected) - set(actual))
        changed = sorted(name for name in set(expected) & set(actual) if expected[name] != actual[name])
        extra = sorted(set(actual) - set(expected))
        raise SystemExit(f"Bundle verification failed: missing={missing} changed={changed} extra={extra}")


def build(bundle: Path, output: Path | None = None) -> Path:
    bundle = bundle.resolve()
    if bundle.exists():
        shutil.rmtree(bundle)
    bundle.mkdir(parents=True)

    for name in ("inkrail", "inkrail_linux"):
        source = HERE / name
        if source.is_dir():
            destination = bundle / name
            shutil.copytree(source, destination, ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
        else:
            shutil.copy2(source, bundle / name)
    launcher = bundle / "inkrail"
    launcher.chmod(launcher.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)

    prepare_ui(bundle / "ui")
    (bundle / "share/applications").mkdir(parents=True)
    (bundle / "share/icons/hicolor/512x512/apps").mkdir(parents=True)
    (bundle / "share/applications/inkrail.desktop").write_text(DESKTOP, encoding="utf-8")
    shutil.copy2(ROOT / "docs/assets/inkrail-app-icon.png",
                 bundle / "share/icons/hicolor/512x512/apps/inkrail.png")
    shutil.copy2(ROOT / "LICENSE", bundle / "LICENSE.txt")
    shutil.copy2(ROOT / "Sources/Inkrail/Resources/Sound-Credits.txt", bundle / "Sound-Credits.txt")
    shutil.copy2(HERE / "START-HERE.md", bundle / "START-HERE.md")
    count = write_manifest(bundle)
    check_manifest(bundle)

    if output is not None:
        output = output.resolve()
        output.parent.mkdir(parents=True, exist_ok=True)
        with tarfile.open(output, "w:gz") as archive:
            archive.add(bundle, arcname=bundle.name)
        print(f"Created {output} ({count} files)")
    print(f"Created {bundle} ({count} files)")
    return bundle


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle", type=Path, default=ROOT / "dist" / f"Inkrail-Linux-{platform.machine()}")
    parser.add_argument("--output", type=Path, default=None, help="optional .tar.gz archive")
    parser.add_argument("--check", action="store_true", help="verify an existing bundle")
    args = parser.parse_args()
    if args.check:
        check_manifest(args.bundle)
        print(f"Verified {args.bundle}")
    else:
        build(args.bundle, args.output)
