#!/usr/bin/env bash
# survey/fixed.json and the patches under packages/ must agree: every CVE a patch file is named
# for is recorded as fixed for that package, and every package with a recorded fix has patches.
# Run from the repository root. Exits 1 listing each disagreement.
set -euo pipefail

bad=0
shopt -s nullglob
patches=(packages/*/*.patch)
[ "${#patches[@]}" -gt 0 ] || { echo "no patches under packages/; refusing to call that consistent" >&2; exit 1; }

for patch in "${patches[@]}"; do
  package="$(basename "$(dirname "$patch")")"
  # One patch can carry several CVEs: ruby-2.0.0-CVE-2026-93577-CVE-2026-97229.patch
  for cve in $(basename "$patch" | grep -oE 'CVE-[0-9]{4}-[0-9]+' || true); do
    if ! jq -e --arg p "$package" --arg c "$cve" '.[$p][$c] | type == "string"' survey/fixed.json > /dev/null; then
      echo "$patch carries $cve, but survey/fixed.json has no $package/$cve" >&2; bad=1
    fi
  done
done

for package in $(jq -r 'keys[]' survey/fixed.json); do
  for cve in $(jq -r --arg p "$package" '.[$p] | keys[]' survey/fixed.json); do
    if ! grep -lq -- "$cve" packages/"$package"/*.patch packages/"$package"/*.spec 2>/dev/null; then
      echo "survey/fixed.json records $package/$cve, but no patch or spec under packages/$package names it" >&2; bad=1
    fi
  done
done

[ "$bad" = 0 ] && echo "fixed.json and packages/ agree"
exit "$bad"
