#!/usr/bin/env bash

# SUBJECT: Resource Approval Request
# BODY:
# Team #: TBD
# Resource Name: 60_account_audit.sh
# Citation: /home/jacob/code/applesauce/linux/60_account_audit.sh
# How Resource Will Be Used: Review account, sudo, SSH key, cron, and listener risks on local or remote hosts.
#
# Reviews local account risk indicators such as unexpected admins, SSH keys,
# sudoers, cron usage, and listening sockets.
#
# Sources:
#   https://man7.org/linux/man-pages/man5/sudoers.5.html
#   https://man7.org/linux/man-pages/man1/crontab.1.html
#   https://man7.org/linux/man-pages/man8/ss.8.html
#
# Flags:
#   --remote    Run the audit across the hosts in HOSTS over SSH.
#
# Usage:
#   ./60_account_audit.sh
#   ./60_account_audit.sh [--remote]

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
  run_current_script_remote_across_hosts "${SUMMARY_FILE}" "account audit"
  exit 0
fi

write_csv_line "${REPORT_FILE}" "category" "item" "result" "details"

record() {
  write_csv_line "${REPORT_FILE}" "$1" "$2" "$3" "$4"
  log "INFO" "$1 | $2 | $3 | $4"
}

while IFS=: read -r user _ uid _ _ home shell; do
  if [[ "${uid}" == "0" && "${user}" != "root" ]]; then
    record "user" "${user}" "warn" "UID 0 non-root account (${shell})"
  fi
  if [[ ! " ${ALLOWED_ADMIN_USERS[*]} " =~ [[:space:]]${user}[[:space:]] ]] && id -nG "${user}" 2>/dev/null | grep -Eq '\b(sudo|wheel)\b'; then
    record "sudo" "${user}" "warn" "Unexpected admin group membership"
  fi
  if [[ -d "${home}/.ssh" ]]; then
    auth_keys="${home}/.ssh/authorized_keys"
    if [[ -f "${auth_keys}" ]]; then
      key_count="$(grep -cEv '^\s*(#|$)' "${auth_keys}" || true)"
      record "ssh_keys" "${user}" "info" "authorized_keys entries=${key_count}"
    fi
  fi
done </etc/passwd

if command_exists sudo; then
  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    record "sudoers" "entry" "warn" "${line}"
  done < <(grep -RIn 'NOPASSWD' /etc/sudoers /etc/sudoers.d 2>/dev/null || true)
fi

if command_exists crontab; then
  while IFS=: read -r user _; do
    if crontab -l -u "${user}" >/dev/null 2>&1; then
      record "cron" "${user}" "info" "User has crontab entries"
    fi
  done </etc/passwd
fi

if command_exists ss; then
  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    record "listener" "socket" "info" "${line}"
  done < <(ss -tulpnH 2>/dev/null || true)
elif command_exists sockstat; then
  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    record "listener" "socket" "info" "${line}"
  done < <(sockstat -4 -6 -l 2>/dev/null | tail -n +2 || true)
fi

{
  printf 'Account audit summary\n'
  printf 'Timestamp: %s\n' "${TIMESTAMP}"
  printf 'Report: %s\n' "${REPORT_FILE}"
  printf 'Log: %s\n' "${LOG_FILE}"
} >"${SUMMARY_FILE}"

log "INFO" "Account audit complete. Summary at ${SUMMARY_FILE}"
