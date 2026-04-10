#!/usr/bin/env bash

# Audits or enforces host firewall allow-rules derived from the configured
# per-host service matrix, locally or over SSH.

SCRIPT_BASENAME="$(basename "$0" .sh)"
# shellcheck source=lib/common.sh
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"

MODE="audit"
REMOTE_MODE="false"
parse_args() {
  while (($# > 0)); do
    case "$1" in
      audit|enforce|verify)
        MODE="$(parse_mode "$1")"
        ;;
      --remote)
        REMOTE_MODE="true"
        ;;
      *)
        die "Unsupported argument '$1'. Use audit|enforce|verify and optional --remote."
        ;;
    esac
    shift
  done
}

parse_args "$@"
SUMMARY_FILE="$(summary_file_for "${SCRIPT_BASENAME}_${MODE}")"
validate_host_policy_mappings

if [[ "${REMOTE_MODE}" == "true" ]]; then
  run_current_script_remote_across_hosts "${SUMMARY_FILE}" "service allow-rules ${MODE}" "${MODE}"
  exit 0
fi

BACKEND="$(detect_firewall_backend)"

[[ "${BACKEND}" != "none" ]] || die "No supported firewall backend found"

for host in "${HOSTS[@]}"; do
  role="$(host_role_for_entry "${host}")"
  ports="$(service_ports_for_host "${host}")"
  log "INFO" "Host $(host_display "${host}") role=${role} allowed ports=${ports}"
done

if [[ "${MODE}" == "enforce" ]]; then
  active_port_list="$(local_service_ports)" || die "Could not determine local service policy. Map this host in HOSTS and HOST_SERVICE_MATRIX before enforcing allow-rules."
  case "${BACKEND}" in
    pf)
      rule_file="${BACKUP_DIR}/pf_service_allow_${TIMESTAMP}.conf"
      {
        printf 'set skip on lo0\n'
        printf 'block in all\n'
        printf 'pass out all keep state\n'
        printf 'pass in proto tcp from { %s } to any port %s keep state\n' "$(IFS=', '; echo "${ADMIN_SOURCE_CIDRS[*]}")" "${SSH_PORT}"
        IFS=',' read -r -a active_ports <<<"${active_port_list}"
        for spec in "${active_ports[@]}"; do
          parse_service_spec "${spec}"
          printf 'pass in proto %s to any port %s keep state\n' "${SERVICE_PROTO}" "${SERVICE_PORT}"
        done
      } >"${rule_file}"
      run_cmd false pfctl -f "${rule_file}"
      run_cmd true pfctl -e
      ;;
    nft)
      log "INFO" "nft backend selected. Merge local_service_ports into the nft host ruleset on the target host."
      ;;
    ufw)
      IFS=',' read -r -a active_ports <<<"${active_port_list}"
      for spec in "${active_ports[@]}"; do
        parse_service_spec "${spec}"
        run_cmd false ufw allow "${SERVICE_PORT}"/"${SERVICE_PROTO}"
      done
      ;;
    iptables)
      IFS=',' read -r -a active_ports <<<"${active_port_list}"
      for spec in "${active_ports[@]}"; do
        parse_service_spec "${spec}"
        run_cmd false iptables -A INPUT -p "${SERVICE_PROTO}" --dport "${SERVICE_PORT}" -j ACCEPT
      done
      ;;
  esac
fi

{
  printf 'Service allow-rules summary\n'
  printf 'Mode: %s\n' "${MODE}"
  printf 'Backend: %s\n' "${BACKEND}"
  printf 'OS flavor: %s\n' "$(os_flavor)"
  printf 'Host matrix entries: %s\n' "${#HOST_SERVICE_MATRIX[@]}"
  printf 'Log: %s\n' "${LOG_FILE}"
} >"${SUMMARY_FILE}"

log "INFO" "Service allow-rules ${MODE} complete. Summary at ${SUMMARY_FILE}"
