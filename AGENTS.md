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
python3 survey/report.py survey/rhel7_cves.json survey/fixed.json survey/CVES.md
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

## Automation

The repository keeps itself current and says so when it cannot. The scripts are in `ci/`.

- `kernel-lt-bump` opens a PR for each new 6.12.y release and starts `kernel-lt` on it.
  `automerge-bump` merges that PR once the build and the boot test are green. It is the
  only thing that merges by itself, and `ci/automerge-bump.sh` lists what qualifies: a PR
  opened by the bump job, carrying only its commits, changing only the spec, the sha256 and
  the config.
- `watchdog` opens one `ci-failure` issue per failing workflow and closes it on the next
  green run. Daily, it also reports a schedule that stopped running, versions on `main`
  that `gh-pages` does not serve (`needs-publish`), and PRs open for more than 7 days.
- `claude-fix` gets one attempt at each new `ci-failure` issue. It opens a PR or explains
  on the issue. Its PRs are never merged automatically, and `ci/claude-fix-gate.sh` lists
  the paths it may change.
- Everything else waits for Jacob: backports, docs, anything under `release/`, and every
  merge that is not a kernel bump.

Do not widen what merges by itself, or what `claude-fix` may change, without Jacob saying so.
