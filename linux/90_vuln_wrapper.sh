#!/usr/bin/env bash

# Runs policy-limited exposure checks such as scoped nmap, Lynis, and simple
# filesystem findings without acting as a broad scanner by default.
#
# Flags:
#   None.
#
# Usage:
#   ./90_vuln_wrapper.sh

SCRIPT_BASENAME="$(basename "$0" .sh)"
# shellcheck source=lib/common.sh
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"

REPORT_FILE="$(report_file_for "${SCRIPT_BASENAME}")"
SUMMARY_FILE="$(summary_file_for "${SCRIPT_BASENAME}")"

write_csv_line "${REPORT_FILE}" "tool" "target" "result" "details" "suggestion"

record() {
  write_csv_line "${REPORT_FILE}" "$1" "$2" "$3" "$4" "$5"
  log "INFO" "$1 $2 $3 $4"
}

for host in "${HOSTS[@]}"; do
  target_host="$(host_address "${host}")"
  display_host="$(host_display "${host}")"
  if [[ "${ENABLE_NMAP}" == "true" && "${ALLOW_NETWORK_SCANNING}" == "true" ]] && command_exists nmap; then
    port_list="$(service_ports_for_host "${host}" | sed 's|/udp||g; s|/tcp||g')"
    nmap_output="$(nmap -Pn -sT -p "${port_list}" "${target_host}" 2>/dev/null || true)"
    if grep -q 'open' <<<"${nmap_output}"; then
      record "nmap" "${display_host}" "info" "Open ports detected" "Review unexpected listeners against HOST_SERVICE_MATRIX"
    else
      record "nmap" "${display_host}" "warn" "No configured open ports detected" "Validate host inventory and service matrix"
    fi
  else
    record "nmap" "${display_host}" "warn" "nmap unavailable, disabled, or blocked by policy" "Keep ALLOW_NETWORK_SCANNING=false during competition unless the action is explicitly allowed"
  fi
done

if [[ "${ENABLE_LYNIS}" == "true" ]]; then
  if command_exists lynis; then
    lynis_output="$(lynis audit system --quick 2>/dev/null || true)"
    hardening_index="$(grep -Eo 'Hardening index : [0-9]+' <<<"${lynis_output}" | awk '{print $4}' || true)"
    record "lynis" "localhost" "info" "Hardening index=${hardening_index:-unknown}" "Review Lynis warnings before enforcement"
  else
    record "lynis" "localhost" "warn" "lynis unavailable" "Install Lynis for host-local triage"
  fi
fi

if command_exists find; then
  world_writable_count="$(find / -xdev -type f -perm -0002 2>/dev/null | wc -l | tr -d ' ')"
  record "filesystem" "localhost" "info" "world-writable files=${world_writable_count}" "Review world-writable files for abuse paths"
fi

{
  printf 'Vulnerability wrapper summary\n'
  printf 'Timestamp: %s\n' "${TIMESTAMP}"
  printf 'Report: %s\n' "${REPORT_FILE}"
  printf 'Log: %s\n' "${LOG_FILE}"
} >"${SUMMARY_FILE}"

log "INFO" "Vulnerability wrapper complete. Summary at ${SUMMARY_FILE}"
