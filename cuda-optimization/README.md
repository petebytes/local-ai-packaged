# CUDA Optimization and Testing

This directory contains all resources related to CUDA version testing, Docker build optimization, and RTX 5090 GPU optimizations for the Local AI Packaged project.

## Directory Structure

```
cuda-optimization/
├── docs/                  # Documentation files
├── scripts/              # Automation scripts
├── cuda-base/           # Base Docker images
└── README.md           # This file
```

## Documentation (docs/)

Comprehensive guides for CUDA optimization and testing:

### [AUTOMATED_TESTING_GUIDE.md](docs/AUTOMATED_TESTING_GUIDE.md) ⭐ **NEW**
Complete guide to the automated CUDA testing and benchmarking system.

**Key Topics:**
- Automated benchmarking with persistent results database
- Parallel testing for 60-70% time savings
- Configuration profiles for easy management
- SQLite database for historical tracking
- Comparison report generation

**Quick Start:** `./scripts/test-cuda-versions-enhanced.sh whisperx --benchmark`

### [CUDA_VERSION_TESTING.md](docs/CUDA_VERSION_TESTING.md)
Complete guide for testing different CUDA versions to find optimal configurations for your RTX 5090.

**Key Topics:**
- Why test multiple CUDA versions
- One-time setup for testing all CUDA versions
- Per-service recommendations (WhisperX, InfiniteTalk)
- Testing workflows and benchmarking
- CUDA version matrix (12.1, 12.8, 12.9, 13.0, 13.1)

**Quick Start:** `./scripts/build-all-cuda-versions.sh quick`

### [DOCKER_OPTIMIZATION_GUIDE.md](docs/DOCKER_OPTIMIZATION_GUIDE.md)
Detailed documentation on Docker build optimizations that dramatically speed up rebuilds.

**Key Topics:**
- Registry pull-through cache (90% reduction in re-downloads)
- Shared CUDA base images (70% reduction in layer duplication)
- Multi-stage builds (50% reduction in final image size)
- Layer caching best practices
- Performance comparisons

**Quick Start:** `./scripts/configure-registry-cache.sh`

### [QUICK_REFERENCE.md](QUICK_REFERENCE.md) ⭐ **NEW**
Ultra-fast reference for automated testing commands.

**Use Case:** Quick lookup for benchmark, parallel testing, and profile commands.

### [QUICK_CUDA_TESTING.md](docs/QUICK_CUDA_TESTING.md)
Quick reference card for common CUDA testing commands and troubleshooting.

**Use Case:** Fast lookup when you need to test a CUDA version quickly.

### [RTX-5090-OPTIMIZATIONS.md](docs/RTX-5090-OPTIMIZATIONS.md)
Service-specific optimizations for the RTX 5090 GPU (Blackwell architecture).

**Key Topics:**
- WhisperX optimizations (CUDA 13.0, batch size 32, NVENC p6)
- ComfyUI optimizations (Sage attention, expandable memory)
- Kokoro TTS GPU acceleration
- VRAM management strategies (32GB)
- Performance benchmarks vs 2x RTX 3090

## Scripts (scripts/)

Automation tools for CUDA testing and Docker optimization:

### Build Scripts

**[build-all-cuda-versions.sh](scripts/build-all-cuda-versions.sh)**
```bash
# Build all CUDA base images (one-time setup)
./scripts/build-all-cuda-versions.sh full    # All versions: 12.1, 12.8, 12.9, 13.0, 13.1
./scripts/build-all-cuda-versions.sh quick   # Essential versions: 12.8, 12.9, 13.0
```

**[build-cuda-base.sh](scripts/build-cuda-base.sh)**
```bash
# Build specific base images
./scripts/build-cuda-base.sh all       # Both runtime and devel
./scripts/build-cuda-base.sh runtime   # Runtime only (~5 min)
./scripts/build-cuda-base.sh devel     # Devel only (~15 min)
```

### Testing Scripts

**[test-cuda-versions-enhanced.sh](scripts/test-cuda-versions-enhanced.sh)** ⭐ **NEW**
```bash
# Enhanced testing with automated benchmarking
./scripts/test-cuda-versions-enhanced.sh whisperx --benchmark          # With benchmarking
./scripts/test-cuda-versions-enhanced.sh whisperx --benchmark --compare # + report
./scripts/test-cuda-versions-enhanced.sh whisperx                      # Simple mode
```

**[test-cuda-versions.sh](scripts/test-cuda-versions.sh)**
```bash
# Original testing script (still supported)
./scripts/test-cuda-versions.sh whisperx          # Test default versions
./scripts/test-cuda-versions.sh infinitetalk all  # Test all versions
./scripts/test-cuda-versions.sh whisperx 12.8 13.0  # Test specific versions
```

### Optimization Scripts

**[switch-profile.sh](scripts/switch-profile.sh)** ⭐ **NEW**
```bash
# Configuration profile management
./scripts/switch-profile.sh list                           # List profiles
./scripts/switch-profile.sh apply whisperx-speed-optimized # Apply profile
./scripts/switch-profile.sh current whisperx               # Show current
```

**[configure-registry-cache.sh](scripts/configure-registry-cache.sh)**
```bash
# Set up Docker registry cache for faster rebuilds
./scripts/configure-registry-cache.sh
```

**[prepull-images.sh](scripts/prepull-images.sh)**
```bash
# Pre-download all base images to cache
./scripts/prepull-images.sh
```

## CUDA Base Images (cuda-base/)

Shared base Docker images that reduce build times and layer duplication:

### Runtime Base Images
- **Dockerfile.runtime**: Standard CUDA runtime base (~4GB)
- **Dockerfile.multi-runtime**: Multi-CUDA-version runtime base

**Use for:** Services that only need to run CUDA code (WhisperX, etc.)

**Contains:** CUDA runtime, PyTorch, common Python packages

### Development Base Images
- **Dockerfile.devel**: Standard CUDA development base (~8GB)
- **Dockerfile.multi-devel**: Multi-CUDA-version development base

**Use for:** Services that compile CUDA extensions (InfiniteTalk, etc.)

**Contains:** CUDA dev tools, PyTorch, build dependencies

## Quick Start Guide

### First-Time Setup (One-Time)

```bash
# 1. Build all CUDA base images (30-60 minutes)
cd /home/ghar/code/local-ai-packaged
./cuda-optimization/scripts/build-all-cuda-versions.sh quick

# 2. Configure registry cache (optional but recommended)
./cuda-optimization/scripts/configure-registry-cache.sh

# 3. Pre-pull images (optional)
./cuda-optimization/scripts/prepull-images.sh
```

### Testing a Service with Different CUDA Versions

```bash
# Automated testing
./cuda-optimization/scripts/test-cuda-versions.sh whisperx

# Manual testing
docker compose build --build-arg CUDA_VERSION=12.8 whisperx
docker compose build --build-arg CUDA_VERSION=13.0 whisperx
```

### Setting Permanent CUDA Version

After testing, update the service Dockerfile:

```dockerfile
# whisperx/Dockerfile
ARG CUDA_VERSION=13.0  # Change this to your optimal version
FROM cuda-base:runtime-${CUDA_VERSION}
```

Then rebuild:
```bash
docker compose build whisperx
```

## Performance Benefits

With these optimizations in place:

| Scenario | Before | After | Improvement |
|----------|--------|-------|-------------|
| First build | 20-30 min | 15-20 min | 25% faster |
| Rebuild (code change) | 10-20 min | 1-3 min | **90% faster** |
| Rebuild (dependency) | 15-25 min | 3-5 min | 80% faster |
| Testing CUDA configs | 10-20 min | 1-3 min | **95% faster** |
| Download bandwidth | ~20GB | ~2GB | **90% reduction** |

## CUDA Version Recommendations

| Service | Original | Recommended | Priority Order |
|---------|----------|-------------|----------------|
| WhisperX | 13.0.1 | 13.0 | 13.0 → 12.9 → 12.8 |
| InfiniteTalk | 12.1.0 | 12.8 | 12.8 → 12.9 → 13.0 |
| ComfyUI | (varies) | 12.9 | 12.9 → 13.0 → 12.8 |
| Kokoro TTS | (varies) | 12.9 | 12.9 → 12.8 → 13.0 |

## RTX 5090 Compatibility

- **Minimum CUDA Version**: 12.8
- **Recommended**: 12.9 or 13.0
- **Architecture**: Blackwell (sm_120)
- **VRAM**: 32GB (manage carefully, see RTX-5090-OPTIMIZATIONS.md)

## Troubleshooting

### Base image not found
```bash
./cuda-optimization/scripts/build-all-cuda-versions.sh quick
```

### Slow builds despite optimizations
Check:
1. Base images built? `docker images | grep cuda-base`
2. Registry cache running? `docker ps | grep registry-cache`
3. Docker daemon configured? `cat /etc/docker/daemon.json`

### Out of memory with RTX 5090
See [RTX-5090-OPTIMIZATIONS.md](docs/RTX-5090-OPTIMIZATIONS.md) for VRAM management strategies.

## Additional Resources

- [Docker BuildKit Documentation](https://docs.docker.com/build/buildkit/)
- [NVIDIA CUDA Images](https://hub.docker.com/r/nvidia/cuda)
- [PyTorch CUDA Compatibility](https://pytorch.org/get-started/locally/)

## Maintenance

### When to Rebuild Base Images

Only rebuild when:
- Upgrading CUDA version
- Upgrading PyTorch version
- Adding new common dependencies

Typical frequency: Once every few months

### Regular Cleanup

```bash
# Monthly: Clean unused images
docker system prune -a

# Check cache size
docker system df -v
```

## Support

For issues or questions:
1. Check the documentation in `docs/`
2. Review troubleshooting sections
3. Verify setup with provided scripts
4. Report issues with full logs and system info
