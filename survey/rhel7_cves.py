"""Survey CVEs published after CentOS 7 EOL and their RHEL 7 status.

Source: Red Hat Security Data API. For each el7 source package we list CVEs
published after EOL, fetch each CVE's detail, and keep the RHEL 7 entries:
`package_state` (unfixed: Affected, Will not fix, Out of support scope, ...)
and `affected_release` (fixed in RHEL 7 ELS, whose sources are not public).

Usage: python3 survey/rhel7_cves.py <cache_dir> <out_json>
"""

import http.client
import json
import sys
import threading
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from dataclasses import asdict, dataclass
from pathlib import Path

API = "https://access.redhat.com/hydra/rest/securitydata"
EOL_DATE = "2024-06-30"
RHEL7 = "Red Hat Enterprise Linux 7"
ATTEMPTS = 4
USER_AGENT = "muertos-cve-survey/1 (+https://github.com/jacobrakaiFoundation/muertos)"

# Kernel CVE volume is too high to survey at every severity.
SEVERITY_FILTER: dict[str, str] = {"kernel": "important,critical"}

PACKAGES: tuple[str, ...] = (
    "kernel", "glibc", "openssl", "openssh", "sudo", "bash", "systemd", "polkit",
    "pam", "shadow-utils", "util-linux", "grub2", "shim", "dbus", "curl", "wget",
    "libssh2", "gnutls", "nss", "krb5", "openldap", "cyrus-sasl", "bind", "dnsmasq",
    "ntp", "chrony", "httpd", "php", "mariadb", "postgresql", "samba", "postfix",
    "git", "rsync", "libxml2", "libxslt", "expat", "zlib", "xz", "bzip2", "tar",
    "cpio", "unzip", "libarchive", "sqlite", "python", "python3", "perl", "ruby",
    "java-1.8.0-openjdk", "tomcat", "vim", "less", "file", "binutils", "libtiff",
    "libpng", "libjpeg-turbo", "freetype", "ghostscript", "cups", "qemu-kvm",
    "libvirt", "xorg-x11-server", "libX11", "rpm", "yum",
)


@dataclass(frozen=True)
class Rhel7Entry:
    cve: str
    package: str
    severity: str
    cvss3: float | None
    public_date: str
    rhel7_state: str
    summary: str


def fetch_json(url: str) -> object:
    last_error: Exception | None = None
    for attempt in range(1, ATTEMPTS + 1):
        try:
            # The CDN rejects urllib's default User-Agent with 403.
            request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(request, timeout=60) as response:
                return json.load(response)
        except (urllib.error.URLError, http.client.HTTPException, ConnectionError,
                TimeoutError, json.JSONDecodeError) as error:
            last_error = error
            print(json.dumps({"event": "fetch_retry", "url": url, "attempt": attempt,
                              "error": repr(error)}), file=sys.stderr)
            time.sleep(2 ** attempt)
    raise RuntimeError(f"GET {url} failed after {ATTEMPTS} attempts: {last_error!r}")


def list_cve_ids(package: str) -> list[str]:
    ids: list[str] = []
    page = 1
    while True:
        query = f"package={package}&after={EOL_DATE}&per_page=1000&page={page}"
        if package in SEVERITY_FILTER:
            query += f"&severity={SEVERITY_FILTER[package]}"
        rows = fetch_json(f"{API}/cve.json?{query}")
        if not isinstance(rows, list):
            raise ValueError(f"cve.json for {package} page {page} is not a list: {rows!r}")
        ids.extend(str(row["CVE"]) for row in rows)
        if len(rows) < 1000:
            return ids
        page += 1


def cached_detail(cve: str, cache_dir: Path) -> dict[str, object]:
    path = cache_dir / f"{cve}.json"
    if not path.exists():
        # Packages share CVEs across threads: write atomically so no reader sees a partial file.
        tmp = path.with_suffix(f".{threading.get_ident()}.tmp")
        tmp.write_text(json.dumps(fetch_json(f"{API}/cve/{cve}.json")))
        tmp.replace(path)
    detail = json.loads(path.read_text())
    if not isinstance(detail, dict) or "name" not in detail:
        raise ValueError(f"{cve} detail has unexpected shape: {str(detail)[:300]}")
    return detail


def rhel7_entries(package: str, detail: dict[str, object]) -> list[Rhel7Entry]:
    cvss3 = detail.get("cvss3")
    score = float(cvss3["cvss3_base_score"]) if isinstance(cvss3, dict) else None
    details = detail.get("details")
    summary = str(details[0]).strip().split("\n")[0][:200] if isinstance(details, list) and details else ""
    unfixed = [(s["package_name"], s["fix_state"]) for s in detail.get("package_state") or []
               if s["product_name"] == RHEL7]
    # affected_release.package is an NEVRA like "openssl-1:1.0.2k-27.el7_9".
    fixed = [(str(r.get("package", "")).rsplit("-", 2)[0], f"Fixed in ELS ({r['advisory']})")
             for r in detail.get("affected_release") or [] if r["product_name"].startswith(RHEL7)]
    return [Rhel7Entry(cve=str(detail["name"]), package=package,
                       severity=str(detail.get("threat_severity", "")), cvss3=score,
                       public_date=str(detail.get("public_date", "")), rhel7_state=state,
                       summary=summary)
            for name, state in unfixed + fixed if name == package]


def survey_package(package: str, cache_dir: Path) -> list[Rhel7Entry]:
    entries: list[Rhel7Entry] = []
    for cve in list_cve_ids(package):
        entries.extend(rhel7_entries(package, cached_detail(cve, cache_dir)))
    print(json.dumps({"event": "package_done", "package": package, "rhel7_entries": len(entries)}),
          file=sys.stderr)
    return entries


def main(cache_dir: Path, out_json: Path) -> None:
    cache_dir.mkdir(parents=True, exist_ok=True)
    with ThreadPoolExecutor(max_workers=4) as pool:
        results = list(pool.map(lambda p: survey_package(p, cache_dir), PACKAGES))
    entries = [asdict(e) for package_entries in results for e in package_entries]
    out_json.write_text(json.dumps(entries, indent=1))


if __name__ == "__main__":
    main(Path(sys.argv[1]), Path(sys.argv[2]))
