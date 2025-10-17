# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is the **Local AI Packaged** repository - a comprehensive self-hosted AI development environment that packages multiple AI services into a unified Docker Compose setup. It's a fork of n8n's AI starter kit enhanced with Supabase integration, HTTPS support, and expanded AI services.

## Common Development Commands

### Starting Services

```bash
# Start with NVIDIA GPU support
python start_services.py --profile gpu-nvidia

# Start with AMD GPU support (Linux only)
python start_services.py --profile gpu-amd

# Start with CPU only
python start_services.py --profile cpu

# Start without external LLM server profile
python start_services.py --profile none

# Start with network access enabled (for access from other computers)
python start_services.py --profile gpu-nvidia --network-access
```

### Network Access Configuration

To enable access from other computers on your network:

```bash
# Generate client configuration instructions
python configure_network_access.py

# Show dnsmasq configuration for network-wide DNS
python configure_network_access.py --dnsmasq

# Show instructions to update local hosts file
python configure_network_access.py --update-local

# Manually specify server IP
python configure_network_access.py --ip 192.168.1.100
```

### Docker Compose Management

```bash
# Stop all services
docker compose -p localai -f docker-compose.yml -f supabase/docker/docker-compose.yml down

# View logs for specific service
docker compose -p localai logs -f [service-name]

# Restart a specific service
docker compose -p localai restart [service-name]

# Pull latest versions of all containers
docker compose -p localai -f docker-compose.yml -f supabase/docker/docker-compose.yml pull
```

### Backup and Restore

```bash
# Manual backup
docker compose exec backup backup

# List available backups
docker compose exec backup ls -l /backup

# Restore from backup
./scripts/restore-backup.sh [backup-filename]
```

### ComfyUI Testing

```bash
# Run all tests (from ComfyUI directory)
cd ComfyUI && pytest

# Run only inference tests
cd ComfyUI && pytest -m inference

# Run only execution tests
cd ComfyUI && pytest -m execution

# Run unit tests
cd ComfyUI && pytest tests-unit/

# Lint check with Ruff
cd ComfyUI && ruff check .
```

### Supabase Development

```bash
# Install dependencies
cd supabase && pnpm install

# Run development server
cd supabase && pnpm dev:studio-local

# Run tests
cd supabase && pnpm test:studio

# Lint and typecheck
cd supabase && pnpm lint
cd supabase && pnpm typecheck

# Format code
cd supabase && pnpm format
```

### WhisperX Transcription

```bash
# Transcribe an audio/video file with default settings (large-v3 model)
curl -X POST https://whisper.lan/transcribe \
  -F "file=@/path/to/audio.mp3" \
  -F "model=large-v3"

# Transcribe with speaker diarization (requires HF_TOKEN in .env)
curl -X POST https://whisper.lan/transcribe \
  -F "file=@/path/to/audio.mp3" \
  -F "model=large-v3" \
  -F "enable_diarization=true" \
  -F "min_speakers=2" \
  -F "max_speakers=4"

# Transcribe with specific language
curl -X POST https://whisper.lan/transcribe \
  -F "file=@/path/to/audio.mp3" \
  -F "model=large-v3" \
  -F "language=en"

# Use faster large-v3-turbo model (6x faster, similar accuracy)
curl -X POST https://whisper.lan/transcribe \
  -F "file=@/path/to/audio.mp3" \
  -F "model=large-v3-turbo"

# List available models
curl https://whisper.lan/models

# View logs
docker compose -p localai logs -f whisperx
```

### Virtual Assistant

```bash
# Access the web interface
# Open your browser to https://va.lan

# View service logs
docker compose -p localai logs -f virtual-assistant-web
docker compose -p localai logs -f riva-asr
docker compose -p localai logs -f riva-tts
docker compose -p localai logs -f audio2face

# The Virtual Assistant includes:
# - Browser-based visual assistant with webcam/screen sharing
# - NVIDIA Riva ASR for speech recognition (gRPC port 50051, HTTP port 9000)
# - NVIDIA Riva TTS for text-to-speech (gRPC port 50052, HTTP port 9001)
# - NVIDIA Audio2Face for avatar animation (HTTP port 8000)
# - Real-time WebSocket communication for video/audio streaming
```

## High-Level Architecture

### Service Orchestration

The system uses a unified Docker Compose project name (`localai`) to manage two main stacks:

1. **Supabase Stack** (`supabase/docker/docker-compose.yml`):
   - PostgreSQL database with logical replication
   - Kong API gateway for authentication and routing
   - GoTrue for authentication services
   - PostgREST for RESTful API
   - Realtime for WebSocket connections
   - Storage API for file management
   - Studio for database management UI
   - Vector database capabilities via pgvector

2. **AI Services Stack** (`docker-compose.yml`):
   - **n8n**: Low-code workflow automation with 400+ integrations
   - **LM Studio**: Local LLM server with OpenAI-compatible API
   - **Open WebUI**: ChatGPT-like interface for local models
   - **ComfyUI**: Visual node-based Stable Diffusion workflow builder
   - **WhisperX**: Audio/video transcription with word-level timestamps and speaker diarization
   - **Virtual Assistant**: Browser-based visual assistant with NVIDIA Riva ASR/TTS and Audio2Face
   - **Flowise**: No-code AI agent builder
   - **Qdrant**: High-performance vector database for RAG
   - **Nginx**: Reverse proxy providing HTTPS termination

### Networking Architecture

- All services run on a shared Docker network (`localai`)
- Nginx provides SSL termination and reverse proxy for all services
- Services communicate internally via Docker service names
- External access via `.lan` domains with self-signed certificates
- Ports are mapped through docker-compose for local development
- Network access from other computers requires hosts file configuration
- Use `configure_network_access.py` to set up remote access

### Data Persistence

- Docker volumes for each service's data persistence
- Automated daily backups via `offen/docker-volume-backup`
- Shared volume (`/data/shared`) for n8n file access
- Database stored in Supabase's PostgreSQL instance

### Security Considerations

- Environment-based secret management via `.env` file
- JWT authentication between services
- Self-signed SSL certificates for local HTTPS
- Isolated Docker network for service communication
- Configurable authentication for each service

## Key Implementation Details

### Service Startup Sequence

The `start_services.py` script orchestrates startup:
1. Checks and prepares environment variables
2. Clones/updates Supabase repository if needed
3. Generates SSL certificates if missing
4. Starts Supabase services first
5. Waits for database initialization
6. Starts AI services with selected GPU profile
7. Performs health checks on all services

### GPU Support Profiles

- **gpu-nvidia**: Uses NVIDIA GPU via Docker GPU runtime
- **gpu-amd**: AMD GPU support on Linux via ROCm
- **cpu**: CPU-only mode for systems without GPU
- **none**: Minimal profile without additional LLM servers

### Inter-Service Communication

- n8n connects to LM Studio at `http://localhost:1234` (or via https://lmstudio.lan)
- WhisperX API accessible at `http://whisperx:8000`
- Virtual Assistant web service connects to NVIDIA services:
  - Riva ASR at `riva-asr:50051` (gRPC) and `riva-asr:9000` (HTTP)
  - Riva TTS at `riva-tts:50052` (gRPC) and `riva-tts:9001` (HTTP)
  - Audio2Face at `http://audio2face:8000`
- Database connections use `db` as hostname (Supabase PostgreSQL)
- Qdrant accessible at `http://qdrant:6333`
- All services resolve via Docker's internal DNS

### Backup Strategy

- Automated daily backups at midnight
- 7-day retention policy (configurable)
- Non-disruptive backup process
- Includes all Docker volumes and PostgreSQL dumps
- Compressed tar.gz format with timestamps

## Working with Specific Components

### When modifying Docker configurations:
- Always use the unified project name `localai`
- Test changes with `docker compose config` first
- Ensure volumes are properly mapped for persistence

### When adding new AI services:
- Add service definition to `docker-compose.yml`
- Configure Nginx reverse proxy in `nginx/nginx.conf`
- Add domain to hosts file update in `start_services.py`
- Document service URLs and credentials

### When working with ComfyUI:
- Test changes with pytest markers for targeted testing
- Follow existing code style (check with Ruff)
- Ensure GPU compatibility for model operations

### When modifying Supabase:
- Use pnpm for package management
- Run tests before committing changes
- Maintain compatibility with existing database schema

## Environment Configuration

Critical environment variables that must be set:
- `N8N_ENCRYPTION_KEY`: n8n data encryption
- `N8N_USER_MANAGEMENT_JWT_SECRET`: n8n authentication
- `POSTGRES_PASSWORD`: Database password
- `JWT_SECRET`: Supabase JWT secret (32+ chars)
- `ANON_KEY`: Supabase anonymous key
- `SERVICE_ROLE_KEY`: Supabase service role key
- `POOLER_TENANT_ID`: Database pooler configuration
- `HF_TOKEN`: HuggingFace token for WhisperX speaker diarization (optional)
- `NGC_API_KEY`: NVIDIA NGC API key for Riva and Audio2Face services (required for Virtual Assistant)

## Service Access URLs

After starting services, access them at:
- Main Dashboard: https://raven.lan
- n8n: https://n8n.lan
- Open WebUI: https://openwebui.lan
- Supabase Studio: https://studio.lan
- ComfyUI: https://comfyui.lan
- WhisperX Transcription: https://whisper.lan
- Virtual Assistant: https://va.lan
- NocoDB: https://nocodb.lan
- Crawl4AI: https://crawl4ai.lan
- Qdrant: https://qdrant.lan
- LM Studio: https://lmstudio.lan
- Kokoro TTS: https://kokoro.lan
- Traefik Dashboard: https://traefik.lan

### Accessing from Other Computers

1. Run `python configure_network_access.py` on the server
2. Follow the generated instructions to configure client machines
3. Add the provided hosts file entry to each client computer
4. Accept self-signed certificates when first accessing each service