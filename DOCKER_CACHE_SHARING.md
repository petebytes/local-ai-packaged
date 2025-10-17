# Docker BuildKit Cache Sharing Strategy

## Overview

This document describes how to share BuildKit cache mounts across multiple Docker services to avoid redundant downloads of the same packages (especially Python pip/uv packages and PyTorch libraries).

## Problem Statement

When building multiple Docker services that use similar dependencies (e.g., WhisperX and Kokoro both use PyTorch, transformers, etc.), each service traditionally downloads the same packages independently during build time. This results in:

- **Redundant downloads**: Same packages downloaded multiple times (e.g., PyTorch 1.2GB downloaded for each service)
- **Slower builds**: Initial builds take much longer than necessary
- **Wasted bandwidth**: Downloading gigabytes of duplicate data

## Solution: Shared BuildKit Cache IDs

Docker BuildKit supports sharing cache mounts across different builds using the **same cache ID**. The key is using identical `id` parameters in the `--mount=type=cache` directive across different Dockerfiles.

### How It Works

1. BuildKit manages a shared cache storage on the Docker host
2. When multiple Dockerfiles use the same cache `id`, they access the same cache directory
3. The cache is shared with `sharing=shared` mode, allowing concurrent access
4. First build downloads packages to cache; subsequent builds reuse cached packages

## Implementation

### 1. Dockerfile Configuration

Add shared cache mounts to your RUN commands that install packages:

```dockerfile
# Use shared cache ID for pip packages
RUN --mount=type=cache,id=pip-cache-shared,target=/root/.cache/pip,sharing=shared \
    pip3 install -r requirements.txt

# Use shared cache ID for uv packages
RUN --mount=type=cache,id=uv-cache-shared,target=/root/.cache/uv,sharing=shared \
    uv sync --extra gpu
```

### 2. Key Parameters Explained

- **`id=pip-cache-shared`**: The shared identifier that links cache across builds
  - All services using this same ID share the same cache
  - Can be any name, but use consistent naming

- **`target=/root/.cache/pip`**: The cache directory location
  - pip default: `/root/.cache/pip`
  - uv default: `/root/.cache/uv`
  - Adjust if using non-root user

- **`sharing=shared`**: Allows concurrent access by multiple builds
  - `shared` (default): Multiple writers can use simultaneously
  - `private`: Exclusive access per build
  - `locked`: Blocks concurrent access

### 3. User Permissions Consideration

If your Dockerfile uses a non-root user, adjust the cache target path:

```dockerfile
# For user with UID 1001
RUN --mount=type=cache,id=pip-cache-shared,target=/home/appuser/.cache/pip,uid=1001,gid=1001,sharing=shared \
    pip3 install -r requirements.txt
```

**Note**: The cache path must match the user running the command, or use `uid` and `gid` parameters.

## Applied Changes

### Services Updated

1. **WhisperX** (`whisperx/Dockerfile`):
   - Lines 41-42: Added `id=pip-cache-shared,sharing=shared`
   - Lines 45-50: Added `id=pip-cache-shared,sharing=shared`

2. **Kokoro** (`kokoro-build/docker/gpu/Dockerfile.rtx5090`):
   - Lines 37-41: Added both `id=pip-cache-shared` and `id=uv-cache-shared` with `sharing=shared`

### Cache IDs Used

- **`pip-cache-shared`**: Shared pip package cache across all services
- **`uv-cache-shared`**: Shared uv package cache across all services

## How to Apply to Future Services

### For Python pip-based services:

```dockerfile
# Before
RUN pip install -r requirements.txt

# After
RUN --mount=type=cache,id=pip-cache-shared,target=/root/.cache/pip,sharing=shared \
    pip install -r requirements.txt
```

### For Python uv-based services:

```dockerfile
# Before
RUN uv sync

# After
RUN --mount=type=cache,id=uv-cache-shared,target=/root/.cache/uv,sharing=shared \
    uv sync
```

### For Node.js npm-based services:

```dockerfile
# Before
RUN npm install

# After
RUN --mount=type=cache,id=npm-cache-shared,target=/root/.npm,sharing=shared \
    npm install
```

### For Node.js pnpm-based services:

```dockerfile
# Before
RUN pnpm install

# After
RUN --mount=type=cache,id=pnpm-cache-shared,target=/root/.cache/pnpm,sharing=shared \
    pnpm install
```

### For Node.js yarn-based services:

```dockerfile
# Before
RUN yarn install

# After
RUN --mount=type=cache,id=yarn-cache-shared,target=/usr/local/share/.cache/yarn,sharing=shared \
    yarn install
```

## Cache Locations by Package Manager

| Package Manager | Default Cache Location | Recommended ID |
|----------------|------------------------|----------------|
| pip | `/root/.cache/pip` | `pip-cache-shared` |
| uv | `/root/.cache/uv` | `uv-cache-shared` |
| npm | `/root/.npm` | `npm-cache-shared` |
| pnpm | `/root/.cache/pnpm` | `pnpm-cache-shared` |
| yarn | `/usr/local/share/.cache/yarn` | `yarn-cache-shared` |
| composer (PHP) | `/root/.composer/cache` | `composer-cache-shared` |
| go modules | `/go/pkg/mod` | `go-cache-shared` |
| cargo (Rust) | `/usr/local/cargo/registry` | `cargo-cache-shared` |

## Benefits

### Initial Build (First Service)
- Downloads all packages as normal
- Populates the shared cache

### Subsequent Builds (Other Services)
- **Reuses cached packages** from first build
- Only downloads packages not already in cache
- **Significantly faster** build times

### Example Time Savings

**Without shared cache:**
- WhisperX build: Downloads 2.5GB
- Kokoro build: Downloads 3.8GB (1.2GB PyTorch + 2.6GB other)
- **Total**: 6.3GB downloaded

**With shared cache:**
- WhisperX build: Downloads 2.5GB (populates cache)
- Kokoro build: Downloads ~1.2GB (only unique packages)
- **Total**: 3.7GB downloaded
- **Savings**: ~40% reduction + faster subsequent rebuilds

## Rebuilds and Cache Persistence

The BuildKit cache persists across:
- ✅ Rebuilds of the same service
- ✅ Builds of different services (when using same cache ID)
- ✅ System restarts
- ✅ Docker daemon restarts

The cache is cleared when:
- ❌ Running `docker buildx prune` or `docker builder prune`
- ❌ Running `docker system prune --all --volumes`
- ❌ Manually deleting BuildKit cache directory

## Verifying Cache Usage

### Check if cache is being used:

```bash
# Build with verbose output
BUILDKIT_PROGRESS=plain docker compose build service-name 2>&1 | grep "cache mount"

# Should see lines like:
# [internal] setting cache mount permissions
```

### Monitor cache size:

```bash
# View BuildKit cache
docker buildx du

# Example output:
# ID              SIZE
# pip-cache-shared    2.5GB
# uv-cache-shared     500MB
```

## Best Practices

1. **Use consistent cache IDs** across all services for the same package manager
2. **Always specify `sharing=shared`** for concurrent build support
3. **Match cache paths** to the user running the install command
4. **Document cache IDs** in your Dockerfile comments
5. **Consider cache size** when choosing what to cache (large, frequently-used packages are best candidates)

## Troubleshooting

### Cache not being reused

**Problem**: Second service still downloads everything

**Solutions**:
1. Verify both Dockerfiles use **identical** cache ID
2. Check that cache paths match (`/root/.cache/pip` vs `/home/user/.cache/pip`)
3. Ensure BuildKit is enabled: `DOCKER_BUILDKIT=1 docker compose build`
4. Check user permissions with `uid` and `gid` parameters if using non-root user

### Permission errors

**Problem**: `Permission denied` errors during build

**Solutions**:
1. Match cache mount UID/GID to the user running the command:
   ```dockerfile
   RUN --mount=type=cache,id=pip-cache-shared,target=/home/user/.cache/pip,uid=1001,gid=1001,sharing=shared \
       pip install -r requirements.txt
   ```
2. Or run as root during installation, then switch user afterward

### Concurrent build conflicts

**Problem**: Builds fail when running simultaneously

**Solutions**:
1. Ensure `sharing=shared` is specified (default is usually shared, but be explicit)
2. Use `sharing=locked` if package manager doesn't support concurrent writes (rare)

## References

- [Docker BuildKit Cache Documentation](https://docs.docker.com/build/cache/optimize/)
- [BuildKit Cache Mounts](https://depot.dev/blog/how-to-use-cache-mount-to-speed-up-docker-builds)
- [Sharing Cache Between Builds](https://github.com/moby/buildkit/issues/1009)

## Changelog

### 2025-10-17
- Initial document created
- Applied shared cache to WhisperX and Kokoro services
- Documented pip and uv cache sharing strategy
