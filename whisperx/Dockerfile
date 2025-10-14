# WhisperX Docker Image - Built from Official Sources
# Base image: NVIDIA CUDA 13.0 runtime on Ubuntu 22.04
# Requires NVIDIA driver version 580.65.06 or higher
FROM nvidia/cuda:13.0.1-runtime-ubuntu22.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install wget and cuDNN for CUDA 13.0
RUN apt-get update && \
    apt-get install -y --no-install-recommends wget && \
    wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.0-1_all.deb && \
    dpkg -i cuda-keyring_1.0-1_all.deb && \
    apt-get update && \
    apt-get install -y cudnn9-cuda-13 && \
    rm -rf /var/lib/apt/lists/* cuda-keyring_1.0-1_all.deb

# Set library path for cuDNN
ENV LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH}

# Install system dependencies
# - python3, python3-pip: Python runtime and package manager
# - ffmpeg: Required for audio processing
# - git: Needed to clone WhisperX from GitHub
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    python3.10 \
    python3-pip \
    ffmpeg \
    git && \
    rm -rf /var/lib/apt/lists/*

# Upgrade pip to latest version
RUN pip3 install --no-cache-dir --upgrade pip

# Install PyTorch with CUDA 12.8 support from official PyTorch repository
# Version 2.7.1 is the latest stable release with CUDA 13.0 compatibility
RUN pip3 install --no-cache-dir \
    torch==2.7.1 \
    torchvision==0.22.1 \
    torchaudio==2.7.1 \
    --index-url https://download.pytorch.org/whl/cu128

# Install WhisperX directly from official GitHub repository
# Using pip install from git ensures we get the latest stable version
RUN pip3 install --no-cache-dir git+https://github.com/m-bain/whisperx.git

# Install FastAPI and uvicorn for API server
RUN pip3 install --no-cache-dir \
    fastapi==0.109.0 \
    uvicorn==0.27.0 \
    python-multipart==0.0.6 \
    pydantic==2.5.3

# Install additional dependencies for enhanced features
# - numpy: Array processing for audio
# - requests: HTTP client for health checks
RUN pip3 install --no-cache-dir \
    numpy>=1.24.0 \
    requests>=2.31.0

# Create working directory
WORKDIR /app

# Copy all Python modules
COPY api_server.py /app/api_server.py
COPY ffmpeg_processor.py /app/ffmpeg_processor.py
COPY video_segmenter.py /app/video_segmenter.py

# Create directories for file uploads, model cache, and shared processing
RUN mkdir -p /app/uploads /root/.cache /app/shared/temp /app/shared/input /app/shared/output

# Expose API port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD python3 -c "import requests; requests.get('http://localhost:8000/health')" || exit 1

# Run the API server
CMD ["python3", "-u", "api_server.py"]
