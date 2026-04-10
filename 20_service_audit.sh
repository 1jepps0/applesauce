#!/usr/bin/env bash

SCRIPT_BASENAME="$(basename "$0" .sh)"
# shellcheck source=lib/common.sh
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"

REPORT_FILE="$(report_file_for "${SCRIPT_BASENAME}")"
SUMMARY_FILE="$(summary_file_for "${SCRIPT_BASENAME}")"

write_csv_line "${REPORT_FILE}" "host" "role" "stage" "target" "result" "details"

pass_count=0
fail_count=0
warn_count=0

run_check() {
  local host="$1"
  local role="$2"
  local stage="$3"
  local target="$4"
  local result="$5"
  local details="$6"

  write_csv_line "${REPORT_FILE}" "${host}" "${role}" "${stage}" "${target}" "${result}" "${details}"
  case "${result}" in
    pass) ((pass_count+=1)) ;;
    fail) ((fail_count+=1)) ;;
    warn) ((warn_count+=1)) ;;
  esac
}

parse_pipe_fields() {
  local raw="$1"
  IFS='|' read -r -a PARSED_FIELDS <<<"${raw}"
}

for host in "${HOSTS[@]}"; do
  role="$(host_role "${host}")"

  if ping_host "${host}"; then
    run_check "${host}" "${role}" "ping" "icmp" "pass" "Host answered ping"
  else
    result="warn"
    [[ "${STRICT_PING_REQUIRED}" == "true" ]] && result="fail"
    run_check "${host}" "${role}" "ping" "icmp" "${result}" "Host did not answer ping"
  fi

  IFS=',' read -r -a host_ports <<<"$(service_ports_for_host "${host}")"
  for port in "${host_ports[@]}"; do
    if tcp_check "${host}" "${port}"; then
      run_check "${host}" "${role}" "service" "tcp/${port}" "pass" "TCP port reachable"
    else
      run_check "${host}" "${role}" "service" "tcp/${port}" "fail" "TCP port unreachable"
    fi
  done

  while IFS= read -r check; do
    [[ -n "${check}" ]] || continue
    IFS=':' read -r _ type target <<<"${check}"
    case "${type}" in
      http)
        if http_check "http" "${host}" "${target}"; then
          run_check "${host}" "${role}" "protocol" "http:${target}" "pass" "HTTP check succeeded"
        else
          run_check "${host}" "${role}" "protocol" "http:${target}" "fail" "HTTP check failed"
        fi
        ;;
      https)
        if http_check "https" "${host}" "${target}"; then
          run_check "${host}" "${role}" "protocol" "https:${target}" "pass" "HTTPS check succeeded"
        else
          run_check "${host}" "${role}" "protocol" "https:${target}" "fail" "HTTPS check failed"
        fi
        ;;
      ssh)
        if ssh_banner_check "${host}" "${target}"; then
          run_check "${host}" "${role}" "protocol" "ssh:${target}" "pass" "SSH banner received"
        else
          run_check "${host}" "${role}" "protocol" "ssh:${target}" "fail" "SSH banner check failed"
        fi
        ;;
      smtp)
        if smtp_banner_check "${host}" "${target}"; then
          run_check "${host}" "${role}" "protocol" "smtp:${target}" "pass" "SMTP banner received"
        else
          run_check "${host}" "${role}" "protocol" "smtp:${target}" "fail" "SMTP banner check failed"
        fi
        ;;
      dns)
        if dns_service_check "${host}"; then
          run_check "${host}" "${role}" "protocol" "dns:${target}" "pass" "DNS query succeeded"
        else
          run_check "${host}" "${role}" "protocol" "dns:${target}" "fail" "DNS query failed"
        fi
        ;;
      tcp)
        if tcp_check "${host}" "${target}"; then
          run_check "${host}" "${role}" "protocol" "tcp:${target}" "pass" "TCP verification succeeded"
        else
          run_check "${host}" "${role}" "protocol" "tcp:${target}" "fail" "TCP verification failed"
        fi
        ;;
      http-status)
        parse_pipe_fields "${target}"
        if [[ "${#PARSED_FIELDS[@]}" -ge 2 ]] && http_status_check "http" "${host}" "${PARSED_FIELDS[0]}" "${PARSED_FIELDS[1]}"; then
          run_check "${host}" "${role}" "functional" "http-status:${target}" "pass" "HTTP status matched expected value"
        else
          run_check "${host}" "${role}" "functional" "http-status:${target}" "fail" "HTTP status check failed"
        fi
        ;;
      https-status)
        parse_pipe_fields "${target}"
        if [[ "${#PARSED_FIELDS[@]}" -ge 2 ]] && http_status_check "https" "${host}" "${PARSED_FIELDS[0]}" "${PARSED_FIELDS[1]}"; then
          run_check "${host}" "${role}" "functional" "https-status:${target}" "pass" "HTTPS status matched expected value"
        else
          run_check "${host}" "${role}" "functional" "https-status:${target}" "fail" "HTTPS status check failed"
        fi
        ;;
      http-body)
        parse_pipe_fields "${target}"
        if [[ "${#PARSED_FIELDS[@]}" -ge 2 ]] && http_body_contains "http" "${host}" "${PARSED_FIELDS[0]}" "${PARSED_FIELDS[1]}"; then
          run_check "${host}" "${role}" "functional" "http-body:${target}" "pass" "HTTP body contained expected text"
        else
          run_check "${host}" "${role}" "functional" "http-body:${target}" "fail" "HTTP body check failed"
        fi
        ;;
      https-body)
        parse_pipe_fields "${target}"
        if [[ "${#PARSED_FIELDS[@]}" -ge 2 ]] && http_body_contains "https" "${host}" "${PARSED_FIELDS[0]}" "${PARSED_FIELDS[1]}"; then
          run_check "${host}" "${role}" "functional" "https-body:${target}" "pass" "HTTPS body contained expected text"
        else
          run_check "${host}" "${role}" "functional" "https-body:${target}" "fail" "HTTPS body check failed"
        fi
        ;;
      ssh-banner)
        parse_pipe_fields "${target}"
        if [[ "${#PARSED_FIELDS[@]}" -ge 2 ]] && tcp_banner_contains "${host}" "${PARSED_FIELDS[0]}" "${PARSED_FIELDS[1]}"; then
          run_check "${host}" "${role}" "functional" "ssh-banner:${target}" "pass" "SSH banner contained expected text"
        else
          run_check "${host}" "${role}" "functional" "ssh-banner:${target}" "fail" "SSH banner content check failed"
        fi
        ;;
      smtp-banner)
        parse_pipe_fields "${target}"
        if [[ "${#PARSED_FIELDS[@]}" -ge 2 ]] && tcp_banner_contains "${host}" "${PARSED_FIELDS[0]}" "${PARSED_FIELDS[1]}"; then
          run_check "${host}" "${role}" "functional" "smtp-banner:${target}" "pass" "SMTP banner contained expected text"
        else
          run_check "${host}" "${role}" "functional" "smtp-banner:${target}" "fail" "SMTP banner content check failed"
        fi
        ;;
      tcp-banner)
        parse_pipe_fields "${target}"
        if [[ "${#PARSED_FIELDS[@]}" -ge 2 ]] && tcp_banner_contains "${host}" "${PARSED_FIELDS[0]}" "${PARSED_FIELDS[1]}"; then
          run_check "${host}" "${role}" "functional" "tcp-banner:${target}" "pass" "TCP banner contained expected text"
        else
          run_check "${host}" "${role}" "functional" "tcp-banner:${target}" "fail" "TCP banner content check failed"
        fi
        ;;
      dns-record)
        parse_pipe_fields "${target}"
        if [[ "${#PARSED_FIELDS[@]}" -ge 3 ]] && dns_record_contains "${host}" "${PARSED_FIELDS[0]}" "${PARSED_FIELDS[1]}" "${PARSED_FIELDS[2]}"; then
          run_check "${host}" "${role}" "functional" "dns-record:${target}" "pass" "DNS record contained expected value"
        else
          run_check "${host}" "${role}" "functional" "dns-record:${target}" "fail" "DNS record check failed"
        fi
        ;;
      *)
        run_check "${host}" "${role}" "protocol" "${type}:${target}" "warn" "Unknown protocol check type"
        ;;
    esac
  done < <(service_checks_for_host "${host}")
done

{
  printf 'Service audit summary\n'
  printf 'Timestamp: %s\n' "${TIMESTAMP}"
  printf 'Pass: %s\n' "${pass_count}"
  printf 'Fail: %s\n' "${fail_count}"
  printf 'Warn: %s\n' "${warn_count}"
  printf 'Report: %s\n' "${REPORT_FILE}"
  printf 'Log: %s\n' "${LOG_FILE}"
} >"${SUMMARY_FILE}"

log "INFO" "Service audit complete. Summary at ${SUMMARY_FILE}"
