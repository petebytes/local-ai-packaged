#!/usr/bin/env python3
"""
Automated Docker Build Cache Optimizer
Adds BuildKit cache mounts to all Dockerfiles for faster rebuilds
"""

import os
import re
import glob
from pathlib import Path

def optimize_dockerfile(filepath):
    """Add cache mounts to a Dockerfile"""
    print(f"\n{'='*60}")
    print(f"Optimizing: {filepath}")
    print(f"{'='*60}")

    with open(filepath, 'r') as f:
        content = f.read()

    original_content = content
    changes = []

    # Pattern 1: pip install without cache mount
    pip_pattern = r'(RUN\s+(?!--mount).*pip\s+install)'
    if re.search(pip_pattern, content):
        content = re.sub(
            pip_pattern,
            r'RUN --mount=type=cache,target=/root/.cache/pip \\\n    \1',
            content
        )
        changes.append("Added pip cache mount")

    # Pattern 2: npm install without cache mount
    npm_pattern = r'(RUN\s+(?!--mount).*npm\s+(?:install|ci))'
    if re.search(npm_pattern, content):
        content = re.sub(
            npm_pattern,
            r'RUN --mount=type=cache,target=/root/.npm \\\n    \1',
            content
        )
        changes.append("Added npm cache mount")

    # Pattern 3: pnpm install without cache mount
    pnpm_pattern = r'(RUN\s+(?!--mount).*pnpm\s+install)'
    if re.search(pnpm_pattern, content):
        content = re.sub(
            pnpm_pattern,
            r'RUN --mount=type=cache,id=pnpm,target=/pnpm/store \\\n    \1',
            content
        )
        changes.append("Added pnpm cache mount")

    # Pattern 4: yarn install without cache mount
    yarn_pattern = r'(RUN\s+(?!--mount).*yarn\s+install)'
    if re.search(yarn_pattern, content):
        content = re.sub(
            yarn_pattern,
            r'RUN --mount=type=cache,target=/usr/local/share/.cache/yarn \\\n    \1',
            content
        )
        changes.append("Added yarn cache mount")

    # Remove PIP_NO_CACHE_DIR if present
    if 'PIP_NO_CACHE_DIR=1' in content:
        content = re.sub(r'\s*PIP_NO_CACHE_DIR=1\s*\\?\s*\n?', '', content)
        changes.append("Removed PIP_NO_CACHE_DIR=1")

    # Remove --no-cache-dir from pip install
    if '--no-cache-dir' in content:
        content = re.sub(r'\s*--no-cache-dir\s*', ' ', content)
        changes.append("Removed --no-cache-dir flags")

    if content != original_content:
        # Backup original
        backup_path = f"{filepath}.backup"
        with open(backup_path, 'w') as f:
            f.write(original_content)
        print(f"✓ Backed up to: {backup_path}")

        # Write optimized version
        with open(filepath, 'w') as f:
            f.write(content)
        print(f"✓ Optimized successfully")
        print(f"  Changes: {', '.join(changes)}")
        return True
    else:
        print("⊘ No changes needed")
        return False

def main():
    code_dir = "/home/ghar/code"

    # Dockerfiles that need optimization
    targets = [
        "/home/ghar/code/SurfSense/surfsense_backend/Dockerfile",
        "/home/ghar/code/SurfSense/surfsense_web/Dockerfile",
        "/home/ghar/code/Wan2GP/Dockerfile",
        "/home/ghar/code/nocodb/packages/nocodb/Dockerfile",
        "/home/ghar/code/nocodb/packages/nocodb/Dockerfile.local",
        "/home/ghar/code/nocodb/packages/nocodb/Dockerfile.timely",
        "/home/ghar/code/openloot-api-clone/Dockerfile",
        "/home/ghar/code/openloot-api-clone/admin/Dockerfile",
        "/home/ghar/code/tools/anything-llm/docker/Dockerfile",
    ]

    optimized = 0
    skipped = 0
    errors = 0

    for dockerfile in targets:
        if not os.path.exists(dockerfile):
            print(f"\n⚠ Skipped (not found): {dockerfile}")
            skipped += 1
            continue

        try:
            if optimize_dockerfile(dockerfile):
                optimized += 1
            else:
                skipped += 1
        except Exception as e:
            print(f"\n✗ Error processing {dockerfile}: {e}")
            errors += 1

    print(f"\n{'='*60}")
    print(f"SUMMARY")
    print(f"{'='*60}")
    print(f"✓ Optimized: {optimized}")
    print(f"⊘ Skipped: {skipped}")
    print(f"✗ Errors: {errors}")
    print(f"\nNote: Backups created with .backup extension")
    print(f"To restore: mv Dockerfile.backup Dockerfile")

if __name__ == "__main__":
    main()
