#!/bin/bash
# Configure Docker Registry Cache - SAFE VERSION
# This version checks for existing config and merges instead of overwriting
#
# Usage: ./scripts/configure-registry-cache-safe.sh

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Docker Registry Cache Configuration (SAFE) ===${NC}"
echo ""

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    SUDO=""
else
    SUDO="sudo"
    echo -e "${YELLOW}Note: This script requires sudo access to modify Docker configuration${NC}"
    echo ""
fi

# Check if jq is installed (needed for JSON merging)
if ! command -v jq &> /dev/null; then
    echo -e "${YELLOW}Installing jq for JSON merging...${NC}"
    $SUDO apt-get update -qq
    $SUDO apt-get install -y jq
    echo -e "${GREEN}✓ jq installed${NC}"
    echo ""
fi

# Step 1: Start registry cache if not running
echo -e "${BLUE}Step 1: Starting registry cache container${NC}"
if docker ps | grep -q "registry-cache"; then
    echo -e "${GREEN}✓ Registry cache is already running${NC}"
else
    echo "Starting registry-cache..."
    docker compose -p localai up -d registry-cache
    sleep 3
    if docker ps | grep -q "registry-cache"; then
        echo -e "${GREEN}✓ Registry cache started${NC}"
    else
        echo -e "${RED}✗ Failed to start registry cache${NC}"
        exit 1
    fi
fi
echo ""

# Step 2: Check and merge Docker daemon config
echo -e "${BLUE}Step 2: Configuring Docker daemon${NC}"
DAEMON_JSON="/etc/docker/daemon.json"
BACKUP_JSON="/etc/docker/daemon.json.backup.$(date +%Y%m%d_%H%M%S)"

# Our desired config
DESIRED_CONFIG='{
  "registry-mirrors": ["http://localhost:5000"],
  "features": {
    "buildkit": true
  },
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}'

if [ -f "$DAEMON_JSON" ]; then
    echo -e "${YELLOW}⚠ Existing daemon.json found${NC}"
    echo ""
    echo "Current configuration:"
    cat "$DAEMON_JSON" | jq '.' 2>/dev/null || cat "$DAEMON_JSON"
    echo ""

    # Backup existing config
    echo "Creating backup at: $BACKUP_JSON"
    $SUDO cp "$DAEMON_JSON" "$BACKUP_JSON"
    echo -e "${GREEN}✓ Backup created${NC}"
    echo ""

    # Check if registry-mirrors already configured
    EXISTING_MIRRORS=$(cat "$DAEMON_JSON" | jq -r '."registry-mirrors" // empty' 2>/dev/null || echo "")

    if [ -n "$EXISTING_MIRRORS" ] && [ "$EXISTING_MIRRORS" != "null" ]; then
        echo -e "${YELLOW}⚠ Registry mirrors already configured:${NC}"
        echo "$EXISTING_MIRRORS" | jq '.'
        echo ""
        read -p "Do you want to replace with localhost:5000? (y/N) " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Keeping existing registry mirrors"
            echo "Note: You may need to manually add localhost:5000 to the mirrors array"
            exit 0
        fi
    fi

    # Merge configs using jq
    echo "Merging configurations..."
    MERGED_CONFIG=$(echo "$DESIRED_CONFIG" | jq -s '.[0] * .[1]' "$DAEMON_JSON" - 2>/dev/null || echo "$DESIRED_CONFIG")

    echo "New configuration will be:"
    echo "$MERGED_CONFIG" | jq '.'
    echo ""

    read -p "Apply this configuration? (y/N) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Configuration not applied"
        exit 0
    fi

    # Write merged config
    echo "$MERGED_CONFIG" | $SUDO tee "$DAEMON_JSON" > /dev/null
    echo -e "${GREEN}✓ Configuration merged and applied${NC}"

else
    # No existing config, create new
    echo "No existing daemon.json found"
    echo "Creating new configuration..."
    echo "$DESIRED_CONFIG" | $SUDO tee "$DAEMON_JSON" > /dev/null
    echo -e "${GREEN}✓ Configuration created${NC}"
fi
echo ""

# Step 3: Restart Docker
echo -e "${BLUE}Step 3: Restart Docker${NC}"
echo -e "${YELLOW}This will restart all Docker containers${NC}"
read -p "Do you want to restart Docker now? (y/N) " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Restarting Docker..."
    $SUDO systemctl restart docker

    # Wait for Docker to be ready
    echo "Waiting for Docker to be ready..."
    sleep 5

    # Restart registry cache
    echo "Restarting registry cache..."
    docker compose -p localai up -d registry-cache

    echo -e "${GREEN}✓ Docker restarted${NC}"

    # Verify configuration
    echo ""
    echo -e "${BLUE}Verifying configuration...${NC}"
    if docker system info 2>/dev/null | grep -q "Registry Mirrors"; then
        echo -e "${GREEN}✓ Registry mirror is active${NC}"
        docker system info | grep -A5 "Registry Mirrors"
    else
        echo -e "${YELLOW}⚠ Registry mirror not showing in docker info${NC}"
        echo "This might be normal. Testing with actual pull..."
    fi

    # Test registry cache
    echo ""
    echo -e "${BLUE}Testing registry cache...${NC}"
    echo "Pulling alpine:latest (first time)..."
    time docker pull alpine:latest 2>&1 | tail -3
    echo ""
    echo "Pulling alpine:latest again (should be instant)..."
    time docker pull alpine:latest 2>&1 | tail -3
    echo ""
    echo -e "${GREEN}✓ If second pull was instant, cache is working!${NC}"

else
    echo -e "${YELLOW}Skipping Docker restart${NC}"
    echo ""
    echo "To apply changes later, run:"
    echo "  $SUDO systemctl restart docker"
    echo "  docker compose -p localai up -d registry-cache"
fi

echo ""
echo -e "${BLUE}=== Configuration Complete ===${NC}"
echo ""
echo -e "${GREEN}Registry cache is configured!${NC}"
echo ""
echo -e "${YELLOW}Backup location:${NC} $BACKUP_JSON"
echo ""
echo -e "${YELLOW}To rollback:${NC}"
if [ -f "$BACKUP_JSON" ]; then
    echo "  $SUDO cp $BACKUP_JSON /etc/docker/daemon.json"
    echo "  $SUDO systemctl restart docker"
fi
echo ""
echo "View cache contents:"
echo "  curl http://localhost:5000/v2/_catalog"
echo ""
