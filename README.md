# muertōs

A maintained continuation of CentOS 7.9.2009 (upstream EOL 2024-06-30):
the frozen vault tree plus rebuilt packages carrying security fixes.

```
vault.centos.org SRPM ---> verify sig ---> + backport patch ---> rpmbuild (el7 x86_64)
                                                                     |
          users' yum <--- signed repo (createrepo + our GPG key) <---+
```

## Install

On an installed CentOS 7.9 (not yet live: needs the first publish to GitHub Pages):

```bash
rpm --import https://jacobrakaifoundation.github.io/muertos/RPM-GPG-KEY-muertos
```

```bash
rpm -Uvh https://jacobrakaifoundation.github.io/muertos/el7/x86_64/muertos-release-0.1-1.el7.noarch.rpm
```

```bash
yum update
```

`muertos-release` adds `/etc/yum.repos.d/muertos.repo` (our repo plus the 7.9.2009 vault
repos) and our public key, and disables `CentOS-Base.repo`'s `base`/`updates`/`extras`,
whose `mirrorlist.centos.org` is gone. It installs with `rpm`, not `yum`, because yum
fails while those dead repos are enabled. Erasing it restores `CentOS-Base.repo`.

## Build

```bash
./rebuild.sh <package>
```

This rebuilds one vault SRPM unchanged, in an amd64 el7 container (Rosetta on Apple
silicon), and writes the results to `out/<package>/`. `tree` rebuilt this way has the
same file list as upstream and installs on stock 7.9.

### Security backports

```bash
./backport.sh build sudo
```

```bash
./backport.sh test sudo
```

`packages/<package>/` holds the package's spec (the vault spec, committed unchanged
first so the next commit shows our edits), our patches, and `test.sh`. `build` verifies
the vault SRPM, overlays that directory and builds into `out/<package>/`; `test` upgrades
el7's last build to ours on a stock `centos:7.9.2009` container and checks each CVE as
an unprivileged user. CI (`.github/workflows/backports.yml`) runs both per package.

| Package | Release | CVEs |
|---|---|---|
| sudo | 1.8.23-10.el7_9.3.muertos1 | CVE-2025-32462, CVE-2026-35535, CVE-2026-96512 |

### kernel-lt

```bash
./kernel.sh build
```

This builds the 6.12 LTS `kernel-lt` RPM (`kernel/kernel-lt.spec`) into `out/kernel-lt/`.
`./kernel.sh config` regenerates `kernel/config-x86_64` from el7's last 3.10 config plus
`kernel/config-overrides`. CI (`.github/workflows/kernel-lt.yml`) builds it, then runs
`tests/boot-test.sh`, which installs it on a stock 7.9 VM under KVM, reboots, and runs
`tests/guest-checks.sh`.

### muertos-release

```bash
./muertos-release.sh build
```

This builds `muertos-release` (`muertos-release/muertos-release.spec`) into
`out/muertos-release/`. `./muertos-release.sh test` installs it on a stock
`centos:7.9.2009` container and runs `tests/release-checks.sh`; CI
(`.github/workflows/muertos-release.yml`) does both. A publish takes one run of each
workflow: `./release/publish-on-mini.sh <kernel-lt run> <muertos-release run>`.

## Scope

- Base: 7.9.2009 `os` + `updates` + `extras`, x86_64 only.
- Changes: security backports only. No version bumps unless no patch can be backported.
- Releases: our packages get `.muertos<N>` in their Release tag, so they sort after
  `.el7` builds and are easy to identify.

## Open decisions

- **Name (decided).** The project and repo are `muertos` (displayed muertōs). We never use
  "CentOS" as a product name; docs say "built from CentOS 7 sources" and "binary
  compatible with CentOS 7". Upstream logos are not shipped. For v0.1 `muertos-release`
  is an add-on and `centos-release` stays installed, because many installers detect el7
  from its `/etc/redhat-release` and `/etc/os-release`; replacing it comes later.
- **Hosting (decided).** v0.1 serves the yum repo as static files from GitHub Pages
  (no credentials, free for public repos). Move to Cloudflare R2 if the site nears
  Pages' ~1 GB limit, which the kernel RPMs will do first.
- **Signing key (decided, owner action).** An OpenPGP key generated on a YubiKey,
  kept on the mini (`release/keygen.sh`), so signing needs the card, its PIN and a touch.
  CI builds unsigned RPMs; `release/publish-on-mini.sh` signs and stages the repo. Only the
  public key is committed. WebAuthn passkeys cannot produce the OpenPGP signatures rpm checks.
- **Patch sources.** Candidates are upstream project commits and Debian/Ubuntu LTS
  backports for the same versions. Whether any commercial el7 extended-support
  vendor publishes its patched sources is still unchecked.
- **Priority list.** `survey/CVES.md` ranks the 1,129 post-EOL package/CVE pairs. Run
  `python3 survey/rhel7_cves.py survey/cache survey/rhel7_cves.json` then
  `python3 survey/report.py survey/rhel7_cves.json survey/CVES.md` to refresh it.
- **Kernel.** See `docs/kernel.md`. Recommended: `kernel-lt` on 6.12 LTS by default,
  with stock 3.10 frozen and Critical/remote fixes only.
- **Capyloon shell.** `docs/capyloon-el7.md` maps the x86_64 reference port onto 7.9:
  what Gecko 123, sway, and PipeWire need, which of those el7 already has, and how
  the WSL tar is packed. The new libraries go in a prefix. They are not security
  backports, and they do not change the rule above.
