#!/usr/bin/env bash

# Summarizes recent authentication and system-log indicators from journalctl
# and common log files for quick triage.
#
# Usage:
#   ./68_log_triage.sh
#   ./68_log_triage.sh --remote

SCRIPT_BASENAME="$(basename "$0" .sh)"
# shellcheck source=lib/common.sh
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"

REMOTE_MODE="false"
if [[ "${1:-}" == "--remote" ]]; then
  REMOTE_MODE="true"
  shift
fi
[[ $# -eq 0 ]] || die "Unsupported argument(s). Use optional --remote only."

REPORT_FILE="$(report_file_for "${SCRIPT_BASENAME}")"
SUMMARY_FILE="$(summary_file_for "${SCRIPT_BASENAME}")"

if [[ "${REMOTE_MODE}" == "true" ]]; then
  run_current_script_remote_across_hosts "${SUMMARY_FILE}" "log triage"
  exit 0
fi

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

for file in /var/log/auth.log /var/log/secure /var/log/messages /var/log/syslog /var/log/maillog /var/log/security /var/log/all.log; do
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
