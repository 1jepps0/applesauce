# BSD Quick Reference

This toolkit now supports BSD in a practical but still conservative way, with the best coverage aimed at FreeBSD and OpenBSD.

## Service Management

FreeBSD:

```bash
service sshd status
service sshd restart
sysrc sshd_enable=YES
```

OpenBSD:

```bash
rcctl check sshd
rcctl restart sshd
rcctl enable sshd
```

## Firewall

BSD support is centered on `pf`.

Audit:

```bash
pfctl -sr
pfctl -si
```

Load rules:

```bash
pfctl -f /etc/pf.conf
pfctl -e
```

## Packages

FreeBSD / DragonFly:

```bash
pkg version -vIL=
pkg audit -F
```

OpenBSD:

```bash
syspatch -c
pkg_info -a
pkg_add -u
```

## Logs

Common files:

```bash
/var/log/messages
/var/log/security
/var/log/maillog
/var/log/all.log
```

## Persistence / Startup

Common BSD locations:

```bash
/etc/rc.conf
/etc/rc.conf.local
/etc/rc.d
/usr/local/etc/rc.d
/etc/pf.conf
/etc/crontab
```

## Notes for This Toolkit

- Replace Linux-specific services like `rsyslog` with BSD-native names like `syslogd`.
- Prefer `pf` by setting `FIREWALL_BACKEND="pf"` when the host uses it.
- Keep protocol-specific service matrix entries, for example `53/udp`.
- Treat OpenBSD package review as more manual than FreeBSD package review.
