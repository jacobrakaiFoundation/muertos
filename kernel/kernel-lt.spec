# kernel.org longterm kernel for el7 (see docs/kernel.md). Installs alongside the
# stock 3.10 kernel and becomes the boot default; removing it falls back to 3.10.
%global kver %{version}-%{release}.%{_target_cpu}
%global devtoolset /opt/rh/devtoolset-11/root/usr/bin
%define debug_package %{nil}
# Only compress docs: el7's default brp scripts would rewrite module files.
%define __spec_install_post /usr/lib/rpm/brp-compress

Name: kernel-lt
Summary: Linux longterm kernel %{version} for el7
Version: 6.12.115
Release: 1%{?dist}
License: GPLv2
URL: https://www.kernel.org
Source0: https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-%{version}.tar.xz
Source1: config-x86_64
ExclusiveArch: x86_64

BuildRequires: devtoolset-11-gcc devtoolset-11-make devtoolset-11-binutils
BuildRequires: bc bison flex perl openssl openssl-devel elfutils-libelf-devel kmod
Requires(post): grubby dracut kmod
Requires(preun): grubby
# Makes yum keep several kernel-lt versions installed instead of replacing them.
Provides: installonlypkg(kernel)

%description
The Linux kernel %{version} from the kernel.org longterm branch, configured from
the CentOS 7 3.10 kernel's config and built for el7 userland.

%prep
%setup -q -n linux-%{version}
cp %{SOURCE1} .config

%build
export PATH=%{devtoolset}:$PATH
# Fail if the committed config is stale for this kernel version.
make olddefconfig
cmp .config %{SOURCE1}
make %{?_smp_mflags} KERNELRELEASE=%{kver} bzImage modules

%install
export PATH=%{devtoolset}:$PATH
make %{?_smp_mflags} KERNELRELEASE=%{kver} INSTALL_MOD_PATH=%{buildroot} DEPMOD=true modules_install
rm -f %{buildroot}/lib/modules/%{kver}/build %{buildroot}/lib/modules/%{kver}/source
install -D -m 755 arch/x86/boot/bzImage %{buildroot}/boot/vmlinuz-%{kver}
install -m 644 System.map %{buildroot}/boot/System.map-%{kver}
install -m 644 .config %{buildroot}/boot/config-%{kver}
touch %{buildroot}/boot/initramfs-%{kver}.img

%post
/sbin/new-kernel-pkg --package kernel-lt --mkinitrd --dracut --depmod --make-default --install %{kver}

%preun
/sbin/new-kernel-pkg --rminitrd --rmmoddep --remove %{kver}

%files
/boot/vmlinuz-%{kver}
/boot/System.map-%{kver}
/boot/config-%{kver}
%ghost /boot/initramfs-%{kver}.img
/lib/modules/%{kver}
