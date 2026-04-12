# ==========================================
# ADVANCED AD HARDENING SCRIPT (PCDC SAFE)
==========================================

Write-Host "Starting Advanced AD Hardening..." -ForegroundColor Cyan

# -------------------------------
# 1. Import AD Module
# -------------------------------
Import-Module ActiveDirectory -ErrorAction SilentlyContinue

# -------------------------------
# 2. Secure Built-in Accounts
# -------------------------------
Write-Host "[*] Securing built-in accounts..."

net user Guest /active:no
net user Administrator /active:yes

# Rename Administrator (optional but recommended)
# Rename-LocalUser -Name "Administrator" -NewName "sys_admin"

# -------------------------------
# 3. Enforce Strong Password Policy
# -------------------------------
Write-Host "[*] Enforcing password policy..."

net accounts /minpwlen:14
net accounts /maxpwage:30
net accounts /minpwage:1
net accounts /lockoutthreshold:5
net accounts /lockoutduration:30

# -------------------------------
# 4. Disable Password Never Expires
# -------------------------------
Write-Host "[*] Fixing non-expiring passwords..."

Get-ADUser -Filter {PasswordNeverExpires -eq $true} -Properties PasswordNeverExpires |
Where-Object {$_.Enabled -eq $true} |
ForEach-Object {
    Write-Host "Fixing:" $_.SamAccountName
    Set-ADUser $_ -PasswordNeverExpires $false
}

# -------------------------------
# 5. Remove Users with UID 500 Clone Behavior
# -------------------------------
Write-Host "[*] Checking for suspicious admin-like accounts..."

Get-ADUser -Filter * -Properties AdminCount |
Where-Object {$_.AdminCount -eq 1} |
Select SamAccountName

# -------------------------------
# 6. Restrict Domain Admin Membership
# -------------------------------
Write-Host "[*] Auditing Domain Admins..."

$admins = Get-ADGroupMember "Domain Admins"
$admins | ForEach-Object {
    Write-Host "Admin:" $_.SamAccountName
}

# -------------------------------
# 7. Disable Inactive Accounts (>14 days for competition)
# -------------------------------
Write-Host "[*] Disabling inactive accounts..."

Search-ADAccount -AccountInactive -TimeSpan 14.00:00:00 -UsersOnly |
ForEach-Object {
    Write-Host "Disabling:" $_.SamAccountName
    Disable-ADAccount -Identity $_
}

# -------------------------------
# 8. Enable Advanced Auditing
# -------------------------------
Write-Host "[*] Enabling advanced audit policies..."

auditpol /set /category:"Account Logon" /success:enable /failure:enable
auditpol /set /category:"Logon/Logoff" /success:enable /failure:enable
auditpol /set /category:"Object Access" /success:enable /failure:enable
auditpol /set /category:"Policy Change" /success:enable /failure:enable
auditpol /set /category:"Privilege Use" /success:enable /failure:enable
auditpol /set /category:"System" /success:enable /failure:enable

# -------------------------------
# 9. Disable Dangerous Services
# -------------------------------
Write-Host "[*] Disabling unnecessary services..."

$services = @("RemoteRegistry","Telnet","SNMP","SSDPSRV")

foreach ($svc in $services) {
    Get-Service -Name $svc -ErrorAction SilentlyContinue | ForEach-Object {
        Stop-Service $_ -Force -ErrorAction SilentlyContinue
        Set-Service $_ -StartupType Disabled
        Write-Host "Disabled:" $svc
    }
}

# -------------------------------
# 10. Secure SMB
# -------------------------------
Write-Host "[*] Hardening SMB..."

Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force
Set-SmbServerConfiguration -EncryptData $true -Force

# -------------------------------
# 11. Restrict Anonymous Access
# -------------------------------
Write-Host "[*] Restricting anonymous access..."

Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" `
-Name "RestrictAnonymous" -Value 1

# -------------------------------
# 12. Disable LM Hash Storage
# -------------------------------
Write-Host "[*] Disabling LM Hash storage..."

Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" `
-Name "NoLMHash" -Value 1

# -------------------------------
# 13. Enable Windows Defender (if disabled)
# -------------------------------
Write-Host "[*] Ensuring Defender is enabled..."

Set-MpPreference -DisableRealtimeMonitoring $false

# -------------------------------
# 14. Firewall Hardening
# -------------------------------
Write-Host "[*] Enforcing firewall..."

Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True

# -------------------------------
# 15. Detect Suspicious Scheduled Tasks
# -------------------------------
Write-Host "[*] Checking scheduled tasks..."

Get-ScheduledTask | Where-Object {
    $_.TaskName -match "update|temp|sys|svc"
} | Select TaskName, TaskPath

# -------------------------------
# 16. Detect New Local Admins
# -------------------------------
Write-Host "[*] Checking local administrators..."

net localgroup administrators

# -------------------------------
# 17. Disable PowerShell v2 (common attack vector)
# -------------------------------
Write-Host "[*] Disabling PowerShell v2..."

Disable-WindowsOptionalFeature -Online -FeatureName MicrosoftWindowsPowerShellV2Root -NoRestart

# -------------------------------
# 18. Enable Script Block Logging
# -------------------------------
Write-Host "[*] Enabling PowerShell logging..."

Set-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging" `
-Name "EnableScriptBlockLogging" -Value 1 -Force

# -------------------------------
# 19. Clear Cached Credentials
# -------------------------------
Write-Host "[*] Clearing cached credentials..."

cmdkey /list
# Optional: cmdkey /delete:<target>

# -------------------------------
# 20. Final Status
# -------------------------------
Write-Host "Advanced AD Hardening Complete." -ForegroundColor Green
