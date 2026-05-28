#!/usr/bin/env bash
# Build the sysroot tarball from upstream sources (maintainer-only).
#
# Output: build/vscode-sysroot-x86_64-linux-gnu.tgz with patchelf 0.18.0 inside.
# Run this on a Mac or Linux machine with Docker installed and running.
#
# After build completes, upload the tarball to a GitHub Release:
#   gh release create v1.0.0 build/vscode-sysroot-x86_64-linux-gnu.tgz \
#     --title "v1.0.0" --notes "Initial release"
#
# Then update assets/checksums.txt with the SHA-256 the script prints.

set -euo pipefail

# Pin to a specific commit so builds are reproducible across maintainers.
# To bump: visit https://github.com/ursetto/vscode-sysroot/commits/main and
# replace the SHA below with the commit you want to lock to.
URSETTO_REPO="https://github.com/ursetto/vscode-sysroot.git"
# Pinned to the only commit on upstream main as of 2026-05-26 ("Initial import",
# dated 2025-05-01). Bump this SHA explicitly when upstream ships changes you
# have audited.
URSETTO_COMMIT="${URSETTO_COMMIT:-ee825cce3ccd6d55eb3e1685c5510a2b8e74b32f}"

PATCHELF_VERSION="0.18.0"
PATCHELF_URL="https://github.com/NixOS/patchelf/releases/download/${PATCHELF_VERSION}/patchelf-${PATCHELF_VERSION}-x86_64.tar.gz"

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${SKILL_DIR}/build"
WORK_DIR="${BUILD_DIR}/work"
OUT_TARBALL="${BUILD_DIR}/vscode-sysroot-x86_64-linux-gnu.tgz"

# ─── Preflight ──────────────────────────────────────────────────────────────
command -v docker >/dev/null || { echo "ERR: Docker not found. Install Docker Desktop and start it."; exit 1; }
docker info >/dev/null 2>&1 || { echo "ERR: Docker daemon not running."; exit 1; }
command -v git    >/dev/null || { echo "ERR: git not found."; exit 1; }
command -v curl   >/dev/null || { echo "ERR: curl not found."; exit 1; }

# Force amd64 even on Apple Silicon — the sysroot is for x86_64 Linux.
export DOCKER_DEFAULT_PLATFORM=linux/amd64

mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# ─── Clone ursetto/vscode-sysroot at pinned commit ─────────────────────────
if [[ ! -d vscode-sysroot ]]; then
  git clone "$URSETTO_REPO" vscode-sysroot
fi
cd vscode-sysroot
git fetch origin
git checkout "$URSETTO_COMMIT"
echo "→ Building from $URSETTO_REPO @ $(git rev-parse --short HEAD)"

# ─── Build the sysroot via Docker ──────────────────────────────────────────
# Inline the upstream `make sysroot` target with two CI-specific fixes:
#   1. Drop `-t` from `docker run -it` — pseudo-TTY fails on TTY-less runners.
#   2. Pin the base image to ubuntu:22.04 LTS. The ursetto Dockerfile uses
#      `ubuntu:latest` which now resolves to Ubuntu 26.04 (Resolute Rhino) on
#      Docker Hub, breaking the crosstool-NG build. We patch the Dockerfile in
#      the cloned work tree before building — we can't change the pinned upstream
#      commit, but we own the build script.
#   3. Use --progress=plain so the actual ct-ng error appears in CI logs rather
#      than being consumed by the Docker progress-spinner animation (which hits
#      the 2 MiB log limit before the real error is printed).

# Patch ubuntu:latest → ubuntu:22.04 in the cloned Dockerfile.
sed -i 's|^FROM ubuntu:latest|FROM ubuntu:22.04|g' Dockerfile
echo "→ Patched Dockerfile FROM ubuntu:latest → ubuntu:22.04"

mkdir -p toolchain
docker build --progress=plain -t vscode-sysroot --target sysroot .
docker run --rm -v "$(pwd)/toolchain:/out" vscode-sysroot cp vscode-sysroot-x86_64-linux-gnu.tgz /out/
ls -l toolchain
INTERMEDIATE_TARBALL="$(pwd)/toolchain/vscode-sysroot-x86_64-linux-gnu.tgz"
[[ -f "$INTERMEDIATE_TARBALL" ]] || { echo "ERR: make did not produce expected tarball"; exit 1; }
echo "→ ursetto build complete: $INTERMEDIATE_TARBALL"

# ─── Download patchelf 0.18 ────────────────────────────────────────────────
PATCHELF_TGZ="${WORK_DIR}/patchelf-${PATCHELF_VERSION}-x86_64.tar.gz"
if [[ ! -f "$PATCHELF_TGZ" ]]; then
  curl -fL "$PATCHELF_URL" -o "$PATCHELF_TGZ"
fi
PATCHELF_SHA=$(shasum -a 256 "$PATCHELF_TGZ" | awk '{print $1}')
echo "→ patchelf SHA-256: $PATCHELF_SHA"

# ─── Splice patchelf 0.18 into the tarball ─────────────────────────────────
SPLICE_DIR="${WORK_DIR}/splice"
rm -rf "$SPLICE_DIR" && mkdir -p "$SPLICE_DIR"
tar zxf "$INTERMEDIATE_TARBALL" -C "$SPLICE_DIR"

# Extract patchelf binary
PATCHELF_EXTRACT="${WORK_DIR}/patchelf-bin"
rm -rf "$PATCHELF_EXTRACT" && mkdir -p "$PATCHELF_EXTRACT"
tar zxf "$PATCHELF_TGZ" -C "$PATCHELF_EXTRACT"
NEW_PATCHELF="$(find "$PATCHELF_EXTRACT" -name patchelf -type f | head -1)"
[[ -f "$NEW_PATCHELF" ]] || { echo "ERR: patchelf binary not found in extract"; exit 1; }

# Replace inside the sysroot (note: writable bit may be off)
chmod -R u+w "$SPLICE_DIR"
cp "$NEW_PATCHELF" "$SPLICE_DIR/sysroot/usr/bin/patchelf"
chmod 755 "$SPLICE_DIR/sysroot/usr/bin/patchelf"
echo "→ patchelf upgraded to $PATCHELF_VERSION"

# Verify
"$SPLICE_DIR/sysroot/usr/bin/patchelf" --version

# ─── Re-tar ─────────────────────────────────────────────────────────────────
tar -C "$SPLICE_DIR" -czf "$OUT_TARBALL" .
TARBALL_SHA=$(shasum -a 256 "$OUT_TARBALL" | awk '{print $1}')

# ─── Done ───────────────────────────────────────────────────────────────────
cat <<EOM

✓ Built: $OUT_TARBALL
  SHA-256: $TARBALL_SHA

Next steps:
  1. Update assets/checksums.txt with:
       $TARBALL_SHA  vscode-sysroot-x86_64-linux-gnu.tgz
       $PATCHELF_SHA  patchelf-0.18.0-x86_64.tar.gz
  2. Commit checksums.txt and push.
  3. Tag a release and upload the tarball:
       gh release create v1.0.0 $OUT_TARBALL --title "v1.0.0" --notes "Initial release"
EOM
