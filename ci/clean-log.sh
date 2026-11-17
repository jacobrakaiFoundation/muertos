#!/usr/bin/env bash
# Clean an Actions log for showing to a person: drop the job and step columns that
# `gh run view --log-failed` prefixes, the byte-order mark, the timestamps and ANSI colour,
# and keep the last N lines. A plain job log (no columns) passes through the same way.
#   ci/clean-log.sh <lines> < raw.log
set -euo pipefail
perl -pe 's/^[^\t]*\t[^\t]*\t//; s/^\xEF\xBB\xBF//; s/^\d{4}-\d\d-\d\dT[\d:.]+Z //; s/\e\[[0-9;]*m//g' | tail -n "$1"
