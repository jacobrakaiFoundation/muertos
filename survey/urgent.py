"""Pick rows out of the "Critical and Important backlog" table of a CVES.md.

Usage:
  python3 survey/urgent.py new <old_md> <new_md>   rows in new and not in old, with no muertos fix
  python3 survey/urgent.py critical <md>           every Critical row with no muertos fix

Prints one Markdown bullet per row, and nothing when there are none.
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


def bullet(cells: list[str]) -> str:
    cve, package, severity, cvss, state, _fix, summary = cells[:7]
    return f"- {cve} ({package}, {severity}{', CVSS ' + cvss if cvss else ''}, {state}): {summary}"


def main(argv: list[str]) -> None:
    if len(argv) == 3 and argv[0] == "new":
        old, new = backlog(Path(argv[1])), backlog(Path(argv[2]))
        picked = [new[k] for k in sorted(new.keys() - old.keys()) if not new[k][5]]
    elif len(argv) == 2 and argv[0] == "critical":
        rows = backlog(Path(argv[1]))
        picked = [rows[k] for k in sorted(rows) if rows[k][2] == "Critical" and not rows[k][5]]
    else:
        raise SystemExit(__doc__)
    for cells in picked:
        print(bullet(cells))


if __name__ == "__main__":
    main(sys.argv[1:])
