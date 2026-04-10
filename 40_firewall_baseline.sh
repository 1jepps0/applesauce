#!/usr/bin/env bash

SCRIPT_BASENAME="$(basename "$0" .sh)"
# shellcheck source=lib/common.sh
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"

MODE="$(parse_mode "${1:-audit}")"
SUMMARY_FILE="$(summary_file_for "${SCRIPT_BASENAME}_${MODE}")"
BACKEND="$(detect_firewall_backend)"

if [[ "${BACKEND}" == "none" ]]; then
  die "No supported firewall backend found"
fi

build_allow_ports() {
  local ports=("${SCORING_PORTS[@]}")
  printf '%s\n' "${ports[@]}" | sort -u
}

audit_backend() {
  case "${BACKEND}" in
    pf)
      run_cmd false pfctl -sr
      ;;
    nft)
      run_cmd false nft list ruleset
      ;;
    ufw)
      run_cmd false ufw status verbose
      ;;
    iptables)
      run_cmd false iptables -S
      ;;
  esac
}

enforce_pf() {
  local rule_file="${BACKUP_DIR}/pf_baseline_${TIMESTAMP}.conf"
  [[ -f /etc/pf.conf ]] && backup_file "/etc/pf.conf"
  {
    printf 'set skip on lo0\n'
    printf 'block in all\n'
    printf 'pass out all keep state\n'
    printf 'pass in proto tcp from { %s } to any port %s keep state\n' "$(IFS=', '; echo "${ADMIN_SOURCE_CIDRS[*]}")" "${SSH_PORT}"
    local spec
    while IFS= read -r spec; do
      parse_service_spec "${spec}"
      printf 'pass in proto %s to any port %s keep state\n' "${SERVICE_PROTO}" "${SERVICE_PORT}"
    done < <(build_allow_ports)
  } >"${rule_file}"
  run_cmd false pfctl -f "${rule_file}"
  run_cmd true pfctl -e
}

enforce_nft() {
  local rule_file="${BACKUP_DIR}/nft_baseline_${TIMESTAMP}.nft"
  {
    printf 'table inet pcdc {\n'
    printf '  chain input {\n'
    printf '    type filter hook input priority 0;\n'
    printf '    policy %s;\n' "$([[ "${DEFAULT_DROP_INPUT}" == "true" ]] && echo drop || echo accept)"
    printf '    iif lo accept\n'
    printf '    ct state established,related accept\n'
    local cidr
    for cidr in "${ADMIN_SOURCE_CIDRS[@]}"; do
      printf '    ip saddr %s tcp dport %s accept\n' "${cidr}" "${SSH_PORT}"
    done
    local spec
    while IFS= read -r spec; do
      parse_service_spec "${spec}"
      printf '    %s dport %s accept\n' "${SERVICE_PROTO}" "${SERVICE_PORT}"
    done < <(build_allow_ports)
    printf '  }\n'
    printf '}\n'
  } >"${rule_file}"
  run_cmd false nft -f "${rule_file}"
}

enforce_ufw() {
  run_cmd false ufw --force reset
  if [[ "${DEFAULT_DROP_INPUT}" == "true" ]]; then
    run_cmd false ufw default deny incoming
  else
    run_cmd false ufw default allow incoming
  fi
  run_cmd false ufw default allow outgoing
  local cidr
  for cidr in "${ADMIN_SOURCE_CIDRS[@]}"; do
    run_cmd false ufw allow from "${cidr}" to any port "${SSH_PORT}" proto tcp
  done
  local spec
  while IFS= read -r spec; do
    parse_service_spec "${spec}"
    run_cmd false ufw allow "${SERVICE_PORT}"/"${SERVICE_PROTO}"
  done < <(build_allow_ports)
  run_cmd false ufw --force enable
}

enforce_iptables() {
  local save_file="${BACKUP_DIR}/iptables_baseline_${TIMESTAMP}.rules"
  if command_exists iptables-save; then
    iptables-save >"${save_file}"
  fi
  run_cmd false iptables -P INPUT "$([[ "${DEFAULT_DROP_INPUT}" == "true" ]] && echo DROP || echo ACCEPT)"
  run_cmd false iptables -P FORWARD DROP
  run_cmd false iptables -P OUTPUT ACCEPT
  run_cmd true iptables -F INPUT
  run_cmd false iptables -A INPUT -i lo -j ACCEPT
  run_cmd false iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  local cidr
  for cidr in "${ADMIN_SOURCE_CIDRS[@]}"; do
    run_cmd false iptables -A INPUT -p tcp -s "${cidr}" --dport "${SSH_PORT}" -j ACCEPT
  done
  local spec
  while IFS= read -r spec; do
    parse_service_spec "${spec}"
    run_cmd false iptables -A INPUT -p "${SERVICE_PROTO}" --dport "${SERVICE_PORT}" -j ACCEPT
  done < <(build_allow_ports)
}

case "${MODE}" in
  audit|verify)
    audit_backend
    ;;
  enforce)
    case "${BACKEND}" in
      pf) enforce_pf ;;
      nft) enforce_nft ;;
      ufw) enforce_ufw ;;
      iptables) enforce_iptables ;;
    esac
    ;;
esac

{
  printf 'Firewall baseline summary\n'
  printf 'Mode: %s\n' "${MODE}"
  printf 'Backend: %s\n' "${BACKEND}"
  printf 'OS flavor: %s\n' "$(os_flavor)"
  printf 'Log: %s\n' "${LOG_FILE}"
} >"${SUMMARY_FILE}"

log "INFO" "Firewall baseline ${MODE} complete. Summary at ${SUMMARY_FILE}"
