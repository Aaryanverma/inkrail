#!/usr/bin/env bash
# Build the portable Linux archive(s) and RPM(s) in a container and copy them to dist/.
# Set VERSION=x.y.z to stamp the RPM (default 0.1.2).
# Usage: packaging/linux/build.sh [x64|arm64|all] [--smoke]
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
engine=${CONTAINER_ENGINE:-$(command -v podman || command -v docker || true)}
[[ -n $engine ]] || { echo "Install podman or docker." >&2; exit 1; }
arches=x64 smoke=0
for arg in "$@"; do
  case $arg in
    x64|arm64) arches=$arg ;;
    all) arches="x64 arm64" ;;
    --smoke) smoke=1 ;;
    *) echo "Usage: $0 [x64|arm64|all] [--smoke]" >&2; exit 2 ;;
  esac
done
mkdir -p "$root/dist"
for arch in $arches; do
  image=inkrail-linux-build:$arch
  "$engine" build -f "$root/packaging/linux/Containerfile" --target dist --build-arg ARCH="$arch" ${VERSION:+--build-arg VERSION="$VERSION"} -t "$image" "$root"
  id=$("$engine" create "$image" /none)
  trap '"$engine" rm -f "$id" >/dev/null' EXIT
  rpm_arch=$([[ $arch == arm64 ]] && echo aarch64 || echo x86_64)
  rm -f "$root/dist/Inkrail-Linux-$arch.tar.gz" "$root/dist/"inkrail-*."$rpm_arch".rpm
  "$engine" cp "$id:/Inkrail-Linux-$arch.tar.gz" "$root/dist/"
  "$engine" export "$id" | tar -x -C "$root/dist" --wildcards 'inkrail-*.rpm'
  "$engine" rm -f "$id" >/dev/null; trap - EXIT
  (cd "$root" && ls dist/Inkrail-Linux-$arch.tar.gz dist/inkrail-*."$rpm_arch".rpm)
  if (( smoke )) && [[ $arch == x64 && $(uname -m) == x86_64 ]]; then
    "$engine" build -f "$root/packaging/linux/Containerfile" --target smoke --build-arg ARCH="$arch" -t inkrail-linux-smoke:$arch "$root"
    "$engine" run --rm inkrail-linux-smoke:$arch
    "$engine" build -f "$root/packaging/linux/Containerfile" --target rpm-smoke --build-arg ARCH="$arch" -t inkrail-linux-rpm-smoke:$arch "$root"
    "$engine" run --rm inkrail-linux-rpm-smoke:$arch
  fi
done
