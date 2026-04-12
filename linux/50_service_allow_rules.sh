#!/usr/bin/env bash

# SUBJECT: Resource Approval Request
# BODY:
# Team #: TBD
# Resource Name: 50_service_allow_rules.sh
# Citation: /home/jacob/code/applesauce/linux/50_service_allow_rules.sh
# How Resource Will Be Used: Audit, enforce, or verify service-specific firewall allow-rules derived from host policy.
#
# Audits or enforces host firewall allow-rules derived from the configured
# per-host service matrix, locally or over SSH.
#
# Sources:
#   https://wiki.nftables.org/wiki-nftables/index.php/Quick_reference-nftables_in_10_minutes
#   https://www.openbsd.org/faq/pf/
#   https://documentation.ubuntu.com/security/security-features/network/firewall/
#
# Flags:
#   --remote    Run the selected mode across the hosts in HOSTS over SSH.
#
# Modes:
#   audit       Show the configured per-host allow policy without changing rules.
#   enforce     Apply allow-rules for the mapped local host policy.
#   verify      Re-check allow-rules after audit or enforce.
#
# Usage:
#   ./50_service_allow_rules.sh [audit|enforce|verify]
#   ./50_service_allow_rules.sh [audit|enforce|verify] [--remote]

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
