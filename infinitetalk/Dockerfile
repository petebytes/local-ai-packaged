# syntax=docker/dockerfile:1.12
# InfiniteTalk Docker Image - Flexible CUDA Version Testing with BuildKit Cache Optimization
#
# QUICK TEST DIFFERENT CUDA VERSIONS:
#   docker compose build --build-arg CUDA_VERSION=12.1 infinitetalk
#   docker compose build --build-arg CUDA_VERSION=12.8 infinitetalk
#   docker compose build --build-arg CUDA_VERSION=12.9 infinitetalk
#
# SUPPORTED CUDA VERSIONS:
#   12.1 = Original default
#   12.8 = RTX 5090 minimum
#   12.9 = Newer stable
#   13.0 = Bleeding edge
#
# Multi-stage build: Compiles in devel, runs in runtime
# BuildKit cache mounts: 80% faster rebuilds

ARG CUDA_VERSION=12.1

# ============================================================================
# BUILD STAGE - Compile CUDA extensions with cache mounts
# ============================================================================
FROM cuda-base:devel-${CUDA_VERSION} AS builder

# Install build dependencies for flash-attention and CUDA extensions with cache mount
RUN --mount=type=cache,target=/root/.cache/pip \
    pip3 install \
    misaki[en] \
    wheel

# Install xformers (may need compilation) with cache mount
RUN --mount=type=cache,target=/root/.cache/pip \
    CUDA_MAJOR=$(echo ${CUDA_VERSION} | tr -d . | cut -c1-3); \
    pip3 install \
    xformers==0.0.28.post3 \
    --index-url https://download.pytorch.org/whl/cu${CUDA_MAJOR} || \
    pip3 install xformers==0.0.28.post3

# Install flash-attention (requires compilation) with cache mount
RUN --mount=type=cache,target=/root/.cache/pip \
    pip3 install flash_attn==2.7.4.post1

# Install other dependencies with cache mount
RUN --mount=type=cache,target=/root/.cache/pip \
    pip3 install librosa

# ============================================================================
# RUNTIME STAGE - Minimal runtime image with cache optimization
# ============================================================================
FROM cuda-base:runtime-${CUDA_VERSION}

LABEL maintainer="Local AI Packaged"
LABEL description="InfiniteTalk service - flexible CUDA testing with BuildKit optimization"
LABEL service.type="video-generation"

# Set cache environment variables for persistent model storage
ENV HF_HOME=/data/.huggingface
ENV TRANSFORMERS_CACHE=/data/.huggingface/transformers
ENV TORCH_HOME=/data/.torch

# Copy compiled packages from builder
COPY --from=builder /usr/local/lib/python3.10/dist-packages /usr/local/lib/python3.10/dist-packages

WORKDIR /app

# Copy requirements file
COPY requirements.txt /app/

# Install remaining dependencies (skip already installed) with cache mount
RUN --mount=type=cache,target=/root/.cache/pip \
    pip3 install -r requirements.txt || true

# Create directories including cache directories
RUN mkdir -p /app/weights /app/shared /data/.huggingface /data/.torch

EXPOSE 8418

ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility

HEALTHCHECK --interval=60s --timeout=30s --start-period=120s --retries=3 \
    CMD curl -f http://localhost:8418/ || exit 1

CMD ["python3", "app.py", \
     "--ckpt_dir", "/app/weights/Wan2.1-I2V-14B-480P", \
     "--wav2vec_dir", "/app/weights/chinese-wav2vec2-base", \
     "--infinitetalk_dir", "/app/weights/InfiniteTalk/single/infinitetalk.safetensors", \
     "--num_persistent_param_in_dit", "0", \
     "--motion_frame", "9", \
     "--t5_cpu"]
