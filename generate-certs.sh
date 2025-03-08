#!/bin/bash
# Script to generate self-signed SSL certificates for local development

# Create certs directory if it doesn't exist
mkdir -p ./certs

# Generate a self-signed wildcard certificate for *.lan domains
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout ./certs/local-key.pem \
  -out ./certs/local-cert.pem \
  -subj "/CN=*.lan" \
  -addext "subjectAltName = DNS:*.lan,DNS:localhost"

echo "Self-signed certificates generated successfully in ./certs/"
echo "  - Certificate: ./certs/local-cert.pem"
echo "  - Private Key: ./certs/local-key.pem"
