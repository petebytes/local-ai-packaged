
```bash
# start kokoru on windows
docker run --gpus all -p 8880:8880 ghcr.io/remsky/kokoro-fastapi-gpu

# start docker containers in WSL
python start_services.py --profile none

# Stop docker containers
docker compose -p localai -f docker-compose.yml -f supabase/docker/docker-compose.yml down
```
