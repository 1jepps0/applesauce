#!/usr/bin/env bash

SCRIPT_BASENAME="$(basename "$0" .sh)"
# shellcheck source=lib/common.sh
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"

ACTION="${1:-push}"
SUMMARY_FILE="$(summary_file_for "${SCRIPT_BASENAME}_${ACTION}")"
REMOTE_STAGE_DIR="/tmp/pcdc_toolkit_stage_${TIMESTAMP}"

run_remote() {
  local host="$1"
  local command="$2"
  ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout="${SSH_CONNECT_TIMEOUT}" \
    -i "${SSH_KEY_PATH}" -p "${SSH_PORT}" "${SSH_USER}@${host}" "${command}"
}

copy_to_remote() {
  local host="$1"
  scp -q -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout="${SSH_CONNECT_TIMEOUT}" \
    -i "${SSH_KEY_PATH}" -P "${SSH_PORT}" -r \
    "${REPO_ROOT}/00_config.sh" \
    "${REPO_ROOT}/lib" \
    "${REPO_ROOT}"/[1-9][0-9]_*.sh \
    "${SSH_USER}@${host}:${REMOTE_STAGE_DIR}/"
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
  if ! tcp_check "${host}" "${SSH_PORT}"; then
    log "WARN" "Skipping ${host}; SSH port ${SSH_PORT} unreachable"
    continue
  fi

  case "${ACTION}" in
    push)
      run_cmd false ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout="${SSH_CONNECT_TIMEOUT}" \
        -i "${SSH_KEY_PATH}" -p "${SSH_PORT}" "${SSH_USER}@${host}" "rm -rf '${REMOTE_STAGE_DIR}' && mkdir -p '${REMOTE_STAGE_DIR}'"
      run_cmd false copy_to_remote "${host}"
      run_cmd false install_remote_toolkit "${host}"
      ;;
    audit)
      run_cmd true run_remote "${host}" "hostname; uname -a; ss -tulpn | head"
      ;;
    service-audit)
      run_cmd true run_remote "${host}" "cd ${REMOTE_TOOLKIT_DIR} && bash ./20_service_audit.sh"
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
