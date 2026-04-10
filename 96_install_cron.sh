#!/usr/bin/env bash

SCRIPT_BASENAME="$(basename "$0" .sh)"
# shellcheck source=lib/common.sh
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"

SCHEDULE=""
SCRIPT_PATH=""

while (($# > 0)); do
  case "$1" in
    --schedule)
      SCHEDULE="$2"
      shift 2
      ;;
    --script)
      SCRIPT_PATH="$2"
      shift 2
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

[[ -n "${SCHEDULE}" ]] || die "--schedule is required"
[[ -n "${SCRIPT_PATH}" ]] || die "--script is required"

ABS_SCRIPT="$(cd "$(dirname "${SCRIPT_PATH}")" && pwd)/$(basename "${SCRIPT_PATH}")"
CRON_LINE="${SCHEDULE} /bin/bash -lc 'cd ${REPO_ROOT} && bash ${ABS_SCRIPT} >> ${LOG_DIR}/cron_$(basename "${SCRIPT_PATH}" .sh).log 2>&1'"

tmp_cron="$(mktemp)"
(crontab -l 2>/dev/null || true) >"${tmp_cron}"

if ! grep -Fq "${ABS_SCRIPT}" "${tmp_cron}"; then
  printf '%s\n' "${CRON_LINE}" >>"${tmp_cron}"
  crontab "${tmp_cron}"
  log "INFO" "Installed cron entry for ${ABS_SCRIPT}"
else
  log "INFO" "Cron entry already present for ${ABS_SCRIPT}"
fi

rm -f "${tmp_cron}"
