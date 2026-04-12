#!/usr/bin/env bash

# Shared toolkit configuration for host inventory, service policy, SSH access,
# credential rotation settings, and feature toggles.
#
# Flags:
#   None. This file is edited directly instead of invoked with CLI flags.
#
# Usage:
#   Edit this file before running the toolkit.

# PCDC 2026 guide notes relevant to this toolkit:
# - Blue team environments may include multiple Linux distros and BSD.
# - Example Linux references include CentOS and Ubuntu.
# - Service availability and incident reporting are heavily scored.
# - Port scans and vulnerability scans against competition assets are prohibited.

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

LOG_DIR="${SCRIPT_ROOT}/logs"
REPORT_DIR="${SCRIPT_ROOT}/reports"
BACKUP_DIR="${SCRIPT_ROOT}/backups"
REMOTE_TOOLKIT_DIR="/opt/pcdc_toolkit"
INCIDENT_REPORT_DIR="${REPORT_DIR}/incident_reports"
COMPETITION_MODE="true"

HOSTS=(
  "jumpbox=10.0.0.72"
  "web01=10.0.0.154"
  "dns01=10.0.0.191"
  "mail01=10.0.0.215"
)

# Prefer HOSTS entries in the form role=ip_or_fqdn once you know the host mapping from
# the blue-team packet, for example:
# HOSTS=(
#   "jumpbox=10.0.0.72"
#   "web01=10.0.0.154"
# )
# Optional alias map when HOSTS must remain plain addresses:
# HOST_ALIASES=(
#   "10.0.0.72:jumpbox"
# )
HOST_ALIASES=(
)

DOMAINS=(
)

SCORING_PORTS=(
  22
  80
  443
  53/udp
)

ADMIN_SOURCE_CIDRS=(
  "10.10.10.0/24"
)
SSH_USER="root"
SSH_PORT="22"
SSH_KEY_PATH="${HOME}/.ssh/id_rsa"
SSH_CONNECT_TIMEOUT="5"
# SSH auth modes:
# - key: use SSH_KEY_PATH with non-interactive key auth
# - password: use sshpass with SSH_PASSWORD, SSH_PASSWORD_FILE, or SSH_PASSWORD_ENV
SSH_AUTH_MODE="password"
SSH_PASSWORD="cookie13433"
SSH_PASSWORD_FILE=""
SSH_PASSWORD_ENV=""

ALLOWED_ADMIN_USERS=(
  "root"
)

ROTATE_ADMIN_USERS=(
  "root"
)

# Keep rotation secrets outside the repo and set this explicitly before enforce mode,
# for example "${HOME}/.config/pcdc_toolkit/passwords.txt".
PASSWORD_FILE=""

REQUIRED_SERVICES=(
  "sshd"
  "cron"
  "rsyslog"
)

# For BSD targets, replace Linux-specific examples like "rsyslog" with native services
# such as "syslogd", and prefer pf-backed firewall handling.
# OpenBSD commonly uses rcctl + pf + syspatch/pkg_add, while FreeBSD commonly uses
# service/sysrc + pf + pkg.

OPTIONAL_DISABLE_SERVICES=(
  "avahi-daemon"
  "cups"
  "rpcbind"
)

HOST_SERVICE_MATRIX=(
  "jumpbox:22"
  "web01:22,80,443"
  "dns01:22,53/tcp,53/udp"
  "mail01:22,25,110,143,465,587,993,995"
  "db01:22,3306,5432"
  "files01:22,139,445"
  "mon01:22,443"
)

HOST_SERVICE_CHECKS=(
  "jumpbox:ssh:22"
  "jumpbox:ssh-banner:22|SSH-"
  "web01:http-status:80|200"
  "web01:https-status:443|200"
  "web01:http-body:/|html"
  "web01:https-body:/|html"
  "web01:ssh-banner:22|SSH-"
  "dns01:tcp:53"
  "dns01:dns-record:corp.local|SOA|corp.local."
  "dns01:dns-record:www.corp.local|A|10.10.20.20"
  "dns01:ssh-banner:22|SSH-"
  "mail01:smtp:25"
  "mail01:smtp-banner:25|220"
  "mail01:tcp-banner:110|+OK"
  "mail01:tcp-banner:143|*"
  "mail01:ssh-banner:22|SSH-"
  "db01:tcp:3306"
  "db01:tcp:5432"
  "db01:ssh-banner:22|SSH-"
  "files01:tcp:139"
  "files01:tcp:445"
  "files01:ssh-banner:22|SSH-"
  "mon01:https-status:443|200"
  "mon01:https-body:/|Security"
  "mon01:ssh-banner:22|SSH-"
)

# Extended service check formats for 20_service_audit.sh:
# - "host:http-status:80|200"
# - "host:https-status:443|200"
# - "host:http-body:/login|Welcome"
# - "host:https-body:/health|OK"
# - "host:ssh-banner:22|SSH-2.0"
# - "host:smtp-banner:25|220"
# - "host:tcp-banner:110|+OK"
# - "host:dns-record:example.local|A|10.0.0.10"

HOST_ROLES=(
  "jumpbox:jumpbox"
  "web01:web"
  "dns01:dns"
  "mail01:mail"
  "db01:database"
  "files01:fileserver"
  "mon01:securityonion"
)

STRICT_PING_REQUIRED="false"
DISABLE_ROOT_SSH="false"
DISABLE_PASSWORD_AUTH="false"
ENABLE_AUDITD="true"
APPLY_SYSCTL_BASELINE="true"

FIREWALL_BACKEND="auto"
DEFAULT_DROP_INPUT="true"
REMOTE_SUDO="true"
ENABLE_NMAP="false"
ENABLE_LYNIS="true"
ALLOW_NETWORK_SCANNING="false"
