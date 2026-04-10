#!/usr/bin/env bash

SCRIPT_BASENAME="$(basename "$0" .sh)"
# shellcheck source=lib/common.sh
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"

REPORT_FILE="$(report_file_for "${SCRIPT_BASENAME}")"
SUMMARY_FILE="$(summary_file_for "${SCRIPT_BASENAME}")"

write_csv_line "${REPORT_FILE}" "source" "result" "details"

record() {
  write_csv_line "${REPORT_FILE}" "$1" "$2" "$3"
  log "INFO" "$1 | $2 | $3"
}

if command_exists journalctl; then
  ssh_failures="$(journalctl --since '24 hours ago' 2>/dev/null | grep -ci 'failed password' || true)"
  sudo_events="$(journalctl --since '24 hours ago' 2>/dev/null | grep -ci 'sudo' || true)"
  record "journalctl" "info" "failed_passwords_24h=${ssh_failures} sudo_events_24h=${sudo_events}"
fi

for file in /var/log/auth.log /var/log/secure /var/log/messages /var/log/syslog; do
  [[ -f "${file}" ]] || continue
  failed="$(grep -ciE 'failed password|authentication failure' "${file}" 2>/dev/null || true)"
  errors="$(grep -ciE 'error|denied|refused' "${file}" 2>/dev/null || true)"
  record "${file}" "info" "failed_auth=${failed} errors=${errors}"
done

{
  printf 'Log triage summary\n'
  printf 'Timestamp: %s\n' "${TIMESTAMP}"
  printf 'Report: %s\n' "${REPORT_FILE}"
  printf 'Log: %s\n' "${LOG_FILE}"
} >"${SUMMARY_FILE}"

log "INFO" "Log triage complete. Summary at ${SUMMARY_FILE}"
