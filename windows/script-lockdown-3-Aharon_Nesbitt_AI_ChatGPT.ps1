# ==========================================
# ACCESS LOCKDOWN SCRIPT (PCDC SAFE)
# Focus: Stop unauthorized access + movement
# ==========================================

Write-Host "Starting Access Lockdown..." -ForegroundColor Cyan

Import-Module ActiveDirectory -ErrorAction SilentlyContinue

# -------------------------------
# 1. Audit & Clean Domain Admins
# -------------------------------
Write-Host "[*] Auditing Domain Admins..."

$allowedAdmins = @("Administrator")  # Add your team admin accounts here

$domainAdmins = Get-ADGroupMember "Domain Admins"

foreach ($user in $domainAdmins) {
    if ($allowedAdmins -notcontains $user.SamAccountName) {
        Write-Host "Removing unauthorized admin:" $user.SamAccountName -ForegroundColor Yellow
        # Uncomment AFTER review
        # Remove-ADGroupMember "Domain Admins" -Members $user -Confirm:$false
    }
}

# -------------------------------
# 2. Disable Suspicious Accounts
# -------------------------------
Write-Host "[*] Checking for suspicious accounts..."

Get-ADUser -Filter * -Properties whenCreated |
Where-Object {
    $_.Enabled -eq $true -and
    ($_.SamAccountName -match "test|temp|backup|svc|admin")
} |
ForEach-Object {
    Write-Host "Suspicious account found:" $_.SamAccountName -ForegroundColor Red
    # Disable after verification
    # Disable-ADAccount $_
}

# -------------------------------
# 3. Restrict RDP Access
# -------------------------------
Write-Host "[*] Restricting RDP access..."

net localgroup "Remote Desktop Users"

# Optional lockdown (ONLY if safe)
# Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" `
# -Name "fDenyTSConnections" -Value 1

# -------------------------------
# 4. Remove Excess Local Admins
# -------------------------------
Write-Host "[*] Checking local administrators..."

net localgroup administrators

# -------------------------------
# 5. Disable WinRM (if not needed)
# -------------------------------
Write-Host "[*] Disabling WinRM..."

Try {
    Disable-PSRemoting -Force -ErrorAction Stop
} Catch {
    Write-Host "WinRM already disabled or blocked"
}

# -------------------------------
# 6. SMB Hardening
# -------------------------------
Write-Host "[*] Hardening SMB..."

Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force
Set-SmbServerConfiguration -EncryptData $true -Force

# -------------------------------
# 7. Lock Down Shares
# -------------------------------
Write-Host "[*] Auditing SMB shares..."

Get-SmbShare | ForEach-Object {
    Write-Host "Share:" $_.Name
}

# -------------------------------
# 8. Kill Active Suspicious Sessions
# -------------------------------
Write-Host "[*] Checking active sessions..."

quser

# -------------------------------
# 9. Enable Account Lockout Policy
# -------------------------------
Write-Host "[*] Enforcing lockout policy..."

net accounts /lockoutthreshold:5
net accounts /lockoutduration:30

# -------------------------------
# 10. Monitor Failed Logins
# -------------------------------
Write-Host "[*] Recent failed logins..."

Get-EventLog -LogName Security -InstanceId 4625 -Newest 20 |
Select TimeGenerated, ReplacementStrings

# -------------------------------
# 11. Monitor Successful Logins
# -------------------------------
Write-Host "[*] Recent successful logins..."

Get-EventLog -LogName Security -InstanceId 4624 -Newest 20 |
Select TimeGenerated, ReplacementStrings

# -------------------------------
# 12. Detect Lateral Movement Ports
# -------------------------------
Write-Host "[*] Checking open ports..."

netstat -ano | findstr ":445"
netstat -ano | findstr ":3389"

# -------------------------------
# DONE
# -------------------------------
Write-Host "Access Lockdown Complete." -ForegroundColor Green
