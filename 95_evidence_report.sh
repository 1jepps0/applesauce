#!/usr/bin/env bash

SCRIPT_BASENAME="$(basename "$0" .sh)"
# shellcheck source=lib/common.sh
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"

BUNDLE_DIR="${REPORT_DIR}/evidence_${TIMESTAMP}"
mkdir -p "${BUNDLE_DIR}"

latest_file() {
  local pattern="$1"
  ls -1t ${pattern} 2>/dev/null | head -n 1 || true
}

copy_if_present() {
  local src="$1"
  [[ -n "${src}" && -f "${src}" ]] || return 0
  cp -a "${src}" "${BUNDLE_DIR}/"
}

copy_if_present "$(latest_file "${REPORT_DIR}/10_host_discovery_*.csv")"
copy_if_present "$(latest_file "${REPORT_DIR}/10_host_discovery_*.txt")"
copy_if_present "$(latest_file "${REPORT_DIR}/20_service_audit_*.csv")"
copy_if_present "$(latest_file "${REPORT_DIR}/20_service_audit_*.txt")"
copy_if_present "$(latest_file "${REPORT_DIR}/60_account_audit_*.csv")"
copy_if_present "$(latest_file "${REPORT_DIR}/60_account_audit_*.txt")"
copy_if_present "$(latest_file "${REPORT_DIR}/65_persistence_audit_*.csv")"
copy_if_present "$(latest_file "${REPORT_DIR}/65_persistence_audit_*.txt")"
copy_if_present "$(latest_file "${REPORT_DIR}/66_package_audit_*.csv")"
copy_if_present "$(latest_file "${REPORT_DIR}/66_package_audit_*.txt")"
copy_if_present "$(latest_file "${REPORT_DIR}/67_process_port_audit_*.csv")"
copy_if_present "$(latest_file "${REPORT_DIR}/67_process_port_audit_*.txt")"
copy_if_present "$(latest_file "${REPORT_DIR}/68_log_triage_*.csv")"
copy_if_present "$(latest_file "${REPORT_DIR}/68_log_triage_*.txt")"
copy_if_present "$(latest_file "${REPORT_DIR}/90_vuln_wrapper_*.csv")"
copy_if_present "$(latest_file "${REPORT_DIR}/90_vuln_wrapper_*.txt")"
if [[ -d "${INCIDENT_REPORT_DIR}" ]]; then
  find "${INCIDENT_REPORT_DIR}" -maxdepth 1 -type f -name '*.md' -print0 2>/dev/null | while IFS= read -r -d '' incident; do
    cp -a "${incident}" "${BUNDLE_DIR}/"
  done
fi

SUMMARY_FILE="${BUNDLE_DIR}/evidence_summary.txt"
{
  printf 'Evidence report bundle\n'
  printf 'Timestamp: %s\n' "${TIMESTAMP}"
  printf 'Bundle dir: %s\n' "${BUNDLE_DIR}"
  printf 'Hosts configured: %s\n' "${#HOSTS[@]}"
  printf '\nIncluded files:\n'
  find "${BUNDLE_DIR}" -maxdepth 1 -type f -printf '%f\n' 2>/dev/null | sort
} >"${SUMMARY_FILE}"

log "INFO" "Evidence bundle created at ${BUNDLE_DIR}"
