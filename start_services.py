#!/usr/bin/env python3
"""
start_services.py

This script starts the Supabase stack first, waits for it to initialize, and then starts
the local AI stack. Both stacks use the same Docker Compose project name ("localai")
so they appear together in Docker Desktop.
"""

import os
import subprocess
import shutil
import time
import argparse
import platform
import sys

def run_command(cmd, cwd=None):
    """Run a shell command and print it."""
    print("Running:", " ".join(cmd))
    subprocess.run(cmd, cwd=cwd, check=True)

def clone_supabase_repo():
    """Clone the Supabase repository using sparse checkout if not already present."""
    if not os.path.exists("supabase"):
        print("Cloning the Supabase repository...")
        run_command([
            "git", "clone", "--filter=blob:none", "--no-checkout",
            "https://github.com/supabase/supabase.git"
        ])
        os.chdir("supabase")
        run_command(["git", "sparse-checkout", "init", "--cone"])
        run_command(["git", "sparse-checkout", "set", "docker"])
        run_command(["git", "checkout", "master"])
        os.chdir("..")
    else:
        print("Supabase repository already exists, updating...")
        os.chdir("supabase")
        run_command(["git", "pull"])
        os.chdir("..")

def prepare_supabase_env():
    """Copy .env to .env in supabase/docker."""
    env_path = os.path.join("supabase", "docker", ".env")
    env_example_path = os.path.join(".env")
    print("Copying .env in root to .env in supabase/docker...")
    shutil.copyfile(env_example_path, env_path)

def stop_existing_containers():
    """Stop and remove existing containers for our unified project ('localai')."""
    print("Stopping and removing existing containers for the unified project 'localai'...")
    run_command([
        "docker", "compose",
        "-p", "localai",
        "-f", "docker-compose.yml",
        "-f", "supabase/docker/docker-compose.yml",
        "down"
    ])

def start_supabase():
    """Start the Supabase services (using its compose file)."""
    print("Starting Supabase services...")
    run_command([
        "docker", "compose", "-p", "localai", "-f", "supabase/docker/docker-compose.yml", "up", "-d"
    ])

def generate_certificates():
    """Generate self-signed certificates if they don't exist."""
    if not os.path.exists("certs/local-cert.pem"):
        print("Generating self-signed certificates...")
        os.makedirs("certs", exist_ok=True)
        run_command([
            "openssl", "req", "-x509", "-nodes", "-days", "365", "-newkey", "rsa:2048",
            "-keyout", "certs/local-key.pem",
            "-out", "certs/local-cert.pem",
            "-subj", "/CN=*.lan",
            "-addext", "subjectAltName = DNS:*.lan,DNS:localhost"
        ])
        print("Certificates generated successfully!")
    else:
        print("Certificates already exist.")

def update_hosts_file():
    """Update hosts file with local domain entries."""
    hosts_entries = [
        "n8n.lan", "openwebui.lan", "kokoro.lan", "studio.lan", "traefik.lan", "comfyui.lan", "crawl4ai.lan"
    ]

    # Determine hosts file location based on OS
    if platform.system() == "Windows":
        hosts_file = r"C:\Windows\System32\drivers\etc\hosts"
    else:  # Linux/macOS
        hosts_file = "/etc/hosts"

    try:
        with open(hosts_file, 'r') as f:
            content = f.read()

        need_update = False
        for entry in hosts_entries:
            if entry not in content:
                need_update = True
                break

        if need_update:
            entries_line = "127.0.0.1 " + " ".join(hosts_entries)
            print("\n===== HOSTS FILE UPDATE NEEDED =====")
            print(f"Please update your hosts file ({hosts_file}) to include:")
            print(entries_line)
            print("\nThis may require administrator/root privileges.")

            # On Linux/macOS, offer additional guidance
            if platform.system() != "Windows":
                print("\nYou can add this by running:")
                print(f"sudo sh -c 'echo \"{entries_line}\" >> {hosts_file}'")
            else:
                print("\nYou'll need to edit the hosts file as Administrator.")
            print("====================================\n")
        else:
            print("Hosts file already contains all required entries.")
    except Exception as e:
        print(f"Error checking hosts file: {e}")
        print("Please manually update your hosts file.")

def fix_open_webui_read_aloud():
    """Fix the Read Aloud feature in Open WebUI."""
    print("Checking if Open WebUI Read Aloud feature needs fixing...")

    # Wait a bit for the container to start
    time.sleep(5)

    # Check if the Open WebUI container is running
    try:
        container_id = subprocess.check_output(
            ["docker", "ps", "-q", "-f", "name=open-webui"],
            text=True
        ).strip()

        if not container_id:
            print("Open WebUI container is not running yet, skipping fix.")
            return

        # Get the original file content
        orig_content = subprocess.check_output(
            ["docker", "exec", container_id, "cat", "/app/backend/open_webui/routers/audio.py"],
            text=True
        )

        # Check if the file contains the error
        if "status_code=getattr(r, \"status\", 500)," in orig_content:
            print("Fixing Open WebUI Read Aloud error handling...")

            # Make a backup of the original file
            subprocess.run(
                ["docker", "exec", container_id, "cp",
                 "/app/backend/open_webui/routers/audio.py",
                 "/app/backend/open_webui/routers/audio.py.bak"],
                check=True
            )

            # Fix the variable scope issue
            fixed_content = orig_content.replace(
                'status_code=getattr(r, "status", 500),',
                'status_code=500,  # Fixed: removed reference to undefined variable r'
            )

            # Write the fixed content to a temporary file
            with open("/tmp/fixed_audio.py", "w") as f:
                f.write(fixed_content)

            # Copy the fixed file back to the container
            subprocess.run(
                ["docker", "cp", "/tmp/fixed_audio.py",
                 f"{container_id}:/app/backend/open_webui/routers/audio.py"],
                check=True
            )

            print("Fix applied successfully! The Read Aloud feature should now work.")
        else:
            print("The Read Aloud feature is already fixed or has been modified.")

    except subprocess.CalledProcessError as e:
        print(f"Error checking Open WebUI container: {e}")
        print("Skipping Read Aloud fix.")

def start_local_ai(profile=None):
    """Start the local AI services (using its compose file)."""
    print("Starting local AI services...")
    cmd = ["docker", "compose", "-p", "localai"]
    if profile and profile != "none":
        cmd.extend(["--profile", profile])
    cmd.extend(["-f", "docker-compose.yml", "up", "-d"])
    run_command(cmd)

    # Fix the Read Aloud feature in Open WebUI
    fix_open_webui_read_aloud()

def start_comfyui():
    """Start the ComfyUI service."""
    print("Starting ComfyUI service...")
    try:
        run_command(["python", "main.py"], cwd="ComfyUI")
    except subprocess.CalledProcessError as e:
        print(f"Error starting ComfyUI: {e}")
        print("Please ensure ComfyUI is properly installed.")

def main():
    parser = argparse.ArgumentParser(description='Start the local AI and Supabase services.')
    parser.add_argument('--profile', choices=['cpu', 'gpu-nvidia', 'gpu-amd', 'none'], default='cpu',
                      help='Profile to use for Docker Compose (default: cpu)')
    parser.add_argument('--skip-certs', action='store_true',
                      help='Skip certificate generation')
    args = parser.parse_args()

    # Generate HTTPS certificates if needed
    if not args.skip_certs:
        generate_certificates()

    # Update hosts file for local domains
    update_hosts_file()

    clone_supabase_repo()
    prepare_supabase_env()
    stop_existing_containers()

    # Start Supabase first
    start_supabase()

    # Give Supabase some time to initialize
    print("Waiting for Supabase to initialize...")
    time.sleep(10)

    # Then start the local AI services
    start_local_ai(args.profile)

    # Start ComfyUI service
    start_comfyui()

    print("\n===== HTTPS SETUP COMPLETE =====")
    print("Your services are now available via HTTPS at:")
    print("- https://traefik.lan - Traefik Dashboard")
    print("- https://n8n.lan - n8n")
    print("- https://openwebui.lan - Open WebUI")
    print("- https://kokoro.lan - Kokoro")
    print("- https://studio.lan - Supabase Studio")
    print("\nNote: You may need to accept browser security warnings for self-signed certificates")
    print("==============================")

if __name__ == "__main__":
    main()
