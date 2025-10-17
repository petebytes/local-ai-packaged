#!/bin/bash
# WhisperX Speed Benchmark - Focus on transcription speed and GPU metrics
# Simpler than accuracy test, focuses on performance
#
# Usage:
#   ./scripts/test-whisperx-speed-benchmark.sh

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

PROJECT_ROOT="/home/ghar/code/local-ai-packaged"
TEST_FILE="$PROJECT_ROOT/shared/librispeech-test/speed-test.flac"

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  WhisperX Speed Benchmark                                  ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if test file exists
if [ ! -f "$TEST_FILE" ]; then
    echo -e "${YELLOW}Downloading test audio file...${NC}"
    mkdir -p "$(dirname "$TEST_FILE")"
    cd "$(dirname "$TEST_FILE")"

    wget -q https://www.openslr.org/resources/12/test-clean.tar.gz
    tar -xzf test-clean.tar.gz "LibriSpeech/test-clean/1089/134686/1089-134686-0000.flac" --strip-components=4
    mv 1089-134686-0000.flac speed-test.flac

    cd "$PROJECT_ROOT"
    echo -e "${GREEN}✓ Test file ready${NC}"
fi

# Get audio duration
DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$TEST_FILE" 2>/dev/null || echo "unknown")
echo -e "Audio duration: ${CYAN}${DURATION}s${NC}"
echo ""

# Test each version
echo -e "${YELLOW}Running speed tests (3 runs per version)...${NC}"
echo ""

for VERSION_PORT in "12.8:8001" "12.9:8002" "13.0:8003"; do
    VERSION=${VERSION_PORT%:*}
    PORT=${VERSION_PORT#*:}

    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}CUDA $VERSION (Port $PORT)${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    TIMES=()

    for RUN in 1 2 3; do
        echo -ne "  Run $RUN: "

        # Capture GPU stats before
        GPU_BEFORE=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits | head -1)

        # Time the transcription
        START=$(date +%s.%N)
        HTTP_CODE=$(curl -s -w "%{http_code}" -o /tmp/whisperx_result_${VERSION}.json \
            -X POST "http://localhost:$PORT/transcribe" \
            -F "file=@$TEST_FILE" \
            -F "model=base")
        END=$(date +%s.%N)

        TIME=$(echo "$END - $START" | bc)
        TIMES+=($TIME)

        # Capture GPU stats after
        GPU_AFTER=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits | head -1)
        GPU_DELTA=$(echo "$GPU_AFTER - $GPU_BEFORE" | bc)

        if [ "$HTTP_CODE" == "200" ]; then
            REALTIME_FACTOR=$(echo "scale=2; $DURATION / $TIME" | bc)
            echo -e "${GREEN}${TIME}s${NC} (${REALTIME_FACTOR}x realtime, GPU: +${GPU_DELTA}MB)"
        else
            echo -e "${RED}Failed (HTTP $HTTP_CODE)${NC}"
        fi

        sleep 1  # Brief pause between runs
    done

    # Calculate average
    AVG=$(echo "scale=3; (${TIMES[0]} + ${TIMES[1]} + ${TIMES[2]}) / 3" | bc)
    REALTIME_AVG=$(echo "scale=2; $DURATION / $AVG" | bc)

    echo ""
    echo -e "  Average: ${GREEN}${AVG}s${NC} (${REALTIME_AVG}x realtime)"
    echo ""
done

echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Benchmark Complete!                                       ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "Summary:"
echo -e "  Audio duration: ${DURATION}s"
echo -e "  Higher realtime factor = faster transcription"
echo ""
echo -e "View GPU usage during tests:"
echo -e "  ${BLUE}nvidia-smi${NC}"
echo ""
