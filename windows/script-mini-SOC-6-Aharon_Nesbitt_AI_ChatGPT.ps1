# ============================
# PCDC MINI SOC - WINDOWS DEFENDER SCRIPT
# ============================

# CONFIG
$LogPath = "C:\SOC\alerts.log"
$SuspiciousThreshold = 5
$ScanInterval = 10

# Ensure log file exists
if (!(Test-Path $LogPath)) {
    New-Item -Path $LogPath -ItemType File -Force | Out-Null
}

function Write-Alert {
    param([string]$Message)

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp] $Message"

    Write-Host $entry -ForegroundColor Red
    Add-Content -Path $LogPath -Value $entry
}

# ============================
# 1. AUTH LOG MONITORING
# ============================
function Check-FailedLogins {
    $events = Get-WinEvent -FilterHashtable @{
        LogName='Security'
        Id=4625
        StartTime=(Get-Date).AddMinutes(-5)
    } -ErrorAction SilentlyContinue

    if ($events) {
        $grouped = $events | Group-Object {$_.Properties[5].Value}

        foreach ($g in $grouped) {
            if ($g.Count -ge $SuspiciousThreshold) {
                Write-Alert "POSSIBLE BRUTE FORCE: User $($g.Name) had $($g.Count) failed logins"
            }
        }
    }
}

# ============================
# 2. PRIVILEGED USER CHECK
# ============================
function Check-AdminUsers {
    $admins = Get-LocalGroupMember -Group "Administrators"

    foreach ($a in $admins) {
        if ($a.Name -notmatch "Administrator|Domain Admins|SYSTEM") {
            Write-Alert "UNEXPECTED ADMIN MEMBER: $($a.Name)"
        }
    }
}

# ============================
# 3. PERSISTENCE CHECK
# ============================
function Check-Persistence {
    # Scheduled tasks
    $tasks = Get-ScheduledTask | Where-Object {$_.TaskPath -notlike "\Microsoft*"}

    foreach ($t in $tasks) {
        Write-Alert "SUSPICIOUS TASK: $($t.TaskName) at $($t.TaskPath)"
    }

    # Startup items
    $startup = Get-CimInstance Win32_StartupCommand
    foreach ($s in $startup) {
        Write-Alert "STARTUP ITEM: $($s.Name) -> $($s.Command)"
    }
}

# ============================
# 4. NETWORK MONITORING
# ============================
function Check-Network {
    $connections = Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue

    foreach ($c in $connections) {
        if ($c.RemotePort -eq 4444 -or $c.RemotePort -eq 1337 -or $c.RemotePort -eq 6667) {
            Write-Alert "SUSPICIOUS CONNECTION: $($c.LocalAddress):$($c.LocalPort) -> $($c.RemoteAddress):$($c.RemotePort)"
        }
    }
}

# ============================
# 5. SYSTEM INTEGRITY CHECK
# ============================
function Check-SystemIntegrity {
    # Disabled services
    $services = Get-Service | Where-Object {$_.Status -eq "Stopped"}

    foreach ($s in $services) {
        if ($s.StartType -eq "Automatic") {
            Write-Alert "CRITICAL SERVICE DOWN: $($s.Name)"
        }
    }
}

# ============================
# 6. DOMAIN / DC HEALTH (ZeroLogon awareness)
# ============================
function Check-DCHealth {
    try {
        $dc = Get-ADDomainController -Discover -ErrorAction Stop
        Write-Host "DC reachable: $($dc.HostName)" -ForegroundColor Green
    } catch {
        Write-Alert "DOMAIN CONTROLLER ISSUE: Cannot validate DC connectivity"
    }

    # Secure channel check (detect trust issues often abused post-exploit)
    try {
        if (!(Test-ComputerSecureChannel)) {
            Write-Alert "SECURE CHANNEL BROKEN: Possible domain trust compromise"
        }
    } catch {
        Write-Alert "SECURE CHANNEL CHECK FAILED"
    }
}

# ============================
# 7. REAL-TIME LOOP
# ============================
Write-Host "Starting MINI SOC monitoring..." -ForegroundColor Cyan

while ($true) {

    try {
        Check-FailedLogins
        Check-AdminUsers
        Check-Persistence
        Check-Network
        Check-SystemIntegrity
        Check-DCHealth
    }
    catch {
        Write-Alert "ERROR IN SOC LOOP: $_"
    }

    Start-Sleep -Seconds $ScanInterval
}