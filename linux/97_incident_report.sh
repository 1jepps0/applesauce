#!/usr/bin/env bash

# SUBJECT: Resource Approval Request
# BODY:
# Team #: TBD
# Resource Name: 97_incident_report.sh
# Citation: /home/jacob/code/applesauce/linux/97_incident_report.sh
# How Resource Will Be Used: Create a structured incident report template for competition reporting.
#
# Creates a markdown incident report template populated with basic attack and
# host details for competition reporting.
#
# Sources:
#   https://csrc.nist.gov/pubs/sp/800/61/r3/final
#   https://www.cisa.gov/ncas/current-activity/2021/11/16/new-federal-government-cybersecurity-incident-and-vulnerability
#   https://www.nist.gov/publications/computer-security-log-management
#
# Flags:
#   None.
#
# Positional arguments:
#   <src_ip>      Source IP or source identifier for the incident.
#   <host>        Compromised host name or IP.
#   "<time>"      Attack or detection time. Defaults to the current timestamp.
#   "summary"     Short incident summary. Defaults to a generic description.
#
# Usage:
#   ./97_incident_report.sh <src_ip> <host> "<time>" "summary"

SCRIPT_BASENAME="$(basename "$0" .sh)"
# shellcheck source=lib/common.sh
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"

SOURCE_IP="${1:-unknown}"
COMPROMISED_HOST="${2:-unknown}"
ATTACK_TIME="${3:-$(date '+%F %T %Z')}"
SHORT_DESC="${4:-Suspected unauthorized activity}"

mkdir -p "${INCIDENT_REPORT_DIR}"

REPORT_PATH="${INCIDENT_REPORT_DIR}/incident_${TIMESTAMP}.md"

cat >"${REPORT_PATH}" <<EOF
# Incident Report

- Source IP: ${SOURCE_IP}
- Compromised Host IP/Name: ${COMPROMISED_HOST}
- Time of Attack: ${ATTACK_TIME}
- Summary: ${SHORT_DESC}

## What Happened

Describe the observed attack path, alerts, logs, service impact, and any unauthorized actions.

## Affected Systems and Services

List systems, accounts, ports, processes, files, and business services affected.

## Evidence

- Detection source:
- Relevant logs:
- Network indicators:
- Host indicators:

## Containment and Remediation

Document what was isolated, blocked, disabled, restored, or patched.

## Recovery Verification

Explain how service functionality and security posture were re-validated.

## Follow-up Actions

List residual risk, monitoring changes, credential resets, and remaining tasks.
EOF

log "INFO" "Incident report template created at ${REPORT_PATH}"
