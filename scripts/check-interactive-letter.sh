#!/bin/bash
# Generate real recipient files with the Mac exporter, without opening a save panel.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT="$ROOT/.build/interactive-letter-check"
mkdir -p "$OUTPUT/ModuleCache" "$OUTPUT/FixtureResources.bundle"
RESOURCES="$ROOT/Sources/Inkrail/Resources"
cp "$RESOURCES"/{InteractiveLetter.html,ProtectedInteractiveLetter.html,letter-seal-wax.png,paper-grain.png,paper-unfold.mp3} "$OUTPUT/FixtureResources.bundle/"
FLAGS=(-swift-version 5 -parse-as-library -sdk "$(xcrun --sdk macosx --show-sdk-path)"
       -target "$(uname -m)-apple-macos13.0" -module-cache-path "$OUTPUT/ModuleCache")
xcrun swiftc "${FLAGS[@]}" -emit-library -emit-module -module-name InkrailCore \
    -emit-module-path "$OUTPUT/InkrailCore.swiftmodule" \
    -Xlinker -install_name -Xlinker @rpath/libInkrailCore.dylib \
    "$ROOT"/Sources/InkrailCore/*.swift -o "$OUTPUT/libInkrailCore.dylib"
xcrun swiftc "${FLAGS[@]}" -I "$OUTPUT" -L "$OUTPUT" -lInkrailCore \
    -Xlinker -rpath -Xlinker @loader_path \
    "$ROOT"/Sources/Inkrail/Services/{Resources,InteractiveLetterExport}.swift \
    "$ROOT/scripts/fixtures/interactive-letter-check.swift" -o "$OUTPUT/check"
"$OUTPUT/check" "$OUTPUT"
if [[ "${1:-}" == "--reader" ]]; then
    xcrun swiftc "${FLAGS[@]}" "$ROOT/scripts/fixtures/interactive-reader-check.swift" -o "$OUTPUT/reader-check"
    "$OUTPUT/reader-check" "$OUTPUT/A locked letter.html"
fi
