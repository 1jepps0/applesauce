# ===============================
# PCDC AD HARDENING SCRIPT
# Author: Mickey Mouse
# ===============================

Write-Host "Starting AD Hardening..." -ForegroundColor Cyan

# -------------------------------
# 1. Disable Guest Account
# -------------------------------
Write-Host "[*] Disabling Guest Account..."
net user Guest /active:no

# -------------------------------
# 2. List Domain Admins
# -------------------------------
Write-Host "[*] Listing Domain Admins..."
net group "Domain Admins" /domain

# -------------------------------
# 3. Find Users with Admin Rights
# -------------------------------
Write-Host "[*] Checking local Administrators group..."
net localgroup administrators

# -------------------------------
# 4. Force Password Change (Optional - USE CAREFULLY)
# -------------------------------
# Uncomment if needed
# Write-Host "[*] Forcing password reset..."
# Get-ADUser -Filter * | Set-ADUser -ChangePasswordAtLogon $true

# -------------------------------
# 5. Set Password Policy
# -------------------------------
Write-Host "[*] Setting password policy..."

net accounts /minpwlen:12
net accounts /maxpwage:30
net accounts /minpwage:1
net accounts /lockoutthreshold:5
net accounts /lockoutduration:30

# -------------------------------
# 6. Disable Unused Accounts
# -------------------------------
Write-Host "[*] Finding inactive users (last 30 days)..."

Search-ADAccount -AccountInactive -TimeSpan 30.00:00:00 -UsersOnly | 
ForEach-Object {
    Write-Host "Disabling:" $_.SamAccountName
    Disable-ADAccount -Identity $_
}

# -------------------------------
# 7. Find Accounts with Password Never Expires
# -------------------------------
Write-Host "[*] Checking for non-expiring passwords..."

Get-ADUser -Filter {PasswordNeverExpires -eq $true} -Properties PasswordNeverExpires |
ForEach-Object {
    Write-Host "Fixing:" $_.SamAccountName
    Set-ADUser $_ -PasswordNeverExpires $false
}

# -------------------------------
# 8. Audit Enabled Admin Accounts
# -------------------------------
Write-Host "[*] Checking enabled privileged accounts..."

Get-ADGroupMember "Domain Admins" |
ForEach-Object {
    $user = Get-ADUser $_.SamAccountName -Properties Enabled
    Write-Host "$($user.SamAccountName) Enabled: $($user.Enabled)"
}

# -------------------------------
# 9. Enable Windows Firewall
# -------------------------------
Write-Host "[*] Enabling Windows Firewall..."

Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True

# -------------------------------
# 10. Disable SMBv1
# -------------------------------
Write-Host "[*] Disabling SMBv1..."

Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force

# -------------------------------
# 11. Enable Auditing
# -------------------------------
Write-Host "[*] Enabling audit policies..."

auditpol /set /category:"Logon/Logoff" /success:enable /failure:enable
auditpol /set /category:"Account Logon" /success:enable /failure:enable

# -------------------------------
# 12. Check for Suspicious Scheduled Tasks
# -------------------------------
Write-Host "[*] Checking scheduled tasks..."

Get-ScheduledTask | Where-Object {$_.State -eq "Ready"} | 
Select-Object TaskName, TaskPath

# -------------------------------
# 13. Check Open Shares
# -------------------------------
Write-Host "[*] Listing SMB Shares..."

Get-SmbShare

# -------------------------------
# 14. Disable Remote Desktop (Optional)
# -------------------------------
# ONLY IF NOT REQUIRED
# Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" `
# -Name "fDenyTSConnections" -Value 1

# -------------------------------
# 15. Output Completion
# -------------------------------
Write-Host "AD Hardening Complete." -ForegroundColor Green
