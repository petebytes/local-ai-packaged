#!/usr/bin/env python3
"""
Network Access Configuration for Local AI Services

This script helps configure access to the local AI services from other computers on your network.
It generates the necessary hosts file entries and provides instructions for client configuration.
"""

import socket
import platform
import subprocess
import sys
import argparse

# List of all services with their .lan domains
SERVICES = [
    "n8n.lan",
    "openwebui.lan",
    "kokoro.lan",
    "studio.lan",
    "traefik.lan",
    "comfyui.lan",
    "wan.lan",
    "crawl4ai.lan",
    "supabase.lan",
    "nocodb.lan",
    "raven.lan",
    "lmstudio.lan",
    "whisper.lan",
    "infinitetalk.lan",
    "va.lan"
]

def get_primary_ip():
    """Get the primary network IP address of this machine."""
    try:
        # Create a socket to determine the primary network interface
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        # Fallback to hostname -I on Linux/Mac
        if platform.system() != "Windows":
            try:
                result = subprocess.run(["hostname", "-I"], capture_output=True, text=True)
                ips = result.stdout.strip().split()
                # Filter out localhost and docker IPs
                for ip in ips:
                    if not ip.startswith("127.") and not ip.startswith("172.17.") and not ip.startswith("172.18."):
                        return ip
            except (subprocess.CalledProcessError, OSError):
                pass
        return None

def generate_hosts_entry(ip_address=None):
    """Generate the hosts file entry for all services."""
    if not ip_address:
        ip_address = get_primary_ip()

    if not ip_address:
        print("Error: Could not determine the network IP address.")
        print("Please provide it manually with --ip option.")
        sys.exit(1)

    return f"{ip_address} {' '.join(SERVICES)}"

def generate_client_instructions(ip_address=None):
    """Generate instructions for configuring client machines."""
    hosts_entry = generate_hosts_entry(ip_address)

    instructions = f"""
{'='*60}
NETWORK ACCESS CONFIGURATION
{'='*60}

Your Local AI services are running on: {ip_address or get_primary_ip()}

To access these services from other computers on your network:

1. ADD HOSTS FILE ENTRIES

   On each client computer, add this line to the hosts file:

   {hosts_entry}

   Hosts file locations:
   - Linux/Mac: /etc/hosts
   - Windows: C:\\Windows\\System32\\drivers\\etc\\hosts

   Linux/Mac command:
   sudo sh -c 'echo "{hosts_entry}" >> /etc/hosts'

   Windows (run as Administrator in PowerShell):
   Add-Content -Path "C:\\Windows\\System32\\drivers\\etc\\hosts" -Value "{hosts_entry}"

2. ACCEPT SELF-SIGNED CERTIFICATES

   When you first visit each service, your browser will warn about
   the self-signed certificate. You'll need to:
   - Click "Advanced" or "Show Details"
   - Click "Proceed to site" or "Accept the risk"

3. ACCESS YOUR SERVICES

   After configuration, you can access:
   - https://n8n.lan - n8n workflow automation
   - https://openwebui.lan - Open WebUI (ChatGPT interface)
   - https://studio.lan - Supabase Studio
   - https://kokoro.lan - Kokoro TTS
   - https://comfyui.lan - ComfyUI
   - https://wan.lan - Wan video generation
   - https://crawl4ai.lan - Crawl4AI
   - https://nocodb.lan - NocoDB
   - https://raven.lan - Main dashboard
   - https://lmstudio.lan - LM Studio API
   - https://whisper.lan - WhisperX Transcription
   - https://infinitetalk.lan - InfiniteTalk Video Generation
   - https://va.lan - Virtual Assistant
   - https://traefik.lan - Status page

4. TROUBLESHOOTING

   If you cannot connect:
   - Verify you can ping {ip_address or get_primary_ip()}
   - Check Windows Firewall or other firewall settings
   - Ensure Docker services are running (docker ps)
   - Try accessing directly: https://{ip_address or get_primary_ip()}

{'='*60}
"""
    return instructions

def update_local_hosts(ip_address=None):
    """Update the local hosts file to use the network IP instead of 127.0.0.1."""
    if not ip_address:
        ip_address = get_primary_ip()

    hosts_entry = generate_hosts_entry(ip_address)

    # Determine hosts file location
    if platform.system() == "Windows":
        hosts_file = r"C:\Windows\System32\drivers\etc\hosts"
    else:
        hosts_file = "/etc/hosts"

    print("\nTo update your LOCAL hosts file for network access:")
    print("1. Remove any existing 127.0.0.1 entries for *.lan domains")
    print(f"2. Add this line to {hosts_file}:")
    print(f"   {hosts_entry}\n")

    if platform.system() != "Windows":
        print("You can do this with:")
        print(f"sudo sed -i '/\\.lan/d' {hosts_file}  # Remove existing .lan entries")
        print(f"sudo sh -c 'echo \"{hosts_entry}\" >> {hosts_file}'  # Add new entry")

def create_dnsmasq_config(ip_address=None):
    """Generate dnsmasq configuration for network-wide DNS."""
    if not ip_address:
        ip_address = get_primary_ip()

    config = """
# DNSMasq Configuration for Local AI Services
# Place this in /etc/dnsmasq.d/local-ai.conf

# Define .lan domains
"""
    for service in SERVICES:
        config += f"address=/{service}/{ip_address}\n"

    config += """
# Optional: Set this machine as DNS server for .lan domains
local=/lan/
"""

    print("\n" + "="*60)
    print("OPTIONAL: DNSMasq Configuration")
    print("="*60)
    print("\nFor automatic DNS resolution across your network, you can set up dnsmasq:")
    print("\n1. Install dnsmasq:")
    print("   sudo apt-get install dnsmasq  # Debian/Ubuntu")
    print("   sudo yum install dnsmasq      # RHEL/CentOS")
    print("\n2. Create /etc/dnsmasq.d/local-ai.conf with:")
    print(config)
    print("\n3. Restart dnsmasq:")
    print("   sudo systemctl restart dnsmasq")
    print("\n4. Configure your router to use this machine as DNS server for .lan domains")
    print("   or configure each client to use this machine as DNS server")

def main():
    parser = argparse.ArgumentParser(description="Configure network access for Local AI services")
    parser.add_argument("--ip", help="Manually specify the server IP address")
    parser.add_argument("--dnsmasq", action="store_true", help="Show dnsmasq configuration")
    parser.add_argument("--update-local", action="store_true", help="Show instructions to update local hosts file")
    args = parser.parse_args()

    # Get or detect IP address
    ip_address = args.ip or get_primary_ip()

    if not ip_address:
        print("Error: Could not determine network IP address.")
        print("Please provide it manually with: python configure_network_access.py --ip YOUR_IP")
        sys.exit(1)

    # Always show client instructions
    print(generate_client_instructions(ip_address))

    # Show additional configurations if requested
    if args.update_local:
        update_local_hosts(ip_address)

    if args.dnsmasq:
        create_dnsmasq_config(ip_address)

if __name__ == "__main__":
    main()