#!/usr/bin/env bash

# Creates a markdown incident report template populated with basic attack and
# host details for competition reporting.

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
