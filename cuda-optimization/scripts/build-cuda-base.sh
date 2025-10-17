#!/bin/bash
# Build CUDA Base Images
# This script builds the shared CUDA base images used by all AI services
# Run this ONCE before building individual services for the first time
#
# Usage: ./scripts/build-cuda-base.sh [runtime|devel|all]
#
# Examples:
#   ./scripts/build-cuda-base.sh all      # Build both runtime and devel
#   ./scripts/build-cuda-base.sh runtime  # Build only runtime image
#   ./scripts/build-cuda-base.sh devel    # Build only devel image

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo -e "${BLUE}=== CUDA Base Image Builder ===${NC}"
echo -e "${YELLOW}This will build shared CUDA base images to speed up service builds${NC}"
echo ""

# Parse arguments
BUILD_TYPE="${1:-all}"

build_runtime() {
    echo -e "${GREEN}Building CUDA runtime base image...${NC}"
    echo "Image: cuda-base:runtime-12.8"
    echo "Size: ~4GB (includes CUDA 12.8 + PyTorch 2.7.1)"
    echo ""

    cd "$PROJECT_ROOT"
    docker build \
        -f cuda-base/Dockerfile.runtime \
        -t cuda-base:runtime-12.8 \
        --progress=plain \
        .

    echo -e "${GREEN}✓ Runtime base image built successfully${NC}"
    echo ""
}

build_devel() {
    echo -e "${GREEN}Building CUDA devel base image...${NC}"
    echo "Image: cuda-base:devel-12.8"
    echo "Size: ~8GB (includes CUDA 12.8 + PyTorch 2.7.1 + build tools)"
    echo ""

    cd "$PROJECT_ROOT"
    docker build \
        -f cuda-base/Dockerfile.devel \
        -t cuda-base:devel-12.8 \
        --progress=plain \
        .

    echo -e "${GREEN}✓ Devel base image built successfully${NC}"
    echo ""
}

# Build based on argument
case "$BUILD_TYPE" in
    runtime)
        build_runtime
        ;;
    devel)
        build_devel
        ;;
    all)
        build_runtime
        build_devel
        ;;
    *)
        echo "Error: Invalid argument '$BUILD_TYPE'"
        echo "Usage: $0 [runtime|devel|all]"
        exit 1
        ;;
esac

echo -e "${BLUE}=== Build Complete ===${NC}"
echo ""
echo "Available base images:"
docker images | grep "cuda-base" || echo "No cuda-base images found"
echo ""
echo -e "${GREEN}Next steps:${NC}"
echo "1. Build your services: docker compose build whisperx infinitetalk"
echo "2. Or rebuild all: docker compose build"
echo ""
echo -e "${YELLOW}Note: These base images will be reused by all services${NC}"
echo "Rebuilding services will now be much faster!"
