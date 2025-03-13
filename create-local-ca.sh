#!/bin/bash

# Function to ask yes/no question
ask_yes_no() {
    while true; do
        read -p "$1 [y/N] " yn
        case $yn in
            [Yy]* ) return 0;;
            [Nn]* | "" ) return 1;;
            * ) echo "Please answer yes or no.";;
        esac
    done
}

# Create directories for CA and domain certificates
mkdir -p ca-cert
cd ca-cert

# Generate Root CA private key
openssl genrsa -out ca.key 4096

# Generate Root CA certificate
openssl req -x509 -new -nodes -key ca.key -sha256 -days 3650 -out ca.crt \
    -subj "/C=US/ST=Local/L=Local/O=Local Network/OU=IT/CN=Local Network Root CA"

# Generate private key for wildcard certificate
openssl genrsa -out local.key 2048

# Create certificate signing request (CSR) for wildcard domain
openssl req -new -key local.key -out local.csr \
    -subj "/C=US/ST=Local/L=Local/O=Local Network/OU=IT/CN=*.lan"

# Create config file for SAN
cat > local.ext << EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = *.lan
DNS.2 = n8n.lan
DNS.3 = flowise.lan
DNS.4 = openwebui.lan
DNS.5 = kokoro.lan
DNS.6 = qdrant.lan
DNS.7 = ollama.lan
DNS.8 = supabase.lan
DNS.9 = nocodb.lan
DNS.10 = comfyui.lan
DNS.11 = traefik.lan
DNS.12 = raven.lan
EOF

# Generate signed certificate
openssl x509 -req -in local.csr -CA ca.crt -CAkey ca.key \
    -CAcreateserial -out local.crt -days 365 -sha256 \
    -extfile local.ext

# Combine certificate and key into PEM files for nginx
cat local.crt > local-cert.pem
cat local.key > local-key.pem

# Create directory for nginx if it doesn't exist
cd ..
mkdir -p certs
cp ca-cert/local-cert.pem certs/
cp ca-cert/local-key.pem certs/

echo "Certificates generated successfully!"
echo "----------------------------------------"
echo "Root CA certificate: ca-cert/ca.crt"
echo "Domain certificate: certs/local-cert.pem"
echo "Domain private key: certs/local-key.pem"
echo "----------------------------------------"

# Check if install-ca.sh exists and offer to run it
if [ -f "install-ca.sh" ]; then
    if ask_yes_no "Would you like to install the CA certificate on this system now?"; then
        chmod +x install-ca.sh
        ./install-ca.sh
    else
        echo "Manual Installation Instructions:"
        echo ""
        echo "Windows Manual Installation:"
        echo "Method 1 - Using Certificate Manager:"
        echo "1. Double-click the certificate file (ca.crt)"
        echo "2. Click 'Install Certificate'"
        echo "3. Select 'Local Machine' (requires admin privileges)"
        echo "4. Click 'Yes' on the UAC prompt"
        echo "5. Choose 'Place all certificates in the following store'"
        echo "6. Click 'Browse'"
        echo "7. Select 'Trusted Root Certification Authorities'"
        echo "8. Click 'OK', then 'Next', then 'Finish'"
        echo ""
        echo "Method 2 - Using MMC:"
        echo "1. Press Win+R, type 'mmc' and press Enter"
        echo "2. Go to File → Add/Remove Snap-in"
        echo "3. Select 'Certificates' → 'Add'"
        echo "4. Choose 'Computer account' → 'Local computer' → 'Finish'"
        echo "5. Click 'OK'"
        echo "6. Expand 'Certificates' → 'Trusted Root Certification Authorities'"
        echo "7. Right-click 'Certificates' folder → All Tasks → Import"
        echo "8. Browse to ca.crt and complete the wizard"
        echo ""
        echo "macOS Manual Installation:"
        echo "1. Double-click the certificate file (ca.crt)"
        echo "2. Keychain Access will open automatically"
        echo "3. Add the certificate to the System keychain (not login)"
        echo "4. Enter your administrator password"
        echo "5. Double-click the imported certificate"
        echo "6. Expand the 'Trust' section"
        echo "7. Set 'When using this certificate' to 'Always Trust'"
        echo "8. Close the certificate window (enter admin password again)"
        echo ""
        echo "Linux Manual Installation:"
        echo "1. Copy the certificate:"
        echo "   sudo cp ca.crt /usr/local/share/ca-certificates/"
        echo "2. Update the certificate store:"
        echo "   sudo update-ca-certificates"
        echo ""
        echo "Firefox (All Systems):"
        echo "1. Open Firefox"
        echo "2. Go to Settings → Privacy & Security → Certificates"
        echo "3. Click 'View Certificates'"
        echo "4. Go to 'Authorities' tab"
        echo "5. Click 'Import' and select ca.crt"
        echo "6. Check 'Trust this CA to identify websites'"
        echo "7. Click 'OK'"
    fi
else
    echo "Warning: install-ca.sh not found. Using manual installation instructions."
    # (Same manual instructions as above)
fi

echo ""
echo "After installing the certificate, restart your nginx container:"
echo "docker-compose restart nginx"
echo ""
echo "Note: Chrome, Edge, and Brave will use the system certificate store automatically"
echo "      after installing the certificate (except Brave on Linux)."
