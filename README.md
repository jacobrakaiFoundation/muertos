# muertōs

A maintained continuation of CentOS 7.9.2009 (upstream EOL 2024-06-30):
the frozen vault tree plus rebuilt packages carrying security fixes.

```
vault.centos.org SRPM ---> verify sig ---> + backport patch ---> rpmbuild (el7 x86_64)
                                                                     |
          users' yum <--- signed repo (createrepo + our GPG key) <---+
```

## Build

```bash
./rebuild.sh <package>
```

This rebuilds one vault SRPM unchanged, in an amd64 el7 container (Rosetta on Apple
silicon), and writes the results to `out/<package>/`. `tree` rebuilt this way has the
same file list as upstream and installs on stock 7.9.

## Scope

- Base: 7.9.2009 `os` + `updates` + `extras`, x86_64 only.
- Changes: security backports only. No version bumps unless no patch can be backported.
- Releases: our packages get `.muertos<N>` in their Release tag, so they sort after
  `.el7` builds and are easy to identify.

## Open decisions

- **Name.** "CentOS" is a Red Hat trademark, so a public fork can't ship under it.
  Upstream branding (`centos-release`, logos) has to be replaced, the way
  Rocky Linux and AlmaLinux did it.
- **Signing key.** We need a GPG key that the owner generates and keeps offline.
- **Hosting.** Where the public yum repo lives.
- **Patch sources.** Candidates are upstream project commits and Debian/Ubuntu LTS
  backports for the same versions. Whether any commercial el7 extended-support
  vendor publishes its patched sources is still unchecked.
- **Priority list.** `survey/CVES.md` ranks the 1,129 post-EOL package/CVE pairs. Run
  `python3 survey/rhel7_cves.py survey/cache survey/rhel7_cves.json` then
  `python3 survey/report.py survey/rhel7_cves.json survey/CVES.md` to refresh it.
- **Kernel.** See `docs/kernel.md`. Recommended: `kernel-lt` on 6.12 LTS by default,
  with stock 3.10 frozen and Critical/remote fixes only.
