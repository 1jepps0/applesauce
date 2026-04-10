# First 45 Minutes: Network / Linux

This runbook is for the Linux / network role during the initial 45-minute secure-the-network window.

## Priorities

1. Do not break scoring services.
2. Confirm access and inventory first.
3. Reduce easy attack paths quickly.
4. Start evidence collection early.
5. Write down every change that affects service behavior.

## Minute 0-5

- Log into every assigned Linux host from the jumpbox.
- Confirm you have working `ssh`, `sudo`, and basic shell access.
- Identify hostnames, IPs, distro/version, and system role.
- Open the blue team packet and map each host to its required services.
- Start a shared notes file with host, role, creds, key service ports, and current status.

Suggested commands:

```bash
hostname -f
ip addr
ss -tulpn
uname -a
cat /etc/os-release
```

## Minute 5-10

- Populate or update `00_config.sh`.
- Set `HOSTS`, `HOST_SERVICE_MATRIX`, `HOST_SERVICE_CHECKS`, `HOST_ROLES`, admin CIDRs, and SSH settings.
- Run host discovery and service audit from the jumpbox.
- Save the first report bundle immediately.

Suggested commands:

```bash
bash ./10_host_discovery.sh
bash ./20_service_audit.sh
bash ./95_evidence_report.sh
```

## Minute 10-20

- Check for unexpected listeners, strange users, suspicious cron/systemd persistence, and obvious misconfigurations.
- Review SSH exposure, root login, password auth, and sudoers.
- Check whether services are actually functioning, not just listening.

Suggested commands:

```bash
bash ./60_account_audit.sh
bash ./65_persistence_audit.sh
bash ./67_process_port_audit.sh
bash ./68_log_triage.sh
```

## Minute 20-30

- Apply the least risky high-value controls first.
- Restrict firewall access to admin source ranges and required service ports only.
- Preserve loopback and established connections.
- Do not disable services unless they are clearly not required.

Suggested sequence:

```bash
bash ./40_firewall_baseline.sh audit
bash ./50_service_allow_rules.sh audit
```

Move to `enforce` only after the service matrix is confirmed.

## Minute 30-40

- Harden SSH and required services cautiously.
- Ensure logging and cron are active.
- Back up configs before edits.
- Do not disable password auth until you confirm working key access.
- Do not disable root SSH until you confirm alternate admin access.

Suggested command:

```bash
bash ./30_linux_hardening.sh audit
```

## Minute 40-45

- Re-run service validation after any changes.
- Bundle evidence again.
- If you detect a compromise, start an incident report immediately.
- Hand the team captain a quick status: what is up, what is at risk, what changed, what still needs approval.

Suggested commands:

```bash
bash ./20_service_audit.sh
bash ./95_evidence_report.sh
bash ./97_incident_report.sh <src_ip> <host> "<time>" "Initial compromise summary"
```

## Quick Do / Do Not

Do:

- keep services up
- verify after every firewall or SSH change
- collect logs before wiping evidence
- document source IPs, times, and affected systems

Do not:

- run broad network scans against competition assets
- rotate every password blindly in the first 45 minutes
- disable services without confirming scoring requirements
- make unlogged changes you cannot explain later
