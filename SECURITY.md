# Security Policy

## Reporting a vulnerability

Please do not open a public issue for a suspected vulnerability.

Use GitHub's **Report a vulnerability** action on the repository Security page
to open a private security advisory. Include the affected platform and version,
steps to reproduce, impact, and any suggested mitigation.

You should receive an initial response within seven days. Please allow time for
a fix and coordinated disclosure before publishing details.

## Scope

Daisy manages local credentials and launches local HTTP proxy processes. Reports
about credential storage, process execution, dependency installation, or access
to the loopback services are especially helpful.

## Managed runtime note

`npm audit` reports GHSA-3vr4-cvmg-7fx4 against `copilot-api@0.7.0`. The issue is
limited to its `/token` route; Daisy removes that route before launch and CI
verifies it remains absent. Daisy also overrides `srvx` to a patched release.
