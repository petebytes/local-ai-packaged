@echo off
REM This script must be run as Administrator in Windows
REM It creates firewall rules to allow incoming connections on ports 80 and 443

echo ============================================
echo Windows Firewall Configuration for Local AI
echo ============================================
echo.
echo This script will create firewall rules to allow
echo incoming connections on ports 80 and 443
echo.
echo IMPORTANT: Run this as Administrator!
echo.
pause

REM Remove any existing rules with our names to avoid duplicates
echo Removing any existing Local AI firewall rules...
netsh advfirewall firewall delete rule name="Local AI HTTP Inbound" >nul 2>&1
netsh advfirewall firewall delete rule name="Local AI HTTPS Inbound" >nul 2>&1

REM Create new inbound rules for HTTP (port 80)
echo Creating firewall rule for HTTP (port 80)...
netsh advfirewall firewall add rule name="Local AI HTTP Inbound" dir=in action=allow protocol=TCP localport=80 profile=private,public enable=yes

REM Create new inbound rules for HTTPS (port 443)
echo Creating firewall rule for HTTPS (port 443)...
netsh advfirewall firewall add rule name="Local AI HTTPS Inbound" dir=in action=allow protocol=TCP localport=443 profile=private,public enable=yes

echo.
echo ============================================
echo Firewall rules created successfully!
echo ============================================
echo.

REM Show the created rules
echo Verifying the rules were created:
echo.
netsh advfirewall firewall show rule name="Local AI HTTP Inbound"
echo.
netsh advfirewall firewall show rule name="Local AI HTTPS Inbound"

echo.
echo ============================================
echo Setup Complete!
echo ============================================
echo.
echo Your services should now be accessible from other devices!
echo.
echo Test from your wireless device:
echo   https://192.168.3.34
echo   https://raven.lan (if hosts file is configured)
echo.
echo You will need to accept the self-signed certificate warning.
echo.
pause