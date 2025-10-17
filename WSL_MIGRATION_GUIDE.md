# WSL Migration Guide to New NVMe Drive

**Current Situation:**
- Distribution: `ubuntu-24-04` (WSL 2)
- Current Size: 929GB used of 1007GB (98% full)
- Target: Move to new 3rd NVMe drive
- Purpose: Resolve critical disk space issue

**Estimated Migration Time:** 2-4 hours (depending on data size and drive speed)

---

## Pre-Migration Checklist

### 1. Prepare New NVMe Drive

**In Windows (PowerShell as Administrator):**

```powershell
# Check new drive is visible
Get-Disk

# Initialize the new drive (if not already done)
# Replace X with your new disk number
Initialize-Disk -Number X -PartitionStyle GPT

# Create a new partition (full disk)
New-Partition -DiskNumber X -UseMaximumSize -DriveLetter E

# Format as NTFS
Format-Volume -DriveLetter E -FileSystem NTFS -NewFileSystemLabel "WSL-Storage" -AllocationUnitSize 4096
```

**Recommended Location on New Drive:**
```
E:\WSL\ubuntu-24-04\
```

### 2. Verify Current WSL State

**Check running distributions:**
```powershell
wsl -l -v
```

**Check disk usage inside WSL:**
```bash
df -h /
du -sh /home/ghar/code/local-ai-packaged
```

### 3. Stop All Docker Containers

**Inside WSL:**
```bash
# Stop all running containers
docker ps -q | xargs -r docker stop

# Verify all stopped
docker ps -a

# Exit WSL
exit
```

**In Windows PowerShell:**
```powershell
# Stop Docker Desktop
Stop-Process -Name "Docker Desktop" -Force

# Verify Docker is stopped
Get-Process | Where-Object {$_.ProcessName -like "*docker*"}
```

---

## Migration Process

### Step 1: Shutdown WSL Completely

```powershell
# Shutdown all WSL distributions
wsl --shutdown

# Verify WSL is completely stopped
wsl -l -v
# All distributions should show "Stopped"
```

### Step 2: Export WSL Distribution

**This creates a complete backup of your WSL distribution:**

```powershell
# Create export directory on new drive
New-Item -ItemType Directory -Path "E:\WSL\Backups" -Force

# Export the distribution (this will take time - 929GB to export)
wsl --export ubuntu-24-04 "E:\WSL\Backups\ubuntu-24-04-export.tar"
```

**⏱️ Expected Time:** 30-90 minutes for 929GB
**💾 Space Required:** 929GB on the new drive

**Monitor Progress:**
- Watch the file size grow in File Explorer: `E:\WSL\Backups\ubuntu-24-04-export.tar`
- No progress bar is shown, but file will grow incrementally

### Step 3: Verify Export Integrity

```powershell
# Check the exported file exists and size is reasonable
Get-ChildItem "E:\WSL\Backups\ubuntu-24-04-export.tar"

# Expected size: Should be close to 929GB (may be compressed slightly)
```

### Step 4: Unregister Old WSL Distribution

**⚠️ WARNING: This deletes the original WSL installation**

```powershell
# BACKUP VERIFICATION: Ensure export completed successfully
# Check file size one more time
Get-ChildItem "E:\WSL\Backups\ubuntu-24-04-export.tar"

# Unregister the distribution (deletes original)
wsl --unregister ubuntu-24-04

# Verify it's removed
wsl -l -v
# ubuntu-24-04 should no longer be listed
```

### Step 5: Import to New Location

```powershell
# Create the new WSL home directory
New-Item -ItemType Directory -Path "E:\WSL\ubuntu-24-04" -Force

# Import the distribution to the new location
wsl --import ubuntu-24-04 "E:\WSL\ubuntu-24-04" "E:\WSL\Backups\ubuntu-24-04-export.tar" --version 2

# This will take time - importing 929GB
```

**⏱️ Expected Time:** 45-120 minutes
**💾 Space Required:** 1TB+ on E: drive

**Monitor Progress:**
- Watch the directory size grow: `E:\WSL\ubuntu-24-04\ext4.vhdx`
- This is your new WSL virtual disk

### Step 6: Verify Import Success

```powershell
# Check distribution is registered
wsl -l -v

# Should show:
# * ubuntu-24-04    Stopped    2

# Start WSL
wsl -d ubuntu-24-04

# Inside WSL, verify data integrity
df -h
ls -la ~/code/local-ai-packaged
```

---

## Post-Migration Configuration

### 1. Restore Default User

**If WSL logs you in as root instead of 'ghar':**

```powershell
# Exit WSL first
exit

# In PowerShell, set default user
ubuntu2404.exe config --default-user ghar

# Or using generic method:
wsl -d ubuntu-24-04 -u ghar

# Verify
wsl -d ubuntu-24-04 whoami
# Should output: ghar
```

### 2. Configure WSL Default Distribution

```powershell
# Set as default distribution (optional)
wsl --set-default ubuntu-24-04

# Verify
wsl -l -v
# The * should be next to ubuntu-24-04
```

### 3. Restart Docker Desktop

```powershell
# Start Docker Desktop
Start-Process "C:\Program Files\Docker\Docker\Docker Desktop.exe"

# Wait 30-60 seconds for Docker to initialize
```

### 4. Verify WSL Integration in Docker Desktop

1. Open Docker Desktop
2. Go to **Settings** → **Resources** → **WSL Integration**
3. Ensure **ubuntu-24-04** is enabled
4. Click **Apply & Restart**

### 5. Test Docker Functionality

**Inside WSL:**

```bash
# Check Docker is accessible
docker --version
docker info

# Check GPU access
nvidia-smi

# Try a simple container
docker run hello-world
```

### 6. Verify Project Files

```bash
cd ~/code/local-ai-packaged

# Check git status
git status

# Verify file integrity
ls -lah

# Check Docker volumes still exist
docker volume ls
```

---

## Expand WSL Disk (Optional)

If you want to expand beyond 1TB on the new drive:

```powershell
# Shutdown WSL
wsl --shutdown

# Open Diskpart
diskpart

# In diskpart:
# Select the VHDX file
select vdisk file="E:\WSL\ubuntu-24-04\ext4.vhdx"

# Expand to desired size (e.g., 2TB = 2048000 MB)
expand vdisk maximum=2048000

# Exit diskpart
exit
```

**Inside WSL (after restarting):**

```bash
# Resize the filesystem
sudo resize2fs /dev/sdb

# Verify new size
df -h /
```

---

## Troubleshooting

### Issue: Export Taking Too Long

**Solution:**
- This is normal for 929GB of data
- Ensure you have enough space on the target drive
- Don't interrupt the process
- Check Windows Event Viewer for any disk errors

### Issue: Import Fails with "Not Enough Space"

**Solution:**
```powershell
# Check available space on E: drive
Get-Volume -DriveLetter E

# You need at least 1.2TB free (929GB + 30% overhead)
```

### Issue: WSL Won't Start After Import

**Solution:**
```powershell
# Check WSL version
wsl --version

# Update WSL to latest
wsl --update

# Try starting with verbose output
wsl -d ubuntu-24-04 --verbose
```

### Issue: Docker Can't See Containers/Volumes

**Cause:** Docker Desktop may be looking at the old location

**Solution:**
1. Open Docker Desktop Settings
2. **Resources** → **Advanced** → Reset to factory defaults (WARNING: This removes all Docker data)
3. Re-enable WSL 2 integration for ubuntu-24-04
4. Restore volumes from backup if needed

**Better Solution (Preserve Docker Data):**
```bash
# Before migration, back up Docker volumes
docker run --rm -v /var/lib/docker:/backup -v $(pwd):/output \
  alpine tar czf /output/docker-volumes-backup.tar.gz /backup
```

### Issue: Permission Errors After Migration

**Solution:**
```bash
# Fix ownership on home directory
sudo chown -R ghar:ghar /home/ghar

# Fix SSH keys permissions
chmod 700 ~/.ssh
chmod 600 ~/.ssh/id_*
chmod 644 ~/.ssh/*.pub
```

### Issue: NAS Mount Doesn't Work

**Solution:**
```bash
# Remount the NAS
sudo umount /mnt/nas/PeggysExtraStorage
sudo mount -t cifs //192.168.3.135/PeggysExtraStorage /mnt/nas/PeggysExtraStorage \
  -o username=peggy,uid=1000,gid=1000,file_mode=0644,dir_mode=0755

# Or add to /etc/fstab for automatic mounting
```

---

## Performance Optimization After Migration

### 1. Configure .wslconfig for New Drive

Create/edit `C:\Users\[YourUsername]\.wslconfig`:

```ini
[wsl2]
# Increase memory limit (you have 98GB)
memory=64GB

# Increase processors
processors=24

# Increase swap
swap=32GB

# Set swap location to new drive
swapFile=E:\\WSL\\swap.vhdx

# Enable sparse VHD (saves space)
sparseVhd=true

# Enable nested virtualization
nestedVirtualization=true

# Increase VM idle timeout (keeps WSL running longer)
vmIdleTimeout=60000
```

### 2. Enable Sparse VHD for Existing Disk

```powershell
# Shutdown WSL
wsl --shutdown

# Optimize the VHDX (reclaim unused space)
Optimize-VHD -Path "E:\WSL\ubuntu-24-04\ext4.vhdx" -Mode Full

# Convert to sparse (if not already)
# This allows dynamic shrinking
```

### 3. Configure NVMe Optimizations

**Inside WSL:**
```bash
# Check if TRIM is enabled
sudo fstrim -v /

# Add to crontab for weekly TRIM
(crontab -l 2>/dev/null; echo "0 3 * * 0 /sbin/fstrim /") | crontab -
```

---

## Alternative: Move Docker Data Separately

If you want to keep WSL where it is but move just Docker data:

### Option 1: Change Docker Data Root

**In Windows, create/edit** `C:\Users\[Username]\.docker\daemon.json`:

```json
{
  "data-root": "E:\\Docker\\data",
  "registry-mirrors": ["http://localhost:5000"]
}
```

**Then restart Docker Desktop.**

### Option 2: Move Specific Volumes

```bash
# Stop containers
docker compose -p localai down

# Backup specific volumes
docker run --rm -v comfyui-models:/data -v /mnt/e/docker-backups:/backup \
  alpine tar czf /backup/comfyui-models.tar.gz /data

# Recreate volume on new location (bind mount to NAS)
docker volume rm comfyui-models
docker volume create \
  --driver local \
  --opt type=none \
  --opt o=bind \
  --opt device=/mnt/e/docker-volumes/comfyui-models \
  comfyui-models
```

---

## Post-Migration Verification Checklist

- [ ] WSL starts successfully: `wsl -d ubuntu-24-04`
- [ ] Correct user logged in: `whoami` returns `ghar`
- [ ] Disk space available: `df -h` shows new capacity
- [ ] Docker CLI works: `docker --version`
- [ ] GPU accessible: `nvidia-smi`
- [ ] Project files intact: `ls ~/code/local-ai-packaged`
- [ ] Git repository functional: `git status`
- [ ] Docker volumes present: `docker volume ls`
- [ ] NAS mount works: `ls /mnt/nas/PeggysExtraStorage`
- [ ] Python environment intact: `python3 --version`
- [ ] Can start services: `python start_services.py --profile gpu-nvidia`

---

## Cleanup After Successful Migration

**Only after verifying everything works!**

```powershell
# Remove the export backup (frees up 929GB on new drive)
Remove-Item "E:\WSL\Backups\ubuntu-24-04-export.tar"

# Optional: Compact the VHDX to reclaim unused space
wsl --shutdown
Optimize-VHD -Path "E:\WSL\ubuntu-24-04\ext4.vhdx" -Mode Full
```

---

## Rollback Plan (If Something Goes Wrong)

If the migration fails, you can restore from the export:

```powershell
# Unregister the broken import
wsl --unregister ubuntu-24-04

# Re-import from the backup
wsl --import ubuntu-24-04 "E:\WSL\ubuntu-24-04" "E:\WSL\Backups\ubuntu-24-04-export.tar" --version 2

# If export is gone, import from original location (if you kept it)
wsl --import ubuntu-24-04 "E:\WSL\ubuntu-24-04" "C:\OriginalBackupLocation\ubuntu-24-04-export.tar" --version 2
```

---

## Additional Resources

**WSL Documentation:**
- [Basic WSL Commands](https://docs.microsoft.com/en-us/windows/wsl/basic-commands)
- [Advanced WSL Configuration](https://docs.microsoft.com/en-us/windows/wsl/wsl-config)
- [Disk Space Management](https://docs.microsoft.com/en-us/windows/wsl/disk-space)

**Useful Commands:**
```powershell
# Check WSL kernel version
wsl --version

# Update WSL
wsl --update

# Check all registered distributions
wsl -l -v

# Get help
wsl --help
```

---

## Estimated Timeline

1. **Preparation:** 15 minutes
2. **Stop Docker & WSL:** 5 minutes
3. **Export (929GB):** 60-90 minutes
4. **Unregister & Import:** 60-120 minutes
5. **Post-configuration:** 15 minutes
6. **Verification:** 15 minutes

**Total:** 3-4 hours

**Note:** Keep your computer plugged in and don't let it sleep during the process!

---

## Quick Command Reference

```powershell
# Full migration in one script (use with caution!)
# Save as: migrate-wsl.ps1

# Step 1: Prepare
wsl --shutdown
docker stop $(docker ps -aq)

# Step 2: Export
New-Item -ItemType Directory -Path "E:\WSL\Backups" -Force
wsl --export ubuntu-24-04 "E:\WSL\Backups\ubuntu-24-04-export.tar"

# Step 3: Verify export
Get-ChildItem "E:\WSL\Backups\ubuntu-24-04-export.tar"
Read-Host "Press Enter to continue with unregister (DELETES ORIGINAL)"

# Step 4: Unregister
wsl --unregister ubuntu-24-04

# Step 5: Import to new location
New-Item -ItemType Directory -Path "E:\WSL\ubuntu-24-04" -Force
wsl --import ubuntu-24-04 "E:\WSL\ubuntu-24-04" "E:\WSL\Backups\ubuntu-24-04-export.tar" --version 2

# Step 6: Set default user
ubuntu2404.exe config --default-user ghar

Write-Host "Migration complete! Test WSL before cleaning up backup."
```

---

**Last Updated:** October 17, 2025
**Migration Status:** Ready to execute
**Critical:** Create backup before unregistering original distribution!
