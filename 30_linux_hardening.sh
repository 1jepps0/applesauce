#!/usr/bin/env bash

SCRIPT_BASENAME="$(basename "$0" .sh)"
# shellcheck source=lib/common.sh
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"

MODE="$(parse_mode "${1:-audit}")"
SUMMARY_FILE="$(summary_file_for "${SCRIPT_BASENAME}_${MODE}")"
SSHD_CONFIG_FILE="/etc/ssh/sshd_config"

changes=0
findings=0

record_finding() {
  ((findings+=1))
  log "WARN" "$*"
}

apply_change() {
  ((changes+=1))
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

if [[ "${DISABLE_ROOT_SSH}" == "true" ]]; then
  ensure_sshd_setting "PermitRootLogin" "no"
else
  log "INFO" "Root SSH disable is not enabled in config"
fi

ensure_sshd_setting "PermitEmptyPasswords" "no"

if [[ "${DISABLE_PASSWORD_AUTH}" == "true" ]]; then
  ensure_sshd_setting "PasswordAuthentication" "no"
else
  log "INFO" "PasswordAuthentication hardening not enforced by config"
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

{
  printf 'Unix hardening summary\n'
  printf 'OS family: %s\n' "$(os_family)"
  printf 'OS name: %s\n' "$(os_name)"
  printf 'OS flavor: %s\n' "$(os_flavor)"
  printf 'Mode: %s\n' "${MODE}"
  printf 'Findings: %s\n' "${findings}"
  printf 'Changes: %s\n' "${changes}"
  printf 'Log: %s\n' "${LOG_FILE}"
} >"${SUMMARY_FILE}"

log "INFO" "Unix hardening ${MODE} complete. Summary at ${SUMMARY_FILE}"
