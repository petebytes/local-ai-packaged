#!/bin/bash
# Check BuildKit Compatibility
# Validates Docker version and BuildKit support before using cache mounts
#
# Usage: ./scripts/check-buildkit-compatibility.sh

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}=== BuildKit Compatibility Check ===${NC}"
echo ""

# Check Docker is installed
if ! command -v docker &> /dev/null; then
    echo -e "${RED}✗ Docker not found${NC}"
    echo "Please install Docker first"
    exit 1
fi
echo -e "${GREEN}✓ Docker found${NC}"

# Get Docker version
DOCKER_VERSION=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "unknown")
echo "Docker version: $DOCKER_VERSION"

# Parse version numbers
DOCKER_MAJOR=$(echo "$DOCKER_VERSION" | cut -d. -f1)
DOCKER_MINOR=$(echo "$DOCKER_VERSION" | cut -d. -f2)

# Check minimum version (18.09 for basic BuildKit, 20.10 for full support)
BUILDKIT_MINIMUM=false
BUILDKIT_FULL=false

if [ "$DOCKER_MAJOR" -gt 20 ]; then
    BUILDKIT_MINIMUM=true
    BUILDKIT_FULL=true
elif [ "$DOCKER_MAJOR" -eq 20 ] && [ "$DOCKER_MINOR" -ge 10 ]; then
    BUILDKIT_MINIMUM=true
    BUILDKIT_FULL=true
elif [ "$DOCKER_MAJOR" -eq 18 ] && [ "$DOCKER_MINOR" -ge 9 ]; then
    BUILDKIT_MINIMUM=true
    BUILDKIT_FULL=false
fi

echo ""
echo -e "${BLUE}BuildKit Support:${NC}"

if [ "$BUILDKIT_MINIMUM" = true ]; then
    echo -e "${GREEN}✓ BuildKit available (Docker $DOCKER_VERSION)${NC}"
else
    echo -e "${RED}✗ BuildKit NOT supported${NC}"
    echo "  Docker version $DOCKER_VERSION is too old"
    echo "  Minimum required: Docker 18.09"
    echo "  Recommended: Docker 20.10+"
    echo ""
    echo "Please upgrade Docker to use BuildKit cache mounts"
    exit 1
fi

if [ "$BUILDKIT_FULL" = true ]; then
    echo -e "${GREEN}✓ Full BuildKit support (Docker 20.10+)${NC}"
else
    echo -e "${YELLOW}⚠ Basic BuildKit support only${NC}"
    echo "  Some advanced features may not work"
    echo "  Recommend upgrading to Docker 20.10+"
fi

# Check if BuildKit is enabled
echo ""
echo -e "${BLUE}Checking BuildKit status...${NC}"

# Check daemon.json
if [ -f /etc/docker/daemon.json ]; then
    BUILDKIT_ENABLED=$(cat /etc/docker/daemon.json | jq -r '.features.buildkit // false' 2>/dev/null || echo "false")
    if [ "$BUILDKIT_ENABLED" = "true" ]; then
        echo -e "${GREEN}✓ BuildKit enabled in daemon.json${NC}"
    else
        echo -e "${YELLOW}⚠ BuildKit not enabled in daemon.json${NC}"
        echo "  BuildKit can still be used with DOCKER_BUILDKIT=1 environment variable"
    fi
else
    echo -e "${YELLOW}⚠ No daemon.json found${NC}"
    echo "  BuildKit can be used with DOCKER_BUILDKIT=1 environment variable"
fi

# Check buildx (BuildKit CLI)
echo ""
echo -e "${BLUE}Checking buildx (BuildKit CLI)...${NC}"
if docker buildx version &> /dev/null; then
    BUILDX_VERSION=$(docker buildx version)
    echo -e "${GREEN}✓ buildx available${NC}"
    echo "  $BUILDX_VERSION"
else
    echo -e "${YELLOW}⚠ buildx not available${NC}"
    echo "  Not required, but recommended for advanced features"
fi

# Test BuildKit with a simple build
echo ""
echo -e "${BLUE}Testing BuildKit cache mount syntax...${NC}"

# Create a test Dockerfile
TEST_DIR=$(mktemp -d)
cat > "$TEST_DIR/Dockerfile" << 'EOF'
# syntax=docker/dockerfile:1.12
FROM alpine:latest
RUN --mount=type=cache,target=/tmp/cache \
    echo "BuildKit cache mount works!" > /tmp/cache/test.txt
EOF

if DOCKER_BUILDKIT=1 docker build -q "$TEST_DIR" &> /dev/null; then
    echo -e "${GREEN}✓ BuildKit cache mounts working!${NC}"
    BUILDKIT_WORKS=true
else
    echo -e "${RED}✗ BuildKit cache mounts failed${NC}"
    echo "  This could be due to:"
    echo "  - Docker version too old"
    echo "  - BuildKit not properly installed"
    echo "  - Syntax not supported"
    BUILDKIT_WORKS=false
fi

# Cleanup
rm -rf "$TEST_DIR"

# Summary
echo ""
echo -e "${BLUE}=== Summary ===${NC}"
echo ""

if [ "$BUILDKIT_WORKS" = true ] && [ "$BUILDKIT_FULL" = true ]; then
    echo -e "${GREEN}✓ READY FOR BUILDKIT OPTIMIZATIONS${NC}"
    echo ""
    echo "Your Docker version supports all BuildKit features."
    echo "Safe to use cache mount syntax in Dockerfiles."
    echo ""
    echo "To build with BuildKit:"
    echo "  DOCKER_BUILDKIT=1 docker compose build"
    echo ""
    echo "Or enable globally in daemon.json:"
    echo '  { "features": { "buildkit": true } }'
    exit 0

elif [ "$BUILDKIT_WORKS" = true ]; then
    echo -e "${YELLOW}⚠ BUILDKIT WORKS BUT LIMITED${NC}"
    echo ""
    echo "BuildKit is available but some features may not work."
    echo "Recommend upgrading to Docker 20.10+"
    echo ""
    echo "Can use BuildKit with:"
    echo "  DOCKER_BUILDKIT=1 docker compose build"
    exit 0

else
    echo -e "${RED}✗ BUILDKIT NOT READY${NC}"
    echo ""
    echo "BuildKit cache mounts are NOT working."
    echo ""
    echo "Options:"
    echo "1. Upgrade Docker to 20.10+ (recommended)"
    echo "2. Use standard Dockerfiles without cache mounts"
    echo "3. Investigate why BuildKit test failed"
    echo ""
    echo "Docker version info:"
    docker version
    exit 1
fi
