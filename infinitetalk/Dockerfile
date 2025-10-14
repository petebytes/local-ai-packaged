FROM nvidia/cuda:12.1.0-cudnn8-devel-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1

# Install system dependencies
RUN apt-get update && apt-get install -y \
    python3.10 \
    python3-pip \
    git \
    ffmpeg \
    libsndfile1 \
    ninja-build \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Set up working directory
WORKDIR /app

# Copy requirements first for better caching
COPY requirements.txt /app/

# Install PyTorch and xformers
RUN pip3 install --no-cache-dir \
    torch==2.4.1 \
    torchvision==0.19.1 \
    torchaudio==2.4.1 \
    --index-url https://download.pytorch.org/whl/cu121

RUN pip3 install --no-cache-dir \
    xformers==0.0.28 \
    --index-url https://download.pytorch.org/whl/cu121

# Install flash-attention dependencies
RUN pip3 install --no-cache-dir \
    misaki[en] \
    ninja \
    psutil \
    packaging \
    wheel

# Install flash-attention (this takes a while)
RUN pip3 install --no-cache-dir flash_attn==2.7.4.post1

# Install librosa from conda-forge equivalent
RUN pip3 install --no-cache-dir librosa

# Install other dependencies
RUN pip3 install --no-cache-dir -r requirements.txt

# Expose Gradio port
EXPOSE 8418

# Set environment variables for GPU
ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility

# Start the Gradio app
CMD ["python3", "app.py", \
     "--ckpt_dir", "/app/weights/Wan2.1-I2V-14B-480P", \
     "--wav2vec_dir", "/app/weights/chinese-wav2vec2-base", \
     "--infinitetalk_dir", "/app/weights/InfiniteTalk/single/infinitetalk.safetensors", \
     "--num_persistent_param_in_dit", "0", \
     "--motion_frame", "9", \
     "--t5_cpu"]
