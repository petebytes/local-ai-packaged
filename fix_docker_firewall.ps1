# PowerShell script to fix Docker Desktop firewall blocking
# Run as Administrator

Write-Host "Fixing Docker Desktop Firewall Rules..." -ForegroundColor Cyan

# Remove blocking Docker Desktop Backend rules
Write-Host "Removing Docker Desktop blocking rules..." -ForegroundColor Yellow
Get-NetFirewallRule -DisplayName "Docker Desktop Backend" | Where-Object {$_.Action -eq "Block"} | Remove-NetFirewallRule

# Create specific allow rules for Docker/nginx ports with higher priority
Write-Host "Creating high-priority allow rules..." -ForegroundColor Yellow

# Remove old rules first
Remove-NetFirewallRule -DisplayName "Docker HTTP Allow" -ErrorAction SilentlyContinue
Remove-NetFirewallRule -DisplayName "Docker HTTPS Allow" -ErrorAction SilentlyContinue

# Create new rules with high priority (low number = high priority)
New-NetFirewallRule -DisplayName "Docker HTTP Allow" `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort 80 `
    -Action Allow `
    -Profile Any `
    -Enabled True `
    -Priority 100 | Out-Null

New-NetFirewallRule -DisplayName "Docker HTTPS Allow" `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort 443 `
    -Action Allow `
    -Profile Any `
    -Enabled True `
    -Priority 100 | Out-Null

Write-Host "✓ High-priority rules created" -ForegroundColor Green

# Alternative: Change your network from Public to Private
Write-Host "`nYour network is currently set as PUBLIC which has stricter rules." -ForegroundColor Yellow
Write-Host "Would you like to change 'Network 2' to Private? (More permissive) [Y/N]" -ForegroundColor Cyan
$response = Read-Host

if ($response -eq 'Y' -or $response -eq 'y') {
    Set-NetConnectionProfile -Name "Network 2" -NetworkCategory Private
    Write-Host "✓ Network profile changed to Private" -ForegroundColor Green
}

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "Docker Firewall Fix Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "`nTest from your wireless device now:" -ForegroundColor Yellow
Write-Host "  https://192.168.3.34" -ForegroundColor Cyan
Write-Host "`nThe connection should work immediately." -ForegroundColor Green