#!/usr/bin/env bash
# ANCHOR: slack-post-reminder | role: Hook | refs: SLACK-PROTOCOL.md
#
# Stop hook. Advisory only — never blocks. Checks two per-session touch-files
# written by slack-post-tracker.sh: propened.$sid (a `gh pr create` ran this
# session) and slackposted.$sid (a Slack tool call ran this session). If a PR
# was opened and Slack was never touched, emits a systemMessage — surfaced to
# the human, not injected into the agent's own context (no `decision` field,
# so this cannot block Stop). Mirrors work-log-reminder.sh's shape exactly,
# markers included: there is no dedup marker, so — same as that hook,
# documented in the plugin README's Known Limitations — this re-fires on
# every Stop of the session until slackposted.$sid exists, not once. "Nags
# once" was the original wording here; corrected during FULL review 2026-09-02
# after it was checked against the actual re-fire behavior and found wrong.
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

[ -f "$DIR/propened.$sid" ] || exit 0
[ -f "$DIR/slackposted.$sid" ] && exit 0

CTX="A PR was opened this session (gh pr create) but no Slack post was sent. Per SLACK-PROTOCOL.md, post to #build-<project> (progress/milestone) or #build-alerts ([BLOCKER]/[REVIEW]/[MERGE-READY], whichever applies) before ending the session — skip only if there is genuinely nothing post-worthy yet. This is advisory: it does not block ending the turn, and it cannot tell whether a blocker or merge-ready condition actually applies, only that a PR opened and Slack stayed silent."

jq -n --arg ctx "$CTX" '{systemMessage: $ctx}'
exit 0
