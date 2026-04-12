#!/usr/bin/env bash

# Copies the toolkit to remote hosts and runs selected remote commands using the
# configured SSH authentication settings.
#
# Flags:
#   None.
#
# Actions:
#   push            Copy the toolkit to each reachable host.
#   audit           Run a remote listener snapshot on each reachable host.
#   service-audit   Run ./20_service_audit.sh from the remote toolkit path.
#
# Usage:
#   ./80_ssh_deploy.sh [push|audit|service-audit]

SCRIPT_BASENAME="$(basename "$0" .sh)"
# shellcheck source=lib/common.sh
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"

ACTION="${1:-push}"
SUMMARY_FILE="$(summary_file_for "${SCRIPT_BASENAME}_${ACTION}")"
REMOTE_STAGE_DIR="/tmp/pcdc_toolkit_stage_${TIMESTAMP}"

run_remote() {
  local host="$1"
  local command="$2"
  ssh_to_host "${host}" "${command}"
}

copy_to_remote() {
  local host="$1"
  scp_to_host "${host}" \
    "${REPO_ROOT}/00_config.sh" \
    "${REPO_ROOT}/lib" \
    "${REPO_ROOT}"/[1-9][0-9]_*.sh
}

remote_listener_snapshot_cmd() {
  printf '%s\n' "hostname; uname -a; if command -v ss >/dev/null 2>&1; then ss -tulpn | head; elif command -v sockstat >/dev/null 2>&1; then sockstat -4 -6 -l | head; elif command -v netstat >/dev/null 2>&1; then netstat -an | grep -E 'LISTEN|udp' | head; else echo 'no supported listener tool found'; fi"
}

install_remote_toolkit() {
  local host="$1"
  if [[ "${REMOTE_SUDO}" == "true" ]]; then
    run_remote "${host}" "sudo mkdir -p '${REMOTE_TOOLKIT_DIR}' && sudo cp -a '${REMOTE_STAGE_DIR}/.' '${REMOTE_TOOLKIT_DIR}/' && rm -rf '${REMOTE_STAGE_DIR}'"
  else
    run_remote "${host}" "mkdir -p '${REMOTE_TOOLKIT_DIR}' && cp -a '${REMOTE_STAGE_DIR}/.' '${REMOTE_TOOLKIT_DIR}/' && rm -rf '${REMOTE_STAGE_DIR}'"
  fi
}

for host in "${HOSTS[@]}"; do
  target_host="$(host_address "${host}")"
  if ! tcp_check "${target_host}" "${SSH_PORT}"; then
    log "WARN" "Skipping $(host_display "${host}"); SSH port ${SSH_PORT} unreachable"
    continue
  fi

  case "${ACTION}" in
    push)
      run_cmd false run_remote "${target_host}" "rm -rf '${REMOTE_STAGE_DIR}' && mkdir -p '${REMOTE_STAGE_DIR}'"
      run_cmd false copy_to_remote "${target_host}"
      run_cmd false install_remote_toolkit "${target_host}"
      ;;
    audit)
      run_cmd true run_remote "${target_host}" "$(remote_listener_snapshot_cmd)"
      ;;
    service-audit)
      run_cmd true run_remote "${target_host}" "cd ${REMOTE_TOOLKIT_DIR} && bash ./20_service_audit.sh"
      ;;
    *)
      die "Unsupported action '${ACTION}'. Use push, audit, or service-audit."
      ;;
  esac
done

{
  printf 'SSH deploy summary\n'
  printf 'Action: %s\n' "${ACTION}"
  printf 'Hosts configured: %s\n' "${#HOSTS[@]}"
  printf 'Log: %s\n' "${LOG_FILE}"
} >"${SUMMARY_FILE}"

log "INFO" "SSH deploy action ${ACTION} complete. Summary at ${SUMMARY_FILE}"
