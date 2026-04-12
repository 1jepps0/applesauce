#!/usr/bin/env bash

# Verifies or rotates explicitly listed admin account passwords using a supplied
# password source, with conservative safeguards around secret handling.
#
# Flags:
#   None.
#
# Modes:
#   audit       Confirm the listed accounts exist and are eligible for rotation.
#   enforce     Rotate passwords using PASSWORD_FILE.
#   verify      Re-check the listed accounts after audit or enforce.
#
# Usage:
#   ./70_credential_rotation.sh [audit|enforce|verify]

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
  case "${PASSWORD_FILE}" in
    "${REPO_ROOT}"/*)
      die "Password file ${PASSWORD_FILE} is inside the repository. Move it to a protected path outside the repo before enforce mode."
      ;;
  esac
  if command_exists stat; then
    local perms
    perms="$(stat -c '%a' "${PASSWORD_FILE}" 2>/dev/null || stat -f '%Lp' "${PASSWORD_FILE}" 2>/dev/null || true)"
    if [[ -n "${perms}" && ! "${perms}" =~ ^[0-7]?[0-6]0$ && ! "${perms}" =~ ^[0-7]?[0-4]0$ ]]; then
      log "WARN" "Password file ${PASSWORD_FILE} permissions are ${perms}; prefer 600 or 400"
    fi
  fi
  mapfile -t ROTATION_PASSWORDS <"${PASSWORD_FILE}"
  [[ "${#ROTATION_PASSWORDS[@]}" -ge "${#ROTATE_ADMIN_USERS[@]}" ]] || die "Password file does not contain enough entries"
}

verify_account() {
  local user="$1"
  id "${user}" >/dev/null 2>&1
}

rotate_account_password() {
  local user="$1"
  local password="$2"

  if command_exists chpasswd; then
    printf '%s:%s\n' "${user}" "${password}" | chpasswd
    return 0
  fi

  case "$(os_flavor)" in
    freebsd|dragonfly)
      command_exists pw || die "pw is required to rotate passwords on $(os_flavor)"
      printf '%s\n' "${password}" | pw usermod "${user}" -h 0
      ;;
    *)
      die "Credential rotation enforce mode is unsupported on $(os_flavor). Use audit/verify or rotate manually on this platform."
      ;;
  esac
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
    rotate_account_password "${user}" "${password}"
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
