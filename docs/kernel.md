# Kernel plan

## The problem

el7 ships kernel 3.10. Since EOL (2024-06-30) Red Hat has marked **122 Important/Critical
kernel CVEs** as affecting RHEL 7 (`survey/CVES.md`). Of those, 31 were fixed for paying RHEL 7 ELS
customers, with no public source. The other 91 are unfixed.

| Slice | Count | Notes |
|---|---|---|
| Local (AV:L) | 82 | needs a shell on the box |
| Network, needs auth (AV:N, PR:L) | 26 | NFSD, ceph, iSCSI target |
| Network, no auth (AV:N, PR:N) | 11 | sctp, ipv6 tunnels, netfilter, ipvs |
| Published in 2026 | 113 | ~11/month, and rising (kernel CNA volume) |

Every fix has to be ported back across ~12 years of divergence from 6.x code into 3.10.
Red Hat keeps a dedicated team on this. At this rate, one maintainer can't keep up.

## Options

```
            effort/month    kABI kept    CVE coverage
  A. patch 3.10   high          yes         partial, always behind
  B. LTS kernel   low           no          upstream stable team does it
  C. no kernel    none          n/a         container / VM-guest users only
```

**A. Patch 3.10.** Keeps third-party kernel modules (kmods, DKMS, vendor drivers) working. At
~11 Important CVEs a month, each needing a manual port into code that has diverged for years, it
needs roughly a half-time kernel engineer, even if scoped to network-reachable bugs.

**B. Ship a kernel.org longterm kernel as `kernel-lt`.** We rebuild upstream stable point
releases; Greg Kroah-Hartman and Sasha Levin's stable team does the CVE backporting.
- Candidate lines (kernel.org, checked 2026-11-01): 6.12 and 6.18, both projected EOL Dec 2028.
  6.1 and 6.6 end Dec 2027; 5.10 and 5.15 end Dec 2026.
- Toolchain: vault still has `devtoolset-11` (gcc 11.2), well above the minimum for 6.x.
- Userland: el7 (glibc 2.17, systemd 219) ran on ELRepo's `kernel-lt`/`kernel-ml` 5.x–6.x builds
  for years before EOL. Our build must boot-test this, not assume it.
- Cost: kABI breaks. Out-of-tree modules (NVIDIA, vendor agents, ELRepo `kmod-*`) must be rebuilt or
  dropped. Plan one LTS-to-LTS rebase per ~2–3 years.

**C. Don't ship a kernel.** Much of the remaining CentOS 7 fleet runs in containers or as guests,
where the host's kernel is what matters. They need userland fixes only.

## Recommendation: B, plus a thin A, documented C

1. **Default: `kernel-lt` on 6.12 LTS.** Track every upstream 6.12.y release with a CI rebuild.
   Move to the next LTS before Dec 2028.
2. **Stock 3.10 stays installable, frozen,** with best-effort fixes for Critical and
   unauthenticated-network bugs only (11 in 28 months). That's for users who need kABI and accept
   the local-exploit risk. Stated plainly in the README.
3. **Containers and guests:** documented as kernel-agnostic. Install `muertos-release`, then update userland.

## Secure Boot (affects A and B)

CentOS's shim only trusts CentOS-signed kernels, and any kernel we build loses that signature.
Secure Boot users must enroll our key with `mokutil --import` or turn Secure Boot off. A
Microsoft-signed shim of our own is a separate, long review process; out of scope for now.

## First proof, before committing to B

1. Build 6.12.y as an RPM in `build/` using devtoolset-11, with el7's `/boot` + dracut + grubby layout.
2. Boot a stock 7.9 x86_64 VM on it (QEMU with KVM in GitHub Actions; the arm64 mini can only
   emulate, too slowly to iterate).
3. Pass criteria: boots to multi-user, `systemctl --failed` empty, sshd/firewalld/SELinux enforcing
   work, XFS root mounts, docker-ce on el7 runs a container.
