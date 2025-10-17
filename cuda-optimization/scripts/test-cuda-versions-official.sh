#!/bin/bash
# Test CUDA Versions Using Official NVIDIA Images
# No base image building required - pulls from Docker Hub
#
# Usage: ./scripts/test-cuda-versions-official.sh <service> [versions...]

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

SERVICE=$1
shift

if [ -z "$SERVICE" ]; then
    echo -e "${RED}Error: No service specified${NC}"
    echo "Usage: $0 <service> [versions...]"
    exit 1
fi

# Official NVIDIA CUDA versions available on Docker Hub
DEFAULT_VERSIONS=("12.1.0" "12.8.1" "12.9.1" "13.0.0")

VERSIONS=()
if [ $# -eq 0 ]; then
    VERSIONS=("${DEFAULT_VERSIONS[@]}")
    echo -e "${YELLOW}No versions specified, using defaults${NC}"
else
    VERSIONS=("$@")
fi

echo -e "${BLUE}=== CUDA Version Testing (Official Images): ${SERVICE} ===${NC}"
echo -e "${GREEN}✓ No base image building required!${NC}"
echo ""
echo "Will test ${#VERSIONS[@]} CUDA versions:"
for v in "${VERSIONS[@]}"; do
    echo -e "  ${CYAN}• CUDA ${v}${NC} (official nvidia/cuda image)"
done
echo ""

# Test each version
for VERSION in "${VERSIONS[@]}"; do
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}Testing: ${SERVICE} with CUDA ${VERSION}${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    START_TIME=$(date +%s)

    # Build with official NVIDIA image
    echo -e "${YELLOW}Building (pulling official nvidia/cuda:${VERSION})...${NC}"

    if docker build \
        -f ${SERVICE}/Dockerfile.official \
        --build-arg CUDA_VERSION=${VERSION} \
        -t localai-${SERVICE}:cuda-${VERSION} \
        . 2>&1 | tee /tmp/build-${SERVICE}-${VERSION}.log; then

        END_TIME=$(date +%s)
        BUILD_TIME=$((END_TIME - START_TIME))
        IMAGE_SIZE=$(docker images | grep "localai-${SERVICE}" | grep "cuda-${VERSION}" | awk '{print $7" "$8}')

        echo ""
        echo -e "${GREEN}✓ Build succeeded${NC}"
        echo -e "  Time: ${BUILD_TIME}s"
        echo -e "  Size: ${IMAGE_SIZE}"
    else
        END_TIME=$(date +%s)
        BUILD_TIME=$((END_TIME - START_TIME))

        echo ""
        echo -e "${RED}✗ Build failed${NC}"
        echo -e "  Time: ${BUILD_TIME}s"
    fi
done

echo ""
echo -e "${BLUE}=== Test Complete ===${NC}"
echo ""
echo "Built images:"
docker images | grep "localai-${SERVICE}" || echo "No images found"
