#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${COMMON_DIR}/.." && pwd)"

# shellcheck source=../00_config.sh
source "${REPO_ROOT}/00_config.sh"

TIMESTAMP="${TIMESTAMP:-$(date +%Y%m%d_%H%M%S)}"

mkdir -p "${LOG_DIR}" "${REPORT_DIR}" "${BACKUP_DIR}"

log_file_for() {
  local script_name="$1"
  printf '%s/%s_%s.log\n' "${LOG_DIR}" "${script_name}" "${TIMESTAMP}"
}

report_file_for() {
  local script_name="$1"
  printf '%s/%s_%s.csv\n' "${REPORT_DIR}" "${script_name}" "${TIMESTAMP}"
}

summary_file_for() {
  local script_name="$1"
  printf '%s/%s_%s.txt\n' "${REPORT_DIR}" "${script_name}" "${TIMESTAMP}"
}

SCRIPT_BASENAME="${SCRIPT_BASENAME:-$(basename "${0}" .sh)}"
LOG_FILE="${LOG_FILE:-$(log_file_for "${SCRIPT_BASENAME}")}"

log() {
  local level="$1"
  shift
  local message="$*"
  printf '%s [%s] %s\n' "$(date '+%F %T')" "${level}" "${message}" | tee -a "${LOG_FILE}" >&2
}

die() {
  log "ERROR" "$*"
  exit 1
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

ensure_dependencies() {
  local missing=()
  local dep
  for dep in "$@"; do
    if ! command_exists "${dep}"; then
      missing+=("${dep}")
    fi
  done
  if ((${#missing[@]} > 0)); then
    die "Missing required commands: ${missing[*]}"
  fi
}

csv_escape() {
  local value="${1:-}"
  value="${value//\"/\"\"}"
  printf '"%s"' "${value}"
}

write_csv_line() {
  local file="$1"
  shift
  local first="true"
  local item
  for item in "$@"; do
    if [[ "${first}" == "true" ]]; then
      first="false"
    else
      printf ',' >>"${file}"
    fi
    csv_escape "${item}" >>"${file}"
  done
  printf '\n' >>"${file}"
}

host_role() {
  local host="$1"
  local item
  for item in "${HOST_ROLES[@]}"; do
    if [[ "${item%%:*}" == "${host}" ]]; then
      printf '%s\n' "${item#*:}"
      return 0
    fi
  done
  printf 'unassigned\n'
}

service_ports_for_host() {
  local host="$1"
  local item
  for item in "${HOST_SERVICE_MATRIX[@]}"; do
    if [[ "${item%%:*}" == "${host}" ]]; then
      printf '%s\n' "${item#*:}"
      return 0
    fi
  done
  printf '%s\n' "$(IFS=, ; echo "${SCORING_PORTS[*]}")"
}

service_checks_for_host() {
  local host="$1"
  local item
  for item in "${HOST_SERVICE_CHECKS[@]}"; do
    if [[ "${item%%:*}" == "${host}" ]]; then
      printf '%s\n' "${item}"
    fi
  done
}

backup_file() {
  local file="$1"
  [[ -e "${file}" ]] || return 0
  local dest="${BACKUP_DIR}/$(basename "${file}").${TIMESTAMP}.bak"
  cp -a "${file}" "${dest}"
  log "INFO" "Backed up ${file} to ${dest}"
}

run_cmd() {
  local allow_fail="${1:-false}"
  shift
  log "INFO" "Running: $*"
  if "$@" >>"${LOG_FILE}" 2>&1; then
    return 0
  fi
  if [[ "${allow_fail}" == "true" ]]; then
    log "WARN" "Command failed but was allowed: $*"
    return 1
  fi
  die "Command failed: $*"
}

ping_host() {
  local host="$1"
  ping -c 1 -W 1 "${host}" >/dev/null 2>&1
}

dns_check() {
  local name="$1"
  getent hosts "${name}" >/dev/null 2>&1
}

tcp_check() {
  local host="$1"
  local port="$2"
  if command_exists nc; then
    nc -z -w 2 "${host}" "${port}" >/dev/null 2>&1
    return $?
  fi
  timeout 3 bash -c ":</dev/tcp/${host}/${port}" >/dev/null 2>&1
}

http_check() {
  local scheme="$1"
  local host="$2"
  local target="$3"
  if [[ "${target}" =~ ^[0-9]+$ ]]; then
    curl --silent --show-error --insecure --max-time 5 --head "${scheme}://${host}:${target}" >/dev/null
    return $?
  fi
  curl --silent --show-error --insecure --max-time 5 --head "${scheme}://${host}${target}" >/dev/null
}

http_status_check() {
  local scheme="$1"
  local host="$2"
  local port_or_path="$3"
  local expected_status="$4"
  local url
  if [[ "${port_or_path}" =~ ^[0-9]+$ ]]; then
    url="${scheme}://${host}:${port_or_path}"
  else
    url="${scheme}://${host}${port_or_path}"
  fi
  [[ "$(curl --silent --show-error --insecure --max-time 5 --output /dev/null --write-out '%{http_code}' "${url}" 2>/dev/null || true)" == "${expected_status}" ]]
}

http_body_contains() {
  local scheme="$1"
  local host="$2"
  local path="$3"
  local needle="$4"
  curl --silent --show-error --insecure --max-time 5 "${scheme}://${host}${path}" 2>/dev/null | grep -Fqi "${needle}"
}

ssh_banner_check() {
  local host="$1"
  local port="$2"
  timeout 5 bash -c "exec 3<>/dev/tcp/${host}/${port}; head -n 1 <&3" | grep -qi '^SSH-'
}

tcp_banner_contains() {
  local host="$1"
  local port="$2"
  local needle="$3"
  timeout 5 bash -c "exec 3<>/dev/tcp/${host}/${port}; head -n 3 <&3" 2>/dev/null | grep -Fqi "${needle}"
}

smtp_banner_check() {
  local host="$1"
  local port="$2"
  timeout 5 bash -c "exec 3<>/dev/tcp/${host}/${port}; head -n 1 <&3" | grep -qE '^(220|554)'
}

dns_record_contains() {
  local resolver="$1"
  local name="$2"
  local record_type="$3"
  local expected="$4"
  command_exists dig || return 1
  dig +time=2 +tries=1 @"${resolver}" "${name}" "${record_type}" 2>/dev/null | grep -Fq "${expected}"
}

dns_service_check() {
  local host="$1"
  command_exists dig || return 1
  dig +time=2 +tries=1 @"${host}" localhost A >/dev/null 2>&1
}

detect_firewall_backend() {
  if [[ "${FIREWALL_BACKEND}" != "auto" ]]; then
    printf '%s\n' "${FIREWALL_BACKEND}"
    return 0
  fi
  if command_exists nft; then
    printf 'nft\n'
    return 0
  fi
  if command_exists ufw; then
    printf 'ufw\n'
    return 0
  fi
  if command_exists iptables; then
    printf 'iptables\n'
    return 0
  fi
  printf 'none\n'
}

parse_mode() {
  local mode="${1:-audit}"
  case "${mode}" in
    audit|enforce|verify)
      printf '%s\n' "${mode}"
      ;;
    *)
      die "Unsupported mode '${mode}'. Use audit, enforce, or verify."
      ;;
  esac
}

safe_systemctl_is_active() {
  local service="$1"
  systemctl is-active "${service}" >/dev/null 2>&1
}

safe_systemctl_is_enabled() {
  local service="$1"
  systemctl is-enabled "${service}" >/dev/null 2>&1
}

local_identity_matches() {
  local candidate="$1"
  local short_host fqdn
  short_host="$(hostname -s 2>/dev/null || hostname 2>/dev/null || true)"
  fqdn="$(hostname -f 2>/dev/null || true)"
  [[ "${candidate}" == "127.0.0.1" ]] && return 0
  [[ -n "${short_host}" && "${candidate}" == "${short_host}" ]] && return 0
  [[ -n "${fqdn}" && "${candidate}" == "${fqdn}" ]] && return 0
  return 1
}

local_service_ports() {
  local item host ports
  for item in "${HOST_SERVICE_MATRIX[@]}"; do
    host="${item%%:*}"
    ports="${item#*:}"
    if local_identity_matches "${host}"; then
      printf '%s\n' "${ports}"
      return 0
    fi
  done
  printf '%s\n' "$(IFS=, ; echo "${SCORING_PORTS[*]}")"
}
