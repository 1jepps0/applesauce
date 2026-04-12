#!/usr/bin/env bash

# Audits or enforces a conservative host-hardening baseline locally or over SSH,
# covering SSH settings, service state, and key sysctl values.
#
# Usage:
#   ./30_linux_hardening.sh [audit|enforce|verify]
#   ./30_linux_hardening.sh [audit|enforce|verify] --remote

SCRIPT_BASENAME="$(basename "$0" .sh)"
# shellcheck source=lib/common.sh
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"

MODE="audit"
REMOTE_MODE="false"
SUMMARY_FILE=""
SSHD_CONFIG_FILE="/etc/ssh/sshd_config"
AUDIT_HOST="$(hostname -f 2>/dev/null || hostname 2>/dev/null || echo localhost)"
REMOTE_STAGE_DIR="/tmp/pcdc_hardening_${TIMESTAMP}"

changes=0
findings=0
declare -a FINDING_LINES=()
declare -a CHANGE_LINES=()
declare -a REMOTE_SUMMARY_LINES=()

log_host_block() {
  local display_host="$1"
  local default_level="$2"
  local content="${3:-}"
  local line
  [[ -n "${content}" ]] || return 0
  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    log "${default_level}" "[${display_host}] ${line}"
  done <<<"${content}"
}

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
  SUMMARY_FILE="$(summary_file_for "${SCRIPT_BASENAME}_${MODE}")"
}

run_remote() {
  local host="$1"
  local command="$2"
  ssh_to_host "${host}" "${command}"
}

stage_remote_toolkit() {
  local host="$1"
  run_remote "${host}" "rm -rf '${REMOTE_STAGE_DIR}' && mkdir -p '${REMOTE_STAGE_DIR}'"
  scp_to_host "${host}" \
    "${REPO_ROOT}/00_config.sh" \
    "${REPO_ROOT}/lib" \
    "${REPO_ROOT}/30_linux_hardening.sh"
}

remote_hardening_cmd() {
  if [[ "${REMOTE_SUDO}" == "true" ]]; then
    printf '%s\n' "cd '${REMOTE_STAGE_DIR}' && sudo bash ./30_linux_hardening.sh ${MODE}"
  else
    printf '%s\n' "cd '${REMOTE_STAGE_DIR}' && bash ./30_linux_hardening.sh ${MODE}"
  fi
}

cleanup_remote_stage() {
  local host="$1"
  if [[ "${REMOTE_SUDO}" == "true" ]]; then
    run_remote "${host}" "sudo rm -rf '${REMOTE_STAGE_DIR}'" >/dev/null 2>&1 || true
  else
    run_remote "${host}" "rm -rf '${REMOTE_STAGE_DIR}'" >/dev/null 2>&1 || true
  fi
}

record_finding() {
  ((findings+=1))
  FINDING_LINES+=("$*")
  log "WARN" "$*"
}

apply_change() {
  ((changes+=1))
  CHANGE_LINES+=("$*")
  log "INFO" "$*"
}

ensure_sshd_setting() {
  local key="$1"
  local value="$2"
  local file="${SSHD_CONFIG_FILE}"

  [[ -f "${file}" ]] || {
    record_finding "Missing ${file}"
    return 1
  }

  if grep -qiE "^[#[:space:]]*${key}[[:space:]]+${value}\$" "${file}"; then
    return 0
  fi

  record_finding "Expected ${key} ${value} in ${file}"
  if [[ "${MODE}" == "enforce" ]]; then
    backup_file "${file}"
    if grep -qiE "^[#[:space:]]*${key}[[:space:]]+" "${file}"; then
      if is_bsd; then
        sed -i '' -E "s|^[#[:space:]]*${key}[[:space:]]+.*|${key} ${value}|I" "${file}"
      else
        sed -i -E "s|^[#[:space:]]*${key}[[:space:]]+.*|${key} ${value}|I" "${file}"
      fi
    else
      printf '\n%s %s\n' "${key}" "${value}" >>"${file}"
    fi
    apply_change "Set ${key} ${value} in ${file}"
  fi
}

ensure_service_state() {
  local service="$1"
  local desired="$2"
  if ! command_exists systemctl && ! command_exists service; then
    record_finding "No supported service manager available; cannot manage ${service}"
    return 1
  fi

  case "${desired}" in
    enabled)
      if service_is_enabled "${service}"; then
        return 0
      fi
      record_finding "Service ${service} is not enabled"
      if [[ "${MODE}" == "enforce" ]]; then
        service_manage "enable" "${service}"
        apply_change "Enabled ${service}"
      fi
      ;;
    active)
      if service_is_active "${service}"; then
        return 0
      fi
      record_finding "Service ${service} is not active"
      if [[ "${MODE}" == "enforce" ]]; then
        service_manage "start" "${service}"
        apply_change "Started ${service}"
      fi
      ;;
    disabled)
      if ! service_is_enabled "${service}" && ! service_is_active "${service}"; then
        return 0
      fi
      record_finding "Service ${service} should be disabled"
      if [[ "${MODE}" == "enforce" ]]; then
        service_manage "disable" "${service}"
        service_manage "stop" "${service}"
        apply_change "Disabled ${service}"
      fi
      ;;
  esac
}

apply_sysctl_control() {
  local key="$1"
  local value="$2"
  local current
  current="$(sysctl -n "${key}" 2>/dev/null || true)"
  if [[ "${current}" == "${value}" ]]; then
    return 0
  fi
  record_finding "Expected sysctl ${key}=${value}, found ${current:-unset}"
  if [[ "${MODE}" == "enforce" ]]; then
    local file
    file="$(sysctl_persist_file)"
    set_persistent_line "${file}" "^${key}[= ]" "${key}=${value}"
    run_cmd false sysctl -w "${key}=${value}"
    apply_change "Applied sysctl ${key}=${value}"
  fi
}

print_local_summary() {
  {
    printf 'Unix hardening summary\n'
    printf 'Host: %s\n' "${AUDIT_HOST}"
    printf 'OS family: %s\n' "$(os_family)"
    printf 'OS name: %s\n' "$(os_name)"
    printf 'OS flavor: %s\n' "$(os_flavor)"
    printf 'Mode: %s\n' "${MODE}"
    printf 'Findings: %s\n' "${findings}"
    printf 'Changes: %s\n' "${changes}"
    printf 'Log: %s\n' "${LOG_FILE}"
  } >"${SUMMARY_FILE}"

  log "INFO" "Hardening summary: host=${AUDIT_HOST} mode=${MODE} findings=${findings} changes=${changes} os=$(os_name)"
  log "INFO" "Checks performed: sshd settings, required services, optional disabled services, audit service, sysctl baseline"

  if ((${#FINDING_LINES[@]} > 0)); then
    log "INFO" "Findings:"
    for item in "${FINDING_LINES[@]}"; do
      log "INFO" "  - ${item}"
    done
  else
    log "INFO" "Findings: none"
  fi

  if ((${#CHANGE_LINES[@]} > 0)); then
    log "INFO" "Changes applied:"
    for item in "${CHANGE_LINES[@]}"; do
      log "INFO" "  - ${item}"
    done
  elif [[ "${MODE}" == "enforce" ]]; then
    log "INFO" "Changes applied: none"
  fi

  log "INFO" "Unix hardening ${MODE} complete. Summary at ${SUMMARY_FILE}"
}

run_local_hardening() {
  if [[ "${DISABLE_ROOT_SSH}" == "true" ]]; then
    ensure_sshd_setting "PermitRootLogin" "no"
  else
    log "INFO" "Config leaves root SSH login unchanged (DISABLE_ROOT_SSH=false)"
  fi

  ensure_sshd_setting "PermitEmptyPasswords" "no"

  if [[ "${DISABLE_PASSWORD_AUTH}" == "true" ]]; then
    ensure_sshd_setting "PasswordAuthentication" "no"
  else
    log "INFO" "Config leaves SSH password auth unchanged (DISABLE_PASSWORD_AUTH=false)"
  fi

  for service in "${REQUIRED_SERVICES[@]}"; do
    ensure_service_state "${service}" "enabled"
    ensure_service_state "${service}" "active"
  done

  for service in "${OPTIONAL_DISABLE_SERVICES[@]}"; do
    ensure_service_state "${service}" "disabled"
  done

  if [[ "${ENABLE_AUDITD}" == "true" ]] && is_linux; then
    ensure_service_state "auditd" "enabled"
    ensure_service_state "auditd" "active"
  fi

  if [[ "${APPLY_SYSCTL_BASELINE}" == "true" ]]; then
    if is_bsd; then
      apply_sysctl_control "net.inet.ip.forwarding" "0"
      apply_sysctl_control "net.inet.icmp.drop_redirect" "1"
      apply_sysctl_control "net.inet.tcp.syncookies" "1"
    else
      apply_sysctl_control "net.ipv4.ip_forward" "0"
      apply_sysctl_control "net.ipv4.conf.all.accept_redirects" "0"
      apply_sysctl_control "net.ipv4.conf.all.send_redirects" "0"
      apply_sysctl_control "net.ipv4.tcp_syncookies" "1"
    fi
  fi

  if [[ "${MODE}" == "enforce" ]]; then
    if command_exists sshd; then
      run_cmd false sshd -t
    fi
    if command_exists systemctl || command_exists service; then
      service_manage "reload" "sshd"
    fi
  fi

  print_local_summary
}

run_remote_hardening() {
  validate_host_policy_mappings

  for host in "${HOSTS[@]}"; do
    target_host="$(host_address "${host}")"
    display_host="$(host_display "${host}")"

    if ! tcp_check "${target_host}" "${SSH_PORT}"; then
      log "WARN" "Skipping ${display_host}; SSH port ${SSH_PORT} unreachable"
      REMOTE_SUMMARY_LINES+=("${display_host}: unreachable")
      continue
    fi

    log "INFO" "========== ${display_host} remote hardening start (mode=${MODE}) =========="

    if ! stage_output="$(stage_remote_toolkit "${target_host}" 2>&1)"; then
      log_host_block "${display_host}" "WARN" "${stage_output}"
      log "WARN" "Remote hardening failed on ${display_host}: could not stage toolkit"
      REMOTE_SUMMARY_LINES+=("${display_host}: staging failed")
      cleanup_remote_stage "${target_host}"
      log "INFO" "========== ${display_host} remote hardening end =========="
      continue
    fi
    log_host_block "${display_host}" "INFO" "${stage_output}"

    if remote_output="$(run_remote "${target_host}" "$(remote_hardening_cmd)" 2>&1)"; then
      log_host_block "${display_host}" "INFO" "${remote_output}"
      log "INFO" "Remote hardening succeeded on ${display_host}"
      REMOTE_SUMMARY_LINES+=("${display_host}: success")
    else
      log_host_block "${display_host}" "WARN" "${remote_output}"
      log "WARN" "Remote hardening failed on ${display_host}"
      REMOTE_SUMMARY_LINES+=("${display_host}: execution failed")
    fi

    cleanup_remote_stage "${target_host}"
    log "INFO" "========== ${display_host} remote hardening end =========="
  done

  {
    printf 'Remote unix hardening summary\n'
    printf 'Mode: %s\n' "${MODE}"
    printf 'Hosts configured: %s\n' "${#HOSTS[@]}"
    printf 'Log: %s\n' "${LOG_FILE}"
    printf '\nHost status:\n'
    printf '%s\n' "${REMOTE_SUMMARY_LINES[@]}"
  } >"${SUMMARY_FILE}"

  log "INFO" "Remote hardening summary:"
  for item in "${REMOTE_SUMMARY_LINES[@]}"; do
    log "INFO" "  - ${item}"
  done
  log "INFO" "Remote unix hardening ${MODE} complete. Summary at ${SUMMARY_FILE}"
}

parse_args "$@"

if [[ "${REMOTE_MODE}" == "true" ]]; then
  run_remote_hardening
else
  run_local_hardening
fi
