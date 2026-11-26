"""Assemble the desk assets shared with the Windows build.

The Windows ZIP build copies the same editor files and bundled recordings into
its ``ui`` folder.  The Linux host does the same so that all three platforms
render and sound identical letters.
"""

from __future__ import annotations

import shutil
from pathlib import Path

HERE = Path(__file__).resolve().parent
LINUX = HERE.parent
ROOT = LINUX.parents[1]
WINDOWS_UI = ROOT / "packaging/windows/ui"
RESOURCES = ROOT / "Sources/Inkrail/Resources"


def prepare_ui(target: Path) -> Path:
    """Copy the shared desk, fonts, artwork and sounds into ``target``."""
    target = target.resolve()
    target.mkdir(parents=True, exist_ok=True)
    for source in sorted(WINDOWS_UI.rglob("*")):
        if not source.is_file() or source.name.startswith("."):
            continue
        destination = target / source.relative_to(WINDOWS_UI)
        destination.parent.mkdir(parents=True, exist_ok=True)
        if not destination.exists() or destination.stat().st_mtime != source.stat().st_mtime:
            shutil.copy2(source, destination)
    for source in sorted(RESOURCES.iterdir()):
        if source.suffix.lower() in {".png", ".wav"} and source.is_file():
            destination = target / "assets" / source.name
            if not destination.exists() or destination.stat().st_mtime != source.stat().st_mtime:
                shutil.copy2(source, destination)
    missing = target / "index.html"
    if not missing.is_file():
        raise FileNotFoundError(f"Inkrail desk was not copied to {missing}")
    return target
