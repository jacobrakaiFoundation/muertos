#!/usr/bin/env bash
# Runs as root in a stock centos:7.9.2009 container: ./test.sh <dir with our ruby RPMs>
# Installs el7's last ruby from vault, upgrades it to ours with rpm -Fvh, and checks
# each backported CVE with the pattern from upstream's regression test.
set -euo pipefail

rpm_dir="$1"
rel=2.0.0.648-39.el7_9

check() {
  echo "CHECK $1"
}

rm -f /etc/yum.repos.d/*.repo
cp /src/build/vault.repo /etc/yum.repos.d/
rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
yum -y -q --disablerepo='*-source,sclo-rh' install "ruby-$rel"

check "upgrades el7's ruby-$rel"
# Freshen: upgrade only the subpackages the stock install pulled in.
rpm -Fvh $(ls "$rpm_dir"/*.rpm | grep -v '\.src\.rpm$')
for p in ruby ruby-libs; do
  rpm -q "$p" | grep -qx "$p-$rel.muertos1.x86_64"
done

# Each case runs in its own ruby so a crash fails the check instead of the shell.
expect_regexp_error() {
  local src="$1" message="$2" out
  out="$(timeout 120 ruby -e 'begin; Regexp.new(eval(ARGV[0])); puts "compiled"; rescue RegexpError => e; puts e.message; end' "$src")"
  echo "$out" | grep -q "$message"
}

check "CVE-2026-89078: a failed parse after an alternation does not double free"
expect_regexp_error "'|{1000000}'" 'too big number for repeat range'

check "CVE-2026-93577, CVE-2026-97229: nested repeats that overflow int are not unrolled"
timeout 120 ruby -e '
  ["(?:.{90000,}){90000}", "(?:.{46341,}){46341}"].each do |src|
    raise "matched #{src}" unless Regexp.new(src).match("x" * 10).nil?
  end'

check "CVE-2026-110264: too many range repeats or null checks raise instead of wrapping IDs"
expect_regexp_error "'(?:foobar){0,100}' * 100000" 'too many range repeat'
expect_regexp_error "'(?:(?:foo)?|(?:bar)?)*' * 100000" 'too many null check'

check "CVE-2026-80212: decoding unknown resource types registers no classes"
ruby -rresolv -e '
  before = Resolv::DNS::Resource::Generic.constants.size
  1000.times {|i| Resolv::DNS::Resource.get_class(60000 + i, 1) }
  raise "constants grew" unless Resolv::DNS::Resource::Generic.constants.size == before
  a = Resolv::DNS::Resource.get_class(65000, 1)
  b = Resolv::DNS::Resource.get_class(65000, 1)
  raise "unknown types no longer compare equal" unless a.new("x") == b.new("x")'

check "CVE-2026-42258: Symbol arguments must be valid flag atoms"
ruby -rnet/imap -e '
  imap = Net::IMAP.allocate
  imap.send(:validate_data, :Seen)
  ["Seen\r\nA1 DELETE INBOX", "Seen Deleted", "Se]en"].each do |bad|
    begin
      imap.send(:validate_data, bad.to_sym)
      raise "accepted #{bad.inspect}"
    rescue Net::IMAP::DataFormatError
    end
  end'

check "CVE-2026-42246: an early tagged OK cannot make STARTTLS succeed without TLS"
ruby -rnet/imap -rsocket -e '
  server = TCPServer.new("127.0.0.1", 0)
  Thread.new do
    sock = server.accept
    # A MITM answers the predictable tag before the client sends STARTTLS.
    sock.write("* OK ready\r\nRUBY0001 OK begin TLS now\r\n")
    sleep 5
  end
  imap = Net::IMAP.new("127.0.0.1", server.addr[1])
  sleep 0.5
  begin
    imap.starttls
    raise "starttls returned without TLS"
  rescue Net::IMAP::InvalidResponseError => e
    puts e.message
  end'

echo "ALL CHECKS PASSED"
