# CUDA Testing Quick Reference

Fast lookup for common CUDA testing commands.

## 🚀 Quick Commands

### Automated Benchmarking

```bash
# Benchmark single version
python3 cuda-optimization/benchmark/benchmark.py --service whisperx --cuda-version 12.8

# Benchmark with comparison report
python3 cuda-optimization/benchmark/benchmark.py --service whisperx --cuda-version 13.0 --compare

# View results
python3 cuda-optimization/benchmark/benchmark.py --service whisperx --report
```

### Sequential Testing

```bash
# Simple test (like original)
./cuda-optimization/scripts/test-cuda-versions-enhanced.sh whisperx

# With automated benchmarking
./cuda-optimization/scripts/test-cuda-versions-enhanced.sh whisperx --benchmark

# With comparison report
./cuda-optimization/scripts/test-cuda-versions-enhanced.sh whisperx --benchmark --compare
```

### Parallel Testing (60-70% faster)

```bash
# Start all tests
docker compose -f cuda-optimization/docker-compose.test-matrix.yml up -d

# Monitor
docker compose -f cuda-optimization/docker-compose.test-matrix.yml logs -f test-orchestrator

# View results
cat cuda-optimization/benchmark/parallel-test-results.json

# Cleanup
docker compose -f cuda-optimization/docker-compose.test-matrix.yml down
```

### Configuration Profiles

```bash
# List profiles
./cuda-optimization/scripts/switch-profile.sh list

# Apply profile
./cuda-optimization/scripts/switch-profile.sh apply whisperx-speed-optimized

# Show current
./cuda-optimization/scripts/switch-profile.sh current whisperx
```

## 📊 Available Profiles

| Profile | CUDA | Use Case | Best For |
|---------|------|----------|----------|
| speed-optimized | 13.0 | Maximum speed | Production throughput |
| stability-focused | 12.8 | Reliability | 24/7 services |
| compatibility | 12.1 | Legacy support | Older GPUs |

## ⏱️ Time Comparison

| Method | Time for 3 Versions | When to Use |
|--------|---------------------|-------------|
| Sequential | 30-45 min | First time, detailed logs |
| Sequential + Benchmark | 40-60 min | Need metrics |
| Parallel | 10-15 min | Quick comparison |

## 🎯 Common Workflows

### Find Best CUDA Version
```bash
./cuda-optimization/scripts/test-cuda-versions-enhanced.sh whisperx --benchmark --compare
cat cuda-optimization/benchmark/comparison_whisperx_*.md
./cuda-optimization/scripts/switch-profile.sh apply whisperx-speed-optimized
```

### Quick Parallel Test
```bash
docker compose -f cuda-optimization/docker-compose.test-matrix.yml up -d
# Wait for completion...
cat cuda-optimization/benchmark/parallel-test-results.json
docker compose -f cuda-optimization/docker-compose.test-matrix.yml down
```

### Save Custom Config
```bash
# After manual tuning...
./cuda-optimization/scripts/switch-profile.sh create whisperx my-production-config
nano cuda-optimization/profiles/my-production-config.yml
```

## 🔧 Troubleshooting

```bash
# Database locked
pkill -f benchmark.py

# Check GPU
nvidia-smi

# View container logs
docker compose logs whisperx

# Restore Dockerfile
git checkout whisperx/Dockerfile
```

## 📚 Full Documentation

- **Complete Guide**: `cuda-optimization/docs/AUTOMATED_TESTING_GUIDE.md`
- **CUDA Testing**: `cuda-optimization/docs/CUDA_VERSION_TESTING.md`
- **Quick Guide**: `cuda-optimization/docs/QUICK_CUDA_TESTING.md`
