# Security policy

## Reporting a vulnerability

Report it privately at
https://github.com/jacobrakaiFoundation/muertos/security/advisories/new with the package,
version (`rpm -q <package>`), and how to reproduce. Please don't open a public issue for an unfixed vulnerability.

## Scope

- The Tier-1 packages we rebuild with backports (`packages/`, listed in the README).
- `kernel-lt` (6.12 LTS).
- `muertos-release` and the repo signing key.

Out of scope: packages we ship unchanged from the 7.9 vault, and the stock 3.10 kernel
beyond Critical and unauthenticated-network bugs (`docs/support.md`). Reports about them
are still welcome; they feed the priority list in `survey/CVES.md`.
