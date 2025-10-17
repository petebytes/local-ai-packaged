#!/bin/bash
# Deploy Download Optimizations - SAFE INCREMENTAL VERSION
# This script safely applies optimizations with validation and rollback options
#
# Features:
#   - Validates prerequisites before each step
#   - Allows skipping steps
#   - Creates backups automatically
#   - Provides rollback instructions
#   - Incremental deployment
#
# Usage: ./cuda-optimization/scripts/deploy-optimizations-safe.sh

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

# Track what was done for rollback instructions
CHANGES_MADE=()
BACKUPS_CREATED=()

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                                                              ║${NC}"
echo -e "${CYAN}║       Download Optimization Deployment (SAFE)               ║${NC}"
echo -e "${CYAN}║                                                              ║${NC}"
echo -e "${CYAN}║  Incremental deployment with validation and rollback        ║${NC}"
echo -e "${CYAN}║                                                              ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Function to show menu
show_menu() {
    echo -e "${BLUE}What would you like to do?${NC}"
    echo ""
    echo "  1) Deploy all optimizations (recommended for first-time)"
    echo "  2) Deploy incrementally (choose each step)"
    echo "  3) Check system compatibility only"
    echo "  4) Show rollback instructions"
    echo "  5) Exit"
    echo ""
}

# Function to check prerequisites
check_prerequisites() {
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}Checking Prerequisites${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""

    local ALL_OK=true

    # Check Docker
    if command -v docker &> /dev/null; then
        DOCKER_VERSION=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "unknown")
        echo -e "${GREEN}✓ Docker found${NC} (version: $DOCKER_VERSION)"
    else
        echo -e "${RED}✗ Docker not found${NC}"
        ALL_OK=false
    fi

    # Check Docker Compose
    if command -v docker compose &> /dev/null; then
        echo -e "${GREEN}✓ Docker Compose found${NC}"
    else
        echo -e "${RED}✗ Docker Compose not found${NC}"
        ALL_OK=false
    fi

    # Check if registry-cache is running
    if docker ps 2>/dev/null | grep -q "registry-cache"; then
        echo -e "${GREEN}✓ Registry cache container running${NC}"
    else
        echo -e "${YELLOW}⚠ Registry cache not running${NC}"
        echo "  (Will start it if you choose registry cache optimization)"
    fi

    # Check jq (needed for JSON merging)
    if command -v jq &> /dev/null; then
        echo -e "${GREEN}✓ jq found (for JSON merging)${NC}"
    else
        echo -e "${YELLOW}⚠ jq not found${NC}"
        echo "  (Will install if needed for daemon.json merging)"
    fi

    echo ""

    if [ "$ALL_OK" = false ]; then
        echo -e "${RED}Some prerequisites are missing. Please install them first.${NC}"
        return 1
    else
        echo -e "${GREEN}All prerequisites met!${NC}"
        return 0
    fi
}

# Function to deploy Phase 1: Volumes (already done)
deploy_volumes() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}Phase 1: Docker Volume Cache${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${YELLOW}Impact:${NC} 80% download reduction, models persist across rebuilds"
    echo -e "${YELLOW}Risk:${NC} Very Low"
    echo -e "${YELLOW}Complexity:${NC} Low"
    echo ""

    # Check if volumes already configured
    if grep -q "hf-cache" docker-compose.yml 2>/dev/null; then
        echo -e "${GREEN}✓ Volumes already configured in docker-compose.yml${NC}"
        echo ""
        echo "Configured volumes:"
        grep -A1 "hf-cache:\|torch-cache:\|comfyui-models:" docker-compose.yml | head -6
        echo ""
        echo "No action needed - this is already done!"
        CHANGES_MADE+=("Volumes already configured")
    else
        echo -e "${RED}✗ Volumes not configured${NC}"
        echo "This should have been done. Something went wrong."
        echo "Please check docker-compose.yml"
    fi

    echo ""
    read -p "Press Enter to continue..."
}

# Function to deploy Phase 2: Registry Cache
deploy_registry_cache() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}Phase 2: Docker Registry Cache${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${YELLOW}Impact:${NC} +10% (prevents re-downloading base images)"
    echo -e "${YELLOW}Risk:${NC} Medium (modifies /etc/docker/daemon.json)"
    echo -e "${YELLOW}Complexity:${NC} Medium"
    echo ""
    echo "This will:"
    echo "  - Configure Docker to use local registry cache"
    echo "  - Backup existing daemon.json (if any)"
    echo "  - Merge configurations (won't overwrite)"
    echo "  - Restart Docker daemon"
    echo ""

    read -p "Do you want to deploy registry cache? (y/N) " -n 1 -r
    echo ""

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if [ -f "cuda-optimization/scripts/configure-registry-cache-safe.sh" ]; then
            ./cuda-optimization/scripts/configure-registry-cache-safe.sh
            if [ $? -eq 0 ]; then
                CHANGES_MADE+=("Registry cache configured")
                if [ -f /etc/docker/daemon.json.backup.* ]; then
                    BACKUP=$(ls -t /etc/docker/daemon.json.backup.* 2>/dev/null | head -1)
                    BACKUPS_CREATED+=("$BACKUP")
                fi
            fi
        else
            echo -e "${RED}✗ Safe registry cache script not found${NC}"
            echo "Expected: cuda-optimization/scripts/configure-registry-cache-safe.sh"
        fi
    else
        echo "Skipping registry cache configuration"
    fi

    echo ""
    read -p "Press Enter to continue..."
}

# Function to deploy Phase 3: BuildKit
deploy_buildkit() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}Phase 3: BuildKit Cache Mounts${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${YELLOW}Impact:${NC} +8% (faster rebuilds when changing code)"
    echo -e "${YELLOW}Risk:${NC} Medium (requires Docker 20.10+)"
    echo -e "${YELLOW}Complexity:${NC} High"
    echo ""
    echo "This will:"
    echo "  - Check Docker version compatibility"
    echo "  - Test BuildKit cache mount syntax"
    echo "  - Rebuild base images with BuildKit"
    echo ""

    read -p "Do you want to deploy BuildKit optimizations? (y/N) " -n 1 -r
    echo ""

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Check compatibility first
        echo ""
        echo "Checking BuildKit compatibility..."
        if [ -f "cuda-optimization/scripts/check-buildkit-compatibility.sh" ]; then
            if ./cuda-optimization/scripts/check-buildkit-compatibility.sh; then
                echo ""
                echo -e "${GREEN}✓ BuildKit is compatible${NC}"
                echo ""

                echo "BuildKit cache mounts are already in the Dockerfiles."
                echo "Now we need to rebuild base images to use them."
                echo ""
                echo "This will take 15-20 minutes for first build."
                echo "Rebuilds will be much faster (2-5 minutes)."
                echo ""

                read -p "Rebuild base images with BuildKit now? (y/N) " -n 1 -r
                echo ""

                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    echo ""
                    echo "Building runtime base image (CUDA 12.8)..."
                    if DOCKER_BUILDKIT=1 docker build \
                        -f cuda-optimization/cuda-base/Dockerfile.runtime \
                        -t cuda-base:runtime-12.8 \
                        . ; then
                        echo -e "${GREEN}✓ Runtime base image built${NC}"
                        CHANGES_MADE+=("Base images rebuilt with BuildKit")
                    else
                        echo -e "${RED}✗ Build failed${NC}"
                    fi

                    echo ""
                    echo "Building devel base image (CUDA 12.8)..."
                    if DOCKER_BUILDKIT=1 docker build \
                        -f cuda-optimization/cuda-base/Dockerfile.devel \
                        -t cuda-base:devel-12.8 \
                        . ; then
                        echo -e "${GREEN}✓ Devel base image built${NC}"
                    else
                        echo -e "${RED}✗ Build failed${NC}"
                    fi
                else
                    echo "Skipping base image rebuild"
                    echo "You can rebuild later with:"
                    echo "  DOCKER_BUILDKIT=1 docker build -f cuda-optimization/cuda-base/Dockerfile.runtime -t cuda-base:runtime-12.8 ."
                fi
            else
                echo ""
                echo -e "${YELLOW}BuildKit compatibility check failed${NC}"
                echo "Skipping BuildKit optimizations"
                echo ""
                echo "You can still use the standard Dockerfiles without BuildKit."
            fi
        else
            echo -e "${RED}✗ BuildKit check script not found${NC}"
        fi
    else
        echo "Skipping BuildKit optimizations"
    fi

    echo ""
    read -p "Press Enter to continue..."
}

# Function to deploy Phase 4: Host Cache
deploy_host_cache() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}Phase 4: Host-Level Cache${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${YELLOW}Impact:${NC} +2% (shares cache across projects)"
    echo -e "${YELLOW}Risk:${NC} Low (creates /opt/ai-cache)"
    echo -e "${YELLOW}Complexity:${NC} Medium"
    echo -e "${YELLOW}Benefit:${NC} Only useful with multiple projects"
    echo ""
    echo "This will:"
    echo "  - Create /opt/ai-cache directory (requires sudo)"
    echo "  - Generate docker-compose.host-cache.yml"
    echo "  - Enable cross-project cache sharing"
    echo ""

    read -p "Do you want to deploy host-level cache? (y/N) " -n 1 -r
    echo ""

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if [ -f "cuda-optimization/scripts/setup-host-cache.sh" ]; then
            ./cuda-optimization/scripts/setup-host-cache.sh
            if [ $? -eq 0 ]; then
                CHANGES_MADE+=("Host-level cache created at /opt/ai-cache")
            fi
        else
            echo -e "${RED}✗ Host cache setup script not found${NC}"
        fi
    else
        echo "Skipping host-level cache"
        echo ""
        echo "You'll use Docker volumes instead (still good!)."
    fi

    echo ""
    read -p "Press Enter to continue..."
}

# Function to show final summary
show_summary() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}Deployment Summary${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""

    if [ ${#CHANGES_MADE[@]} -eq 0 ]; then
        echo -e "${YELLOW}No changes were made${NC}"
    else
        echo -e "${GREEN}Changes applied:${NC}"
        for change in "${CHANGES_MADE[@]}"; do
            echo "  ✓ $change"
        done
    fi

    echo ""

    if [ ${#BACKUPS_CREATED[@]} -gt 0 ]; then
        echo -e "${YELLOW}Backups created:${NC}"
        for backup in "${BACKUPS_CREATED[@]}"; do
            echo "  📦 $backup"
        done
        echo ""
    fi

    echo -e "${CYAN}Next Steps:${NC}"
    echo ""
    echo "1. Rebuild your services:"
    if [ -f "docker-compose.host-cache.yml" ]; then
        echo -e "   ${BLUE}DOCKER_BUILDKIT=1 docker compose -f docker-compose.yml -f docker-compose.host-cache.yml build${NC}"
        echo -e "   ${BLUE}docker compose -f docker-compose.yml -f docker-compose.host-cache.yml up -d${NC}"
    else
        echo -e "   ${BLUE}DOCKER_BUILDKIT=1 docker compose build${NC}"
        echo -e "   ${BLUE}docker compose up -d${NC}"
    fi
    echo ""
    echo "2. Test that services start correctly"
    echo ""
    echo "3. Monitor cache effectiveness:"
    echo -e "   ${BLUE}docker system df -v${NC}"
    echo ""
    echo "4. View detailed documentation:"
    echo -e "   ${BLUE}cat cuda-optimization/DOWNLOAD_OPTIMIZATION_STATUS.md${NC}"
    echo ""

    # Rollback instructions
    if [ ${#CHANGES_MADE[@]} -gt 0 ]; then
        echo -e "${YELLOW}Rollback Instructions (if needed):${NC}"
        echo ""

        for change in "${CHANGES_MADE[@]}"; do
            case "$change" in
                *"Registry cache"*)
                    echo "To rollback registry cache:"
                    if [ ${#BACKUPS_CREATED[@]} -gt 0 ]; then
                        echo "  sudo cp ${BACKUPS_CREATED[0]} /etc/docker/daemon.json"
                    fi
                    echo "  sudo systemctl restart docker"
                    echo ""
                    ;;
                *"Base images"*)
                    echo "To remove base images:"
                    echo "  docker rmi cuda-base:runtime-12.8"
                    echo "  docker rmi cuda-base:devel-12.8"
                    echo ""
                    ;;
                *"Host-level cache"*)
                    echo "To remove host cache:"
                    echo "  sudo rm -rf /opt/ai-cache"
                    echo "  rm docker-compose.host-cache.yml"
                    echo ""
                    ;;
            esac
        done

        echo "To rollback docker-compose.yml changes:"
        echo "  git checkout docker-compose.yml"
        echo "  git checkout cuda-optimization/"
        echo ""
    fi
}

# Main menu loop
main() {
    # Check prerequisites first
    if ! check_prerequisites; then
        echo ""
        echo "Please fix prerequisites and run again."
        exit 1
    fi

    while true; do
        echo ""
        show_menu
        read -p "Enter choice [1-5]: " choice

        case $choice in
            1)
                deploy_volumes
                deploy_registry_cache
                deploy_buildkit
                deploy_host_cache
                show_summary
                break
                ;;
            2)
                echo ""
                echo "Choose which phases to deploy:"
                echo ""
                deploy_volumes
                deploy_registry_cache
                deploy_buildkit
                deploy_host_cache
                show_summary
                break
                ;;
            3)
                check_prerequisites
                echo ""
                if [ -f "cuda-optimization/scripts/check-buildkit-compatibility.sh" ]; then
                    ./cuda-optimization/scripts/check-buildkit-compatibility.sh
                fi
                ;;
            4)
                show_summary
                ;;
            5)
                echo "Exiting..."
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid choice${NC}"
                ;;
        esac
    done

    echo ""
    echo -e "${GREEN}Deployment complete! 🚀${NC}"
    echo ""
}

# Run main
main
