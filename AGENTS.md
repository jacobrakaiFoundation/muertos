# muertōs

A maintained continuation of CentOS 7.9.2009: the frozen vault tree plus rebuilt
packages that carry security backports. `README.md` covers scope and decisions;
`docs/kernel.md` covers the kernel.

## Commands

```bash
./rebuild.sh <package>     # rebuild one vault SRPM in an amd64 el7 container -> out/<package>/
./kernel.sh build          # 6.12 LTS kernel-lt RPM -> out/kernel-lt/
./kernel.sh config         # regenerate kernel/config-x86_64 from el7's config + kernel/config-overrides
python3 survey/rhel7_cves.py survey/cache survey/rhel7_cves.json
python3 survey/report.py survey/rhel7_cves.json survey/CVES.md
```

`tests/boot-test.sh` needs a Linux host with `/dev/kvm`, so it runs in CI
(`.github/workflows/kernel-lt.yml`), not on the Macs.

## Rules

- Security backports only. No version bumps unless no patch can be backported.
- Rebuilt packages carry `.muertos<N>` in their Release tag.
- Never use "CentOS" as a product name. Say "built from CentOS 7 sources".
- Signing and publishing happen only on the mini, with the YubiKey, via
  `release/publish-on-mini.sh`, which commits to the `gh-pages` branch that serves the
  yum repo. An agent never signs, publishes, or pushes `gh-pages`. Jacob does.
