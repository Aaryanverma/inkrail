"""Assemble a portable Inkrail ZIP from a published Windows host and the shared desk."""

import argparse
import hashlib
import os
from pathlib import Path
import struct
from tempfile import NamedTemporaryFile
from zipfile import ZIP_DEFLATED, ZipFile


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
RESOURCES = ROOT / "Sources/Inkrail/Resources"
MACHINES = {"x64": 0x8664, "arm64": 0xAA64}


def verify_host(executable, architecture):
    with executable.open("rb") as host:
        if host.read(2) != b"MZ":
            raise ValueError(f"{executable.name} is not a Windows executable")
        host.seek(0x3C)
        pe_offset, = struct.unpack("<I", host.read(4))
        host.seek(pe_offset)
        if host.read(4) != b"PE\0\0":
            raise ValueError(f"{executable.name} has no PE signature")
        machine, = struct.unpack("<H", host.read(2))
    if machine != MACHINES[architecture]:
        raise ValueError(f"{executable.name} has machine 0x{machine:04x}, expected {architecture}")


def package_files(host_dir):
    for path in sorted(host_dir.rglob("*")):
        if path.is_file() and path.suffix.lower() not in {".pdb", ".xml"}:
            yield path.relative_to(host_dir).as_posix(), path
    # Both Windows builds ship the same editor, fonts, artwork and recordings.
    for folder in ("ui", "notices"):
        for path in sorted((HERE / folder).rglob("*")):
            if path.is_file() and not path.name.startswith("."):
                yield path.relative_to(HERE).as_posix(), path
    for path in sorted(RESOURCES.iterdir()):
        if path.suffix in {".png", ".wav", ".mp3"}:
            yield "ui/assets/" + path.name, path
    for template in ("InteractiveLetter.html", "ProtectedInteractiveLetter.html"):
        yield "ui/assets/" + template, RESOURCES / template
    yield "notices/Sound-Credits.txt", RESOURCES / "Sound-Credits.txt"
    yield "LICENSE.txt", ROOT / "LICENSE"
    for name in ("START-HERE.txt", "Check-Inkrail.ps1"):
        yield name, HERE / name


def build_zip(architecture, host_dir, output):
    verify_host(host_dir / "Inkrail.exe", architecture)
    output = output.resolve()
    if output.is_relative_to(host_dir.resolve()):
        raise ValueError("Place the ZIP outside the host publish directory")
    output.parent.mkdir(parents=True, exist_ok=True)
    prefix = f"Inkrail-Windows-{architecture}/"
    hashes = []
    names = {"files.sha256"}
    with NamedTemporaryFile(dir=output.parent, delete=False) as temp:
        temporary = Path(temp.name)
    try:
        with ZipFile(temporary, "w", compression=ZIP_DEFLATED) as archive:
            for name, path in package_files(host_dir):
                if name.casefold() in names:
                    raise ValueError(f"Duplicate package file: {name}")
                names.add(name.casefold())
                digest = hashlib.sha256()
                with path.open("rb") as source, archive.open(prefix + name, "w") as target:
                    while chunk := source.read(1024 * 1024):
                        digest.update(chunk)
                        target.write(chunk)
                hashes.append(f"{digest.hexdigest()}  {name}\n")
            archive.writestr(prefix + "files.sha256", "".join(hashes).encode("utf-8"))
        os.replace(temporary, output)
    finally:
        temporary.unlink(missing_ok=True)
    print(f"Created {output} with {len(hashes)} files ({architecture})")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--arch", required=True, choices=MACHINES)
    parser.add_argument("--host-dir", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    build_zip(args.arch, args.host_dir, args.output)
