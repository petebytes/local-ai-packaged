#!/bin/bash
# Setup Host-Level Cache Directories for Cross-Project Sharing
# This script creates shared cache directories on the host that can be used across multiple projects
#
# Usage: ./scripts/setup-host-cache.sh [cache-dir]
#        Default cache-dir: /opt/ai-cache

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Host-Level AI Cache Setup ===${NC}"
echo ""

# Parse arguments
CACHE_DIR="${1:-/opt/ai-cache}"

echo -e "${BLUE}Cache directory: ${CACHE_DIR}${NC}"
echo ""

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    SUDO=""
    echo -e "${YELLOW}Running as root${NC}"
else
    SUDO="sudo"
    echo -e "${YELLOW}This script requires sudo access to create directories in /opt${NC}"
fi
echo ""

# Create cache directories
echo -e "${BLUE}Step 1: Creating cache directories${NC}"
$SUDO mkdir -p "${CACHE_DIR}/huggingface"
$SUDO mkdir -p "${CACHE_DIR}/torch"
$SUDO mkdir -p "${CACHE_DIR}/pip"
$SUDO mkdir -p "${CACHE_DIR}/transformers"
echo -e "${GREEN}✓ Directories created${NC}"
echo ""

# Set ownership
echo -e "${BLUE}Step 2: Setting ownership to current user${NC}"
$SUDO chown -R $USER:$USER "${CACHE_DIR}"
echo -e "${GREEN}✓ Ownership set to $USER:$USER${NC}"
echo ""

# Set permissions
echo -e "${BLUE}Step 3: Setting permissions${NC}"
$SUDO chmod -R 755 "${CACHE_DIR}"
echo -e "${GREEN}✓ Permissions set to 755${NC}"
echo ""

# Display created structure
echo -e "${BLUE}Created directory structure:${NC}"
ls -lah "${CACHE_DIR}/"
echo ""

# Calculate current usage
CACHE_SIZE=$(du -sh "${CACHE_DIR}" 2>/dev/null | cut -f1 || echo "0B")
echo -e "${BLUE}Current cache size: ${CACHE_SIZE}${NC}"
echo ""

# Generate docker-compose override
echo -e "${BLUE}Step 4: Generating docker-compose.host-cache.yml${NC}"
cat > /tmp/docker-compose.host-cache.yml << EOF
# Docker Compose Override for Host-Level Cache
# Use this to share cache across all projects on the same machine
#
# Usage:
#   docker compose -f docker-compose.yml -f docker-compose.host-cache.yml up -d
#
# Benefits:
#   - Shared HuggingFace models across all projects
#   - Shared PyTorch model zoo across all projects
#   - One download, multiple projects benefit
#   - Survives docker volume prune

services:
  whisperx:
    volumes:
      - ${CACHE_DIR}/huggingface:/data/.huggingface
      - ${CACHE_DIR}/torch:/data/.torch

  comfyui:
    volumes:
      - ${CACHE_DIR}/huggingface:/data/.huggingface
      - ${CACHE_DIR}/torch:/data/.torch

  crawl4ai:
    volumes:
      - ${CACHE_DIR}/huggingface:/data/.huggingface
      - ${CACHE_DIR}/torch:/data/.torch

  # Uncomment if using infinitetalk
  # infinitetalk:
  #   volumes:
  #     - ${CACHE_DIR}/huggingface:/data/.huggingface
  #     - ${CACHE_DIR}/torch:/data/.torch
EOF

mv /tmp/docker-compose.host-cache.yml ./docker-compose.host-cache.yml
echo -e "${GREEN}✓ Created docker-compose.host-cache.yml${NC}"
echo ""

# Summary
echo -e "${BLUE}=== Setup Complete ===${NC}"
echo ""
echo -e "${GREEN}Host-level cache directories created at: ${CACHE_DIR}${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo ""
echo -e "1. To use host-level cache (recommended for multiple projects):"
echo -e "   ${BLUE}docker compose -f docker-compose.yml -f docker-compose.host-cache.yml up -d${NC}"
echo ""
echo -e "2. To use Docker volumes (current default):"
echo -e "   ${BLUE}docker compose up -d${NC}"
echo ""
echo -e "3. To pre-download common models:"
echo -e "   ${BLUE}python3 cuda-optimization/scripts/pre-download-models.py${NC}"
echo ""
echo -e "${YELLOW}Benefits of host-level cache:${NC}"
echo "  - Shared across ALL projects on this machine"
echo "  - Download large models once, use everywhere"
echo "  - Survives docker system prune"
echo "  - Easy to backup/restore"
echo ""
echo -e "${YELLOW}Monitoring cache usage:${NC}"
echo "  watch -n 60 du -sh ${CACHE_DIR}/*"
echo ""
