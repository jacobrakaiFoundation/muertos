#!/usr/bin/env bash
# Clean `gh run view --log-failed` output for showing to a person: drop the job and step
# columns, the byte-order mark, the timestamps and ANSI colour, and keep the last N lines.
#   ci/clean-log.sh <lines> < raw.log
set -euo pipefail
cut -f3- | perl -pe 's/^\xEF\xBB\xBF//; s/^\d{4}-\d\d-\d\dT[\d:.]+Z //; s/\e\[[0-9;]*m//g' | tail -n "$1"
