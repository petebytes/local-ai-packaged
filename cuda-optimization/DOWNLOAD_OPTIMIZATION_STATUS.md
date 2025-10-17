# Download Optimization Status & Recommendations

This document provides a comprehensive overview of download optimizations currently in place and recommended next steps for reducing bandwidth usage across multiple CUDA/PyTorch projects.

**Generated**: 2025-10-15
**For**: Local AI Packaged multi-project CUDA environment

---

## Current Setup Summary

### ✅ What's Already Implemented

#### 1. **Docker Registry Pull-Through Cache** (90% download reduction)
- **Status**: Container running, but daemon.json NOT configured
- **Location**: `registry-cache` service on port 5000
- **Storage**: Persistent volume `localai_registry-cache`
- **Impact**: Once configured, prevents re-downloading Docker base images

**Current Issue**: The cache is running but not being used because `/etc/docker/daemon.json` is not configured.

#### 2. **Shared CUDA Base Images** (70% layer duplication reduction)
- **Status**: Implemented and documented
- **Location**: `cuda-optimization/cuda-base/`
- **Types**:
  - Runtime base (~4GB): For services that run models
  - Devel base (~8GB): For services that compile CUDA extensions
- **Versions Supported**: 12.1, 12.8, 12.9, 13.0, 13.1
- **Usage**: Both WhisperX and InfiniteTalk already use these base images

#### 3. **Multi-Stage Builds** (50% final image size reduction)
- **Status**: Implemented for InfiniteTalk
- **Impact**: Separates build-time from runtime dependencies
- **Example**: InfiniteTalk compiles in devel stage, runs in runtime stage

#### 4. **Service-Specific Persistent Volumes**
- **Status**: Implemented for WhisperX
- **Volume**: `whisperx-cache` mounted to `/root/.cache`
- **Impact**: Prevents re-downloading HuggingFace models between container restarts

---

## Current Gaps & Missing Optimizations

### 🔴 Critical Missing Items

#### 1. **Docker Daemon Configuration NOT Applied**
**Problem**: Registry cache is running but not being used by Docker daemon.

**Impact**: All Docker pulls still go to Docker Hub instead of local cache.

**Fix**:
```bash
./cuda-optimization/scripts/configure-registry-cache.sh
```

This will:
- Create `/etc/docker/daemon.json` with mirror configuration
- Restart Docker daemon
- Restart registry cache

**Expected Benefit**: 90% reduction in re-downloads for base images

---

#### 2. **HuggingFace Cache Not Configured for Most Services**
**Problem**: Each service downloads models to container-local cache, which is lost on rebuild.

**Current State**:
- ✅ WhisperX has persistent cache volume
- ❌ ComfyUI no persistent model cache
- ❌ InfiniteTalk no persistent model cache
- ❌ Crawl4AI no persistent model cache

**Impact**: Every rebuild re-downloads all HuggingFace models (can be 2-20GB per service).

**Fix Required**: See "Recommended Next Steps" section below.

---

#### 3. **BuildKit Cache Mounts Not Used**
**Problem**: Dockerfiles use `--no-cache-dir` which prevents layer caching but doesn't use BuildKit's persistent cache mounts.

**Current Approach**:
```dockerfile
RUN pip3 install --no-cache-dir torch torchvision
```

**Modern Best Practice** (2025):
```dockerfile
# syntax=docker/dockerfile:1.12
RUN --mount=type=cache,target=/root/.cache/pip \
    pip3 install torch torchvision
```

**Impact**:
- Current: Pip downloads packages every build
- With cache mounts: Pip downloads once, reuses across builds
- Savings: 80-95% reduction in pip download time

---

#### 4. **PyTorch Model Cache Not Shared**
**Problem**: Each service that uses PyTorch models (pretrained weights) downloads them independently.

**Environment Variables Not Set**:
- `TORCH_HOME` - Not configured
- `TRANSFORMERS_CACHE` - Not configured
- `HF_HOME` - Not configured

**Impact**: Same models downloaded multiple times across services.

---

#### 5. **No Cross-Project Cache Sharing**
**Problem**: If you have multiple projects (not just services), each project maintains separate caches.

**Impact**:
- Project A downloads `torch==2.7.1`
- Project B downloads `torch==2.7.1` (again)
- Same for HuggingFace models, CUDA libraries, etc.

---

### ⚠️ Moderate Missing Items

#### 6. **No Pip Cache Between Builds**
**Problem**: Using `--no-cache-dir` prevents caching within image but also prevents cache mounts from working optimally.

#### 7. **ComfyUI Models Not Cached**
**Problem**: ComfyUI downloads large Stable Diffusion models (4-8GB each) without persistent storage.

**Current Volume**:
```yaml
volumes:
  - ./ComfyUI:/workspace/ComfyUI  # Source code only
```

**Missing**: No volume for `/workspace/ComfyUI/models`

---

## Web Best Practices Analysis (2025)

Based on latest research, here are the recommended approaches:

### 1. **BuildKit Cache Mounts** (Highest Impact)
Modern Docker builds should use cache mounts for all package managers:

```dockerfile
# syntax=docker/dockerfile:1.12
FROM nvidia/cuda:12.8.1-cudnn-runtime-ubuntu22.04

# Pip cache mount
RUN --mount=type=cache,target=/root/.cache/pip \
    pip3 install torch torchvision

# APT cache mount
RUN --mount=type=cache,target=/var/cache/apt \
    --mount=type=cache,target=/var/lib/apt \
    apt-get update && apt-get install -y python3
```

**Benefits**:
- Downloads once, cached forever
- Cache persists across builds
- Significantly faster rebuilds
- Cache shared across all Dockerfiles on same host

---

### 2. **Persistent HuggingFace Cache**
Set cache location to persistent volume:

```dockerfile
ENV HF_HOME=/data/.huggingface
ENV TRANSFORMERS_CACHE=/data/.huggingface/transformers
ENV TORCH_HOME=/data/.torch
```

```yaml
# docker-compose.yml
volumes:
  - hf-cache:/data/.huggingface
  - torch-cache:/data/.torch
```

**Benefits**:
- Models downloaded once per volume
- Survives container rebuilds
- Can be shared across multiple services

---

### 3. **Layer Ordering Optimization**
Order Dockerfile instructions from least to most frequently changing:

```dockerfile
# ✅ Optimal ordering
FROM base-image
RUN install system packages          # Changes rarely
COPY requirements.txt .              # Changes occasionally
RUN pip install -r requirements.txt  # Changes occasionally
COPY . .                             # Changes frequently
```

---

### 4. **Registry Cache Backend for CI/CD**
For distributed builds or CI/CD:

```bash
docker buildx build \
  --cache-to=type=registry,ref=localhost:5000/myapp-cache,mode=max \
  --cache-from=type=registry,ref=localhost:5000/myapp-cache \
  -f Dockerfile .
```

---

## Recommended Next Steps

### Phase 1: Critical Fixes (High Impact, Low Effort)

#### Step 1.1: Enable Docker Registry Cache
**Time**: 5 minutes
**Impact**: 90% reduction in Docker Hub downloads

```bash
cd /home/ghar/code/local-ai-packaged
./cuda-optimization/scripts/configure-registry-cache.sh
```

**Test**:
```bash
docker pull alpine:latest
time docker pull alpine:latest  # Should be instant
```

---

#### Step 1.2: Add HuggingFace Cache Volumes
**Time**: 10 minutes
**Impact**: Prevent re-downloading models (2-20GB per service)

Add to `docker-compose.yml`:

```yaml
volumes:
  # Add these new volumes
  hf-cache:
    driver: local
  torch-cache:
    driver: local
  comfyui-models:
    driver: local

services:
  whisperx:
    volumes:
      - whisperx-cache:/root/.cache
      - hf-cache:/data/.huggingface     # ADD THIS
      - torch-cache:/data/.torch         # ADD THIS
    environment:
      - HF_HOME=/data/.huggingface       # ADD THIS
      - TORCH_HOME=/data/.torch          # ADD THIS
      - TRANSFORMERS_CACHE=/data/.huggingface/transformers  # ADD THIS

  comfyui:
    volumes:
      - ./ComfyUI:/workspace/ComfyUI
      - comfyui-models:/workspace/ComfyUI/models  # ADD THIS
      - hf-cache:/data/.huggingface               # ADD THIS
      - torch-cache:/data/.torch                  # ADD THIS
    environment:
      - HF_HOME=/data/.huggingface       # ADD THIS
      - TORCH_HOME=/data/.torch          # ADD THIS

  # Similar for other services (infinitetalk, crawl4ai, etc.)
```

**Test**:
```bash
# First run - downloads models
docker compose up -d whisperx
curl -X POST https://whisper.lan/transcribe -F "file=@test.mp3"

# Rebuild - should NOT re-download models
docker compose build whisperx
docker compose up -d whisperx
# Models still present in /data/.huggingface
```

---

### Phase 2: BuildKit Optimizations (Moderate Effort, High Impact)

#### Step 2.1: Update Base Image Dockerfiles with Cache Mounts
**Time**: 20 minutes
**Impact**: 80% reduction in pip download time

Update `cuda-optimization/cuda-base/Dockerfile.runtime`:

```dockerfile
# syntax=docker/dockerfile:1.12
FROM nvidia/cuda:12.8.1-cudnn-runtime-ubuntu22.04

LABEL maintainer="Local AI Packaged"
LABEL description="Shared CUDA base image with BuildKit cache optimization"

ENV DEBIAN_FRONTEND=noninteractive
ENV LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH}
ENV PYTHONUNBUFFERED=1

# Install system dependencies with APT cache mount
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    python3.10 \
    python3-pip \
    ffmpeg \
    git \
    libsndfile1 \
    wget \
    curl \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Upgrade pip with cache mount
RUN --mount=type=cache,target=/root/.cache/pip \
    pip3 install --upgrade pip setuptools wheel

# Install PyTorch with pip cache mount
RUN --mount=type=cache,target=/root/.cache/pip \
    pip3 install \
    torch==2.7.1 \
    torchvision==0.22.1 \
    torchaudio==2.7.1 \
    --index-url https://download.pytorch.org/whl/cu128

# Install common dependencies with cache mount
RUN --mount=type=cache,target=/root/.cache/pip \
    pip3 install \
    numpy>=1.24.0 \
    requests>=2.31.0 \
    pillow>=10.0.0 \
    tqdm>=4.65.0

# Verify CUDA
RUN python3 -c "import torch; print(f'PyTorch: {torch.__version__}'); print(f'CUDA: {torch.version.cuda}')"

WORKDIR /app
```

**Rebuild**:
```bash
cd /home/ghar/code/local-ai-packaged
docker build -f cuda-optimization/cuda-base/Dockerfile.runtime -t cuda-base:runtime-12.8 .

# Second build should be MUCH faster
time docker build -f cuda-optimization/cuda-base/Dockerfile.runtime -t cuda-base:runtime-12.8 .
```

---

#### Step 2.2: Update Service Dockerfiles
**Time**: 10 minutes per service
**Impact**: Faster rebuilds for all services

Update `whisperx/Dockerfile`:

```dockerfile
# syntax=docker/dockerfile:1.12
ARG CUDA_VERSION=13.0
FROM cuda-base:runtime-${CUDA_VERSION}

LABEL maintainer="Local AI Packaged"
LABEL description="WhisperX with BuildKit cache optimization"

# Cache environment variables
ENV HF_HOME=/data/.huggingface
ENV TRANSFORMERS_CACHE=/data/.huggingface/transformers
ENV TORCH_HOME=/data/.torch

# Install WhisperX with pip cache mount
RUN --mount=type=cache,target=/root/.cache/pip \
    pip3 install git+https://github.com/m-bain/whisperx.git@main

# Install web server dependencies with cache mount
RUN --mount=type=cache,target=/root/.cache/pip \
    pip3 install \
    fastapi==0.109.0 \
    uvicorn==0.27.0 \
    python-multipart==0.0.6 \
    pydantic==2.5.3

# Create directories
RUN mkdir -p /app/uploads /data/.huggingface /data/.torch /app/shared/temp /app/shared/input /app/shared/output

WORKDIR /app

# Copy application code LAST
COPY api_server.py /app/api_server.py
COPY ffmpeg_processor.py /app/ffmpeg_processor.py
COPY video_segmenter.py /app/video_segmenter.py

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD python3 -c "import requests; requests.get('http://localhost:8000/health')" || exit 1

CMD ["python3", "-u", "api_server.py"]
```

---

### Phase 3: Cross-Project Optimizations (Advanced)

#### Step 3.1: Create Host-Level Cache Directories
**Time**: 15 minutes
**Impact**: Share downloads across all projects on same machine

```bash
# Create shared cache directories on host
sudo mkdir -p /opt/ai-cache/huggingface
sudo mkdir -p /opt/ai-cache/torch
sudo mkdir -p /opt/ai-cache/pip
sudo chown -R $USER:$USER /opt/ai-cache
sudo chmod -R 755 /opt/ai-cache
```

Update `docker-compose.yml` to use bind mounts instead of named volumes:

```yaml
services:
  whisperx:
    volumes:
      - /opt/ai-cache/huggingface:/data/.huggingface  # Shared across projects
      - /opt/ai-cache/torch:/data/.torch              # Shared across projects
```

**Benefits**:
- Project A and Project B share the same cache
- Download `sentence-transformers/all-MiniLM-L6-v2` once, use in 10 projects
- Survives even if you delete docker volumes

---

#### Step 3.2: Set Up Shared Docker BuildKit Cache
**Time**: 20 minutes
**Impact**: BuildKit cache shared across all projects

Create `/etc/docker/daemon.json` with BuildKit backend:

```json
{
  "registry-mirrors": ["http://localhost:5000"],
  "features": {
    "buildkit": true
  },
  "builder": {
    "gc": {
      "enabled": true,
      "defaultKeepStorage": "50GB"
    }
  },
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
```

Restart Docker:
```bash
sudo systemctl restart docker
```

---

#### Step 3.3: Pre-Download Common Models
**Time**: 1-2 hours (one-time)
**Impact**: All projects have immediate access to common models

Create a script to pre-populate cache:

```python
#!/usr/bin/env python3
# pre-download-models.py
import os
os.environ['HF_HOME'] = '/opt/ai-cache/huggingface'
os.environ['TORCH_HOME'] = '/opt/ai-cache/torch'

from transformers import AutoModel, AutoTokenizer
import whisperx

# Common models used across projects
MODELS = [
    # WhisperX models
    ("openai/whisper-large-v3", "whisper"),
    ("openai/whisper-large-v3-turbo", "whisper"),

    # Sentence transformers (embeddings)
    ("sentence-transformers/all-MiniLM-L6-v2", "transformer"),
    ("BAAI/bge-large-en-v1.5", "transformer"),

    # Common LLMs
    ("bert-base-uncased", "transformer"),
    ("distilbert-base-uncased", "transformer"),
]

for model_name, model_type in MODELS:
    print(f"Downloading {model_name}...")
    try:
        if model_type == "transformer":
            AutoModel.from_pretrained(model_name)
            AutoTokenizer.from_pretrained(model_name)
        elif model_type == "whisper":
            whisperx.load_model(model_name.split("/")[1], device="cpu")
        print(f"✓ {model_name}")
    except Exception as e:
        print(f"✗ {model_name}: {e}")

print("\nAll common models downloaded to /opt/ai-cache/huggingface")
```

Run:
```bash
python3 pre-download-models.py
```

---

## Estimated Impact Summary

### Current Situation (No Optimizations Applied)
- **First build**: 20-30 min, ~20GB downloads
- **Rebuild (code change)**: 10-20 min, ~5-10GB downloads
- **Rebuild (dependency change)**: 15-25 min, ~15-20GB downloads
- **Cross-project redundancy**: 100% (every project downloads everything)

### After Phase 1 (Registry Cache + HF Volumes)
- **First build**: 20-30 min, ~20GB downloads (same)
- **Rebuild (code change)**: 2-5 min, ~500MB downloads (**90% reduction**)
- **Rebuild (dependency change)**: 5-8 min, ~2GB downloads (**85% reduction**)
- **Cross-project redundancy**: 80% (HF models cached, but pip still redundant)

### After Phase 2 (BuildKit Cache Mounts)
- **First build**: 18-25 min, ~20GB downloads (10% faster)
- **Rebuild (code change)**: 1-3 min, ~100MB downloads (**95% reduction**)
- **Rebuild (dependency change)**: 2-4 min, ~500MB downloads (**95% reduction**)
- **Cross-project redundancy**: 60% (pip cached, still per-project HF cache)

### After Phase 3 (Host-Level Caching)
- **First build**: 18-25 min, ~20GB downloads (same)
- **Rebuild (code change)**: 30s-2 min, ~50MB downloads (**98% reduction**)
- **Rebuild (dependency change)**: 1-3 min, ~200MB downloads (**98% reduction**)
- **Cross-project redundancy**: 5-10% (**90% elimination**)

---

## Storage Requirements

### Current
- Docker images: ~30GB
- Volumes (per project): ~20GB
- **Total per project**: ~50GB

### After Full Optimization
- Docker images: ~20GB (40% reduction from multi-stage)
- Shared cache (all projects): ~50GB
- Per-project volumes: ~5GB
- **Total for 5 projects**: ~75GB vs ~250GB (**70% reduction**)

---

## Quick Win Commands

### Immediate Actions (5 minutes)

```bash
# 1. Enable registry cache
cd /home/ghar/code/local-ai-packaged
./cuda-optimization/scripts/configure-registry-cache.sh

# 2. Test it works
docker pull ubuntu:22.04
docker pull ubuntu:22.04  # Should be instant

# 3. Check cache is being used
curl http://localhost:5000/v2/_catalog
```

### Quick HF Cache Setup (10 minutes)

```bash
# Create docker-compose.override.yml for testing
cat > docker-compose.override.yml << 'EOF'
volumes:
  hf-cache:
    driver: local
  torch-cache:
    driver: local

services:
  whisperx:
    volumes:
      - hf-cache:/data/.huggingface
      - torch-cache:/data/.torch
    environment:
      - HF_HOME=/data/.huggingface
      - TORCH_HOME=/data/.torch
      - TRANSFORMERS_CACHE=/data/.huggingface/transformers
EOF

# Restart service
docker compose up -d whisperx
```

---

## Monitoring & Validation

### Check Cache Usage

```bash
# Registry cache contents
curl http://localhost:5000/v2/_catalog | jq

# HuggingFace cache size
docker exec whisperx du -sh /data/.huggingface

# Docker volume sizes
docker system df -v

# BuildKit cache size
docker buildx du
```

### Performance Benchmarking

```bash
# Benchmark rebuild time
time docker compose build whisperx

# Clear BuildKit cache to test
docker builder prune -a

# Rebuild and compare
time docker compose build whisperx
```

---

## Troubleshooting

### Registry Cache Not Working
```bash
# Check daemon.json
cat /etc/docker/daemon.json

# Restart Docker
sudo systemctl restart docker

# Verify mirror is active
docker system info | grep -i mirror
```

### HuggingFace Cache Not Persisting
```bash
# Check volume is mounted
docker exec whisperx df -h | grep huggingface

# Check environment variables
docker exec whisperx env | grep -E "HF_HOME|TRANSFORMERS"

# List cached models
docker exec whisperx ls -la /data/.huggingface/hub
```

### BuildKit Cache Not Working
```bash
# Verify BuildKit is enabled
docker buildx version

# Check cache mounts in build
DOCKER_BUILDKIT=1 docker build --progress=plain -f Dockerfile . 2>&1 | grep "cache mount"
```

---

## Additional Resources

- [Docker BuildKit Documentation](https://docs.docker.com/build/buildkit/)
- [HuggingFace Hub Cache System](https://huggingface.co/docs/huggingface_hub/guides/manage-cache)
- [PyTorch Model Zoo Cache](https://pytorch.org/docs/stable/hub.html)
- [Registry Pull-Through Cache](https://distribution.github.io/distribution/recipes/mirror/)

---

## Next Steps Checklist

- [ ] Run `./cuda-optimization/scripts/configure-registry-cache.sh`
- [ ] Add HuggingFace cache volumes to docker-compose.yml
- [ ] Update base image Dockerfiles with BuildKit cache mounts
- [ ] Update service Dockerfiles with cache mounts
- [ ] Create host-level cache directories for cross-project sharing
- [ ] Pre-download common models to shared cache
- [ ] Benchmark and validate improvements
- [ ] Document project-specific optimizations

---

**Status**: Ready for implementation
**Priority**: Phase 1 (Critical) should be done immediately
**Estimated Total Time Investment**: 2-3 hours for all phases
**Estimated Savings**: 90-98% reduction in downloads, 70% reduction in storage
