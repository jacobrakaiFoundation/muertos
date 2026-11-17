"""List the Critical and Important CVEs a refreshed CVES.md adds, and that muertos has not fixed.

Usage: python3 survey/new_urgent.py <old_md> <new_md>

Reads the "Critical and Important backlog" table of both files and prints, one Markdown
bullet per line, every (CVE, package) row that is in the new table, not in the old one, and
has an empty "muertos fix" column. Prints nothing when there are none.
"""

import sys
from pathlib import Path

HEADING = "## Critical and Important backlog"


def backlog(path: Path) -> dict[tuple[str, str], list[str]]:
    lines = path.read_text().splitlines()
    if HEADING not in lines:
        raise ValueError(f"{path} has no '{HEADING}' section")
    rows: dict[tuple[str, str], list[str]] = {}
    for line in lines[lines.index(HEADING) + 1:]:
        if line.startswith("## "):
            break
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) < 7 or not cells[0].startswith("CVE-"):
            continue
        rows[(cells[0], cells[1])] = cells
    if not rows:
        # An empty table means the parse failed, not that el7 has no urgent CVEs.
        raise ValueError(f"{path}: the backlog table has no CVE rows")
    return rows


def main(old_md: Path, new_md: Path) -> None:
    old, new = backlog(old_md), backlog(new_md)
    for key in sorted(new.keys() - old.keys()):
        cve, package, severity, cvss, state, fix, summary = new[key][:7]
        if not fix:
            print(f"- {cve} ({package}, {severity}{', CVSS ' + cvss if cvss else ''}, {state}): {summary}")


if __name__ == "__main__":
    main(Path(sys.argv[1]), Path(sys.argv[2]))
