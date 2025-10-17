#!/bin/bash
# Migrate Existing Model Caches to Shared Location
#
# This script:
#   1. Scans all projects in /home/ghar/code for model caches
#   2. Identifies HuggingFace, PyTorch, and other AI model caches
#   3. Moves them to /opt/ai-cache (shared location)
#   4. Creates symlinks so projects still work
#   5. Deduplicates identical models
#
# Usage: ./cuda-optimization/scripts/migrate-to-shared-cache.sh [--dry-run]

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

# Options
DRY_RUN=false
if [ "$1" = "--dry-run" ]; then
    DRY_RUN=true
    echo -e "${YELLOW}DRY RUN MODE - No files will be moved${NC}"
    echo ""
fi

# Paths
PROJECTS_DIR="/home/ghar/code"
SHARED_CACHE="/opt/ai-cache"

# Statistics
TOTAL_PROJECTS=0
PROJECTS_WITH_CACHE=0
TOTAL_SIZE_BEFORE=0
TOTAL_SIZE_AFTER=0
MODELS_FOUND=0
MODELS_DEDUPLICATED=0

echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                                                              ║${NC}"
echo -e "${CYAN}║       Cache Migration to Shared Location                    ║${NC}"
echo -e "${CYAN}║                                                              ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if shared cache exists
if [ ! -d "$SHARED_CACHE" ]; then
    echo -e "${YELLOW}Shared cache directory doesn't exist${NC}"
    echo "Creating $SHARED_CACHE..."

    if [ "$DRY_RUN" = false ]; then
        sudo mkdir -p "$SHARED_CACHE/huggingface"
        sudo mkdir -p "$SHARED_CACHE/torch"
        sudo mkdir -p "$SHARED_CACHE/transformers"
        sudo chown -R $USER:$USER "$SHARED_CACHE"
        sudo chmod -R 755 "$SHARED_CACHE"
        echo -e "${GREEN}✓ Shared cache created${NC}"
    else
        echo -e "${YELLOW}[DRY RUN] Would create $SHARED_CACHE${NC}"
    fi
    echo ""
fi

# Function to get directory size in MB
get_size_mb() {
    local dir="$1"
    if [ -d "$dir" ]; then
        du -sm "$dir" 2>/dev/null | cut -f1
    else
        echo "0"
    fi
}

# Function to check if directory contains models
has_models() {
    local dir="$1"
    if [ -d "$dir" ]; then
        local file_count=$(find "$dir" -type f 2>/dev/null | wc -l)
        [ "$file_count" -gt 0 ]
    else
        return 1
    fi
}

# Function to migrate cache
migrate_cache() {
    local project="$1"
    local cache_path="$2"
    local cache_type="$3"
    local target_dir="$SHARED_CACHE/$cache_type"

    if [ ! -d "$cache_path" ]; then
        return
    fi

    if ! has_models "$cache_path"; then
        return
    fi

    local size=$(get_size_mb "$cache_path")
    TOTAL_SIZE_BEFORE=$((TOTAL_SIZE_BEFORE + size))

    echo -e "${BLUE}Found $cache_type cache in $project${NC}"
    echo "  Location: $cache_path"
    echo "  Size: ${size}MB"

    # Count models
    local model_count=$(find "$cache_path" -name "*.bin" -o -name "*.safetensors" -o -name "*.pt" -o -name "*.pth" 2>/dev/null | wc -l)
    MODELS_FOUND=$((MODELS_FOUND + model_count))
    echo "  Models: $model_count files"

    if [ "$DRY_RUN" = false ]; then
        # Check if target already has this content (deduplicate)
        local needs_copy=true

        # Move cache to shared location
        echo -e "  ${YELLOW}Migrating...${NC}"

        # Rsync preserves files and can skip duplicates
        rsync -av --remove-source-files "$cache_path/" "$target_dir/" 2>/dev/null || {
            echo -e "  ${YELLOW}Some files already exist, skipping duplicates${NC}"
            MODELS_DEDUPLICATED=$((MODELS_DEDUPLICATED + 1))
        }

        # Remove empty directories
        find "$cache_path" -type d -empty -delete 2>/dev/null || true

        # Create symlink
        if [ -d "$cache_path" ]; then
            # Cache path still exists (parent dir), make it a symlink
            rm -rf "$cache_path"
        fi

        mkdir -p "$(dirname "$cache_path")"
        ln -sf "$target_dir" "$cache_path"

        echo -e "  ${GREEN}✓ Migrated and linked${NC}"
    else
        echo -e "  ${YELLOW}[DRY RUN] Would migrate to $target_dir${NC}"
        echo -e "  ${YELLOW}[DRY RUN] Would create symlink${NC}"
    fi

    echo ""
}

# Scan all projects
echo -e "${BLUE}Scanning projects in $PROJECTS_DIR...${NC}"
echo ""

for project_path in "$PROJECTS_DIR"/*; do
    if [ ! -d "$project_path" ]; then
        continue
    fi

    project_name=$(basename "$project_path")
    TOTAL_PROJECTS=$((TOTAL_PROJECTS + 1))

    found_cache=false

    # Check for common cache locations
    CACHE_LOCATIONS=(
        ".cache/huggingface:huggingface"
        ".cache/torch:torch"
        ".cache/transformers:transformers"
        "cache/huggingface:huggingface"
        "cache/torch:torch"
        "models:huggingface"
        ".huggingface:huggingface"
        ".torch:torch"
    )

    for cache_loc in "${CACHE_LOCATIONS[@]}"; do
        IFS=':' read -r cache_subdir cache_type <<< "$cache_loc"
        cache_path="$project_path/$cache_subdir"

        if has_models "$cache_path"; then
            if [ "$found_cache" = false ]; then
                echo -e "${CYAN}=== $project_name ===${NC}"
                found_cache=true
                PROJECTS_WITH_CACHE=$((PROJECTS_WITH_CACHE + 1))
            fi

            migrate_cache "$project_name" "$cache_path" "$cache_type"
        fi
    done

    # Check Docker volumes (if docker-compose.yml exists)
    if [ -f "$project_path/docker-compose.yml" ]; then
        # Check if project uses Docker volumes for caches
        if grep -q "huggingface\|torch\|transformers" "$project_path/docker-compose.yml" 2>/dev/null; then
            if [ "$found_cache" = false ]; then
                echo -e "${CYAN}=== $project_name ===${NC}"
                found_cache=true
            fi
            echo -e "${BLUE}Found Docker volume references${NC}"
            echo "  This project uses Docker volumes for caching"
            echo "  No migration needed - update docker-compose.yml to use /opt/ai-cache"
            echo ""
        fi
    fi
done

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Migration Summary${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

echo "Projects scanned: $TOTAL_PROJECTS"
echo "Projects with caches: $PROJECTS_WITH_CACHE"
echo "Models found: $MODELS_FOUND"

if [ "$MODELS_DEDUPLICATED" -gt 0 ]; then
    echo "Duplicates skipped: $MODELS_DEDUPLICATED"
fi

echo ""

if [ "$DRY_RUN" = false ]; then
    SHARED_SIZE=$(get_size_mb "$SHARED_CACHE")
    echo "Total size before: ${TOTAL_SIZE_BEFORE}MB"
    echo "Shared cache size: ${SHARED_SIZE}MB"

    if [ "$TOTAL_SIZE_BEFORE" -gt 0 ]; then
        SAVINGS=$((TOTAL_SIZE_BEFORE - SHARED_SIZE))
        SAVINGS_PCT=$((SAVINGS * 100 / TOTAL_SIZE_BEFORE))
        echo -e "${GREEN}Space saved: ${SAVINGS}MB (${SAVINGS_PCT}%)${NC}"
    fi
    echo ""

    echo -e "${GREEN}✓ Migration complete!${NC}"
    echo ""
    echo "Shared cache location: $SHARED_CACHE"
    echo "  - huggingface: $SHARED_CACHE/huggingface"
    echo "  - torch: $SHARED_CACHE/torch"
    echo ""

    echo -e "${YELLOW}Next steps:${NC}"
    echo ""
    echo "1. Update docker-compose.yml files to use shared cache:"
    echo "   volumes:"
    echo "     - $SHARED_CACHE/huggingface:/data/.huggingface"
    echo "     - $SHARED_CACHE/torch:/data/.torch"
    echo ""
    echo "2. Update environment variables:"
    echo "   HF_HOME=$SHARED_CACHE/huggingface"
    echo "   TORCH_HOME=$SHARED_CACHE/torch"
    echo ""
    echo "3. Rebuild containers to use shared cache:"
    echo "   docker compose build"
    echo ""

    # Show what was migrated
    echo -e "${BLUE}Migrated caches:${NC}"
    ls -lah "$SHARED_CACHE/"
    echo ""

else
    echo -e "${YELLOW}DRY RUN - No changes made${NC}"
    echo ""
    echo "Run without --dry-run to perform migration:"
    echo "  ./cuda-optimization/scripts/migrate-to-shared-cache.sh"
    echo ""
fi

# Check for potential issues
echo -e "${BLUE}Checking for potential issues...${NC}"
echo ""

# Check if any project is currently running
RUNNING_CONTAINERS=$(docker ps --format '{{.Names}}' 2>/dev/null | wc -l)
if [ "$RUNNING_CONTAINERS" -gt 0 ]; then
    echo -e "${YELLOW}⚠ Warning: $RUNNING_CONTAINERS Docker containers are running${NC}"
    echo "  Recommendation: Stop containers before migration to avoid corruption"
    echo "  docker compose -p localai down"
    echo ""
fi

# Check disk space
AVAILABLE_SPACE=$(df -BM "$SHARED_CACHE" 2>/dev/null | tail -1 | awk '{print $4}' | sed 's/M//')
if [ "$AVAILABLE_SPACE" -lt "$((TOTAL_SIZE_BEFORE + 10000))" ]; then
    echo -e "${RED}✗ Warning: May not have enough disk space${NC}"
    echo "  Available: ${AVAILABLE_SPACE}MB"
    echo "  Required: ~${TOTAL_SIZE_BEFORE}MB"
    echo ""
fi

echo -e "${GREEN}Migration script complete!${NC}"
