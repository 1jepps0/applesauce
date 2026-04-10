# PCDC Linux / Network Toolkit

Competition-focused Bash toolkit for Linux host auditing, service validation, safe hardening, firewall baselining, SSH deployment, credential rotation scaffolding, and evidence reporting.

The included PCDC 2026 prep guide indicates an approximate equal mix of Windows and Unix/Linux systems, with Unix/Linux examples including multiple Linux distros and BSD, and it emphasizes service availability, business continuity, and incident reporting. It also explicitly prohibits offensive scanning activity on the competition network.

## Design goals

- One shared config file for hosts, ports, services, credentials, and exceptions
- Safe defaults with `audit`, `enforce`, `verify`, and `rollback` oriented workflows
- Timestamped logs and reports for quick operator review
- Jumpbox-friendly execution and cron support

## Layout

- `00_config.sh`: shared inventory, service matrix, admin network, key paths, and policy toggles
- `lib/common.sh`: shared logging, report generation, config helpers, backups, and command wrappers
- `10_host_discovery.sh`: ping, DNS, and TCP reachability checks
- `20_service_audit.sh`: protocol-aware service checks and summaries
- `30_linux_hardening.sh`: safe hardening checks and enforceable controls
- `40_firewall_baseline.sh`: host firewall baseline by detected firewall stack
- `50_service_allow_rules.sh`: allow-rules from the per-host service matrix
- `60_account_audit.sh`: user, sudo, SSH key, cron, and listener review
- `65_persistence_audit.sh`: cron, systemd timer, startup path, and SUID/SGID review
- `66_package_audit.sh`: pending package update triage
- `67_process_port_audit.sh`: local listeners mapped against expected ports
- `68_log_triage.sh`: auth and system log triage
- `70_credential_rotation.sh`: admin account rotation scaffold with verification
- `80_ssh_deploy.sh`: push toolkit to Linux hosts and run remote commands
- `90_vuln_wrapper.sh`: wrapper for safe scans and local exposure checks
- `95_evidence_report.sh`: consolidate latest results into a single report bundle
- `96_install_cron.sh`: install cron entries for recurring checks
- `97_incident_report.sh`: generate incident report templates aligned to PCDC scoring guidance
- `98_first_45_minutes.md`: Linux/network first-45-minute runbook

## Quick start

1. Edit `00_config.sh`.
2. Confirm host inventory, ports, admin subnets, and per-host allowed service matrix.
3. Run:

```bash
bash ./10_host_discovery.sh
bash ./20_service_audit.sh
bash ./95_evidence_report.sh
```

4. After validating access and services, use:

```bash
bash ./60_account_audit.sh
bash ./65_persistence_audit.sh
bash ./67_process_port_audit.sh
bash ./68_log_triage.sh
bash ./40_firewall_baseline.sh audit
bash ./50_service_allow_rules.sh audit
bash ./30_linux_hardening.sh audit
```

5. Only move to `enforce` after you confirm scoring requirements.

## PCDC-specific usage notes

- Keep `HOSTS` restricted to systems your team owns.
- Leave `ALLOW_NETWORK_SCANNING=false` during live competition unless the action is explicitly allowed and scoped to your own systems.
- Prefer service validation, logs, host-local audits, and incident reports over broad network scanning.
- BSD is mentioned in the guide, but this toolkit is Linux-first. Use it for audit/reporting on BSD unless you add BSD-specific handlers.

## Recommended operator flow

1. Discovery and service validation
2. Evidence collection
3. Account audit
4. Firewall baseline in audit mode
5. Service-specific allow-rules
6. Linux hardening in audit mode
7. Narrow, verified enforcement
8. Credential rotation after access validation

## Safety notes

- `70_credential_rotation.sh` is intentionally conservative and only rotates explicitly listed admin accounts by default.
- Firewall and hardening scripts create backups before changes where possible.
- Service allow-rules are config-driven. They do not auto-open ports based on discovery.
- Host and service checks should be kept current in `00_config.sh` to avoid false confidence.
- `90_vuln_wrapper.sh` defaults to non-network checks because the competition rules prohibit offensive scans.

## Cron example

```bash
bash ./96_install_cron.sh --schedule "*/5 * * * *" --script ./20_service_audit.sh
```

## Outputs

- Logs: `./logs`
- Reports: `./reports`
- Backups: `./backups`
