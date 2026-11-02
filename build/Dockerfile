# el7 x86_64 build root. On Apple silicon this runs under Rosetta via OrbStack.
FROM --platform=linux/amd64 centos:7.9.2009

RUN rm -f /etc/yum.repos.d/*.repo
COPY vault.repo /etc/yum.repos.d/vault.repo
RUN rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7 \
 && yum -y install rpm-build yum-utils rpmdevtools gcc make \
 && yum clean all

RUN useradd -m builder
COPY rebuild-in-container.sh /usr/local/bin/rebuild-in-container
