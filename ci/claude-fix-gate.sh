#!/usr/bin/env bash
# Decide what may happen to the files the repair agent changed. Reads one path per line on
# stdin and prints exactly one verdict:
#   none     nothing changed
#   push     every path is one the agent may change: commit and open a pull request
#   comment  a workflow file changed: GITHUB_TOKEN cannot push those, so post the patch instead
# Exits 1, naming the path, if anything else changed. The list is an allow-list: a path nobody
# thought about is refused, not waved through.
set -euo pipefail

verdict=none
while IFS= read -r path; do
  [ -n "$path" ] || continue
  case "$path" in
    # The gates themselves. The agent does not get to loosen what checks it or what merges.
    ci/automerge-bump.sh|ci/claude-fix-gate.sh|.github/workflows/automerge-bump.yml|.github/workflows/claude-fix.yml)
      echo "forbidden: $path is one of the automation's own gates" >&2; exit 1 ;;
    # Signing, publishing, the site, and the patches and fix records a person vouches for.
    release/*|web/*|*.patch|survey/fixed.json|survey/CVES.md|AGENTS.md|CLAUDE.md|SECURITY.md)
      echo "forbidden: $path is outside what the repair agent may change" >&2; exit 1 ;;
    .github/workflows/*.yml)
      verdict=comment ;;
    tests/*|build/*|ci/*|survey/*.py|muertos-release/*|kernel/kernel-lt.spec|kernel/config-overrides|packages/*.sh|packages/*/test.sh|packages/*/*.spec)
      [ "$verdict" = comment ] || verdict=push ;;
    */*)
      echo "forbidden: $path is outside what the repair agent may change" >&2; exit 1 ;;
    *.sh)
      [ "$verdict" = comment ] || verdict=push ;;
    *)
      echo "forbidden: $path is outside what the repair agent may change" >&2; exit 1 ;;
  esac
done
echo "$verdict"
