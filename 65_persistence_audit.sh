#!/usr/bin/env bash

SCRIPT_BASENAME="$(basename "$0" .sh)"
# shellcheck source=lib/common.sh
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"

REPORT_FILE="$(report_file_for "${SCRIPT_BASENAME}")"
SUMMARY_FILE="$(summary_file_for "${SCRIPT_BASENAME}")"

write_csv_line "${REPORT_FILE}" "category" "path" "result" "details"

record() {
  write_csv_line "${REPORT_FILE}" "$1" "$2" "$3" "$4"
  log "INFO" "$1 | $2 | $3 | $4"
}

for path in /etc/crontab /etc/cron.d /etc/cron.daily /etc/cron.hourly /etc/cron.weekly /etc/cron.monthly; do
  [[ -e "${path}" ]] || continue
  record "cron_path" "${path}" "info" "Present"
done

if is_linux && [[ -d /etc/systemd/system ]]; then
  while IFS= read -r unit; do
    [[ -n "${unit}" ]] || continue
    record "systemd_unit" "${unit}" "info" "Custom unit file present"
  done < <(find /etc/systemd/system -maxdepth 2 -type f \( -name '*.service' -o -name '*.timer' \) 2>/dev/null || true)
fi

for startup_dir in /etc/init.d /etc/rc.local /usr/local/bin /usr/local/sbin; do
  [[ -e "${startup_dir}" ]] || continue
  record "startup_path" "${startup_dir}" "info" "Present"
done

if is_bsd; then
  for path in /etc/rc.conf /etc/rc.conf.local /etc/rc.d /usr/local/etc/rc.d /etc/pf.conf /etc/crontab; do
    [[ -e "${path}" ]] || continue
    record "bsd_startup" "${path}" "info" "Present"
  done
fi

if command_exists find; then
  while IFS= read -r suid_file; do
    [[ -n "${suid_file}" ]] || continue
    record "suid" "${suid_file}" "warn" "SUID/SGID file present"
  done < <(find / -xdev \( -perm -4000 -o -perm -2000 \) -type f 2>/dev/null | head -n 200 || true)
fi

{
  printf 'Persistence audit summary\n'
  printf 'Timestamp: %s\n' "${TIMESTAMP}"
  printf 'Report: %s\n' "${REPORT_FILE}"
  printf 'Log: %s\n' "${LOG_FILE}"
} >"${SUMMARY_FILE}"

log "INFO" "Persistence audit complete. Summary at ${SUMMARY_FILE}"
