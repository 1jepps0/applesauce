# ============================
# PCDC WINDOWS DETECTION PACK
# ============================

Write-Host "Starting Detection Engine..." -ForegroundColor Cyan

# ============================
# 1. FAILED LOGIN DETECTION
# ============================
Write-Host "`n[FAILED LOGINS - 4625]" -ForegroundColor Yellow

Get-WinEvent -FilterHashtable @{
    LogName='Security'
    Id=4625
} -MaxEvents 30 | ForEach-Object {
    [PSCustomObject]@{
        Time = $_.TimeCreated
        Event = "FAILED LOGIN"
        Details = $_.Message
    }
}

# ============================
# 2. SUCCESSFUL LOGINS (WATCH ADMIN ACCESS)
# ============================
Write-Host "`n[ADMIN LOGINS - 4672]" -ForegroundColor Yellow

Get-WinEvent -FilterHashtable @{
    LogName='Security'
    Id=4672
} -MaxEvents 30 | ForEach-Object {
    [PSCustomObject]@{
        Time = $_.TimeCreated
        Event = "PRIVILEGED LOGIN"
        Details = $_.Message
    }
}

# ============================
# 3. NEW USER CREATION
# ============================
Write-Host "`n[USER CREATION - 4720]" -ForegroundColor Yellow

Get-WinEvent -FilterHashtable @{
    LogName='Security'
    Id=4720
} -MaxEvents 20 | ForEach-Object {
    [PSCustomObject]@{
        Time = $_.TimeCreated
        Event = "USER CREATED"
        Details = $_.Message
    }
}

# ============================
# 4. GROUP MEMBERSHIP CHANGES
# ============================
Write-Host "`n[GROUP CHANGES - 4732/4733]" -ForegroundColor Yellow

Get-WinEvent -FilterHashtable @{
    LogName='Security'
    Id=4732,4733
} -MaxEvents 20 | ForEach-Object {
    [PSCustomObject]@{
        Time = $_.TimeCreated
        Event = "GROUP CHANGE"
        Details = $_.Message
    }
}

# ============================
# 5. POWERSHELL SUSPICIOUS EXECUTION
# ============================
Write-Host "`n[POWERSHELL ACTIVITY]" -ForegroundColor Yellow

Get-WinEvent -LogName "Windows PowerShell" -MaxEvents 30 |
Where-Object {
    $_.Message -match "Invoke-|DownloadString|IEX|EncodedCommand"
} | ForEach-Object {
    [PSCustomObject]@{
        Time = $_.TimeCreated
        Event = "SUSPICIOUS POWERSHELL"
        Details = $_.Message
    }
}

# ============================
# 6. SERVICE CHANGES (PERSISTENCE DETECTION)
# ============================
Write-Host "`n[SERVICE STATE]" -ForegroundColor Yellow

Get-Service | Where-Object {
    $_.Status -ne "Running"
} | Select-Object Name, Status, StartType

# ============================
# 7. ACTIVE NETWORK CONNECTIONS
# ============================
Write-Host "`n[NETWORK CONNECTIONS]" -ForegroundColor Yellow

netstat -ano | Select-String "ESTABLISHED"

# ============================
# 8. RECENT ADMIN GROUP MEMBERS
# ============================
Write-Host "`n[LOCAL ADMIN GROUP]" -ForegroundColor Yellow

Get-LocalGroupMember -Group "Administrators" | Select Name, ObjectClass

Write-Host "`nDetection Scan Complete." -ForegroundColor Green


while ($true) {

    $failures = Get-WinEvent -FilterHashtable @{LogName='Security'; Id=4625} -MaxEvents 5

    if ($failures) {
        Write-Host "[ALERT] Failed login detected!" -ForegroundColor Red
        $failures | Select TimeCreated, Message
    }

    $users = Get-WinEvent -FilterHashtable @{LogName='Security'; Id=4720} -MaxEvents 3

    if ($users) {
        Write-Host "[ALERT] New user created!" -ForegroundColor Red
        $users | Select TimeCreated, Message
    }

    Start-Sleep -Seconds 10
}