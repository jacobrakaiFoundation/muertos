#!/usr/bin/env bash
# Merge a kernel-lt bump pull request once kernel-lt built and boot-tested it green.
# This is the only thing in the repository that merges by itself, so every condition is
# checked here and a miss refuses with the reason. Nothing else qualifies: not a backport,
# not a docs change, not a bump a person has pushed to.
#
#   ci/automerge-bump.sh <kernel-lt run id>            # merge if every check holds
#   ci/automerge-bump.sh --dry-run <kernel-lt run id>  # report the verdict, change nothing
#   ci/automerge-bump.sh --dry-run --pr <number>       # judge a PR by its newest kernel-lt run
#
# Env: REPO, DEFAULT_BRANCH, GH_TOKEN. Exit 0 = merged or not a bump; exit 3 = refused.
set -euo pipefail

: "${REPO:?}" "${DEFAULT_BRANCH:?}"
dry=''; pr=''; run=''
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) dry=1 ;;
    --pr) pr="$2"; shift ;;
    *) run="$1" ;;
  esac
  shift
done

bump_files=$'kernel/config-x86_64\nkernel/kernel-lt.spec\nkernel/sources.sha256'
bot='github-actions[bot]'

if [ -n "$pr" ]; then
  branch="$(gh api "repos/$REPO/pulls/$pr" --jq .head.ref)"
  sha="$(gh api "repos/$REPO/pulls/$pr" --jq .head.sha)"
  run="$(gh run list -R "$REPO" --workflow kernel-lt.yml --commit "$sha" --limit 1 \
    --json databaseId --jq '.[0].databaseId // empty')"
else
  [ -n "$run" ] || { echo "usage: $0 [--dry-run] <run id> | --dry-run --pr <number>" >&2; exit 2; }
  gh run view "$run" -R "$REPO" --json headBranch,headSha > "$work/run.json"
  branch="$(jq -r .headBranch "$work/run.json")"
  sha="$(jq -r .headSha "$work/run.json")"
fi

if [[ ! "$branch" =~ ^kernel-lt-6\.12\.([0-9]+)$ ]]; then
  echo "not a bump: branch '$branch' is not kernel-lt-6.12.N"
  [ -n "$pr" ] && exit 3
  exit 0
fi
version="${branch#kernel-lt-}"

if [ -z "$pr" ]; then
  pr="$(gh pr list -R "$REPO" --head "$branch" --state open --json number --jq '.[0].number // empty')"
  [ -n "$pr" ] || { echo "no open pull request for $branch"; exit 0; }
fi

refuse() {
  echo "REFUSED #$pr: $1"
  if [ -z "$dry" ]; then
    gh pr comment "$pr" -R "$REPO" --body "Not merging this automatically: $1

It needs a person." > /dev/null
  fi
  exit 3
}

gh api "repos/$REPO/pulls/$pr" > "$work/pr.json"
[ "$(jq -r .state "$work/pr.json")" = open ] || refuse "the pull request is not open"
[ "$(jq -r .base.ref "$work/pr.json")" = "$DEFAULT_BRANCH" ] || refuse "its base is not $DEFAULT_BRANCH"
[ "$(jq -r .head.repo.full_name "$work/pr.json")" = "$REPO" ] || refuse "its branch is in a fork"
[ "$(jq -r .user.login "$work/pr.json")" = "$bot" ] || refuse "it was not opened by kernel-lt-bump"
[ "$(jq -r .head.sha "$work/pr.json")" = "$sha" ] \
  || refuse "the branch moved after the tested commit ${sha:0:7}"

authors="$(gh api "repos/$REPO/pulls/$pr/commits" --paginate --jq '.[] | .author.login // "unknown"' | sort -u)"
[ "$authors" = "$bot" ] || refuse "it carries commits from $(tr '\n' ' ' <<< "$authors")"

files="$(gh api "repos/$REPO/pulls/$pr/files" --paginate --jq '.[].filename' | sort)"
[ "$files" = "$bump_files" ] \
  || refuse "it changes files a bump does not: $(tr '\n' ' ' <<< "$files")"

spec_version="$(gh api "repos/$REPO/contents/kernel/kernel-lt.spec?ref=$sha" \
  -H 'Accept: application/vnd.github.raw' | awk '/^Version:/ {print $2}')"
[ "$spec_version" = "$version" ] || refuse "the spec says $spec_version, the branch says $version"
main_version="$(gh api "repos/$REPO/contents/kernel/kernel-lt.spec?ref=$DEFAULT_BRANCH" \
  -H 'Accept: application/vnd.github.raw' | awk '/^Version:/ {print $2}')"
[ -n "$main_version" ] || refuse "could not read the version on $DEFAULT_BRANCH"
if [ "$version" = "$main_version" ] \
   || [ "$(printf '%s\n%s\n' "$main_version" "$version" | sort -V | tail -1)" != "$version" ]; then
  refuse "$version is not newer than $DEFAULT_BRANCH's $main_version"
fi

# The run itself: the right workflow, on this commit, with both jobs green. A run's overall
# conclusion is not enough to stand on; read the jobs.
[ -n "$run" ] || refuse "no kernel-lt run exists for ${sha:0:7}"
gh run view "$run" -R "$REPO" --json workflowName,headSha,conclusion,jobs > "$work/run.json"
[ "$(jq -r .workflowName "$work/run.json")" = kernel-lt ] || refuse "run $run is not a kernel-lt run"
[ "$(jq -r .headSha "$work/run.json")" = "$sha" ] || refuse "run $run tested a different commit"
for job in build boot-test; do
  got="$(jq -r --arg j "$job" '[.jobs[] | select(.name == $j) | .conclusion][0] // "missing"' "$work/run.json")"
  [ "$got" = success ] || refuse "kernel-lt job '$job' is '$got' in run $run"
done

if [ -n "$dry" ]; then
  echo "WOULD MERGE #$pr: kernel-lt $main_version -> $version, run $run green on ${sha:0:7}"
  exit 0
fi

gh pr merge "$pr" -R "$REPO" --squash --match-head-commit "$sha" --delete-branch
echo "merged #$pr: kernel-lt $main_version -> $version"
# A merge made with GITHUB_TOKEN starts no workflow, and publish-on-mini.sh signs a run on main.
gh workflow run kernel-lt.yml -R "$REPO" --ref "$DEFAULT_BRANCH"
