# Docker Desktop Data Migration Guide to New NVMe Drive

**Current Situation:**
- Docker Desktop WSL 2 backend
- All data currently stored in WSL distribution: `docker-desktop-data`
- Target: Move all Docker data to new NVMe drive (E:)
- Components: Images, Containers, Volumes, Build Cache, Networks

**Purpose:**
- Free up space on current drive
- Improve Docker performance on faster NVMe
- Separate Docker data from WSL system

---

## Understanding Docker Desktop Data Storage

Docker Desktop on WSL 2 stores data in **two separate WSL distributions**:

1. **`docker-desktop`** - Docker engine and services (~500MB-1GB)
2. **`docker-desktop-data`** - All your images, volumes, containers (can be 100GB+)

**Current Location (typical):**
```
C:\Users\[Username]\AppData\Local\Docker\wsl\
├── data\ext4.vhdx              (docker-desktop-data)
└── distro\ext4.vhdx             (docker-desktop)
```

---

## Migration Strategy Options

### Option 1: Move Docker Desktop Data Distribution (RECOMMENDED)
**Pros:**
- Cleanest approach
- Moves ALL Docker data at once
- Maintains Docker Desktop integration
- No configuration file editing needed

**Cons:**
- Requires export/import (takes time)
- Must stop Docker Desktop completely

### Option 2: Change Docker Data Root via daemon.json
**Pros:**
- Quick configuration change
- No data migration needed initially

**Cons:**
- Data still in VHDX on C: drive
- Only changes where NEW data goes
- Requires manual migration of existing data

### Option 3: Move Both Docker WSL Distributions
**Pros:**
- Complete separation from C: drive
- Everything Docker-related on new drive

**Cons:**
- More complex
- Longer migration time
- May need to reconfigure Docker Desktop

---

## RECOMMENDED: Option 1 - Move docker-desktop-data

This is the best approach for your situation.

### Step 1: Preparation

**Check current Docker data size:**

```powershell
# In PowerShell
wsl -l -v

# Check docker-desktop-data VHDX size
Get-ChildItem "C:\Users\$env:USERNAME\AppData\Local\Docker\wsl\data\ext4.vhdx"
```

**Create target directories on new drive:**

```powershell
# Create Docker directories on E: drive
New-Item -ItemType Directory -Path "E:\Docker\wsl\data" -Force
New-Item -ItemType Directory -Path "E:\Docker\backups" -Force
```

### Step 2: Stop Docker Desktop Completely

```powershell
# Close Docker Desktop if open
Stop-Process -Name "Docker Desktop" -Force -ErrorAction SilentlyContinue

# Wait 10 seconds
Start-Sleep -Seconds 10

# Shutdown all WSL (including Docker distributions)
wsl --shutdown

# Verify everything is stopped
wsl -l -v
# All should show "Stopped"

# Verify Docker processes are stopped
Get-Process | Where-Object {$_.ProcessName -like "*docker*"}
# Should return nothing
```

### Step 3: Export docker-desktop-data

```powershell
# Export docker-desktop-data to backup
wsl --export docker-desktop-data "E:\Docker\backups\docker-desktop-data.tar"

# This may take 30-90 minutes depending on size
# Monitor file growth in File Explorer
```

**⏱️ Expected Time:** 30-120 minutes (depends on data size)

### Step 4: Verify Export

```powershell
# Check the exported file exists and size is reasonable
Get-ChildItem "E:\Docker\backups\docker-desktop-data.tar"

# Expected size: Could be 10GB-200GB+ depending on images/volumes
```

### Step 5: Unregister docker-desktop-data

**⚠️ WARNING: This deletes the original Docker data WSL distribution**

```powershell
# ENSURE EXPORT IS COMPLETE FIRST!
# Check file size one more time
Get-ChildItem "E:\Docker\backups\docker-desktop-data.tar"

# Unregister (deletes original)
wsl --unregister docker-desktop-data

# Verify it's removed
wsl -l -v
# docker-desktop-data should no longer be listed
```

### Step 6: Import to New Location

```powershell
# Import docker-desktop-data to new location
wsl --import docker-desktop-data "E:\Docker\wsl\data" "E:\Docker\backups\docker-desktop-data.tar" --version 2

# This will take time - importing all Docker data
```

**⏱️ Expected Time:** 45-120 minutes

**Monitor Progress:**
- Watch the directory: `E:\Docker\wsl\data\ext4.vhdx`
- This file will grow as import progresses

### Step 7: Restart Docker Desktop

```powershell
# Start Docker Desktop
Start-Process "C:\Program Files\Docker\Docker\Docker Desktop.exe"

# Wait for Docker to initialize (60-120 seconds)
Start-Sleep -Seconds 90
```

**Docker Desktop should:**
1. Detect the new location automatically
2. Start the Docker engine
3. Mount the docker-desktop-data distribution

### Step 8: Verify Docker Data

**In PowerShell:**
```powershell
# Check WSL distributions
wsl -l -v

# Should show:
# * docker-desktop       Running    2
#   docker-desktop-data  Running    2
#   ubuntu-24-04         Running    2
```

**Inside WSL (your ubuntu-24-04):**
```bash
# Check Docker is working
docker --version
docker info

# List your volumes (should all be there)
docker volume ls

# List your images
docker images

# Check system disk usage
docker system df
```

---

## Alternative: Option 2 - Change Docker Data Root Only

If you want to change where NEW Docker data is stored (but keep existing data):

### Method A: Using Docker Desktop UI (Easiest)

1. Open Docker Desktop
2. Go to **Settings** ⚙️
3. Click **Resources** → **Advanced**
4. Look for **Disk image location** or **Data directory**
5. Click **Browse** and select `E:\Docker\data`
6. Click **Apply & Restart**

**Note:** Docker Desktop on Windows may not expose this setting in UI for WSL 2 backend.

### Method B: Edit daemon.json

**Create/Edit:** `C:\Users\[Username]\.docker\daemon.json`

```json
{
  "data-root": "E:\\Docker\\data",
  "storage-driver": "overlay2",
  "registry-mirrors": ["http://localhost:5000"]
}
```

**Then:**
```powershell
# Restart Docker Desktop
# This only affects NEW data, existing data stays in WSL
```

**Migrate Existing Data:**
```bash
# Inside WSL
sudo rsync -aP /var/lib/docker/ /mnt/e/Docker/data/

# Or using Windows paths (slower)
# Then update daemon.json with new path
```

---

## Option 3: Move BOTH Docker WSL Distributions

If you want complete separation from C: drive:

### Move docker-desktop-data (see Option 1 above)

### Then Move docker-desktop:

```powershell
# Export docker-desktop
wsl --export docker-desktop "E:\Docker\backups\docker-desktop.tar"

# Unregister
wsl --unregister docker-desktop

# Import to new location
wsl --import docker-desktop "E:\Docker\wsl\distro" "E:\Docker\backups\docker-desktop.tar" --version 2

# Restart Docker Desktop
# It should detect the new locations
```

**⚠️ Warning:** This may require reconfiguring Docker Desktop. Less recommended unless you need complete separation.

---

## Post-Migration Verification Checklist

**Docker Desktop:**
- [ ] Docker Desktop starts successfully
- [ ] System tray icon shows green (running)
- [ ] Settings → Resources shows WSL integration enabled

**Docker CLI:**
```bash
# Inside WSL
docker --version              # Should work
docker info                   # Should show server running
docker system df              # Should show your disk usage
```

**Images:**
```bash
docker images                 # Should list all your images
docker image ls --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"
```

**Volumes:**
```bash
docker volume ls              # Should list all your volumes
docker volume inspect [volume-name]  # Check a specific volume
```

**Networks:**
```bash
docker network ls             # Should show your networks
```

**Containers:**
```bash
docker ps -a                  # Should show all containers (stopped/running)
```

**Test Run:**
```bash
# Try running a test container
docker run --rm hello-world

# Try starting your local-ai services
cd ~/code/local-ai-packaged
python start_services.py --profile gpu-nvidia
```

---

## Troubleshooting

### Issue: Docker Desktop Won't Start After Migration

**Solution 1 - Reset Docker Desktop:**
```powershell
# Close Docker Desktop
Stop-Process -Name "Docker Desktop" -Force

# Delete Docker Desktop settings (keeps data)
Remove-Item "$env:APPDATA\Docker\settings.json"

# Restart Docker Desktop
```

**Solution 2 - Check WSL Integration:**
1. Open Docker Desktop
2. Settings → Resources → WSL Integration
3. Enable ubuntu-24-04
4. Apply & Restart

### Issue: "Cannot connect to Docker daemon"

**Cause:** Docker Desktop service not running

**Solution:**
```powershell
# Check if Docker Desktop is running
Get-Process | Where-Object {$_.ProcessName -like "*Docker Desktop*"}

# If not running, start it
Start-Process "C:\Program Files\Docker\Docker\Docker Desktop.exe"

# Wait 60 seconds
Start-Sleep -Seconds 60

# Check WSL distributions
wsl -l -v
# docker-desktop should be Running
```

### Issue: Volumes/Images Missing After Migration

**Cause:** Import failed or incomplete

**Solution - Restore from Backup:**
```powershell
# Unregister the failed import
wsl --unregister docker-desktop-data

# Re-import from backup
wsl --import docker-desktop-data "E:\Docker\wsl\data" "E:\Docker\backups\docker-desktop-data.tar" --version 2

# Restart Docker Desktop
```

### Issue: "Not enough space" During Import

**Solution:**
```powershell
# Check space on E: drive
Get-Volume -DriveLetter E

# You need 2x the size of the .tar file
# Clear space or use a larger drive
```

### Issue: Slow Docker Performance After Migration

**Cause:** New drive not optimized or fragmented

**Solution:**
```powershell
# Optimize the VHDX
wsl --shutdown
Optimize-VHD -Path "E:\Docker\wsl\data\ext4.vhdx" -Mode Full

# Enable sparse VHD in .wslconfig
# See optimization section below
```

---

## Performance Optimization After Migration

### Configure .wslconfig for Better Performance

**Create/Edit:** `C:\Users\[Username]\.wslconfig`

```ini
[wsl2]
# Memory for WSL (you have 98GB)
memory=64GB

# Processors
processors=24

# Swap
swap=32GB
swapFile=E:\\Docker\\swap.vhdx

# Sparse VHD (saves space)
sparseVhd=true

# Nested virtualization (for Docker)
nestedVirtualization=true

# Network settings
networkingMode=mirrored

# DNS settings
dnsTunneling=true

# VM idle timeout (milliseconds)
vmIdleTimeout=60000
```

**Apply changes:**
```powershell
wsl --shutdown
# Restart Docker Desktop
```

### Compact Docker Data VHDX

```powershell
# Shutdown WSL
wsl --shutdown

# Compact the VHDX (reclaims unused space)
Optimize-VHD -Path "E:\Docker\wsl\data\ext4.vhdx" -Mode Full

# Check new size
Get-ChildItem "E:\Docker\wsl\data\ext4.vhdx"
```

### Enable Docker BuildKit (if not already)

**In daemon.json:**
```json
{
  "data-root": "E:\\Docker\\data",
  "features": {
    "buildkit": true
  },
  "builder": {
    "gc": {
      "enabled": true,
      "defaultKeepStorage": "20GB"
    }
  }
}
```

---

## Docker Data Management Best Practices

### Regular Cleanup

```bash
# Clean up unused data (be careful with volumes!)
docker system prune -a

# Clean up volumes (CAUTION: This deletes data!)
docker volume prune

# Clean up build cache
docker builder prune -a

# See what's taking space
docker system df -v
```

### Backup Strategy

**Weekly Volume Backups:**
```bash
#!/bin/bash
# backup-docker-volumes.sh

BACKUP_DIR="/mnt/e/Docker/volume-backups"
DATE=$(date +%Y%m%d)

# Backup each volume
for volume in $(docker volume ls -q); do
  docker run --rm \
    -v $volume:/data \
    -v $BACKUP_DIR:/backup \
    alpine tar czf /backup/${volume}-${DATE}.tar.gz /data
done
```

**Image Export:**
```bash
# Export specific images to NAS
docker save -o /mnt/nas/docker-images/image-backup.tar \
  image1:tag image2:tag image3:tag
```

---

## Directory Structure After Migration

```
E:\Docker\
├── wsl\
│   ├── data\
│   │   └── ext4.vhdx           (docker-desktop-data - all your Docker data)
│   └── distro\                 (optional - if you moved docker-desktop too)
│       └── ext4.vhdx
├── backups\
│   ├── docker-desktop-data.tar (keep until verified working)
│   └── docker-desktop.tar      (optional)
├── volume-backups\             (for scheduled backups)
│   ├── volume1-20251017.tar.gz
│   └── volume2-20251017.tar.gz
└── swap.vhdx                   (WSL swap file)
```

---

## Rollback Procedure

If something goes wrong, you can restore:

```powershell
# 1. Shutdown everything
Stop-Process -Name "Docker Desktop" -Force
wsl --shutdown

# 2. Unregister the broken docker-desktop-data
wsl --unregister docker-desktop-data

# 3. Restore from original location (if you didn't delete it yet)
# OR re-import from backup
wsl --import docker-desktop-data "C:\Users\$env:USERNAME\AppData\Local\Docker\wsl\data" "E:\Docker\backups\docker-desktop-data.tar" --version 2

# 4. Restart Docker Desktop
```

---

## Advanced: Hybrid Approach

Keep Docker system on C:, but move specific large volumes to new drive:

```bash
# Stop containers using the volume
docker compose -p localai down

# Backup volume
docker run --rm -v comfyui-models:/data -v /mnt/e/docker-volumes:/backup \
  alpine tar czf /backup/comfyui-models.tar.gz /data

# Remove old volume
docker volume rm comfyui-models

# Create new volume pointing to E: drive
docker volume create \
  --driver local \
  --opt type=none \
  --opt o=bind \
  --opt device=/mnt/e/docker-volumes/comfyui-models \
  comfyui-models

# Restore data
docker run --rm -v comfyui-models:/data -v /mnt/e/docker-volumes:/backup \
  alpine tar xzf /backup/comfyui-models.tar.gz -C /

# Update docker-compose.yml if using external volumes
```

**Example docker-compose.yml with external volumes:**
```yaml
volumes:
  comfyui-models:
    external: true
  hf-cache:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /mnt/e/docker-volumes/hf-cache
```

---

## Monitoring Docker Storage

### PowerShell Script to Check Docker Data Size

```powershell
# check-docker-size.ps1

Write-Host "Docker Desktop Data Sizes:" -ForegroundColor Cyan

# docker-desktop-data VHDX
$dataVHDX = Get-ChildItem "E:\Docker\wsl\data\ext4.vhdx" -ErrorAction SilentlyContinue
if ($dataVHDX) {
    $sizeGB = [math]::Round($dataVHDX.Length / 1GB, 2)
    Write-Host "docker-desktop-data: $sizeGB GB" -ForegroundColor Green
} else {
    Write-Host "docker-desktop-data: Not found on E: drive" -ForegroundColor Yellow
}

# Inside Docker
Write-Host "`nDocker System Disk Usage:" -ForegroundColor Cyan
wsl -d ubuntu-24-04 docker system df
```

---

## Cleanup After Successful Migration

**Only after verifying everything works for 1-2 weeks:**

```powershell
# Remove backup tar files (saves space)
Remove-Item "E:\Docker\backups\docker-desktop-data.tar"

# Remove old VHDX from C: drive (if not already deleted by unregister)
# This is usually automatic, but verify:
Get-ChildItem "C:\Users\$env:USERNAME\AppData\Local\Docker\wsl\data\" -ErrorAction SilentlyContinue

# Compact the new VHDX
wsl --shutdown
Optimize-VHD -Path "E:\Docker\wsl\data\ext4.vhdx" -Mode Full
```

---

## Timeline Estimate

| Step | Duration |
|------|----------|
| Preparation | 10 minutes |
| Stop Docker & WSL | 2 minutes |
| Export docker-desktop-data | 30-120 minutes |
| Verify export | 2 minutes |
| Unregister | 1 minute |
| Import to new location | 45-120 minutes |
| Restart & verify | 15 minutes |

**Total: 2-4 hours** (depending on data size)

---

## Quick Command Reference

```powershell
# Full migration script (use with caution!)
# Save as: migrate-docker-desktop.ps1

# Stop everything
Stop-Process -Name "Docker Desktop" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 10
wsl --shutdown

# Create directories
New-Item -ItemType Directory -Path "E:\Docker\wsl\data" -Force
New-Item -ItemType Directory -Path "E:\Docker\backups" -Force

# Export
Write-Host "Exporting docker-desktop-data (this will take time)..." -ForegroundColor Yellow
wsl --export docker-desktop-data "E:\Docker\backups\docker-desktop-data.tar"

# Verify
$exportSize = (Get-ChildItem "E:\Docker\backups\docker-desktop-data.tar").Length / 1GB
Write-Host "Export size: $([math]::Round($exportSize, 2)) GB" -ForegroundColor Green

# Confirm before unregister
Read-Host "Press Enter to continue with unregister (DELETES ORIGINAL)"

# Unregister
wsl --unregister docker-desktop-data

# Import
Write-Host "Importing to new location (this will take time)..." -ForegroundColor Yellow
wsl --import docker-desktop-data "E:\Docker\wsl\data" "E:\Docker\backups\docker-desktop-data.tar" --version 2

# Restart Docker Desktop
Write-Host "Starting Docker Desktop..." -ForegroundColor Green
Start-Process "C:\Program Files\Docker\Docker\Docker Desktop.exe"
Start-Sleep -Seconds 90

Write-Host "Migration complete! Verify Docker is working before cleaning up backup." -ForegroundColor Cyan
```

---

## Additional Resources

**Docker Desktop Documentation:**
- [Docker Desktop WSL 2 backend](https://docs.docker.com/desktop/windows/wsl/)
- [Docker data management](https://docs.docker.com/storage/)

**Useful Commands:**
```powershell
# Check WSL distributions
wsl -l -v

# Check Docker process
Get-Process | Where-Object {$_.Name -like "*Docker*"}

# Docker Desktop settings location
explorer "$env:APPDATA\Docker"

# Docker Desktop installation location
explorer "C:\Program Files\Docker\Docker"
```

---

**Last Updated:** October 17, 2025
**Status:** Ready to execute
**Critical:** Keep backup until migration is fully verified!
**Estimated Space Savings on C: Drive:** 50GB-200GB+ (depending on current Docker data size)
