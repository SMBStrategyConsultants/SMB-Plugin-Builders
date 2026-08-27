#!/usr/bin/env bash
# ANCHOR: work-log-reminder | role: Hook | refs: WORK-LOG-PROTOCOL.md
#
# Stop hook. Advisory only — never blocks. Checks two per-session touch-files
# written by code-edit-tracker.sh: codechanged.$sid (code was written this
# session) and worklogged.$sid (WORK-LOG.md was touched this session). If code
# changed and the log wasn't, nags once via additionalContext.
#
# Fail open always: missing jq, missing session id, unreadable state dir all
# exit 0 silent. A reminder hook that blocks Stop is worse than no reminder.
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
DIR="$PROJECT_DIR/.agent/tmp/code-review"

# shellcheck source=lib/code-review-session.sh
. "$HOOK_DIR/lib/code-review-session.sh" 2>/dev/null || exit 0

command -v jq >/dev/null 2>&1 || exit 0

payload="$(cat)"
sid="$(session_id_from "$payload")"
[ -z "$sid" ] && exit 0

[ -f "$DIR/codechanged.$sid" ] || exit 0
[ -f "$DIR/worklogged.$sid" ] && exit 0

CTX="Code changed this session but WORK-LOG.md was not touched. Per WORK-LOG-PROTOCOL.md, append an entry before ending the session — what changed, why, which files. This is advisory: it does not block ending the turn."

jq -n --arg ctx "$CTX" '{systemMessage: $ctx}'
exit 0
