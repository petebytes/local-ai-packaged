#!/bin/bash
# Build All CUDA Base Image Versions
# This script builds base images for all CUDA versions you might want to test
#
# Usage: ./scripts/build-all-cuda-versions.sh [quick|full]
#
# Options:
#   quick - Build only RTX 5090 essential versions (12.8, 12.9, 13.0)
#   full  - Build all versions including legacy (default)

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo -e "${BLUE}=== CUDA Multi-Version Base Image Builder ===${NC}"
echo ""

MODE="${1:-full}"

# Define version matrix
# Format: VERSION:UBUNTU:DESCRIPTION
# Note: Check https://hub.docker.com/r/nvidia/cuda/tags for available combinations
VERSIONS_FULL=(
    "12.1.1:22.04:Legacy stable - original InfiniteTalk"
    "12.8.1:22.04:RTX 5090 minimum (Blackwell) ⭐"
    "12.9.0:22.04:Newer stable - Kokoro compatible ⭐"
    "13.0.0:24.04:Bleeding edge - latest ⭐"
)

VERSIONS_QUICK=(
    "12.8.1:22.04:RTX 5090 minimum (Blackwell)"
    "12.9.0:22.04:Newer stable"
    "13.0.0:24.04:Bleeding edge"
)

if [ "$MODE" == "quick" ]; then
    VERSIONS=("${VERSIONS_QUICK[@]}")
    echo -e "${YELLOW}Quick mode: Building only essential RTX 5090 versions${NC}"
else
    VERSIONS=("${VERSIONS_FULL[@]}")
    echo -e "${YELLOW}Full mode: Building all versions including legacy${NC}"
fi

echo ""
echo "Will build ${#VERSIONS[@]} CUDA versions (runtime + devel each)"
echo ""

# Parse and display what will be built
for version_info in "${VERSIONS[@]}"; do
    IFS=':' read -r VERSION UBUNTU DESC <<< "$version_info"
    SHORT_VERSION=$(echo $VERSION | cut -d. -f1,2)
    echo -e "${GREEN}  • CUDA ${SHORT_VERSION}${NC} - ${DESC}"
done

echo ""
read -p "Continue with build? This will take 30-60 minutes. (y/N) " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Build cancelled"
    exit 0
fi

cd "$PROJECT_ROOT"

# Build function
build_image() {
    local VERSION=$1
    local UBUNTU=$2
    local TYPE=$3  # runtime or devel
    local SHORT_VERSION=$(echo $VERSION | cut -d. -f1,2)

    # Determine cuDNN suffix based on CUDA version
    # CUDA < 12.4 uses cudnn8, >= 12.4 uses cudnn
    local MAJOR_MINOR=$(echo $VERSION | cut -d. -f1,2)
    local CUDNN_SUFFIX="cudnn"
    if (( $(echo "$MAJOR_MINOR < 12.4" | bc -l) )); then
        CUDNN_SUFFIX="cudnn8"
    fi

    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}Building: cuda-base:${TYPE}-${SHORT_VERSION}${NC}"
    echo -e "${YELLOW}  CUDA: ${VERSION}  |  Ubuntu: ${UBUNTU}  |  cuDNN: ${CUDNN_SUFFIX}  |  Type: ${TYPE}${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    docker build \
        -f cuda-base/Dockerfile.multi-${TYPE} \
        --build-arg CUDA_VERSION=${VERSION} \
        --build-arg UBUNTU_VERSION=${UBUNTU} \
        --build-arg CUDNN_SUFFIX=${CUDNN_SUFFIX} \
        -t cuda-base:${TYPE}-${SHORT_VERSION} \
        --progress=plain \
        . || {
            echo -e "${RED}✗ Failed to build cuda-base:${TYPE}-${SHORT_VERSION}${NC}"
            return 1
        }

    echo -e "${GREEN}✓ Successfully built cuda-base:${TYPE}-${SHORT_VERSION}${NC}"
}

# Build all versions
TOTAL=$((${#VERSIONS[@]} * 2))  # runtime + devel
CURRENT=0
FAILED=()

for version_info in "${VERSIONS[@]}"; do
    IFS=':' read -r VERSION UBUNTU DESC <<< "$version_info"

    # Build runtime
    CURRENT=$((CURRENT + 1))
    echo ""
    echo -e "${BLUE}[${CURRENT}/${TOTAL}] Building runtime image...${NC}"
    if ! build_image "$VERSION" "$UBUNTU" "runtime"; then
        FAILED+=("cuda-base:runtime-$(echo $VERSION | cut -d. -f1,2)")
    fi

    # Build devel
    CURRENT=$((CURRENT + 1))
    echo ""
    echo -e "${BLUE}[${CURRENT}/${TOTAL}] Building devel image...${NC}"
    if ! build_image "$VERSION" "$UBUNTU" "devel"; then
        FAILED+=("cuda-base:devel-$(echo $VERSION | cut -d. -f1,2)")
    fi
done

# Summary
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}=== Build Complete ===${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

if [ ${#FAILED[@]} -eq 0 ]; then
    echo -e "${GREEN}✓ All images built successfully!${NC}"
else
    echo -e "${RED}✗ Failed to build ${#FAILED[@]} image(s):${NC}"
    for img in "${FAILED[@]}"; do
        echo -e "${RED}  • ${img}${NC}"
    done
fi

echo ""
echo "Available CUDA base images:"
docker images | grep "cuda-base" | sort
echo ""

# Calculate total size
TOTAL_SIZE=$(docker images | grep "cuda-base" | awk '{print $7}' | grep -oE '[0-9.]+' | awk '{sum+=$1} END {print sum}')
echo -e "${YELLOW}Total size: ~${TOTAL_SIZE}GB${NC}"
echo ""

echo -e "${GREEN}Next steps:${NC}"
echo "1. Test a service with different CUDA versions:"
echo "   ${BLUE}docker compose build --build-arg CUDA_VERSION=12.8 whisperx${NC}"
echo "   ${BLUE}docker compose build --build-arg CUDA_VERSION=13.0 whisperx${NC}"
echo ""
echo "2. Or use the testing script:"
echo "   ${BLUE}./scripts/test-cuda-versions.sh whisperx${NC}"
