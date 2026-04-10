#!/usr/bin/env bash

SCRIPT_BASENAME="$(basename "$0" .sh)"
# shellcheck source=lib/common.sh
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"

REPORT_FILE="$(report_file_for "${SCRIPT_BASENAME}")"
SUMMARY_FILE="$(summary_file_for "${SCRIPT_BASENAME}")"

write_csv_line "${REPORT_FILE}" "category" "target" "result" "details"

record() {
  write_csv_line "${REPORT_FILE}" "$1" "$2" "$3" "$4"
  log "INFO" "$1 | $2 | $3 | $4"
}

expected_ports="$(local_service_ports | sed 's|/udp||g; s|/tcp||g')"

if command_exists ss; then
  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    port="$(awk '{print $5}' <<<"${line}" | sed 's/.*://')"
    if grep -qw "${port}" <<<"${expected_ports//,/ }"; then
      record "listener" "tcp/${port}" "info" "${line}"
    else
      record "listener" "tcp/${port}" "warn" "Unexpected listener: ${line}"
    fi
  done < <(ss -tulpnH 2>/dev/null || true)
elif command_exists sockstat; then
  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    port="$(awk '{print $6}' <<<"${line}" | sed 's/.*://')"
    if grep -qw "${port}" <<<"${expected_ports//,/ }"; then
      record "listener" "tcp/${port}" "info" "${line}"
    else
      record "listener" "tcp/${port}" "warn" "Unexpected listener: ${line}"
    fi
  done < <(sockstat -4 -6 -l 2>/dev/null | tail -n +2 || true)
elif command_exists netstat; then
  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    port="$(awk '{print $4}' <<<"${line}" | sed 's/.*[.:]//')"
    if grep -qw "${port}" <<<"${expected_ports//,/ }"; then
      record "listener" "tcp/${port}" "info" "${line}"
    else
      record "listener" "tcp/${port}" "warn" "Unexpected listener: ${line}"
    fi
  done < <(netstat -an 2>/dev/null | grep LISTEN || true)
else
  record "listener" "local" "warn" "No supported socket listing command available"
fi

{
  printf 'Process/port audit summary\n'
  printf 'Timestamp: %s\n' "${TIMESTAMP}"
  printf 'Report: %s\n' "${REPORT_FILE}"
  printf 'Log: %s\n' "${LOG_FILE}"
} >"${SUMMARY_FILE}"

log "INFO" "Process/port audit complete. Summary at ${SUMMARY_FILE}"
