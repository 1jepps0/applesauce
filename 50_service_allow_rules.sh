#!/usr/bin/env bash

SCRIPT_BASENAME="$(basename "$0" .sh)"
# shellcheck source=lib/common.sh
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"

MODE="$(parse_mode "${1:-audit}")"
SUMMARY_FILE="$(summary_file_for "${SCRIPT_BASENAME}_${MODE}")"
BACKEND="$(detect_firewall_backend)"

[[ "${BACKEND}" != "none" ]] || die "No supported firewall backend found"

for host in "${HOSTS[@]}"; do
  role="$(host_role "${host}")"
  ports="$(service_ports_for_host "${host}")"
  log "INFO" "Host ${host} role=${role} allowed ports=${ports}"
done

if [[ "${MODE}" == "enforce" ]]; then
  case "${BACKEND}" in
    nft)
      log "INFO" "nft backend selected. Merge local_service_ports into the nft host ruleset on the target host."
      ;;
    ufw)
      IFS=',' read -r -a active_ports <<<"$(local_service_ports)"
      for port in "${active_ports[@]}"; do
        run_cmd false ufw allow "${port}"/tcp
      done
      ;;
    iptables)
      IFS=',' read -r -a active_ports <<<"$(local_service_ports)"
      for port in "${active_ports[@]}"; do
        run_cmd false iptables -A INPUT -p tcp --dport "${port}" -j ACCEPT
      done
      ;;
  esac
fi

{
  printf 'Service allow-rules summary\n'
  printf 'Mode: %s\n' "${MODE}"
  printf 'Backend: %s\n' "${BACKEND}"
  printf 'Host matrix entries: %s\n' "${#HOST_SERVICE_MATRIX[@]}"
  printf 'Log: %s\n' "${LOG_FILE}"
} >"${SUMMARY_FILE}"

log "INFO" "Service allow-rules ${MODE} complete. Summary at ${SUMMARY_FILE}"
