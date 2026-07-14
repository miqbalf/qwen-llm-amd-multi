#!/bin/bash
# build-docker.sh — Run ON the AMD server to build and push Docker image
#
# Usage:
#   chmod +x scripts/build-docker.sh
#   ./scripts/build-docker.sh [tag]
#
# Prerequisites:
#   - Docker installed and running
#   - GitHub PAT with write:packages scope
#   - docker login ghcr.io -u miqbalf --password-stdin
#
# Default tag: latest

set -euo pipefail

TAG="${1:-latest}"
IMAGE="ghcr.io/miqbalf/qwen-llm-amd:${TAG}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "==> Cleaning staging directories..."
rm -rf "$PROJECT_DIR/build-bin" "$PROJECT_DIR/rocm-libs" "$PROJECT_DIR/rocm-syslibs"
mkdir -p "$PROJECT_DIR/build-bin" "$PROJECT_DIR/rocm-libs" "$PROJECT_DIR/rocm-syslibs"

# ── llama.cpp build artifacts ───────────────────────────────
echo "==> Copying llama.cpp build binaries..."
cp -a /opt/llm/llama.cpp/build/bin/* "$PROJECT_DIR/build-bin/"

# ── ROCm 7.2.4 runtime libs (from AMD install) ──────────────
echo "==> Copying ROCm 7.2.4 runtime libs..."
ROCMLIB="/opt/rocm-7.2.4/lib"

cp -a \
    "$ROCMLIB/librocblas.so" "$ROCMLIB/librocblas.so.5" "$ROCMLIB/librocblas.so.5.2.70204" \
    "$ROCMLIB/libamdhip64.so" "$ROCMLIB/libamdhip64.so.7" "$ROCMLIB/libamdhip64.so.7.2.70204" \
    "$ROCMLIB/libhipblaslt.so" "$ROCMLIB/libhipblaslt.so.1" "$ROCMLIB/libhipblaslt.so.1.2.70204" \
    "$ROCMLIB/libhsa-runtime64.so" "$ROCMLIB/libhsa-runtime64.so.1" "$ROCMLIB/libhsa-runtime64.so.1.18.70204" \
    "$ROCMLIB/libroctx64.so.4" "$ROCMLIB/libroctx64.so.4.1.70204" \
    "$ROCMLIB/librocprofiler-register.so" "$ROCMLIB/librocprofiler-register.so.0" "$ROCMLIB/librocprofiler-register.so.0.6.0" \
    "$ROCMLIB/librocroller.so" "$ROCMLIB/librocroller.so.1" "$ROCMLIB/librocroller.so.1.0.0" \
    "$ROCMLIB/libamd_comgr.so" "$ROCMLIB/libamd_comgr.so.3" "$ROCMLIB/libamd_comgr.so.3.0.0" \
    "$PROJECT_DIR/rocm-libs/" 2>/dev/null || true

# Copy GPU kernel libraries (required for inference)
cp -a "$ROCMLIB/rocblas" "$PROJECT_DIR/rocm-libs/" 2>/dev/null || true
cp -a "$ROCMLIB/hipblaslt" "$PROJECT_DIR/rocm-libs/" 2>/dev/null || true

# Ensure symlinks exist in rocm-libs/
cd "$PROJECT_DIR/rocm-libs"
[ -f librocblas.so ] || ln -sf librocblas.so.5 librocblas.so
[ -f libamdhip64.so ] || ln -sf libamdhip64.so.7 libamdhip64.so
[ -f libhipblaslt.so ] || ln -sf libhipblaslt.so.1 libhipblaslt.so
[ -f libhsa-runtime64.so ] || ln -sf libhsa-runtime64.so.1 libhsa-runtime64.so
[ -f librocprofiler-register.so ] || ln -sf librocprofiler-register.so.0 librocprofiler-register.so
[ -f librocroller.so ] || ln -sf librocroller.so.1 librocroller.so
[ -f libamd_comgr.so ] || ln -sf libamd_comgr.so.3 libamd_comgr.so
cd "$PROJECT_DIR"

# ── ROCm libs from system paths ─────────────────────────────
echo "==> Copying ROCm system libs..."
SYSLIB="/usr/lib/x86_64-linux-gnu"
cp -a \
    "$SYSLIB/libhipblas.so" "$SYSLIB/libhipblas.so.3" "$SYSLIB/libhipblas.so.3.1" \
    "$SYSLIB/librocsolver.so" "$SYSLIB/librocsolver.so.0" "$SYSLIB/librocsolver.so.0.7" \
    "$PROJECT_DIR/rocm-syslibs/"

# ── Build Docker image ──────────────────────────────────────
echo "==> Building Docker image: $IMAGE"
docker build \
    -t "$IMAGE" \
    -f "$PROJECT_DIR/Dockerfile" \
    "$PROJECT_DIR"

# Cleanup staging
rm -rf "$PROJECT_DIR/build-bin" "$PROJECT_DIR/rocm-libs" "$PROJECT_DIR/rocm-syslibs"

echo ""
echo "==> Done. Image: $IMAGE"
echo ""
if [[ "${PUSH:-0}" == "1" ]]; then
    echo "==> Pushing to registry..."
    docker push "$IMAGE"
    echo "==> Push complete."
else
    echo "To push:"
    echo "  PUSH=1 $0 $TAG"
    echo "  # or: docker push $IMAGE"
    echo ""
    echo "Requires: echo \$GITHUB_PAT | docker login ghcr.io -u miqbalf --password-stdin"
    echo "  (PAT needs write:packages scope)"
fi
echo ""
echo "To test locally:"
echo "  docker run --rm --device /dev/dri --device /dev/kfd \\"
echo "    -v /opt/llm/models:/opt/llm/models:ro \\"
echo "    --network host \\"
echo "    $IMAGE"
