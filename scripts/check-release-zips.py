"""Check the three release ZIPs against the feature payload in this checkout."""

import argparse
import hashlib
import plistlib
import struct
from pathlib import Path, PurePosixPath
from zipfile import ZipFile


ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / "Sources/Inkrail/Resources"
WINDOWS = ROOT / "packaging/windows"
RUNTIME_NOTICES = {
    "notices/DotNet/LICENSE.TXT",
    "notices/DotNet/THIRD-PARTY-NOTICES.TXT",
    "notices/WebView2/LICENSE.txt",
    "notices/WebView2/NOTICE.txt",
    "notices/WindowsDesktop/LICENSE",
}


def source_files(folder):
    return {p.relative_to(folder).as_posix(): p for p in folder.rglob("*")
            if p.is_file() and not any(part.startswith(".") for part in p.relative_to(folder).parts)}


def check_contents(archive, name, source):
    if archive.read(name) != source.read_bytes():
        raise ValueError(f"{archive.filename}: {name} differs from {source.relative_to(ROOT)}")


def check_no_screenshots(archive, screenshots):
    names = {source.name.casefold() for source in screenshots}
    by_size = {}
    for source in screenshots:
        by_size.setdefault(source.stat().st_size, []).append(source)
    for entry in archive.infolist():
        path = PurePosixPath(entry.filename.casefold())
        if "screenshots" in path.parts or path.name in names:
            raise ValueError(f"{archive.filename}: contains documentation screenshot {entry.filename}")
        for source in by_size.get(entry.file_size, ()):
            if archive.read(entry) == source.read_bytes():
                raise ValueError(f"{archive.filename}: {entry.filename} contains {source.name}")


def check_universal_executable(archive, executable):
    if not (executable.external_attr >> 16) & 0o111:
        raise ValueError("Inkrail.zip: the app binary is missing its executable permission")

    # mach-o/fat.h uses big-endian headers with either 32- or 64-bit file offsets.
    arch_records = {0xCAFEBABE: struct.Struct(">IIIII"), 0xCAFEBABF: struct.Struct(">IIQQII")}
    with archive.open(executable) as binary:
        magic, count = struct.unpack(">II", binary.read(8))
        if magic not in arch_records or count != 2:
            raise ValueError("Inkrail.zip: expected a universal app for x86_64 and arm64")
        record = arch_records[magic]
        slices = list(record.iter_unpack(binary.read(count * record.size)))
        if {entry[0] for entry in slices} != {0x01000007, 0x0100000C}:  # x86_64, arm64
            raise ValueError("Inkrail.zip: expected both x86_64 and arm64 slices")
        for cpu, _, offset, size, *_ in slices:
            if size < 32 or offset + size > executable.file_size:
                raise ValueError("Inkrail.zip: truncated Mach-O slice")
            binary.seek(offset)
            # Both architectures use little-endian 64-bit Mach-O executables (MH_EXECUTE).
            magic, inner_cpu, _, file_type = struct.unpack("<IIII", binary.read(16))
            if (magic, inner_cpu, file_type) != (0xFEEDFACF, cpu, 2):
                raise ValueError("Inkrail.zip: invalid Mach-O executable slice")


def check_mac(directory, resources, screenshots):
    with ZipFile(directory / "Inkrail.zip") as archive:
        check_no_screenshots(archive, screenshots)
        contents = "Inkrail.app/Contents/"
        plist = plistlib.loads(archive.read(contents + "Info.plist"))
        executable = archive.getinfo(contents + "MacOS/" + plist["CFBundleExecutable"])
        check_universal_executable(archive, executable)
        check_contents(archive, contents + "Resources/LICENSE.txt", ROOT / "LICENSE")
        bundle = contents + "Resources/Inkrail_Inkrail.bundle/"
        if bundle + "Contents/Info.plist" in archive.namelist():
            bundle += "Contents/Resources/"
        for name, source in resources.items():
            check_contents(archive, bundle + name, source)
        media_extensions = (".png", ".wav", ".mp3")
        artwork_and_audio = {name[len(bundle):] for name in archive.namelist()
                             if name.startswith(bundle) and name.endswith(media_extensions)}
        if artwork_and_audio != {name for name in resources if name.endswith(media_extensions)}:
            raise ValueError("Inkrail.zip: unexpected artwork or sound in the app bundle")


def check_architecture(archive, name, arch):
    with archive.open(name) as binary:
        if binary.read(2) != b"MZ":
            raise ValueError(f"{arch}: {name} has no DOS header")
        binary.seek(0x3C)
        binary.seek(int.from_bytes(binary.read(4), "little"))
        magic, machine = struct.unpack("<4sH", binary.read(6))
        if magic != b"PE\0\0" or machine != {"x64": 0x8664, "arm64": 0xAA64}[arch]:
            raise ValueError(f"{arch}: {name} has the wrong PE architecture")


def check_windows(directory, arch, expected, screenshots):
    root = f"Inkrail-Windows-{arch}/"
    with ZipFile(directory / (root[:-1] + ".zip")) as archive:
        check_no_screenshots(archive, screenshots)
        entries = [item.filename for item in archive.infolist() if not item.is_dir()]
        if not all(name.startswith(root) for name in entries) or len(entries) != len(set(entries)):
            raise ValueError(f"{arch}: unexpected ZIP root or duplicate file")
        for name in ("Inkrail.exe", "coreclr.dll", "WebView2Loader.dll"):
            check_architecture(archive, root + name, arch)

        for name, source in expected.items():
            check_contents(archive, root + name, source)
        feature_files = {entry[len(root):] for entry in entries
                         if entry.startswith((root + "ui/", root + "notices/"))}
        unexpected = feature_files - expected.keys() - RUNTIME_NOTICES
        if unexpected:
            raise ValueError(f"{arch}: unexpected editor assets or notices: {sorted(unexpected)}")
        notices = {name: archive.read(root + name) for name in RUNTIME_NOTICES}
        if not all(content.strip() for content in notices.values()):
            raise ValueError(f"{arch}: empty runtime redistribution notice")

        manifest = archive.read(root + "files.sha256").decode("utf-8").splitlines()
        checked = set()
        for line in manifest:
            digest, name = line.split("  ", 1)
            with archive.open(root + name) as item:
                actual = hashlib.sha256()
                while chunk := item.read(1024 * 1024):
                    actual.update(chunk)
            if actual.hexdigest() != digest or name in checked:
                raise ValueError(f"{arch}: invalid or duplicate checksum for {name}")
            checked.add(name)
        if checked != {entry[len(root):] for entry in entries} - {"files.sha256"}:
            raise ValueError(f"{arch}: checksums do not cover the complete package")
        return notices


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    args = parser.parse_args()
    resources = source_files(RESOURCES)
    screenshots = source_files(ROOT / "screenshots").values()
    expected = {"LICENSE.txt": ROOT / "LICENSE", "START-HERE.txt": WINDOWS / "START-HERE.txt",
                "Check-Inkrail.ps1": WINDOWS / "Check-Inkrail.ps1"}
    for folder in ("ui", "notices"):
        expected.update({f"{folder}/{name}": source for name, source in source_files(WINDOWS / folder).items()})
    for name, source in resources.items():
        destination = "notices/" if name == "Sound-Credits.txt" else "ui/assets/"
        expected[destination + name] = source

    check_mac(args.directory, resources, screenshots)
    x64_notices = check_windows(args.directory, "x64", expected, screenshots)
    arm64_notices = check_windows(args.directory, "arm64", expected, screenshots)
    if x64_notices != arm64_notices:
        raise ValueError("The two Windows releases contain different runtime notices")
    print("Verified the universal macOS app, native x64 and ARM64 hosts, Windows manifests, "
          "and the shared editor, fonts, artwork, sounds and credits.")


if __name__ == "__main__":
    main()
