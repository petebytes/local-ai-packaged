# Video Transcription Workflows for n8n + WhisperX

Two n8n workflows for transcribing videos using WhisperX with word-level timestamps and speaker diarization.

## Available Workflows

### 1. **video-transcription-simple.json** (Recommended)
- Uses `curl` via Execute Command for reliable file uploads
- Simpler, more robust
- **Start with this one**

### 2. **video-transcription-whisperx.json** (Advanced)
- Uses n8n HTTP Request nodes
- More n8n-native approach
- May have issues with multipart/form-data uploads

## Features

✅ **Automatic video download** from URL
✅ **Audio extraction** using ffmpeg (16kHz mono WAV for optimal quality)
✅ **WhisperX transcription** with large-v3 model
✅ **Speaker diarization** - identifies who's speaking when
✅ **Multiple output formats** - Plain text, SRT subtitles, WebVTT
✅ **Automatic cleanup** - removes temporary files
✅ **Error handling** - Retry logic with exponential backoff

## Quick Start

1. **Import the simple workflow** into n8n
2. **Fix permissions**: `sudo chown -R 1000:1000 ./shared`
3. **Rebuild n8n**:
   ```bash
   docker compose -p localai stop n8n
   docker compose -p localai build n8n
   docker compose -p localai up -d n8n
   ```
4. **Test with a sample video**:
   - Open the workflow
   - Click "Execute Workflow"
   - Provide test input:
   ```json
   {
     "video_url": "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4",
     "language": "en",
     "model": "base"
   }
   ```
   - Watch it process!

## Installation

### 1. Import the Workflow

1. Open n8n at https://n8n.lan
2. Click the **+** button → **Import from File**
3. Select `video-transcription-whisperx.json`
4. Click **Import**

### 2. Enable Speaker Diarization (Optional)

For speaker identification, add your HuggingFace token:

1. Get a token from https://huggingface.co/settings/tokens
2. Add to `.env` file in the project root:
   ```bash
   HF_TOKEN=your_hf_token_here
   ```
3. Restart WhisperX:
   ```bash
   docker compose -p localai restart whisperx
   ```

## Usage

### Manual Execution

1. Open the workflow in n8n
2. Click **Execute Workflow** button
3. In the "Manual Trigger" node input, provide:
   ```json
   {
     "video_url": "https://example.com/video.mp4",
     "language": "en"
   }
   ```
4. Click **Execute Node**

### Webhook/API Execution

Add a Webhook trigger node at the start to allow external calls:

```bash
curl -X POST https://n8n.lan/webhook/transcribe-video \
  -H "Content-Type: application/json" \
  -d '{
    "video_url": "https://example.com/sample.mp4",
    "language": "en"
  }'
```

## Workflow Steps

1. **Manual Trigger** - Accepts video URL and optional language
2. **Download Video** - Downloads video from provided URL (30s timeout)
3. **Write Video to Shared** - Saves to `/data/shared/` with timestamp
4. **Prepare File Paths** - Generates audio output path
5. **Extract Audio with FFmpeg** - Converts to 16kHz mono WAV
6. **Read Audio File** - Loads audio as binary data
7. **Transcribe with WhisperX** - Sends to WhisperX API (1hr timeout)
8. **Format Transcription Results** - Generates SRT, VTT, and formatted text
9. **Cleanup Files** - Removes temporary video and audio files

## Output Format

The workflow outputs:

```json
{
  "transcription": "[0.00s - 5.23s] Speaker_0: Hello, welcome to...\n[5.23s - 12.45s] Speaker_1: Thank you for having me...",
  "srtSubtitles": "1\n00:00:00,000 --> 00:00:05,230\nHello, welcome to...\n\n2\n00:00:05,230 --> 00:00:12,450\nThank you for having me...",
  "vttSubtitles": "WEBVTT\n\n1\n00:00:00.000 --> 00:00:05.230\nHello, welcome to...",
  "language": "en",
  "segmentCount": 42,
  "rawResponse": { ... }
}
```

## Configuration Options

### Model Selection

Edit the "Transcribe with WhisperX" node to change models:

- `tiny` - Fastest, least accurate
- `base` - Good balance for quick transcription
- `small` - Better accuracy
- `medium` - High accuracy
- `large-v3` - Best accuracy (default)
- `large-v3-turbo` - 6x faster than large-v3, similar quality

### Language Detection

Supported languages: en, es, fr, de, it, pt, nl, pl, ru, zh, ja, ko, and 90+ more

Set to `auto` or omit for automatic detection.

### Speaker Diarization

In the "Transcribe with WhisperX" node parameters:
- `enable_diarization`: true/false
- `min_speakers`: Minimum number of speakers (optional)
- `max_speakers`: Maximum number of speakers (optional)

## Troubleshooting

### "FFmpeg not found" error

Rebuild n8n with the custom Dockerfile:
```bash
docker compose -p localai stop n8n
docker compose -p localai build n8n
docker compose -p localai up -d n8n
```

### "Permission denied" writing to /data/shared

Fix shared directory permissions:
```bash
sudo chown -R 1000:1000 ./shared
```

### WhisperX timeout for long videos

Increase timeout in "Transcribe with WhisperX" node:
- Current: 3600000ms (1 hour)
- For 2-hour videos: 7200000ms (2 hours)

### Large video download fails

Increase n8n payload size in docker-compose.yml:
```yaml
environment:
  - N8N_PAYLOAD_SIZE_MAX=200
```

## Advanced Usage

### Batch Processing

To process multiple videos:
1. Add a "Loop Over Items" or "Split in Batches" node after the trigger
2. Process videos one at a time to avoid memory issues
3. Add delays between batches using "Wait" node

### Save Subtitles to Files

Add "Write File" nodes after "Format Transcription Results":

**For SRT:**
- File Name: `={{ $('Prepare File Paths').item.json.audioPath.replace('.wav', '.srt') }}`
- Data: `={{ $json.srtSubtitles }}`

**For VTT:**
- File Name: `={{ $('Prepare File Paths').item.json.audioPath.replace('.wav', '.vtt') }}`
- Data: `={{ $json.vttSubtitles }}`

### Email Results

Add a "Send Email" node at the end with the transcription results attached.

### Store in Database

Add a database node (PostgreSQL, MongoDB, etc.) to store:
- Video URL
- Transcription text
- Timestamp
- Language
- Speaker count

## Performance Tips

1. **Use large-v3-turbo** for faster processing with minimal accuracy loss
2. **Disable diarization** if you don't need speaker identification (2-3x faster)
3. **Pre-process audio** - If you already have audio files, skip the ffmpeg step
4. **Batch similar videos** - Process videos in the same language together
5. **Monitor GPU usage** - Check `docker stats whisperx` during processing

## Cost Considerations

This workflow runs entirely locally with no API costs:
- ✅ No OpenAI Whisper API charges
- ✅ No cloud transcription fees
- ✅ Uses your RTX 3090s for processing

## Support

For issues:
1. Check WhisperX logs: `docker compose -p localai logs -f whisperx`
2. Check n8n logs: `docker compose -p localai logs -f n8n`
3. Verify shared volume: `ls -la ./shared`
4. Test WhisperX directly: `curl https://whisper.lan/health`
