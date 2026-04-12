#!/usr/bin/env bash

# Reports pending package updates using the host's native package manager to
# highlight obvious patch backlog without changing the system.
#
# Flags:
#   --remote    Run the audit across the hosts in HOSTS over SSH.
#
# Usage:
#   ./66_package_audit.sh
#   ./66_package_audit.sh [--remote]

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
  run_current_script_remote_across_hosts "${SUMMARY_FILE}" "package audit"
  exit 0
fi

write_csv_line "${REPORT_FILE}" "tool" "result" "details"

record() {
  write_csv_line "${REPORT_FILE}" "$1" "$2" "$3"
  log "INFO" "$1 | $2 | $3"
}

if command_exists apt-get; then
  updates="$(apt list --upgradable 2>/dev/null | tail -n +2 || true)"
  count="$(printf '%s\n' "${updates}" | sed '/^\s*$/d' | wc -l | tr -d ' ')"
  record "apt" "info" "Upgradable packages=${count}"
elif command_exists dnf; then
  count="$(dnf check-update -q 2>/dev/null | grep -Ec '^[A-Za-z0-9_.-]+' || true)"
  record "dnf" "info" "Upgradable packages=${count}"
elif command_exists yum; then
  count="$(yum check-update -q 2>/dev/null | grep -Ec '^[A-Za-z0-9_.-]+' || true)"
  record "yum" "info" "Upgradable packages=${count}"
elif command_exists zypper; then
  count="$(zypper list-updates 2>/dev/null | grep -Ec '^[v| ]' || true)"
  record "zypper" "info" "Update output collected"
elif command_exists pkg; then
  if [[ "$(os_flavor)" == "freebsd" || "$(os_flavor)" == "dragonfly" ]]; then
    count="$(pkg version -vIL= 2>/dev/null | wc -l | tr -d ' ')"
    record "pkg" "info" "Outdated packages=${count}"
  else
    installed="$(pkg_info -a 2>/dev/null | wc -l | tr -d ' ')"
    record "pkg" "info" "Installed packages=${installed}; use syspatch/pkg_add -u workflow for OpenBSD review"
  fi
else
  record "packages" "warn" "No supported package manager detected"
fi

{
  printf 'Package audit summary\n'
  printf 'Timestamp: %s\n' "${TIMESTAMP}"
  printf 'Report: %s\n' "${REPORT_FILE}"
  printf 'Log: %s\n' "${LOG_FILE}"
} >"${SUMMARY_FILE}"

log "INFO" "Package audit complete. Summary at ${SUMMARY_FILE}"
