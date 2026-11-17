#!/usr/bin/env bash
# Daily checks for what a failed run cannot report, because nothing ran:
#   1. the scheduled kernel-lt-bump has not succeeded in 48 hours;
#   2. main carries a package version the signed repo on gh-pages does not serve;
#   3. a pull request has been open for more than 7 days.
# Each check keeps one rolling issue and closes it when the condition clears.
#
# Env: REPO, DEFAULT_BRANCH, GH_TOKEN. Optional: DRY_RUN=1. Run from a checkout of main.
set -euo pipefail

: "${REPO:?}" "${DEFAULT_BRANCH:?}"
dry="${DRY_RUN:-}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# rolling <label> <title> <body-file|"">: open, refresh, or (empty body) close the one issue.
rolling() {
  local label="$1" title="$2" body="$3" existing
  existing="$(gh issue list -R "$REPO" --label "$label" --state open --limit 200 --json number,title \
    | jq -r --arg t "$title" '[.[] | select(.title == $t) | .number][0] // empty')"
  if [ -z "$body" ]; then
    [ -z "$existing" ] && return 0
    echo "closing #$existing: $title"
    [ -n "$dry" ] || gh issue close "$existing" -R "$REPO" --comment 'Cleared.'
    return 0
  fi
  if [ -n "$dry" ]; then
    echo "DRY RUN: would ${existing:+refresh #$existing}${existing:-open '$title'}"; cat "$body"; return 0
  fi
  if [ -n "$existing" ]; then
    gh issue edit "$existing" -R "$REPO" --body-file "$body" > /dev/null
    echo "refreshed #$existing: $title"
  else
    gh issue create -R "$REPO" --title "$title" --label "$label" --body-file "$body"
  fi
}

# --- 1. silent schedule ---------------------------------------------------------------------
last="$(gh run list -R "$REPO" --workflow kernel-lt-bump.yml --status success --limit 1 \
  --json createdAt --jq '.[0].createdAt // empty')"
if [ -z "$last" ]; then
  age_h=99999
else
  age_h="$(jq -n --arg t "$last" '(now - ($t | fromdateiso8601)) / 3600 | floor')"
fi
if [ "$age_h" -gt 48 ]; then
  {
    echo "\`kernel-lt-bump\` runs daily and last succeeded ${last:-never} (${age_h}h ago)."
    echo
    echo "GitHub disables scheduled workflows after 60 days without repository activity, and a"
    echo "disabled or failing schedule reports nothing by itself. Check the Actions tab:"
    echo "https://github.com/$REPO/actions/workflows/kernel-lt-bump.yml"
  } > "$work/silent.md"
  rolling ci-failure 'Scheduled job silent: kernel-lt-bump' "$work/silent.md"
else
  echo "kernel-lt-bump last succeeded ${age_h}h ago"
  rolling ci-failure 'Scheduled job silent: kernel-lt-bump' ''
fi

# --- 2. main ahead of the signed repo -------------------------------------------------------
gh api "repos/$REPO/git/trees/gh-pages?recursive=1" --jq '.tree[].path' > "$work/pages.txt"
# Assert the instrument before trusting an absence: an unreadable or empty listing would make
# every package look unpublished, or (worse, with a different bug) every package look fine.
if ! grep -q '\.rpm$' "$work/pages.txt"; then
  echo "gh-pages listing has no RPMs; refusing to judge what is published" >&2; exit 1
fi

: > "$work/missing.md"
need() { # need <rpm name prefix> <workflow file>
  if ! grep -qF "/$1" "$work/pages.txt"; then
    run="$(gh run list -R "$REPO" --workflow "$2" --branch "$DEFAULT_BRANCH" --status success \
      --limit 1 --json databaseId --jq '.[0].databaseId // empty')"
    echo "- \`$1\` — ${run:+last green \`$2\` run on $DEFAULT_BRANCH: \`$run\`}${run:-no green \`$2\` run on $DEFAULT_BRANCH yet}" >> "$work/missing.md"
  fi
}

kver="$(awk '/^Version:/ {print $2}' kernel/kernel-lt.spec)"
[ -n "$kver" ] || { echo "no Version: in kernel/kernel-lt.spec" >&2; exit 1; }
need "kernel-lt-$kver-" kernel-lt.yml

rver="$(awk '/^Version:/ {print $2}' muertos-release/muertos-release.spec)"
[ -n "$rver" ] || { echo "no Version: in muertos-release.spec" >&2; exit 1; }
need "muertos-release-$rver-" muertos-release.yml

# survey/fixed.json is the declared list of backported packages and the release that fixes each.
jq -r 'to_entries[] | .key as $p | .value | to_entries[] | "\($p)-\(.value)"' survey/fixed.json \
  | sort -u > "$work/backports.txt"
[ -s "$work/backports.txt" ] || { echo "survey/fixed.json lists no fixes" >&2; exit 1; }
while read -r nvr; do need "$nvr." backports.yml; done < "$work/backports.txt"

if [ -s "$work/missing.md" ]; then
  {
    echo "\`$DEFAULT_BRANCH\` has versions the signed yum repo on \`gh-pages\` does not serve:"
    echo
    cat "$work/missing.md"
    echo
    echo "Signing is a human step. On the mini:"
    echo
    echo '```bash'
    echo './release/publish-on-mini.sh <run id>...'
    echo '```'
  } > "$work/publish.md"
  rolling needs-publish 'Signed repo is behind main' "$work/publish.md"
else
  echo "gh-pages serves everything on $DEFAULT_BRANCH"
  rolling needs-publish 'Signed repo is behind main' ''
fi

# --- 3. pull requests waiting on the owner --------------------------------------------------
cutoff="$(jq -rn 'now - 7 * 86400 | todate')"
gh pr list -R "$REPO" --state open --limit 200 --json number,title,createdAt,isDraft \
  | jq -r --arg c "$cutoff" '.[] | select(.isDraft | not) | select(.createdAt < $c)
      | "- #\(.number) \(.title) (opened \(.createdAt[0:10]))"' > "$work/stale.md"
if [ -s "$work/stale.md" ]; then
  { echo "Open for more than 7 days:"; echo; cat "$work/stale.md"; } > "$work/waiting.md"
  rolling waiting-on-owner 'Pull requests waiting on the owner' "$work/waiting.md"
else
  echo "no pull request is older than 7 days"
  rolling waiting-on-owner 'Pull requests waiting on the owner' ''
fi
