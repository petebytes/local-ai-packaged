#!/bin/bash
# Update all Local AI and Supabase container images

echo "Pulling latest container images for all services..."
docker compose -p localai -f docker-compose.yml -f supabase/docker/docker-compose.yml pull
echo "All images updated. Run './start.sh' to restart with new versions."
