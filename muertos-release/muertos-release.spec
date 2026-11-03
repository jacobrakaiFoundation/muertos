# Points an installed CentOS 7.9 at the muertos repo and the frozen vault. An add-on:
# centos-release stays installed and keeps owning /etc/redhat-release and os-release.
# yum cannot install this while CentOS-Base.repo's dead mirrorlist is enabled, so
# users install it with rpm -Uvh.
%global centos_base /etc/yum.repos.d/CentOS-Base.repo
%global marker # disabled by muertos-release: mirrorlist.centos.org is gone

Name: muertos-release
Summary: muertos repository configuration and signing key
Version: 0.1
Release: 1%{?dist}
License: GPLv2
URL: https://github.com/jacobrakaiFoundation/muertos
Source0: muertos.repo
Source1: RPM-GPG-KEY-muertos
BuildArch: noarch

Requires: centos-release >= 7-9.2009.0
Requires(post): grep sed
Requires(postun): sed

%description
yum configuration for muertos, a maintained continuation built from CentOS 7
sources: the muertos repo and its signing key, plus the 7.9.2009 vault repos in
place of the retired CentOS mirrors.

%prep

%build

%install
install -D -m 644 %{SOURCE0} %{buildroot}%{_sysconfdir}/yum.repos.d/muertos.repo
install -D -m 644 %{SOURCE1} %{buildroot}%{_sysconfdir}/pki/rpm-gpg/RPM-GPG-KEY-muertos

%post
# Disable CentOS-Base.repo's base/updates/extras; vault-* in muertos.repo replace them.
# The marker line makes this idempotent across upgrades and reversible on erase.
if [ -f %{centos_base} ] && ! grep -q '^%{marker}$' %{centos_base}; then
  sed -i '/^\[\(base\|updates\|extras\)\]$/a %{marker}\nenabled=0' %{centos_base}
fi

%postun
if [ "$1" -eq 0 ] && [ -f %{centos_base} ]; then
  sed -i '/^%{marker}$/{N;d}' %{centos_base}
fi

%files
%config(noreplace) %{_sysconfdir}/yum.repos.d/muertos.repo
%{_sysconfdir}/pki/rpm-gpg/RPM-GPG-KEY-muertos
