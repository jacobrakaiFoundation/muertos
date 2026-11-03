# Support

muertōs is built from CentOS 7 sources and is binary compatible with CentOS 7.9.2009,
x86_64 only. The reasoning behind the kernel choice is in `docs/kernel.md`.

```
  where you run el7        kernel that matters        what to install
  bare metal / VM host --> kernel-lt 6.12 (ours)  --> muertos-release, kernel-lt
  bare metal, needs kABI -> stock 3.10, frozen    --> muertos-release
  container / VM guest --> the host's kernel      --> muertos-release
```

## Userland

Security backports for the Tier-1 packages, with `.muertos<N>` in the Release tag. No
version bumps unless no patch can be backported.

## Kernel

- **`kernel-lt` 6.12 LTS is the default.** We rebuild every upstream 6.12.y stable release
  and move to the next LTS before 6.12 reaches EOL (Dec 2028). kABI is not kept:
  out-of-tree modules (NVIDIA, vendor agents, `kmod-*`) must be rebuilt or dropped.
- **Stock 3.10 stays installable and frozen.** It gets best-effort fixes for Critical and
  unauthenticated-network bugs only. Local privilege escalations stay unfixed. Use it only if
  you need kABI and accept that risk.
- **Containers and VM guests are kernel-agnostic.** The host's kernel is what matters; install
  `muertos-release` and run `yum update` for userland fixes.

## Secure Boot

The stock shim only trusts kernels signed by the original vendor, and any kernel we build
loses that signature. With Secure Boot on, enroll our kernel signing certificate, then
reboot and confirm the enrollment in the MOK manager:

```bash
mokutil --import KERNEL_CERT.der
```

`KERNEL_CERT.der` is a placeholder: `mokutil` needs an X.509 certificate in DER form, not
the RPM GPG key, and `kernel-lt` does not ship one yet.

Or turn Secure Boot off. A Microsoft-signed shim of our own is out of scope for now.
