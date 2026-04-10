#!/usr/bin/env bash

SCRIPT_BASENAME="$(basename "$0" .sh)"
# shellcheck source=lib/common.sh
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"

MODE="$(parse_mode "${1:-audit}")"
SUMMARY_FILE="$(summary_file_for "${SCRIPT_BASENAME}_${MODE}")"

load_passwords() {
  if [[ -z "${PASSWORD_FILE}" ]]; then
    die "PASSWORD_FILE is not set. Populate 00_config.sh before rotation."
  fi
  [[ -f "${PASSWORD_FILE}" ]] || die "Password file ${PASSWORD_FILE} not found"
  mapfile -t ROTATION_PASSWORDS <"${PASSWORD_FILE}"
  [[ "${#ROTATION_PASSWORDS[@]}" -ge "${#ROTATE_ADMIN_USERS[@]}" ]] || die "Password file does not contain enough entries"
}

verify_account() {
  local user="$1"
  id "${user}" >/dev/null 2>&1
}

if [[ "${MODE}" == "audit" || "${MODE}" == "verify" ]]; then
  for user in "${ROTATE_ADMIN_USERS[@]}"; do
    if verify_account "${user}"; then
      log "INFO" "Account ${user} exists and is eligible for rotation"
    else
      log "WARN" "Account ${user} does not exist"
    fi
  done
else
  load_passwords
  for idx in "${!ROTATE_ADMIN_USERS[@]}"; do
    user="${ROTATE_ADMIN_USERS[$idx]}"
    password="${ROTATION_PASSWORDS[$idx]}"
    if ! verify_account "${user}"; then
      log "WARN" "Skipping missing account ${user}"
      continue
    fi
    printf '%s:%s\n' "${user}" "${password}" | chpasswd
    log "INFO" "Rotated password for ${user}"
  done
fi

{
  printf 'Credential rotation summary\n'
  printf 'Mode: %s\n' "${MODE}"
  printf 'Users configured: %s\n' "${#ROTATE_ADMIN_USERS[@]}"
  printf 'Log: %s\n' "${LOG_FILE}"
} >"${SUMMARY_FILE}"

log "INFO" "Credential rotation ${MODE} complete. Summary at ${SUMMARY_FILE}"
