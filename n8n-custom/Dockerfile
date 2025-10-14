# Custom n8n Dockerfile with ffmpeg
# Based on official n8n image with added multimedia tools

# Use official n8n image as base
FROM n8nio/n8n:latest

# Switch to root to install packages
USER root

# Install ffmpeg and other useful tools
# - ffmpeg: Audio/video processing
# - ffprobe: Media file inspection (part of ffmpeg package)
RUN apk add --no-cache \
    ffmpeg

# Switch back to node user (UID 1000) for security
USER node

# No need to change CMD or ENTRYPOINT - inherited from base image
