# CUDA Version Testing Guide

This guide shows you how to quickly test different CUDA versions for each service to find the optimal configuration for your RTX 5090.

## Why Test Multiple CUDA Versions?

Different CUDA versions offer different benefits:
- **Newer versions (13.0+)**: Latest features, bleeding-edge optimizations
- **Stable versions (12.8-12.9)**: Proven reliability, RTX 5090 support
- **Legacy versions (12.1)**: Maximum compatibility, well-tested

The RTX 5090 (Blackwell architecture) requires **CUDA 12.8 minimum**, but newer versions may offer better performance.

## Quick Start

### 1. One-Time Setup: Build All CUDA Base Images

```bash
# Build all versions (takes 30-60 minutes, but only once!)
./scripts/build-all-cuda-versions.sh full

# Or quick mode (essential versions only, ~20 minutes)
./scripts/build-all-cuda-versions.sh quick
```

This creates base images for CUDA versions: **12.1, 12.8, 12.9, 13.0, 13.1**

### 2. Configure Registry Cache (Optional but Recommended)

```bash
./scripts/configure-registry-cache.sh
```

Caches downloads so testing multiple versions is fast.

### 3. Test a Service with Different CUDA Versions

**Option A: Automated testing script**
```bash
# Test WhisperX with default versions (12.1, 12.8, 12.9, 13.0)
./scripts/test-cuda-versions.sh whisperx

# Test InfiniteTalk with all available versions
./scripts/test-cuda-versions.sh infinitetalk all

# Test specific versions only
./scripts/test-cuda-versions.sh whisperx 12.8 13.0
```

**Option B: Manual testing**
```bash
# Test CUDA 12.8
docker compose build --build-arg CUDA_VERSION=12.8 whisperx
docker compose up -d whisperx
# ... test functionality ...
docker compose down whisperx

# Test CUDA 13.0
docker compose build --build-arg CUDA_VERSION=13.0 whisperx
docker compose up -d whisperx
# ... test functionality ...
docker compose down whisperx
```

## CUDA Version Matrix

| Version | Release | RTX 5090 | Status | Use Case |
|---------|---------|----------|--------|----------|
| **12.1.0** | 2023 | ❌ No | Legacy | Max compatibility with older code |
| **12.8.1** | 2024 | ✅ Yes | Stable | RTX 5090 minimum, recommended baseline |
| **12.9.1** | 2024 | ✅ Yes | Stable | Newer features, Kokoro default |
| **13.0.1** | 2025 | ✅ Yes | Bleeding | Latest features, WhisperX original |
| **13.1.0** | 2025 | ✅ Yes | Experimental | Cutting edge, may be unstable |

## Per-Service Recommendations

### WhisperX (Audio Transcription)

**Original**: CUDA 13.0.1
**Test priority**: 13.0 → 12.9 → 12.8

```bash
# Test versions optimized for inference speed
./scripts/test-cuda-versions.sh whisperx 13.0 12.9 12.8

# Manual test
docker compose build --build-arg CUDA_VERSION=13.0 whisperx
```

**What to test**:
- Transcription speed (time per minute of audio)
- Memory usage (watch `nvidia-smi`)
- Accuracy (compare outputs)
- Model load time

### InfiniteTalk (Video Generation)

**Original**: CUDA 12.1.0
**Test priority**: 12.8 → 12.9 → 13.0

```bash
# Test versions optimized for video generation
./scripts/test-cuda-versions.sh infinitetalk 12.8 12.9 13.0

# Manual test
docker compose build --build-arg CUDA_VERSION=12.8 infinitetalk
```

**What to test**:
- Video generation speed
- VRAM usage (32GB capacity on RTX 5090)
- Flash-attention compilation success
- Output quality

### Future Services

For any new CUDA-enabled service:

1. Check service documentation for recommended CUDA version
2. Start with CUDA 12.8 (RTX 5090 minimum)
3. Test newer versions if issues occur
4. Use automated testing script

## Testing Workflow

### Step 1: Initial Test Matrix

Build all versions and run basic tests:

```bash
# Automated test (recommended)
./scripts/test-cuda-versions.sh whisperx

# Results show:
# - Which versions build successfully
# - Build time for each version
# - Final image size
# - CUDA availability check
```

### Step 2: Benchmark Top Candidates

For versions that built successfully, run detailed benchmarks:

```bash
# Example: WhisperX with CUDA 13.0
docker compose build --build-arg CUDA_VERSION=13.0 whisperx
docker compose up -d whisperx

# Benchmark transcription
time curl -X POST https://whisper.lan/transcribe \
  -F "file=@test-audio.mp3" \
  -F "model=large-v3"

# Monitor GPU usage
nvidia-smi dmon -s u -c 10

docker compose down whisperx
```

### Step 3: Compare Results

Create a comparison matrix:

| CUDA | Build Time | Runtime | VRAM Peak | Speed | Quality |
|------|-----------|---------|-----------|-------|---------|
| 12.8 | 3m 45s    | ✅      | 8.2 GB    | 1.2x  | Good    |
| 12.9 | 4m 12s    | ✅      | 8.0 GB    | 1.3x  | Good    |
| 13.0 | 5m 30s    | ✅      | 7.8 GB    | 1.5x  | Great   |

### Step 4: Select Winner

Choose based on your priorities:
- **Speed**: Fastest runtime performance
- **Stability**: Most mature/tested version
- **Features**: Latest capabilities
- **Size**: Smallest image size

### Step 5: Lock In Version

Update the service Dockerfile default:

```dockerfile
# whisperx/Dockerfile
ARG CUDA_VERSION=13.0  # ← Change this to your winner
FROM cuda-base:runtime-${CUDA_VERSION}
```

## Performance Testing Commands

### GPU Monitoring

```bash
# Real-time GPU stats
watch -n 1 nvidia-smi

# GPU utilization over time
nvidia-smi dmon -s u -c 60

# Memory usage
nvidia-smi --query-gpu=memory.used,memory.total --format=csv
```

### WhisperX Benchmarks

```bash
# Transcribe test file
time docker compose exec whisperx curl -X POST http://localhost:8000/transcribe \
  -F "file=@/app/shared/test-audio.mp3" \
  -F "model=large-v3"

# With diarization
time docker compose exec whisperx curl -X POST http://localhost:8000/transcribe \
  -F "file=@/app/shared/test-audio.mp3" \
  -F "model=large-v3" \
  -F "enable_diarization=true"
```

### InfiniteTalk Benchmarks

```bash
# Video generation test
docker compose exec infinitetalk python3 -c "
import torch
print(f'CUDA: {torch.version.cuda}')
print(f'Available: {torch.cuda.is_available()}')
print(f'Device: {torch.cuda.get_device_name(0)}')
"

# Memory test
docker compose exec infinitetalk python3 -c "
import torch
torch.cuda.empty_cache()
print(f'Free: {torch.cuda.mem_get_info()[0]/1024**3:.2f}GB')
print(f'Total: {torch.cuda.mem_get_info()[1]/1024**3:.2f}GB')
"
```

## Troubleshooting

### Base Image Not Found

**Error**: `cuda-base:runtime-12.8: not found`

**Solution**:
```bash
# Build the base images first
./scripts/build-all-cuda-versions.sh quick
```

### Build Fails with CUDA Version

**Error**: `Could not find a version that satisfies torch`

**Cause**: PyTorch doesn't have pre-built wheels for that CUDA version

**Solution**: Try adjacent version or check PyTorch website for supported CUDA versions

### Service Won't Start After Build

**Check**:
```bash
# View logs
docker compose logs whisperx

# Test CUDA inside container
docker compose exec whisperx python3 -c "import torch; print(torch.cuda.is_available())"

# Check driver compatibility
nvidia-smi
```

### Different Results Between Versions

This is expected! Document the differences:
- Performance variations
- Memory usage changes
- Output quality differences
- Compatibility issues

## Advanced: Version Matrix Testing

Test ALL combinations automatically:

```bash
# Create test matrix
cat > test-matrix.sh << 'EOF'
#!/bin/bash
SERVICES=("whisperx" "infinitetalk")
VERSIONS=("12.8" "12.9" "13.0")

for service in "${SERVICES[@]}"; do
  for version in "${VERSIONS[@]}"; do
    echo "Testing $service with CUDA $version"
    ./scripts/test-cuda-versions.sh $service $version
  done
done
EOF

chmod +x test-matrix.sh
./test-matrix.sh
```

## Tips for Faster Testing

1. **Use registry cache**: First test downloads, rest are instant
2. **Build base images once**: Reused across all service tests
3. **Test in parallel**: Build multiple versions simultaneously
4. **Keep notes**: Document what works and what doesn't
5. **Start conservative**: Begin with CUDA 12.8 (RTX 5090 minimum)

## Recommended Testing Order

### For New RTX 5090 Setups

1. **CUDA 12.8** - Baseline (must work)
2. **CUDA 12.9** - Stable newer
3. **CUDA 13.0** - Bleeding edge
4. Compare results, pick winner

### For Existing Projects

1. **Current version** - Establish baseline
2. **CUDA 12.8** - RTX 5090 minimum
3. **One version newer** - Check improvements
4. **One version older** - Fallback option

## Build Time Expectations

With base images pre-built and registry cache:

| Scenario | First Time | Subsequent |
|----------|-----------|------------|
| Base images (all) | 30-60 min | N/A (reuse) |
| Service (new CUDA) | 3-8 min | 1-2 min |
| Service (code change) | N/A | 30-60 sec |

Without optimizations: **10-20 minutes per test** 😱
With optimizations: **1-3 minutes per test** 🚀

## Summary

```bash
# Complete testing workflow:

# 1. One-time setup (60 min)
./scripts/build-all-cuda-versions.sh full
./scripts/configure-registry-cache.sh

# 2. Test service with multiple versions (5-15 min)
./scripts/test-cuda-versions.sh whisperx

# 3. Benchmark winner (varies)
docker compose build --build-arg CUDA_VERSION=13.0 whisperx
# ... run benchmarks ...

# 4. Lock in winner (1 min)
# Edit whisperx/Dockerfile: ARG CUDA_VERSION=13.0
docker compose build whisperx

# Done! Now you have the optimal CUDA version for your RTX 5090
```

## Next Steps

After finding optimal versions:
1. Update service Dockerfiles with winning versions
2. Document why you chose each version
3. Re-test periodically as new CUDA versions release
4. Share findings with the community

**Remember**: The "best" version depends on your specific workload. Always benchmark with your actual use cases!
