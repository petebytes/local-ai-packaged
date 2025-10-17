#!/bin/bash
# Manual Setup for WSL (Windows Subsystem for Linux)
# WSL doesn't use systemd, so we need different commands
#
# Usage: ./cuda-optimization/scripts/manual-setup-wsl.sh

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}=== WSL Docker Setup ===${NC}"
echo ""
echo -e "${YELLOW}Note: WSL detected - using WSL-specific commands${NC}"
echo ""

# Check if /etc/docker exists
if [ ! -d /etc/docker ]; then
    echo "Creating /etc/docker directory..."
    sudo mkdir -p /etc/docker
    echo -e "${GREEN}✓ Directory created${NC}"
fi

# Create daemon.json
echo ""
echo "Creating /etc/docker/daemon.json..."
sudo tee /etc/docker/daemon.json > /dev/null << 'EOF'
{
  "registry-mirrors": ["http://localhost:5000"],
  "features": {
    "buildkit": true
  },
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF

echo -e "${GREEN}✓ daemon.json created${NC}"
echo ""

# Show the config
echo "Configuration:"
cat /etc/docker/daemon.json | jq '.'
echo ""

# Restart Docker (WSL method)
echo -e "${YELLOW}On WSL, you need to restart Docker Desktop from Windows${NC}"
echo ""
echo "Please:"
echo "  1. Right-click Docker Desktop icon in Windows system tray"
echo "  2. Click 'Restart'"
echo "  3. Wait for Docker to fully restart (30-60 seconds)"
echo ""
read -p "Press Enter after Docker Desktop has restarted..."

echo ""
echo "Starting registry cache..."
docker compose -p localai up -d registry-cache
echo -e "${GREEN}✓ Registry cache started${NC}"

echo ""
echo -e "${BLUE}Testing registry cache...${NC}"
echo "First pull (will download)..."
docker pull alpine:latest > /dev/null 2>&1
echo "Second pull (should be instant from cache)..."
time docker pull alpine:latest
echo ""

echo -e "${GREEN}✓ Setup complete!${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Registry cache is now configured"
echo "  2. BuildKit is enabled"
echo "  3. Ready to rebuild images with optimizations"
echo ""
echo "To rebuild services with optimizations:"
echo -e "  ${BLUE}DOCKER_BUILDKIT=1 docker compose build${NC}"
echo -e "  ${BLUE}docker compose up -d${NC}"
echo ""
