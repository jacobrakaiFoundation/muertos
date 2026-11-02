# el7 x86_64 build root. On Apple silicon this runs under Rosetta via OrbStack.
FROM --platform=linux/amd64 centos:7.9.2009

RUN rm -f /etc/yum.repos.d/*.repo
COPY vault.repo /etc/yum.repos.d/vault.repo
# centos-release-scl-rh ships the SCLo signing key; its own .repo points at the dead mirror.
RUN rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7 \
 && yum -y --disablerepo=sclo-rh install centos-release-scl-rh \
 && rm -f /etc/yum.repos.d/CentOS-SCLo-*.repo \
 && rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-SIG-SCLo \
 && yum -y install rpm-build yum-utils rpmdevtools rpm-sign createrepo gcc make \
 && yum clean all

RUN useradd -m builder
COPY rebuild-in-container.sh /usr/local/bin/rebuild-in-container
COPY update-kernel-config-in-container.sh /usr/local/bin/update-kernel-config-in-container
COPY build-kernel-lt-in-container.sh /usr/local/bin/build-kernel-lt-in-container
COPY sign-and-index-in-container.sh /usr/local/bin/sign-and-index-in-container
