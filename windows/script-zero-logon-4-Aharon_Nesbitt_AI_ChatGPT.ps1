# =========================
# ZEROLOGON DEFENSIVE CHECK
# =========================

Write-Host "Checking ZeroLogon (Netlogon security status)..."

# 1. Check if DC is patched (critical)
$patches = Get-HotFix | Where-Object {
    $_.HotFixID -match "KB4570006|KB4578974|KB4580390|KB4594440"
}

if ($patches) {
    Write-Host "[OK] Likely patched against ZeroLogon"
} else {
    Write-Host "[WARNING] Missing known ZeroLogon patches!"
}

# 2. Check Netlogon secure channel enforcement
$netlogon = Get-ItemProperty `
  "HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters" `
  -ErrorAction SilentlyContinue

if ($netlogon.FullSecureChannelProtection -eq 1) {
    Write-Host "[OK] Full Secure Channel Protection enabled"
} else {
    Write-Host "[CRITICAL] Secure Channel Protection NOT enabled"
}

# 3. Check suspicious Netlogon events (authentication anomalies)
Get-WinEvent -LogName "System" -MaxEvents 200 |
Where-Object {
    $_.ProviderName -match "Netlogon"
} | Select-Object TimeCreated, Id, Message

Write-Host "ZeroLogon check complete"
