#!/bin/bash
# Stop all Local AI and Supabase services

echo "Stopping all Local AI services..."
docker compose -p localai -f docker-compose.yml -f supabase/docker/docker-compose.yml down
echo "All services stopped."
