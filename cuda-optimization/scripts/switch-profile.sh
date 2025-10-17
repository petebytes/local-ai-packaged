#!/bin/bash
# CUDA Configuration Profile Switcher
# Quickly switch between different CUDA/performance configurations
#
# Usage:
#   ./scripts/switch-profile.sh list
#   ./scripts/switch-profile.sh apply whisperx-speed-optimized
#   ./scripts/switch-profile.sh show whisperx-speed-optimized
#   ./scripts/switch-profile.sh current whisperx

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
PROFILES_DIR="$PROJECT_ROOT/cuda-optimization/profiles"

# Parse command
COMMAND=$1
shift || true

list_profiles() {
    echo -e "${BLUE}=== Available CUDA Configuration Profiles ===${NC}"
    echo ""

    for profile in "$PROFILES_DIR"/*.yml; do
        if [ -f "$profile" ]; then
            filename=$(basename "$profile")
            name=$(grep "^name:" "$profile" | sed 's/name: *"\(.*\)"/\1/')
            service=$(grep "^service:" "$profile" | awk '{print $2}' | tr -d '"')
            cuda_version=$(grep "CUDA_VERSION:" "$profile" | sed 's/.*CUDA_VERSION: *"\(.*\)".*/\1/')

            echo -e "${CYAN}${filename%.yml}${NC}"
            echo -e "  Name:         $name"
            echo -e "  Service:      $service"
            echo -e "  CUDA Version: $cuda_version"
            echo ""
        fi
    done
}

show_profile() {
    local profile_name=$1

    if [ -z "$profile_name" ]; then
        echo -e "${RED}Error: Profile name required${NC}"
        echo "Usage: $0 show <profile-name>"
        exit 1
    fi

    local profile_file="$PROFILES_DIR/${profile_name}.yml"

    if [ ! -f "$profile_file" ]; then
        echo -e "${RED}Error: Profile not found: $profile_name${NC}"
        echo "Available profiles:"
        list_profiles
        exit 1
    fi

    echo -e "${BLUE}=== Profile: ${profile_name} ===${NC}"
    echo ""
    cat "$profile_file"
}

get_current_config() {
    local service=$1

    if [ -z "$service" ]; then
        echo -e "${RED}Error: Service name required${NC}"
        echo "Usage: $0 current <service>"
        exit 1
    fi

    local dockerfile="$PROJECT_ROOT/${service}/Dockerfile"

    if [ ! -f "$dockerfile" ]; then
        echo -e "${RED}Error: Dockerfile not found: $dockerfile${NC}"
        exit 1
    fi

    echo -e "${BLUE}=== Current Configuration: ${service} ===${NC}"
    echo ""

    # Extract CUDA version
    cuda_version=$(grep "^ARG CUDA_VERSION" "$dockerfile" | sed 's/ARG CUDA_VERSION=\(.*\)/\1/')
    echo -e "CUDA Version: ${CYAN}${cuda_version}${NC}"

    # Extract FROM statement
    base_image=$(grep "^FROM cuda-base" "$dockerfile" | head -1)
    echo -e "Base Image:   ${base_image}"

    echo ""
}

apply_profile() {
    local profile_name=$1

    if [ -z "$profile_name" ]; then
        echo -e "${RED}Error: Profile name required${NC}"
        echo "Usage: $0 apply <profile-name>"
        exit 1
    fi

    local profile_file="$PROFILES_DIR/${profile_name}.yml"

    if [ ! -f "$profile_file" ]; then
        echo -e "${RED}Error: Profile not found: $profile_name${NC}"
        echo "Available profiles:"
        list_profiles
        exit 1
    fi

    # Parse profile
    local service=$(grep "^service:" "$profile_file" | awk '{print $2}' | tr -d '"')
    local cuda_version=$(grep "CUDA_VERSION:" "$profile_file" | sed 's/.*CUDA_VERSION: *"\(.*\)".*/\1/')

    echo -e "${BLUE}=== Applying Profile: ${profile_name} ===${NC}"
    echo ""
    echo -e "Service:      ${CYAN}${service}${NC}"
    echo -e "CUDA Version: ${CYAN}${cuda_version}${NC}"
    echo ""

    # Update Dockerfile
    local dockerfile="$PROJECT_ROOT/${service}/Dockerfile"

    if [ ! -f "$dockerfile" ]; then
        echo -e "${RED}Error: Dockerfile not found: $dockerfile${NC}"
        exit 1
    fi

    # Backup current Dockerfile
    cp "$dockerfile" "${dockerfile}.backup"
    echo -e "${YELLOW}Backed up Dockerfile to ${dockerfile}.backup${NC}"

    # Update CUDA version in Dockerfile
    sed -i "s/^ARG CUDA_VERSION=.*/ARG CUDA_VERSION=${cuda_version}/" "$dockerfile"

    echo -e "${GREEN}✓ Updated Dockerfile with CUDA ${cuda_version}${NC}"
    echo ""

    # Show what changed
    echo -e "${YELLOW}Changes made:${NC}"
    diff "${dockerfile}.backup" "$dockerfile" || true
    echo ""

    # Extract environment variables from profile
    echo -e "${YELLOW}Environment variables from profile:${NC}"
    sed -n '/^environment:/,/^[^ ]/p' "$profile_file" | grep -v "^environment:" | grep -v "^[^ ]" | grep ":" || echo "  (none specified in profile)"
    echo ""

    # Prompt to rebuild
    echo -e "${CYAN}To apply changes, rebuild the service:${NC}"
    echo -e "  ${BLUE}docker compose build ${service}${NC}"
    echo ""
    echo -e "${CYAN}To update environment variables, edit docker-compose.yml${NC}"
    echo ""

    # Ask if user wants to rebuild now
    read -p "Rebuild service now? (y/N) " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Building ${service} with CUDA ${cuda_version}...${NC}"
        cd "$PROJECT_ROOT"
        docker compose build "$service"
        echo -e "${GREEN}✓ Build complete${NC}"
    else
        echo -e "${YELLOW}Skipped rebuild. Run manually when ready.${NC}"
    fi
}

create_profile_from_current() {
    local service=$1
    local profile_name=$2

    if [ -z "$service" ] || [ -z "$profile_name" ]; then
        echo -e "${RED}Error: Service and profile name required${NC}"
        echo "Usage: $0 create <service> <profile-name>"
        exit 1
    fi

    local dockerfile="$PROJECT_ROOT/${service}/Dockerfile"
    local profile_file="$PROFILES_DIR/${profile_name}.yml"

    if [ ! -f "$dockerfile" ]; then
        echo -e "${RED}Error: Dockerfile not found: $dockerfile${NC}"
        exit 1
    fi

    if [ -f "$profile_file" ]; then
        echo -e "${RED}Error: Profile already exists: $profile_name${NC}"
        exit 1
    fi

    # Extract CUDA version
    cuda_version=$(grep "^ARG CUDA_VERSION" "$dockerfile" | sed 's/ARG CUDA_VERSION=\(.*\)/\1/')

    echo -e "${BLUE}=== Creating Profile from Current Configuration ===${NC}"
    echo ""
    echo -e "Service:      ${CYAN}${service}${NC}"
    echo -e "CUDA Version: ${CYAN}${cuda_version}${NC}"
    echo -e "Profile:      ${CYAN}${profile_name}${NC}"
    echo ""

    # Create profile file
    cat > "$profile_file" <<EOF
# ${service} Custom Profile
# Created from current configuration on $(date)

name: "Custom Profile: ${profile_name}"
service: "${service}"

docker:
  build_args:
    CUDA_VERSION: "${cuda_version}"

environment:
  # Add your environment variables here
  # Example:
  # COMPUTE_TYPE: "float16"
  # BATCH_SIZE: 32

notes: |
  Custom profile created from current ${service} configuration.
  CUDA Version: ${cuda_version}

  Edit this file to customize environment variables and settings.

recommended_for:
  - Custom use case
EOF

    echo -e "${GREEN}✓ Profile created: $profile_file${NC}"
    echo ""
    echo -e "Edit the profile:"
    echo -e "  ${BLUE}nano $profile_file${NC}"
    echo ""
}

# Main command dispatch
case "$COMMAND" in
    list)
        list_profiles
        ;;
    show)
        show_profile "$@"
        ;;
    current)
        get_current_config "$@"
        ;;
    apply)
        apply_profile "$@"
        ;;
    create)
        create_profile_from_current "$@"
        ;;
    *)
        echo -e "${BLUE}CUDA Configuration Profile Switcher${NC}"
        echo ""
        echo "Usage: $0 <command> [args]"
        echo ""
        echo "Commands:"
        echo "  list                        List all available profiles"
        echo "  show <profile>              Show profile details"
        echo "  current <service>           Show current configuration"
        echo "  apply <profile>             Apply profile to service"
        echo "  create <service> <name>     Create profile from current config"
        echo ""
        echo "Examples:"
        echo "  $0 list"
        echo "  $0 show whisperx-speed-optimized"
        echo "  $0 current whisperx"
        echo "  $0 apply whisperx-speed-optimized"
        echo "  $0 create whisperx my-custom-profile"
        echo ""
        exit 1
        ;;
esac
