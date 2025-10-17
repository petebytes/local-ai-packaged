#!/bin/bash
# WhisperX CUDA Version Accuracy and Speed Testing
# Tests multiple CUDA versions with LibriSpeech samples and compares accuracy/speed
#
# Usage:
#   ./scripts/test-whisperx-accuracy.sh [num_samples]
#
# Example:
#   ./scripts/test-whisperx-accuracy.sh 5    # Test with 5 audio samples

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
NUM_SAMPLES=${1:-3}  # Default to 3 samples
PROJECT_ROOT="/home/ghar/code/local-ai-packaged"
TEST_DIR="$PROJECT_ROOT/shared/librispeech-test"
RESULTS_DIR="$PROJECT_ROOT/cuda-optimization/benchmark/accuracy-results"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# CUDA versions to test (version:port)
CUDA_VERSIONS=(
    "12.8:8001"
    "12.9:8002"
    "13.0:8003"
)

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  WhisperX CUDA Version Accuracy & Speed Test              ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "Testing ${CYAN}${#CUDA_VERSIONS[@]}${NC} CUDA versions with ${CYAN}${NUM_SAMPLES}${NC} audio samples"
echo ""

# Create directories
mkdir -p "$TEST_DIR"
mkdir -p "$RESULTS_DIR"

# Download LibriSpeech test samples
download_samples() {
    echo -e "${YELLOW}Downloading LibriSpeech test samples...${NC}"
    cd "$TEST_DIR"

    if [ ! -f "test-clean.tar.gz" ]; then
        echo "  Downloading test-clean.tar.gz (~337MB)..."
        wget -q --show-progress https://www.openslr.org/resources/12/test-clean.tar.gz
    else
        echo "  test-clean.tar.gz already exists, skipping download"
    fi

    # Extract a few samples with their transcripts
    echo "  Extracting $NUM_SAMPLES samples..."

    # Known good samples from LibriSpeech test-clean
    SAMPLES=(
        "LibriSpeech/test-clean/1089/134686/1089-134686-0000"
        "LibriSpeech/test-clean/1089/134686/1089-134686-0001"
        "LibriSpeech/test-clean/1089/134686/1089-134686-0002"
        "LibriSpeech/test-clean/1221/135766/1221-135766-0000"
        "LibriSpeech/test-clean/1221/135766/1221-135766-0001"
    )

    for i in $(seq 0 $((NUM_SAMPLES-1))); do
        SAMPLE=${SAMPLES[$i]}
        FILENAME=$(basename "$SAMPLE")

        if [ ! -f "${FILENAME}.flac" ]; then
            tar -xzf test-clean.tar.gz "${SAMPLE}.flac" --strip-components=4 2>/dev/null || true
            tar -xzf test-clean.tar.gz "${SAMPLE}.trans.txt" --strip-components=4 2>/dev/null || true
        fi
    done

    # Extract transcript file
    if [ ! -f "transcripts.txt" ]; then
        tar -xzf test-clean.tar.gz --wildcards "*/134686/*.trans.txt" --strip-components=4 2>/dev/null || true
        tar -xzf test-clean.tar.gz --wildcards "*/135766/*.trans.txt" --strip-components=4 2>/dev/null || true
        cat *.trans.txt > transcripts.txt 2>/dev/null || true
    fi

    echo -e "${GREEN}✓ Samples ready${NC}"
    cd "$PROJECT_ROOT"
}

# Get ground truth transcript for a file
get_ground_truth() {
    local AUDIO_FILE=$1
    local BASE=$(basename "$AUDIO_FILE" .flac)
    grep "^$BASE " "$TEST_DIR/transcripts.txt" | cut -d' ' -f2- || echo ""
}

# Calculate Word Error Rate (WER)
calculate_wer() {
    local REF="$1"
    local HYP="$2"

    python3 << EOF
import sys
from difflib import SequenceMatcher

ref = """$REF""".upper().split()
hyp = """$HYP""".upper().split()

# Simple WER calculation
sm = SequenceMatcher(None, ref, hyp)
matches = sum(triple[-1] for triple in sm.get_matching_blocks())
wer = 1.0 - (matches / max(len(ref), len(hyp)))
print(f"{wer*100:.2f}")
EOF
}

# Test single audio file with specific CUDA version
test_sample() {
    local AUDIO_FILE=$1
    local CUDA_VERSION=$2
    local PORT=$3
    local SAMPLE_NUM=$4

    local BASENAME=$(basename "$AUDIO_FILE" .flac)
    local OUTPUT_FILE="$RESULTS_DIR/result_${CUDA_VERSION}_${BASENAME}_${TIMESTAMP}.json"

    # Time the transcription
    local START=$(date +%s.%N)

    local HTTP_CODE=$(curl -s -w "%{http_code}" -o "$OUTPUT_FILE" \
        -X POST "http://localhost:$PORT/transcribe" \
        -F "file=@$AUDIO_FILE" \
        -F "model=base")

    local END=$(date +%s.%N)
    local DURATION=$(echo "$END - $START" | bc)

    if [ "$HTTP_CODE" != "200" ]; then
        echo -e "${RED}✗ HTTP $HTTP_CODE${NC}"
        echo "ERROR:$DURATION:0:N/A"
        return 1
    fi

    # Extract transcript from JSON
    local TRANSCRIPT=$(python3 -c "
import json, sys
try:
    with open('$OUTPUT_FILE') as f:
        data = json.load(f)
        text = ' '.join([seg['text'].strip() for seg in data.get('segments', [])])
        print(text)
except Exception as e:
    print('', file=sys.stderr)
" 2>/dev/null)

    # Get ground truth
    local GROUND_TRUTH=$(get_ground_truth "$AUDIO_FILE")

    # Calculate WER
    local WER=$(calculate_wer "$GROUND_TRUTH" "$TRANSCRIPT")

    echo "$TRANSCRIPT:$DURATION:$WER:$OUTPUT_FILE"
}

# Run all tests
run_tests() {
    echo -e "${YELLOW}Running transcription tests...${NC}"
    echo ""

    # Results storage
    declare -A RESULTS
    declare -A TOTAL_TIME
    declare -A TOTAL_WER
    declare -A SUCCESS_COUNT

    # Initialize counters
    for VERSION_PORT in "${CUDA_VERSIONS[@]}"; do
        VERSION=${VERSION_PORT%:*}
        TOTAL_TIME[$VERSION]=0
        TOTAL_WER[$VERSION]=0
        SUCCESS_COUNT[$VERSION]=0
    done

    # Test each sample with each CUDA version
    for i in $(seq 0 $((NUM_SAMPLES-1))); do
        echo -e "${CYAN}Sample $((i+1))/$NUM_SAMPLES${NC}"

        # Get audio file
        SAMPLES=(
            "$TEST_DIR/1089-134686-0000.flac"
            "$TEST_DIR/1089-134686-0001.flac"
            "$TEST_DIR/1089-134686-0002.flac"
            "$TEST_DIR/1221-135766-0000.flac"
            "$TEST_DIR/1221-135766-0001.flac"
        )

        AUDIO_FILE=${SAMPLES[$i]}

        if [ ! -f "$AUDIO_FILE" ]; then
            echo -e "  ${RED}✗ Audio file not found: $AUDIO_FILE${NC}"
            continue
        fi

        GROUND_TRUTH=$(get_ground_truth "$AUDIO_FILE")
        echo -e "  Ground truth: ${GROUND_TRUTH:0:60}..."
        echo ""

        for VERSION_PORT in "${CUDA_VERSIONS[@]}"; do
            VERSION=${VERSION_PORT%:*}
            PORT=${VERSION_PORT#*:}

            echo -ne "  CUDA $VERSION: "

            RESULT=$(test_sample "$AUDIO_FILE" "$VERSION" "$PORT" "$i")
            IFS=':' read -r TRANSCRIPT DURATION WER OUTPUT <<< "$RESULT"

            if [ "$TRANSCRIPT" == "ERROR" ]; then
                echo -e "${RED}✗ Failed${NC}"
            else
                echo -e "${GREEN}✓${NC} ${DURATION}s, WER: ${WER}%"

                # Accumulate stats
                TOTAL_TIME[$VERSION]=$(echo "${TOTAL_TIME[$VERSION]} + $DURATION" | bc)
                TOTAL_WER[$VERSION]=$(echo "${TOTAL_WER[$VERSION]} + $WER" | bc)
                SUCCESS_COUNT[$VERSION]=$((${SUCCESS_COUNT[$VERSION]} + 1))

                # Store result
                RESULTS["${VERSION}_${i}"]="$TRANSCRIPT:$DURATION:$WER"
            fi
        done
        echo ""
    done

    # Generate summary report
    generate_report
}

# Generate markdown report
generate_report() {
    local REPORT_FILE="$RESULTS_DIR/comparison_report_${TIMESTAMP}.md"

    echo -e "${YELLOW}Generating comparison report...${NC}"

    cat > "$REPORT_FILE" << 'REPORT_HEADER'
# WhisperX CUDA Version Comparison Report

**Test Date:** TIMESTAMP_PLACEHOLDER
**Samples Tested:** NUM_SAMPLES_PLACEHOLDER
**Model:** Whisper Base

## Summary

| CUDA Version | Avg Time (s) | Avg WER (%) | Success Rate | Total Samples |
|--------------|--------------|-------------|--------------|---------------|
REPORT_HEADER

    # Replace placeholders
    sed -i "s/TIMESTAMP_PLACEHOLDER/$(date)/" "$REPORT_FILE"
    sed -i "s/NUM_SAMPLES_PLACEHOLDER/$NUM_SAMPLES/" "$REPORT_FILE"

    # Calculate and add summary statistics
    for VERSION_PORT in "${CUDA_VERSIONS[@]}"; do
        VERSION=${VERSION_PORT%:*}

        if [ ${SUCCESS_COUNT[$VERSION]} -gt 0 ]; then
            AVG_TIME=$(echo "scale=3; ${TOTAL_TIME[$VERSION]} / ${SUCCESS_COUNT[$VERSION]}" | bc)
            AVG_WER=$(echo "scale=2; ${TOTAL_WER[$VERSION]} / ${SUCCESS_COUNT[$VERSION]}" | bc)
            SUCCESS_RATE=$(echo "scale=0; ${SUCCESS_COUNT[$VERSION]} * 100 / $NUM_SAMPLES" | bc)
        else
            AVG_TIME="N/A"
            AVG_WER="N/A"
            SUCCESS_RATE="0"
        fi

        echo "| CUDA $VERSION | $AVG_TIME | $AVG_WER | $SUCCESS_RATE% | ${SUCCESS_COUNT[$VERSION]}/$NUM_SAMPLES |" >> "$REPORT_FILE"
    done

    # Add detailed results
    cat >> "$REPORT_FILE" << 'REPORT_DETAILS'

## Detailed Results

### Per-Sample Performance

REPORT_DETAILS

    # Add sample-by-sample comparison table
    for i in $(seq 0 $((NUM_SAMPLES-1))); do
        echo "" >> "$REPORT_FILE"
        echo "#### Sample $((i+1))" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        echo "| CUDA | Time (s) | WER (%) | Transcript Preview |" >> "$REPORT_FILE"
        echo "|------|----------|---------|-------------------|" >> "$REPORT_FILE"

        for VERSION_PORT in "${CUDA_VERSIONS[@]}"; do
            VERSION=${VERSION_PORT%:*}

            if [ -n "${RESULTS[${VERSION}_${i}]}" ]; then
                IFS=':' read -r TRANSCRIPT DURATION WER <<< "${RESULTS[${VERSION}_${i}]}"
                PREVIEW="${TRANSCRIPT:0:40}..."
                echo "| $VERSION | $DURATION | $WER | $PREVIEW |" >> "$REPORT_FILE"
            fi
        done
    done

    # Add recommendations
    cat >> "$REPORT_FILE" << 'REPORT_FOOTER'

## Recommendations

### Fastest Version
Based on average transcription time.

### Most Accurate Version
Based on lowest Word Error Rate (WER).

### Best Overall
Consider both speed and accuracy for your use case.

## Test Environment

- **GPU:** Check with `nvidia-smi`
- **Docker Images:** cuda-optimization-whisperx-*
- **Parallel Testing:** All versions tested simultaneously
- **Model:** Whisper Base (smaller, faster model for testing)

## Next Steps

1. Test with larger models (large-v3) for production use
2. Test with longer audio files (5+ minutes)
3. Enable speaker diarization if needed
4. Apply winning configuration with profile switcher

```bash
# Apply winning profile
./cuda-optimization/scripts/switch-profile.sh apply whisperx-speed-optimized
```

---

Generated by: `test-whisperx-accuracy.sh`
REPORT_FOOTER

    echo -e "${GREEN}✓ Report saved: $REPORT_FILE${NC}"
}

# Main execution
main() {
    download_samples
    run_tests

    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  Testing Complete!                                         ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "Results directory: ${CYAN}$RESULTS_DIR${NC}"
    echo ""
    echo -e "View comparison report:"
    echo -e "  ${BLUE}cat $RESULTS_DIR/comparison_report_${TIMESTAMP}.md${NC}"
    echo ""
    echo -e "View detailed JSON results:"
    echo -e "  ${BLUE}ls -lh $RESULTS_DIR/result_*_${TIMESTAMP}.json${NC}"
    echo ""
}

# Run main
main
