#!/usr/bin/env bash
# React to one finished workflow run: open or update a ci-failure issue when it failed, close
# the issue when the same workflow goes green on the same branch.
#
# Env: REPO, WORKFLOW_NAME, WORKFLOW_PATH, CONCLUSION, RUN_ID, RUN_URL, HEAD_BRANCH, EVENT,
#      DEFAULT_BRANCH, GH_TOKEN. Optional: NTFY_URL, DRY_RUN=1 (print, change nothing),
#      SELF_REPORT=1 (called from inside the run it reports on, which is still in progress).
#
# Two callers. The watchdog workflow calls this on workflow_run. But GitHub raises no
# workflow_run for a run that GITHUB_TOKEN started, and the bump job starts kernel-lt that
# way, so such a run reports on itself from its last job with SELF_REPORT=1.
#
# Every value above comes from the run's metadata or its logs. All of it is data: nothing here
# is ever evaluated, and it reaches gh only as an argument or a file.
set -euo pipefail

: "${REPO:?}" "${WORKFLOW_NAME:?}" "${CONCLUSION:?}" "${RUN_ID:?}" "${RUN_URL:?}"
: "${HEAD_BRANCH:?}" "${EVENT:?}" "${DEFAULT_BRANCH:?}"
dry="${DRY_RUN:-}"

# A push or pull_request run on a feature branch is its author's business. A scheduled or
# dispatched run, and anything on the default branch, is nobody's unless this speaks up.
case "$EVENT" in
  schedule|workflow_dispatch) ;;
  *) if [ "$HEAD_BRANCH" != "$DEFAULT_BRANCH" ]; then
       echo "ignoring $EVENT run on $HEAD_BRANCH"; exit 0
     fi ;;
esac

title="CI failing: $WORKFLOW_NAME ($HEAD_BRANCH)"
# Exact-title match: the search API is fuzzy, so filter its results here.
existing="$(gh issue list -R "$REPO" --label ci-failure --state open --limit 200 --json number,title \
  | jq -r --arg t "$title" '[.[] | select(.title == $t) | .number][0] // empty')"

case "$CONCLUSION" in
  success)
    if [ -n "$existing" ]; then
      # Runs do not finish in the order they started. An older green run must not close an
      # issue that a newer red run opened.
      newest="$(gh run list -R "$REPO" --workflow "$WORKFLOW_NAME" --branch "$HEAD_BRANCH" --status completed \
        --limit 1 --json databaseId --jq '.[0].databaseId // empty')"
      if [ -z "${SELF_REPORT:-}" ] && [ "$newest" != "$RUN_ID" ]; then
        echo "run $RUN_ID is green but not the newest completed run ($newest); leaving #$existing open"; exit 0
      fi
      echo "closing #$existing: $WORKFLOW_NAME is green on $HEAD_BRANCH"
      [ -n "$dry" ] || gh issue close "$existing" -R "$REPO" --comment "Green again: $RUN_URL"
    fi
    exit 0 ;;
  failure|timed_out|startup_failure) ;;
  *) echo "conclusion '$CONCLUSION' is not a failure"; exit 0 ;;
esac

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

gh run view "$RUN_ID" -R "$REPO" --json jobs > "$work/jobs.json"
jq -r '.jobs[] | select(.conclusion != "success" and .conclusion != "skipped")
       | "- job `\(.name)`: \(.conclusion)"
         + ([.steps[]? | select(.conclusion == "failure") | ", step `\(.name)`"] | join(""))' \
  "$work/jobs.json" > "$work/failed.md"

# The log can be missing (startup_failure has none). Say so instead of showing an empty block.
if ! gh run view "$RUN_ID" -R "$REPO" --log-failed > "$work/log.raw" 2>/dev/null || [ ! -s "$work/log.raw" ]; then
  # A run still in progress has no run log yet, but its finished jobs do.
  : > "$work/log.raw"
  for job in $(jq -r '.jobs[] | select(.conclusion == "failure") | .databaseId' "$work/jobs.json"); do
    curl -fsSL --retry 3 -H "Authorization: Bearer $GH_TOKEN" \
      "https://api.github.com/repos/$REPO/actions/jobs/$job/logs" >> "$work/log.raw" 2>/dev/null || true
  done
fi
if [ -s "$work/log.raw" ]; then
  # Break any code fence in the log so it cannot close ours.
  "$(dirname "$0")/clean-log.sh" 60 < "$work/log.raw" | sed 's/```/` ` `/g' > "$work/log.txt"
else
  echo "(no failed-step log was available for this run)" > "$work/log.txt"
fi

{
  echo "\`$WORKFLOW_NAME\` finished **$CONCLUSION** on \`$HEAD_BRANCH\` ($EVENT)."
  echo
  echo "Run: $RUN_URL"
  echo
  cat "$work/failed.md"
  echo
  echo "Last lines of the failed step:"
  echo
  echo '```text'
  cat "$work/log.txt"
  echo '```'
  echo
  echo "Opened by the watchdog. It closes when \`$WORKFLOW_NAME\` next succeeds on \`$HEAD_BRANCH\`."
} > "$work/body.md"

if [ -n "$dry" ]; then
  if [ -n "$existing" ]; then echo "DRY RUN: would comment on #$existing"; else echo "DRY RUN: would open '$title'"; fi
  cat "$work/body.md"; exit 0
fi

if [ -n "$existing" ]; then
  gh issue comment "$existing" -R "$REPO" --body-file "$work/body.md"
  echo "updated #$existing"
  exit 0
fi

url="$(gh issue create -R "$REPO" --title "$title" --label ci-failure --body-file "$work/body.md")"
number="${url##*/}"
echo "opened #$number"

if [ -n "${NTFY_URL:-}" ]; then
  curl -fsS --retry 3 -H "Title: muertos: $WORKFLOW_NAME failing" -H 'Priority: high' \
    -d "$WORKFLOW_NAME $CONCLUSION on $HEAD_BRANCH. $url" "$NTFY_URL" > /dev/null \
    || echo "ntfy push failed; the issue is still open" >&2
fi

# First failure only: hand it to the repair agent. Never for the agent's or the watchdog's own
# failures, which would loop.
case "$WORKFLOW_NAME" in
  claude-fix|watchdog) ;;
  *) gh workflow run claude-fix.yml -R "$REPO" --ref "$DEFAULT_BRANCH" \
       -f issue="$number" -f run_id="$RUN_ID" -f workflow_path="${WORKFLOW_PATH:-}" \
       || echo "could not start claude-fix; the issue is still open" >&2 ;;
esac
