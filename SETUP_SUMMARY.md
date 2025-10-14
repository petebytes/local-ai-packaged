# Setup Summary: WhisperX + n8n Integration

## What Was Built

### 1. WhisperX Service ✅
- **Custom Dockerfile** (`whisperx/Dockerfile`) - Built from official sources
- **FastAPI Server** (`whisperx/api_server.py`) - REST API for transcription
- **Docker Integration** - Configured with both RTX 3090s
- **Nginx Proxy** - Accessible at `https://whisper.lan`

### 2. Enhanced n8n Service ✅
- **Custom n8n Dockerfile** (`n8n-custom/Dockerfile`) - Includes ffmpeg
- **Shared Volume** - Mounted at `/data/shared` for file exchange
- **Increased Payload Size** - Set to 100MB for large files

### 3. n8n Workflows ✅
- **Simple Workflow** (`n8n/workflows/video-transcription-simple.json`) - Uses curl
- **Advanced Workflow** (`n8n/workflows/video-transcription-whisperx.json`) - Uses HTTP nodes
- **Documentation** (`n8n/workflows/README.md`) - Complete usage guide

## What You Need to Do

### Step 1: Fix Shared Directory Permissions

```bash
cd /home/ghar/code/local-ai-packaged
sudo chown -R 1000:1000 ./shared
```

### Step 2: Rebuild n8n with ffmpeg

```bash
docker compose -p localai stop n8n
docker compose -p localai build n8n
docker compose -p localai up -d n8n
```

### Step 3: Build and Start WhisperX

```bash
# Build WhisperX image (this will take 5-10 minutes)
docker compose -p localai build whisperx

# Start WhisperX
docker compose -p localai up -d whisperx
```

### Step 4: Update Hosts File (if needed)

If `whisper.lan` isn't in your hosts file yet:

**Windows (as Administrator):**
```powershell
Add-Content C:\Windows\System32\drivers\etc\hosts "127.0.0.1 whisper.lan"
```

**Linux/WSL:**
```bash
echo "127.0.0.1 whisper.lan" | sudo tee -a /etc/hosts
```

### Step 5: Test WhisperX

```bash
# Check health
curl https://whisper.lan/health

# List available models
curl https://whisper.lan/models
```

### Step 6: Import n8n Workflow

1. Open https://n8n.lan
2. Click **+** → **Import from File**
3. Select `n8n/workflows/video-transcription-simple.json`
4. Click **Import**

### Step 7: Test the Workflow

1. Open the imported workflow in n8n
2. Click **Execute Workflow**
3. Provide test data:
   ```json
   {
     "video_url": "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4",
     "language": "en",
     "model": "base"
   }
   ```
4. Click **Execute Node** and watch it work!

## Optional: Enable Speaker Diarization

For speaker identification, you need a HuggingFace token:

1. Get token from https://huggingface.co/settings/tokens
2. Add to `.env`:
   ```bash
   echo "HF_TOKEN=your_token_here" >> .env
   ```
3. Restart WhisperX:
   ```bash
   docker compose -p localai restart whisperx
   ```

## File Locations

```
/home/ghar/code/local-ai-packaged/
├── whisperx/
│   ├── Dockerfile              # WhisperX container build
│   └── api_server.py           # FastAPI transcription service
├── n8n-custom/
│   └── Dockerfile              # n8n with ffmpeg
├── n8n/workflows/
│   ├── video-transcription-simple.json      # Recommended workflow
│   ├── video-transcription-whisperx.json    # Advanced workflow
│   └── README.md                             # Usage documentation
├── docker-compose.yml          # Updated with whisperx service
├── nginx/nginx.conf            # Updated with whisper.lan
├── start_services.py           # Updated with whisper.lan
└── CLAUDE.md                   # Updated documentation
```

## Service URLs

After starting:
- **WhisperX API**: https://whisper.lan
- **n8n Workflows**: https://n8n.lan
- **API Docs**: https://whisper.lan/docs (FastAPI auto-docs)

## Verification Commands

```bash
# Check all services
docker compose -p localai ps

# Check WhisperX logs
docker compose -p localai logs -f whisperx

# Check n8n logs
docker compose -p localai logs -f n8n

# Check GPU usage
docker stats whisperx

# Test ffmpeg in n8n
docker exec n8n ffmpeg -version

# Check shared directory
ls -la ./shared
```

## Performance Expectations

With your dual RTX 3090s:

- **Model**: large-v3
- **Speed**: ~10-20x realtime (e.g., 1 hour video → 3-6 minutes)
- **VRAM**: ~10GB per GPU
- **Accuracy**: Best available
- **Alternative**: Use `large-v3-turbo` for 6x faster (1 hour → 30-60 seconds)

## Troubleshooting

### WhisperX won't start
```bash
docker compose -p localai logs whisperx
# Check for CUDA/GPU errors
nvidia-smi  # Should show both RTX 3090s
```

### n8n can't write to /data/shared
```bash
sudo chown -R 1000:1000 ./shared
docker compose -p localai restart n8n
```

### ffmpeg not found in n8n
```bash
docker exec n8n which ffmpeg
# If empty, rebuild: docker compose -p localai build n8n
```

### Transcription times out
Edit the workflow's "Transcribe with Curl" node:
- Change `--max-time 3600` to `--max-time 7200` (2 hours)

## Next Steps

1. **Complete the setup steps above** ✓
2. **Test with a short video** to verify everything works
3. **Try speaker diarization** with a multi-speaker video
4. **Integrate with other n8n workflows** (webhooks, scheduling, etc.)
5. **Explore batch processing** for multiple videos

## Support

- WhisperX docs: https://github.com/m-bain/whisperX
- n8n docs: https://docs.n8n.io
- FastAPI docs: https://whisper.lan/docs

All components are built from official sources and run locally - no external API costs!
