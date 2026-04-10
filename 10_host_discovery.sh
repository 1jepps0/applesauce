#!/usr/bin/env bash

SCRIPT_BASENAME="$(basename "$0" .sh)"
# shellcheck source=lib/common.sh
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"

REPORT_FILE="$(report_file_for "${SCRIPT_BASENAME}")"
SUMMARY_FILE="$(summary_file_for "${SCRIPT_BASENAME}")"

write_csv_line "${REPORT_FILE}" "host" "role" "ping" "dns" "reachable_ports" "failed_ports"

up_count=0
down_count=0

for host in "${HOSTS[@]}"; do
  role="$(host_role "${host}")"
  if ping_host "${host}"; then
    ping_state="up"
    ((up_count+=1))
  else
    ping_state="down"
    ((down_count+=1))
  fi

  if dns_check "${host}"; then
    dns_state="ok"
  else
    dns_state="fail"
  fi

  reachable=()
  failed=()
  IFS=',' read -r -a host_ports <<<"$(service_ports_for_host "${host}")"
  for spec in "${host_ports[@]}"; do
    parse_service_spec "${spec}"
    if [[ "${SERVICE_PROTO}" == "udp" ]]; then
      if udp_check "${host}" "${SERVICE_PORT}"; then
        reachable+=("${SERVICE_PORT}/udp")
      else
        failed+=("${SERVICE_PORT}/udp")
      fi
    else
      if tcp_check "${host}" "${SERVICE_PORT}"; then
        reachable+=("${SERVICE_PORT}/tcp")
      else
        failed+=("${SERVICE_PORT}/tcp")
      fi
    fi
  done

  write_csv_line \
    "${REPORT_FILE}" \
    "${host}" \
    "${role}" \
    "${ping_state}" \
    "${dns_state}" \
    "$(IFS=' ' ; echo "${reachable[*]:-none}")" \
    "$(IFS=' ' ; echo "${failed[*]:-none}")"

  log "INFO" "Host ${host} role=${role} ping=${ping_state} dns=${dns_state} reachable=${reachable[*]:-none} failed=${failed[*]:-none}"
done

{
  printf 'Host discovery summary\n'
  printf 'Timestamp: %s\n' "${TIMESTAMP}"
  printf 'Hosts checked: %s\n' "${#HOSTS[@]}"
  printf 'Up: %s\n' "${up_count}"
  printf 'Down: %s\n' "${down_count}"
  printf 'Report: %s\n' "${REPORT_FILE}"
  printf 'Log: %s\n' "${LOG_FILE}"
} >"${SUMMARY_FILE}"

log "INFO" "Discovery complete. Summary at ${SUMMARY_FILE}"
