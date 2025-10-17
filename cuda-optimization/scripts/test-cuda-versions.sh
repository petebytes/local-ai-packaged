#!/bin/bash
# Test Service with Different CUDA Versions
# Quickly rebuild and test a service with different CUDA versions
#
# Usage: ./scripts/test-cuda-versions.sh <service> [versions...]
#
# Examples:
#   ./scripts/test-cuda-versions.sh whisperx              # Test with default versions
#   ./scripts/test-cuda-versions.sh whisperx 12.8 13.0    # Test specific versions
#   ./scripts/test-cuda-versions.sh infinitetalk all      # Test all available

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
    echo ""
    echo "Usage: $0 <service> [versions...]"
    echo ""
    echo "Available services:"
    echo "  • whisperx"
    echo "  • infinitetalk"
    echo ""
    exit 1
fi

# Default test versions (essential for RTX 5090)
DEFAULT_VERSIONS=("12.1" "12.8" "12.9" "13.0")

# All available versions
ALL_VERSIONS=("12.1" "12.8" "12.9" "13.0" "13.1")

# Parse version arguments
VERSIONS=()
if [ $# -eq 0 ]; then
    VERSIONS=("${DEFAULT_VERSIONS[@]}")
    echo -e "${YELLOW}No versions specified, using defaults${NC}"
elif [ "$1" == "all" ]; then
    VERSIONS=("${ALL_VERSIONS[@]}")
    echo -e "${YELLOW}Testing all available versions${NC}"
else
    VERSIONS=("$@")
fi

echo -e "${BLUE}=== CUDA Version Testing: ${SERVICE} ===${NC}"
echo ""
echo "Will test ${#VERSIONS[@]} CUDA versions:"
for v in "${VERSIONS[@]}"; do
    echo -e "  ${CYAN}• CUDA ${v}${NC}"
done
echo ""

# Results tracking
declare -A RESULTS
declare -A BUILD_TIMES

test_version() {
    local VERSION=$1
    local SERVICE=$2

    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}Testing: ${SERVICE} with CUDA ${VERSION}${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    START_TIME=$(date +%s)

    # Build with specified CUDA version
    echo -e "${YELLOW}Building...${NC}"
    if docker compose build --build-arg CUDA_VERSION=${VERSION} ${SERVICE} 2>&1 | tee /tmp/build-${SERVICE}-${VERSION}.log; then
        END_TIME=$(date +%s)
        BUILD_TIME=$((END_TIME - START_TIME))

        # Check image size
        IMAGE_SIZE=$(docker images | grep "localai.*${SERVICE}" | head -1 | awk '{print $7" "$8}')

        echo ""
        echo -e "${GREEN}✓ Build succeeded${NC}"
        echo -e "  Time: ${BUILD_TIME}s"
        echo -e "  Size: ${IMAGE_SIZE}"

        RESULTS[$VERSION]="SUCCESS"
        BUILD_TIMES[$VERSION]="${BUILD_TIME}s (${IMAGE_SIZE})"

        # Optional: Quick runtime test
        echo ""
        read -p "Run container to test CUDA availability? (y/N) " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}Starting container...${NC}"
            docker compose up -d ${SERVICE}
            sleep 5

            if docker compose ps ${SERVICE} | grep -q "Up"; then
                echo -e "${GREEN}✓ Container started successfully${NC}"

                # Test CUDA inside container
                echo -e "${YELLOW}Testing CUDA inside container...${NC}"
                docker compose exec ${SERVICE} python3 -c "import torch; print(f'PyTorch: {torch.__version__}'); print(f'CUDA: {torch.version.cuda}'); print(f'Available: {torch.cuda.is_available()}')" || echo -e "${RED}CUDA test failed${NC}"
            else
                echo -e "${RED}✗ Container failed to start${NC}"
                RESULTS[$VERSION]="RUNTIME_FAIL"
            fi

            docker compose down ${SERVICE}
        fi
    else
        END_TIME=$(date +%s)
        BUILD_TIME=$((END_TIME - START_TIME))

        echo ""
        echo -e "${RED}✗ Build failed${NC}"
        echo -e "  Time: ${BUILD_TIME}s"
        echo -e "  Log: /tmp/build-${SERVICE}-${VERSION}.log"

        RESULTS[$VERSION]="BUILD_FAIL"
        BUILD_TIMES[$VERSION]="${BUILD_TIME}s (failed)"
    fi
}

# Test each version
for VERSION in "${VERSIONS[@]}"; do
    test_version "$VERSION" "$SERVICE"
done

# Final summary
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}=== Test Summary: ${SERVICE} ===${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

SUCCESS_COUNT=0
FAIL_COUNT=0

printf "%-12s %-15s %s\n" "CUDA Ver" "Status" "Build Time & Size"
echo "────────────────────────────────────────────────────────────"

for VERSION in "${VERSIONS[@]}"; do
    STATUS="${RESULTS[$VERSION]}"
    TIME="${BUILD_TIMES[$VERSION]}"

    if [ "$STATUS" == "SUCCESS" ]; then
        echo -e "$(printf "%-12s" "CUDA ${VERSION}") ${GREEN}✓ SUCCESS${NC}      ${TIME}"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        echo -e "$(printf "%-12s" "CUDA ${VERSION}") ${RED}✗ ${STATUS}${NC}   ${TIME}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
done

echo ""
echo -e "${GREEN}Successful: ${SUCCESS_COUNT}${NC}  |  ${RED}Failed: ${FAIL_COUNT}${NC}"
echo ""

# Recommendations
if [ ${SUCCESS_COUNT} -gt 0 ]; then
    echo -e "${YELLOW}Recommendation:${NC}"

    # Find fastest successful build
    FASTEST_VERSION=""
    FASTEST_TIME=999999

    for VERSION in "${VERSIONS[@]}"; do
        if [ "${RESULTS[$VERSION]}" == "SUCCESS" ]; then
            TIME=$(echo "${BUILD_TIMES[$VERSION]}" | grep -oE '[0-9]+' | head -1)
            if [ "$TIME" -lt "$FASTEST_TIME" ]; then
                FASTEST_TIME=$TIME
                FASTEST_VERSION=$VERSION
            fi
        fi
    done

    echo -e "  Fastest successful build: ${CYAN}CUDA ${FASTEST_VERSION}${NC} (${FASTEST_TIME}s)"
    echo ""
    echo "To use this version permanently, update ${SERVICE}/Dockerfile:"
    echo -e "  ${BLUE}ARG CUDA_VERSION=${FASTEST_VERSION}${NC}"
fi

echo ""
echo "Build logs available at: /tmp/build-${SERVICE}-*.log"
