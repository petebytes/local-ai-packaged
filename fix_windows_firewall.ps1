# PowerShell script to configure Windows Firewall for Local AI services
# Must be run as Administrator

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Windows Firewall Configuration for Local AI" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# Check if running as Administrator
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))
{
    Write-Host "This script must be run as Administrator!" -ForegroundColor Red
    Write-Host "Please right-click and select 'Run as Administrator'" -ForegroundColor Yellow
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host "Running as Administrator ✓" -ForegroundColor Green
Write-Host ""

# Remove existing rules
Write-Host "Removing any existing Local AI firewall rules..." -ForegroundColor Yellow
Remove-NetFirewallRule -DisplayName "Local AI HTTP Inbound" -ErrorAction SilentlyContinue
Remove-NetFirewallRule -DisplayName "Local AI HTTPS Inbound" -ErrorAction SilentlyContinue

# Create HTTP rule (port 80)
Write-Host "Creating firewall rule for HTTP (port 80)..." -ForegroundColor Yellow
New-NetFirewallRule -DisplayName "Local AI HTTP Inbound" `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort 80 `
    -Action Allow `
    -Profile Private,Public `
    -Enabled True | Out-Null

Write-Host "✓ HTTP rule created" -ForegroundColor Green

# Create HTTPS rule (port 443)
Write-Host "Creating firewall rule for HTTPS (port 443)..." -ForegroundColor Yellow
New-NetFirewallRule -DisplayName "Local AI HTTPS Inbound" `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort 443 `
    -Action Allow `
    -Profile Private,Public `
    -Enabled True | Out-Null

Write-Host "✓ HTTPS rule created" -ForegroundColor Green
Write-Host ""

# Verify the rules
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Verifying firewall rules:" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

$rules = Get-NetFirewallRule -DisplayName "Local AI*" | Get-NetFirewallPortFilter

foreach ($rule in $rules) {
    Write-Host "Port $($rule.LocalPort): " -NoNewline
    Write-Host "Allowed ✓" -ForegroundColor Green
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "Setup Complete!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Your services should now be accessible from other devices!"
Write-Host ""
Write-Host "Test from your wireless device:" -ForegroundColor Yellow
Write-Host "  https://192.168.3.34" -ForegroundColor Cyan
Write-Host "  https://raven.lan (if hosts file is configured)" -ForegroundColor Cyan
Write-Host ""
Write-Host "Note: You will need to accept the self-signed certificate warning." -ForegroundColor Yellow
Write-Host ""
Read-Host "Press Enter to exit"