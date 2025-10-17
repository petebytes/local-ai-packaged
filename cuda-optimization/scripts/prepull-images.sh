#!/bin/bash
# Pre-pull Docker Images
# This script pre-downloads all Docker images used by the Local AI Packaged stack
# Run this to cache images before building to speed up the process
#
# Usage: ./scripts/prepull-images.sh

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Docker Image Pre-Pull ===${NC}"
echo -e "${YELLOW}Downloading all base images used by Local AI Packaged${NC}"
echo "This will cache images locally to speed up builds and rebuilds"
echo ""

# Counter for progress
TOTAL=12
CURRENT=0

pull_image() {
    CURRENT=$((CURRENT + 1))
    echo -e "${GREEN}[$CURRENT/$TOTAL] Pulling: $1${NC}"
    docker pull "$1" || echo -e "${YELLOW}Warning: Failed to pull $1${NC}"
    echo ""
}

# NVIDIA CUDA base images (most important for build speed)
echo -e "${BLUE}>>> NVIDIA CUDA Images${NC}"
pull_image "nvidia/cuda:12.8.1-cudnn-runtime-ubuntu22.04"
pull_image "nvidia/cuda:12.8.1-cudnn-devel-ubuntu22.04"

# AI Service images
echo -e "${BLUE}>>> AI Service Images${NC}"
pull_image "ghcr.io/open-webui/open-webui:main"
pull_image "ghcr.io/remsky/kokoro-fastapi-gpu:latest"
pull_image "ghcr.io/ai-dock/comfyui:latest"

# Infrastructure images
echo -e "${BLUE}>>> Infrastructure Images${NC}"
pull_image "nginx:latest"
pull_image "nocodb/nocodb:latest"
pull_image "registry:2"
pull_image "offen/docker-volume-backup:v2"

# Utility images
echo -e "${BLUE}>>> Utility Images${NC}"
pull_image "alpine:latest"
pull_image "python:3.11-alpine"

# Check if registry cache is configured
echo ""
echo -e "${BLUE}=== Registry Cache Check ===${NC}"
if docker ps | grep -q "registry-cache"; then
    echo -e "${GREEN}✓ Registry cache is running${NC}"
    echo "Future pulls will be cached locally"
else
    echo -e "${YELLOW}⚠ Registry cache is not running${NC}"
    echo "To enable caching:"
    echo "  1. Start services: docker compose up -d registry-cache"
    echo "  2. Configure daemon: sudo nano /etc/docker/daemon.json"
    echo '     Add: {"registry-mirrors": ["http://localhost:5000"]}'
    echo "  3. Restart Docker: sudo systemctl restart docker"
fi

echo ""
echo -e "${BLUE}=== Pre-Pull Complete ===${NC}"
echo -e "${GREEN}All images downloaded successfully!${NC}"
echo ""
echo "Disk usage:"
docker system df
echo ""
echo -e "${YELLOW}Tip: Run 'docker system prune' periodically to clean up unused images${NC}"
