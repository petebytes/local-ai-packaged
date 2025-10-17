# Quick CUDA Testing Reference

## One-Time Setup (Do This First)

```bash
# 1. Build all CUDA base images (30-60 min, but only once!)
./scripts/build-all-cuda-versions.sh quick

# 2. Configure Docker registry cache (optional but recommended)
./scripts/configure-registry-cache.sh
```

## Quick Commands

### Test a Service with Different CUDA Versions

```bash
# Automated testing (recommended)
./scripts/test-cuda-versions.sh whisperx        # Test with 12.1, 12.8, 12.9, 13.0
./scripts/test-cuda-versions.sh infinitetalk    # Test InfiniteTalk
./scripts/test-cuda-versions.sh whisperx all    # Test all available versions

# Manual single version test
docker compose build --build-arg CUDA_VERSION=12.8 whisperx
docker compose build --build-arg CUDA_VERSION=13.0 whisperx
```

### Available CUDA Versions

| Version | Status | Best For |
|---------|--------|----------|
| 12.1 | Legacy | Compatibility |
| 12.8 | ✅ RTX 5090 Min | Baseline |
| 12.9 | ✅ Stable | Recommended |
| 13.0 | Bleeding Edge | Latest Features |
| 13.1 | Experimental | Cutting Edge |

### Quick Benchmark

```bash
# Start service
docker compose up -d whisperx

# Test transcription speed
time curl -X POST https://whisper.lan/transcribe \
  -F "file=@test.mp3" \
  -F "model=large-v3"

# Watch GPU usage
nvidia-smi dmon -s u -c 10
```

### Set Permanent Version

Edit service Dockerfile:
```dockerfile
ARG CUDA_VERSION=12.9  # Change this line
```

Then rebuild:
```bash
docker compose build whisperx
```

## Common Issues

**Base image not found?**
```bash
./scripts/build-all-cuda-versions.sh quick
```

**Build fails?**
- Check CUDA version exists in base images: `docker images | grep cuda-base`
- Try adjacent version: `12.8` → `12.9`

**Container won't start?**
```bash
docker compose logs whisperx
nvidia-smi  # Check driver version
```

## Performance Comparison Template

Test each version and record:

| CUDA | Build Time | Speed | VRAM | Status |
|------|-----------|-------|------|--------|
| 12.8 | ___min | ___x | ___GB | ✅/❌ |
| 12.9 | ___min | ___x | ___GB | ✅/❌ |
| 13.0 | ___min | ___x | ___GB | ✅/❌ |

**Winner**: _______ (because: _____________)

## Full Documentation

- Complete guide: `CUDA_VERSION_TESTING.md`
- Optimization details: `DOCKER_OPTIMIZATION_GUIDE.md`
