#!/bin/bash

# Function to detect OS
get_os() {
    case "$(uname -s)" in
        Linux*)     echo "Linux";;
        Darwin*)    echo "macOS";;
        MINGW*|CYGWIN*) echo "Windows";;
        *)          echo "Unknown";;
    esac
}

# Function to install on Linux
install_linux() {
    local cert_file="$1"
    if [ -d "/usr/local/share/ca-certificates" ]; then
        # Debian/Ubuntu based
        sudo cp "$cert_file" /usr/local/share/ca-certificates/local-ca.crt
        sudo update-ca-certificates
    elif [ -d "/etc/pki/ca-trust/source/anchors" ]; then
        # RHEL/CentOS/Fedora based
        sudo cp "$cert_file" /etc/pki/ca-trust/source/anchors/local-ca.crt
        sudo update-ca-trust
    else
        echo "Error: Unsupported Linux distribution"
        exit 1
    fi
    echo "CA certificate installed successfully on Linux"
}

# Function to install on macOS
install_macos() {
    local cert_file="$1"
    # Add to System Keychain and trust it
    sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain "$cert_file"
    echo "CA certificate installed successfully on macOS"
}

# Function to install on Windows (requires admin privileges)
install_windows() {
    local cert_file="$1"
    # Convert path to Windows format
    cert_file=$(cygpath -w "$cert_file")
    # Import certificate to Trusted Root Certification Authorities
    powershell -Command "Start-Process certutil -ArgumentList '-addstore', 'ROOT', '$cert_file' -Verb RunAs -Wait"
    echo "CA certificate installed successfully on Windows"
}

# Main script
main() {
    local cert_file="ca-cert/ca.crt"

    # Check if certificate exists
    if [ ! -f "$cert_file" ]; then
        echo "Error: Certificate file not found at $cert_file"
        echo "Please run create-local-ca.sh first"
        exit 1
    fi

    # Get OS type
    OS=$(get_os)
    echo "Detected OS: $OS"

    # Install based on OS type
    case "$OS" in
        "Linux")
            install_linux "$cert_file"
            ;;
        "macOS")
            install_macos "$cert_file"
            ;;
        "Windows")
            install_windows "$cert_file"
            ;;
        *)
            echo "Error: Unsupported operating system"
            exit 1
            ;;
    esac

    echo ""
    echo "Note: For Firefox, you'll need to install the certificate manually:"
    echo "1. Open Firefox"
    echo "2. Go to Settings -> Privacy & Security -> Certificates -> View Certificates"
    echo "3. Go to Authorities tab"
    echo "4. Click Import and select the ca-cert/ca.crt file"
    echo "5. Check 'Trust this CA to identify websites' and click OK"
}

# Run main function
main
