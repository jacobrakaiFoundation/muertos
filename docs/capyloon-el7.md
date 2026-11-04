# Capyloon on Muertos

Package map for the first milestone: get [capyloon/gecko-b2g](https://github.com/capyloon/gecko-b2g)
(Gecko 123, branch `capyloon`) to compile on Muertos, then boot the shell as a WSL distro.
The reference port is [luogen-vip/capyloon-x86_64](https://github.com/luogen-vip/capyloon-x86_64).
Its build scripts are the dependency list. This file is that list, mapped onto CentOS 7.9.2009.

Versions below were read from the git trees and from repo metadata on 4 Nov 2026 (Pacific):
vault `7.9.2009` os, updates, extras, and sclo rh; the EPEL 7 archive; Debian bookworm
via sources.debian.org. They are a snapshot, not a lockfile.

The shell stack is a parallel prefix (`/opt/muertos` plus the existing SCL prefixes).
It is not a security backport of the vault packages, and it does not change the
"security backports only" rule in the README. Replacing `/usr` wayland, glib, or
libstdc++ would be hard to walk back. A prefix uninstalls.

The familiars and the lockdown gate stay deferred until a shell actually runs.

## What the reference build pins

The GitHub workflow (`.github/workflows/build.yml`) is five stages. Stages 1–2 compile.
Stage 3 packs a Debian deb. Stage 4 is `live-build` on Debian 12 and does not apply
to Muertos. Stage 5 publishes an ISO.

| Tool | Pin | Where it is set |
|---|---|---|
| Gecko | branch `capyloon`, packaged as `b2g-123.0` | `scripts/build-gecko.sh` |
| rustc for Gecko | **1.76.0** | same script. 1.99 fails configure: "Don't know how to translate x86_64-pc-linux-gnu for rustc" |
| cbindgen | **0.26.0 exactly**, `cargo install --locked` from the tag | same script. 0.28 rejects duplicate keys in Gecko 123's `cbindgen.toml` |
| rustc for api-daemon and ipfsd | **1.70.0** | `scripts/build-daemons.sh`. Newer rustc breaks the old `time` crate in those lockfiles |
| rustc for b2ghald | unpinned `cargo build` | same script. On a clean el7 there is no default toolchain; use 1.70.0 |
| rustc for nutria's `jackady` | **1.79.0** | `scripts/build-deb.sh`. Packaging tool only, not shipped in the image |
| C++ compiler on the runner | Ubuntu 22.04 `clang` + `lld` | `scripts/build-gecko.sh` apt line, `runs-on: ubuntu-22.04` |
| Linker | `--enable-linker=lld` | `mozconfig-ci` in that script |
| LTO, tests, updater, sandbox, debug symbols | off | same mozconfig |
| Node floor | >= 12.22.12 | `python/mozbuild/mozbuild/nodeutil.py` in gecko-b2g |

`./mach bootstrap` is broken on the b2g application (`ensure_android()` missing `os_arch`).
The reference script installs tools by hand. Do the same.

Daemons built on Ubuntu 22.04 link glibc 2.35. The workflow comment says that is
deliberate so they run on Debian 12 (glibc 2.36). Those binaries will not start on
el7's glibc 2.17. Gecko has the same problem. Rebuild both on Muertos; do not reuse
the upstream CI tarballs.

## Floors from the gecko-b2g `capyloon` tree

| Check | Floor | Source |
|---|---|---|
| Python | 3.8, and `mach` looks for 3.8 through 3.11 | `mach` `MIN_PYTHON_VERSION` |
| rustc / cargo | 1.70.0 | `python/mozboot/mozboot/util.py` `MINIMUM_RUST_VERSION` |
| GCC | 8.1.0 | `build/moz.configure/toolchain.configure` `minimum_gcc_version` |
| clang | 8.0 | same file, fatal below 8.0 |
| C++ | `-std=gnu++17` | same file |
| cbindgen | 0.26.0 | `build/moz.configure/bindgen.configure` |
| Node | 12.22.12 | `python/mozbuild/mozbuild/nodeutil.py` |
| nasm | 2.14 | `third_party/dav1d/meson.build` |
| shipped glibc symbols | **at most** 2.17 | `python/mozbuild/mozbuild/action/check_binary.py` `GLIBC_MAX_VERSION` |
| shipped libstdc++ | **at most** `GLIBCXX_3.4.19`, `CXXABI_1.3.7` | same file |
| shipped libgcc | **at most** `GCC_4.8` | same file |

The last three are ceilings, not floors. A binary that needs glibc 2.28 or
`GLIBCXX_3.4.29` fails Mozilla's own release check and will not run on el7.
That is why the compiler has to be devtoolset-style: GCC 11, linked so new
libstdc++ symbols come from `libstdc++_nonshared.a` and the dynamic dependency
stays on the system libstdc++. A vanilla GCC 11 dropped into `/usr` fails this.

Rust's own host tools for the pinned releases still run on that glibc.
`x86_64-unknown-linux-gnu` in the Rust 1.76.0 platform docs requires kernel >= 3.2
and glibc >= 2.17, for rustc itself and for libstd. el7 updates ship
glibc `2.17-326.el7_9.3`. Stock kernel 3.10 and `kernel-lt` 6.12 both clear
the kernel floor. Use the official rustup builds of 1.70.0, 1.76.0, and 1.79.0.
EPEL's `rust` 1.72.1 is the wrong pin.

Do not upgrade those three rustc pins to "current" without re-checking the
target-spec break the reference script already hit on 1.99.

## Gecko build dependencies

`scripts/build-gecko.sh` apt line, plus the tools the script then installs itself.
"Stock" means the 7.9 vault package is enough. SCL is `centos-release-scl` from extras.

| Reference package | el7 package | el7 version | Disposition |
|---|---|---|---|
| `build-essential` (gcc, g++) | `gcc`, `gcc-c++` | 4.8.5-44.el7 | Below GCC 8.1. Use SCL `devtoolset-11-gcc` / `devtoolset-11-gcc-c++` **11.2.1-9.1.el7** and `devtoolset-11-binutils` 2.36.1 |
| `build-essential` (make) | `make` | 3.82-24.el7 | Stock for now. Move to make 4.3 if `mach` rejects 3.82 |
| `curl` `wget` `unzip` `xz-utils` `bzip2` `m4` `file` | same names (`xz` for xz-utils) | vault | Stock |
| `git` | `git` | 1.8.3.1-25.el7_9 | Stock. SCL `rh-git227` if a clone needs a newer client |
| `python3` `python3-dev` `python3-pip` | `python3` 3.6.8-21.el7_9 | 3.6.8 | Below 3.8. Use SCL `rh-python38-python` **3.8.13-1.el7** and `rh-python38-python-devel` |
| `libgtk-3-dev` | `gtk3-devel` | 3.22.30-8.el7_9 | Stock for the first compile. Bookworm is 3.24.38. The nutria deb only requires `libgtk-3-0 >= 3.0`. Bump to 3.24 only if the GTK backend fails to compile |
| `libdbus-glib-1-dev` | `dbus-glib-devel` | 0.100-7.el7 | Stock |
| `libxt-dev` | `libXt-devel` | vault | Stock |
| `libasound2-dev` | `alsa-lib-devel` | 1.1.8-1.el7 | Stock |
| `libpulse-dev` | `pulseaudio-libs-devel` | 10.0-6.el7_9 | Stock. Gecko links Pulse, not PipeWire |
| `uuid-dev` | `libuuid-devel` | 2.23.2-65.el7_9.1 | Stock |
| `clang` `lld` `llvm` | EPEL `clang` 3.4.2; SCL `llvm-toolset-7.0-clang` **7.0.1** and `llvm-toolset-7.0-lld` 7.0.1 | 7.0.1 | Below clang 8.0. Build clang 14 + lld + libclang (the Ubuntu 22.04 set the reference CI apt-installs). EPEL `cmake3` is 3.17.5 and system cmake is 2.8.12; LLVM 14 wants a newer cmake, so cmake is built first |
| `libx11-dev` `libx11-xcb-dev` | `libX11-devel` | vault | Stock. xcb glue is in libX11 |
| `libxcb1-dev` `libxcb-shm0-dev` | `libxcb-devel` | vault | Stock. shm is in libxcb |
| `libxext-dev` `libxrandr-dev` `libxcomposite-dev` `libxcursor-dev` `libxdamage-dev` `libxfixes-dev` `libxi-dev` | `libXext-devel` `libXrandr-devel` `libXcomposite-devel` `libXcursor-devel` `libXdamage-devel` `libXfixes-devel` `libXi-devel` | vault | Stock |
| `libdrm-dev` | `libdrm-devel` | 2.4.97-2.el7 | Stock is enough to start the Gecko compile. wlroots 0.15.1 requires libdrm >= 2.4.109, so the shell prefix needs bookworm's **2.4.114** |
| `libegl1-mesa-dev` `libgles2-mesa-dev` | `mesa-libEGL-devel` `mesa-libGLES-devel` | 18.3.4-12.el7_9 | Stock for the first Gecko link. wlroots' gbm check is `>= 17.1.0`, which 18.3 passes. A real compositor may still need bookworm mesa 22.3.6 for modifiers; that is a later bump, not a configure floor |
| `libwayland-dev` `libwayland-egl-backend-dev` | `wayland-devel` | 1.15.0-1.el7 | Too old. sway 1.7 and wlroots 0.15.1 both require wayland-server >= 1.20. Backport bookworm **wayland 1.21.0** into the prefix. Debian splits out `libwayland-egl-backend-dev`; on el7 the egl backend header is in `wayland-devel` |
| `yasm` | `yasm` | 1.2.0-4.el7 | EPEL |
| `nasm` | `nasm` | 2.10.07-7.el7 | Below dav1d's 2.14. Backport bookworm **nasm 2.16.01** |
| (not in the apt line) Node | `nodejs` | 16.20.2-1.el7 | EPEL. Clears 12.22.12 |
| (not in the apt line) rustc 1.76.0, 1.70.0, 1.79.0 | EPEL `rust` 1.72.1 | wrong pin | rustup, official `x86_64-unknown-linux-gnu` |
| (not in the apt line) cbindgen 0.26.0 | absent | | `cargo +1.76.0 install --locked` from `eqrion/cbindgen` tag `v0.26.0` |
| (not in the apt line) pkg-config | `pkgconfig` | 0.27.1-4.el7 | Stock |
| (not in the apt line) meson | `meson` | 0.55.1-1.el7 | EPEL is below sway's `>= 0.60`. Install meson 0.60+ with `rh-python38` pip into the prefix. EPEL `ninja-build` 1.10.2 is fine |

`pkgconfig` has to see the prefix first (`PKG_CONFIG_PATH=/opt/muertos/lib/pkgconfig`)
or Gecko and sway will link the vault wayland 1.15.

## Rust daemons

`scripts/build-daemons.sh` installs no `-dev` packages. The three daemons are Rust
crates. They still need a C compiler on `PATH` because some crates compile C
(`ring`, bundled sqlite). They do not need `openssl-devel`: `api-daemon` uses
`reqwest` with `rustls-tls`, and arti is built with rustls.

| Daemon | Repo | Toolchain | System libraries |
|---|---|---|---|
| api-daemon, appscmd | `capyloon/api-daemon` | cargo +1.70.0 | libc via `nix`. rustls, not OpenSSL. Optional `breakpad` pulls a private KaiOS git URL; leave it off |
| b2ghald, b2ghalctl | `capyloon/b2ghald` | use +1.70.0 (script forgot the pin) | libc via `nix` 0.27 (`reboot`, `time`, and `fs` under the `cmdline` feature). No dbus, no udev |
| ipfsd | `capyloon/iroh`, binary renamed to `ipfsd` | cargo +1.70.0 | libc. rustls |

Nutria's Debian control (`builder/src/templates/debian/control`) is the runtime
dependency line of the shell, not of these daemons:

```
libgtk-3-0 (>= 3.0.0), libasound2 (>= 1.0.16), libdbus-glib-1-2 (>= 0.78),
fonts-arphic-ukai, fonts-arphic-uming, sway, network-manager
```

el7 equivalents that already exist: `gtk3`, `alsa-lib` 1.1.8, `dbus-glib` 0.100,
`cjkuni-ukai-fonts`, `cjkuni-uming-fonts`, `NetworkManager` 1.18.8-2.el7_9.
`sway` does not exist in os, updates, extras, sclo, or EPEL 7.

## Sway, the compositor the shell actually runs

Bookworm, which is what the ISO is built from (`iso/livebuild/auto/config`),
ships sway **1.7-6** and wlroots **0.15.1-6**. Match those, not current sway.
Sway 1.8 moved to wlroots 0.16 and pcre2; the reference image did not.

Hard requirements from the 1.7 / 0.15.1 meson files, against el7:

| Library | Required | el7 | Action |
|---|---|---|---|
| wayland-server | >= 1.20 (sway and wlroots) | 1.15.0 | Backport 1.21.0 |
| wayland-protocols | >= 1.24 (sway) | absent | Backport 1.31 |
| wlroots | 0.15.x (sway 1.7) | absent | Backport 0.15.1 |
| seatd / libseat | >= 0.2.0 (wlroots) | absent | Backport 0.7.0 |
| libdrm | >= 2.4.109 (wlroots) | 2.4.97 | Backport 2.4.114 |
| libinput | >= 1.14.0 (wlroots); sway itself only asks >= 1.6 | 1.10.7 | Backport 1.22.1 (bookworm). Hold-gesture support wants 1.19, optional |
| json-c | >= 0.13 (sway) | 0.11 | Backport 0.16 |
| gbm | >= 17.1.0 (wlroots) | mesa 18.3.4 | Version check passes |
| libxkbcommon | unversioned | 0.7.1 | Try stock. Bookworm's known-good is 1.5.0; bump if wlroots fails to compile |
| pixman, cairo, pango, gdk-pixbuf, libpcre, libudev, glesv2 | unversioned or already satisfied | pixman 0.34, cairo 1.15.12, pango 1.42.4, gdk-pixbuf 2.36, pcre 8.32, systemd 219 | Try stock |
| libevdev | unversioned for sway; libinput 1.22 only feature-tests >= 1.9.902 | 1.5.6 | Try stock. Bump if libinput's build breaks |
| meson | >= 0.60 (sway), >= 0.58.1 (wlroots) | 0.55.1 (EPEL) | Prefix meson, see above |
| scdoc | >= 1.9.2, man pages only | 1.9.6 (EPEL) | Skip man pages, or use EPEL |

Nothing in this table is in the vault at the required version except the
"try stock" rows and gbm's version number. The first shell prefix is:

wayland 1.21.0, wayland-protocols 1.31, libdrm 2.4.114, libinput 1.22.1,
json-c 0.16, seatd 0.7.0, wlroots 0.15.1, sway 1.7.

Build them in that order, into `/opt/muertos`.

## PipeWire

The ISO package list installs `pipewire`, `pipewire-alsa`, `pipewire-pulse`,
`pipewire-audio`, and `wireplumber`. None of those names exist in os, updates,
extras, sclo, or EPEL 7.

PipeWire 0.3.65 (bookworm `0.3.65-3+deb12u1`) needs meson >= 0.59. GLib is
optional (Flatpak portal only) and the optional floor is glib >= 2.32, which
el7's glib2 2.56.1 clears. So PipeWire itself can be built in the prefix.

WirePlumber 0.4.13 needs `glib-2.0 >= 2.62`, `libpipewire-0.3 >= 0.3.52`,
and Lua >= 5.3. el7 glib2 is **2.56.1-9.el7_9**. Replacing the system glib
is not a walk-back-friendly change; almost every process links it. A parallel
glib just for WirePlumber is a large extra project.

Gecko does not need PipeWire to compile. It links `libpulse`. For the WSL
milestone, WSLg already provides a Pulse server (`PULSE_SERVER`). Use that
and package PipeWire afterwards. On a native ISO, either accept a parallel
glib for WirePlumber, or pick a session manager that still builds against
glib 2.56. Do not block the Gecko compile on this.

## Other ISO packages

These are runtime packages from `iso/livebuild/config/package-lists/capyloon.list.chroot`.
WSL does not need the firmware or the live-boot set. Native hardware does, later.

| Group | Reference | On el7 |
|---|---|---|
| Network | network-manager, iw, wpasupplicant, modemmanager | `NetworkManager` 1.18.8, `iw` 4.3, `wpa_supplicant` 2.6, `ModemManager` 1.6.10. All stock |
| Bluetooth | bluez | `bluez` 5.44-7.el7. Old, but present. A bump waits on a failure |
| Disks | udisks2, dosfstools, ntfs-3g, exfat, libmtp, jmtpfs | `udisks2` 2.8.4, `dosfstools` 3.0.20, EPEL `ntfs-3g` 2022.10.3, `libmtp` 1.1.14, EPEL `jmtpfs` 0.5. `exfat-utils` and `fuse-exfat` were absent from os, updates, and the EPEL 7 archive |
| Fonts | fonts-noto-cjk, dejavu, liberation, arphic ukai/uming | EPEL `google-noto-cjk-fonts`, vault `dejavu-sans-fonts`, `liberation-fonts`, `cjkuni-ukai-fonts`, `cjkuni-uming-fonts` |
| Firmware | firmware-linux, amd, intel, realtek, iwlwifi, sof, microcode | vault `linux-firmware` is 20200421. `kernel-lt` 6.12 wants newer firmware on real hardware. WSL does not |
| Boot | live-boot, grub, plymouth, shim | Debian live-build only. WSL has no ISO. Plymouth theme is cosmetic |
| Entropy | haveged | EPEL `haveged` 1.9.13. kernel-lt 6.12 does not need it the way kernel 3.10 did |

## Order for the compile milestone

1. Enable SCL (`centos-release-scl`) and enter `devtoolset-11` plus `rh-python38`.
2. rustup: 1.70.0, 1.76.0, 1.79.0. Confirm `rustc +1.76.0 -vV` runs on this glibc.
3. cbindgen 0.26.0 with `cargo +1.76.0 install --locked`.
4. EPEL `nodejs` 16, EPEL `yasm`, EPEL `ninja-build`. Backport nasm 2.16.01.
5. A prefix cmake new enough for LLVM 14, then clang 14, lld, and libclang.
   Point `LIBCLANG_PATH` at that libclang. The tree vendors bindgen 0.69
   (`Cargo.toml` in gecko-b2g). SCL clang 7 is below the configure floor of 8
   and is the wrong libclang to try first.
6. Prefix meson >= 0.60 via rh-python38.
7. `mozconfig-ci` from `scripts/build-gecko.sh`, unchanged: b2g, no sandbox,
   no LTO, no debug symbols, linker lld, api-daemon port 8081.
   `CC`/`CXX` are clang 14 once it exists. devtoolset-11 GCC is a valid
   configure compiler (floor is 8.1) if clang is not ready yet, but the
   known-good CI build is clang + lld.
8. `./mach build` then `./mach package`. Expect a long first failure in
   wayland or nasm if steps 4–5 were skipped. Python 3.6 will fail before any
   of that, in `mach` itself.

Then the daemons, with the toolchain pins above, and install the binaries
where nutria's start script looks: `/opt/capyloon/b2g`, `/opt/capyloon/api-daemon`,
`/opt/capyloon/b2ghald`, `/opt/capyloon/ipfsd`. The deb builder is optional
on Muertos. The files it would have installed are what matter.

The sway prefix (the table above) is required for the shell to show a window.
It is not required to prove Gecko compiled.

## WSL tar, the first thing to ship

Format, from Microsoft's custom-distro doc (WSL 2.4.4 and newer) and Ubuntu's
note that `wsl --install --from-file` wants WSL 2.4.8 or newer. Target 2.4.8+.

A `.wsl` file is a gzip-compressed tar whose root is `/`, renamed from `.tar.gz`
to `.tar.wsl` (or `.wsl`). Gzip is the compression they tell you to use.
Entries are numeric owners (`tar --numeric-owner`). There is no wrapper directory.

Two files make it a distro rather than a rootfs dump:

`/etc/wsl-distribution.conf` is read on first launch. `oobe.defaultName` is
required for the double-click install. A Muertos image would carry:

```
[oobe]
defaultName = muertos
defaultUid = 1000
command = /usr/lib/wsl/oobe.sh

[shortcut]
enabled = true

[windowsterminal]
enabled = true
```

`/etc/wsl.conf` is the per-distro system config. Set `[boot] systemd=true` if
`capyloon.service` and `b2ghald.service` should come up as units. The oobe
script creates the uid 1000 user the reference hook creates (`capyloon` in
the ISO; the name is ours to pick).

Install:

```
wsl --install --from-file muertos.tar.wsl
```

Build the tar from the prefix rootfs, not from an ISO. `live-build`, squashfs,
and GRUB stay on the reference port.

### Wayland under WSLg

WSLg's system distro runs Weston (RDP backend) and a Pulse server, and projects
the sockets into the user distro. A normal WSL session already has
`WAYLAND_DISPLAY`, `DISPLAY`, and `PULSE_SERVER`, and the mount `/mnt/wslg`.
Weston is the compositor. Sway is also a compositor, so it has to nest:

```
WLR_BACKENDS=wayland sway
```

with the outer `WAYLAND_DISPLAY` still pointing at WSLg's socket
(`/mnt/wslg/runtime-dir/wayland-0` when `WAYLAND_DISPLAY=wayland-0`). Sway
then creates its own socket and the b2g process uses that, which is what
`MOZ_ENABLE_WAYLAND=1` in the reference desktop patch is for.

The upstream start script will not do this unmodified. After launching sway,
`builder/src/templates/debian/start.sh` overwrites `WAYLAND_DISPLAY` with

```
ls /run/user/1000/wayland-* | grep -v lock
```

WSLg's socket is under `/mnt/wslg`, not `/run/user/1000`, and that `ls` also
discards the socket sway just wrote down. The x86_64 patch in the reference
repo only adds fullscreen rules and `MOZ_ENABLE_WAYLAND=1`. The WSL image
needs a small further change: if `/mnt/wslg/runtime-dir/wayland-0` exists,
export `WLR_BACKENDS=wayland` before starting sway, and do not replace
`WAYLAND_DISPLAY` with a scan of `/run/user/1000` when sway already reported
its socket. Do not chmod `/mnt/wslg`. It is the platform's socket directory,
not a private `XDG_RUNTIME_DIR`.

Skipping sway and pointing b2g straight at WSLg's Weston also works and is
fewer moving parts. It drops the kiosk fullscreen rules. Nesting keeps one
start script for the ISO and for WSL, so that is the path to try first.

Pulse comes from `PULSE_SERVER`. No PipeWire in the WSL image until the
native ISO needs it.

## Explicitly not in this pass

- Booting the reference ISO in a VM. This run has no Mac and no display.
- A Gecko compile. The map is the input to that build.
- The threshold scheme for the three familiars plus a human share. The gate
  waits until the shell runs. Entering lockdown is free and leaving needs
  the human plus two familiars; that policy is unchanged, and it is not
  implemented here.
