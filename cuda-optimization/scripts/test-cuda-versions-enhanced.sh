#!/bin/bash
# Enhanced CUDA Version Testing with Automated Benchmarking
# Integrates with benchmark.py for persistent results storage
#
# Usage:
#   ./scripts/test-cuda-versions-enhanced.sh <service> [versions...] [--benchmark] [--compare] [--parallel]
#
# Examples:
#   ./scripts/test-cuda-versions-enhanced.sh whisperx --benchmark              # Test with benchmarking
#   ./scripts/test-cuda-versions-enhanced.sh whisperx 12.8 13.0 --compare     # Test and generate report
#   ./scripts/test-cuda-versions-enhanced.sh whisperx --benchmark --parallel   # Parallel testing (future)

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
BENCHMARK_SCRIPT="$PROJECT_ROOT/cuda-optimization/benchmark/benchmark.py"

# Parse arguments
SERVICE=""
VERSIONS=()
RUN_BENCHMARK=false
GENERATE_COMPARISON=false
PARALLEL_MODE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --benchmark)
            RUN_BENCHMARK=true
            shift
            ;;
        --compare)
            GENERATE_COMPARISON=true
            shift
            ;;
        --parallel)
            PARALLEL_MODE=true
            shift
            ;;
        *)
            if [ -z "$SERVICE" ]; then
                SERVICE=$1
            else
                VERSIONS+=("$1")
            fi
            shift
            ;;
    esac
done

if [ -z "$SERVICE" ]; then
    echo -e "${RED}Error: No service specified${NC}"
    echo ""
    echo "Usage: $0 <service> [versions...] [--benchmark] [--compare] [--parallel]"
    echo ""
    echo "Options:"
    echo "  --benchmark    Run automated benchmarks with each version"
    echo "  --compare      Generate comparison report after testing"
    echo "  --parallel     Enable parallel testing (future feature)"
    echo ""
    echo "Available services:"
    echo "  • whisperx"
    echo "  • infinitetalk"
    echo ""
    exit 1
fi

# Default versions if none specified
DEFAULT_VERSIONS=("12.1" "12.8" "12.9" "13.0")
if [ ${#VERSIONS[@]} -eq 0 ]; then
    VERSIONS=("${DEFAULT_VERSIONS[@]}")
    echo -e "${YELLOW}No versions specified, using defaults: ${VERSIONS[*]}${NC}"
fi

echo -e "${BLUE}=== Enhanced CUDA Version Testing ===${NC}"
echo ""
echo "Service: ${CYAN}${SERVICE}${NC}"
echo "Versions to test: ${CYAN}${VERSIONS[*]}${NC}"
echo "Benchmark mode: ${CYAN}${RUN_BENCHMARK}${NC}"
echo "Comparison report: ${CYAN}${GENERATE_COMPARISON}${NC}"
echo ""

# Check if benchmark script exists
if [ "$RUN_BENCHMARK" = true ] && [ ! -f "$BENCHMARK_SCRIPT" ]; then
    echo -e "${RED}Error: Benchmark script not found at $BENCHMARK_SCRIPT${NC}"
    echo "Run without --benchmark flag or install benchmark.py"
    exit 1
fi

# Results tracking
declare -A RESULTS
declare -A BUILD_TIMES
TESTED_VERSIONS=()

test_version_simple() {
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
        TESTED_VERSIONS+=("$VERSION")

        # Quick runtime test (non-interactive)
        echo -e "${YELLOW}Starting container for quick test...${NC}"
        docker compose up -d ${SERVICE}
        sleep 5

        if docker compose ps ${SERVICE} | grep -q "Up"; then
            echo -e "${GREEN}✓ Container started successfully${NC}"

            # Test CUDA inside container
            echo -e "${YELLOW}Testing CUDA inside container...${NC}"
            if docker compose exec -T ${SERVICE} python3 -c "import torch; print(f'PyTorch: {torch.__version__}'); print(f'CUDA: {torch.version.cuda}'); print(f'Available: {torch.cuda.is_available()}')"; then
                echo -e "${GREEN}✓ CUDA test passed${NC}"
            else
                echo -e "${RED}✗ CUDA test failed${NC}"
                RESULTS[$VERSION]="RUNTIME_FAIL"
            fi
        else
            echo -e "${RED}✗ Container failed to start${NC}"
            RESULTS[$VERSION]="RUNTIME_FAIL"
        fi

        docker compose down ${SERVICE}
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

test_version_with_benchmark() {
    local VERSION=$1
    local SERVICE=$2

    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}Benchmark Testing: ${SERVICE} with CUDA ${VERSION}${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    # Run benchmark script
    if python3 "$BENCHMARK_SCRIPT" --service "$SERVICE" --cuda-version "$VERSION"; then
        RESULTS[$VERSION]="SUCCESS"
        TESTED_VERSIONS+=("$VERSION")
        echo -e "${GREEN}✓ Benchmark completed successfully${NC}"
    else
        RESULTS[$VERSION]="BENCHMARK_FAIL"
        echo -e "${RED}✗ Benchmark failed${NC}"
    fi
}

# Test each version
for VERSION in "${VERSIONS[@]}"; do
    if [ "$RUN_BENCHMARK" = true ]; then
        test_version_with_benchmark "$VERSION" "$SERVICE"
    else
        test_version_simple "$VERSION" "$SERVICE"
    fi
done

# Final summary
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}=== Test Summary: ${SERVICE} ===${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

SUCCESS_COUNT=0
FAIL_COUNT=0

printf "%-12s %-15s %s\n" "CUDA Ver" "Status" "Details"
echo "────────────────────────────────────────────────────────────"

for VERSION in "${VERSIONS[@]}"; do
    STATUS="${RESULTS[$VERSION]}"
    DETAILS="${BUILD_TIMES[$VERSION]}"

    if [ "$STATUS" == "SUCCESS" ]; then
        echo -e "$(printf "%-12s" "CUDA ${VERSION}") ${GREEN}✓ SUCCESS${NC}      ${DETAILS}"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        echo -e "$(printf "%-12s" "CUDA ${VERSION}") ${RED}✗ ${STATUS}${NC}   ${DETAILS}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
done

echo ""
echo -e "${GREEN}Successful: ${SUCCESS_COUNT}${NC}  |  ${RED}Failed: ${FAIL_COUNT}${NC}"
echo ""

# Generate comparison report if requested
if [ "$GENERATE_COMPARISON" = true ] && [ "$RUN_BENCHMARK" = true ] && [ ${#TESTED_VERSIONS[@]} -gt 0 ]; then
    echo -e "${YELLOW}Generating comparison report...${NC}"
    python3 "$BENCHMARK_SCRIPT" --service "$SERVICE" --compare
    echo ""
fi

# Show benchmark database info
if [ "$RUN_BENCHMARK" = true ]; then
    echo -e "${CYAN}Benchmark results saved to database${NC}"
    echo "View results:"
    echo "  python3 $BENCHMARK_SCRIPT --service $SERVICE --report"
    echo "  python3 $BENCHMARK_SCRIPT --list"
    echo ""
fi

# Recommendations
if [ ${SUCCESS_COUNT} -gt 0 ]; then
    echo -e "${YELLOW}Recommendation:${NC}"

    if [ "$RUN_BENCHMARK" = true ]; then
        echo "Review the comparison report to choose the optimal CUDA version"
        echo "Consider: build time, image size, VRAM usage, and compatibility"
    else
        # Find fastest successful build (simple mode)
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

        if [ -n "$FASTEST_VERSION" ]; then
            echo -e "  Fastest successful build: ${CYAN}CUDA ${FASTEST_VERSION}${NC} (${FASTEST_TIME}s)"
            echo ""
            echo "To use this version permanently, update ${SERVICE}/Dockerfile:"
            echo -e "  ${BLUE}ARG CUDA_VERSION=${FASTEST_VERSION}${NC}"
        fi
    fi
fi

echo ""
echo "Build logs available at: /tmp/build-${SERVICE}-*.log"
echo ""

# Exit with success if at least one version worked
if [ ${SUCCESS_COUNT} -gt 0 ]; then
    exit 0
else
    exit 1
fi
