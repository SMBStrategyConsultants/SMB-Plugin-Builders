#!/usr/bin/env bash
# ANCHOR: slack-post-tracker | role: Hook | refs: SLACK-PROTOCOL.md
#
# Records two per-session signals so slack-post-reminder.sh can tell at Stop
# time whether a PR-shaped session ended with zero Slack activity:
#   - propened.$sid   : a `gh pr create` command ran this session
#   - slackposted.$sid: a Slack MCP tool call ran this session
#
# PostToolUse, matcher "*" (same shape as context-gate.py's "*" entry) — cheap
# to run on every tool call since both checks are single string tests.
#
# COARSE BY DESIGN. This cannot detect a blocker or a merge-ready condition —
# those are judgment calls SLACK-PROTOCOL.md leaves to the agent, not a
# mechanical event. What it detects is the narrower, still-useful signal: "a PR
# got opened this session and the agent never touched Slack at all." A session
# that legitimately has nothing post-worthy (no blocker, no milestone) will
# still trip this — that's why slack-post-reminder.sh is advisory, never a
# gate, same as work-log-reminder.sh.
#
# ASYMMETRIC BIAS, DELIBERATE (FULL review, 2026-09-02): this hook cannot
# block, so the only thing a wrong detection can cost is credibility — and
# that cost is not symmetric. A missed `propened` is silent (nobody notices).
# A missed `slackposted` is loud and, worse, UNFIXABLE by compliant behavior —
# the contractor DID post, gets nagged anyway, and there is nothing they could
# have done differently. So `slackposted` matches permissively (any Slack MCP
# tool name, minus drafts and read-only lookups) and `propened` matches
# strictly (a real `gh pr create` invocation, not a mention of one). Getting
# this backwards was the root cause of the FULL review's High finding
# (SPR-01) — see .agent/REVIEW_LEDGER.md.
#
# KNOWN GAPS, logged not hidden — verified by direct probe, not assumed. Two
# review rounds (FULL + DELTA, 2026-09-02) each found the previous version of
# this comment wrong about its own behavior — see .agent/REVIEW_LEDGER.md
# (SPR-02) for the corrected history:
#   - `xargs`/`env -i`/`timeout` wrapping, an executed heredoc (`bash <<EOF`/
#     `cat <<EOF | bash`/`ssh host <<EOF`), and command substitution/grouping
#     (`$(gh pr create ...)`, backticks, parens) are all DETECTED — the
#     heredoc-opener consumer check below (ported from
#     destructive-command-guard.sh, same reasoning) skips stripping when the
#     heredoc's own consumer is a shell/executor, so the body is scanned as a
#     real invocation rather than treated as inert data.
#   - A plain MENTION of the phrase still matches — `echo "remember to gh pr
#     create later"`, a comment, a doc line. Same class as
#     destructive-command-guard.sh's own logged position-anchoring gap
#     (README.md) — a line-based text matcher cannot distinguish "this runs
#     the command" from "this is prose about the command." Not fixed here;
#     the false-positive direction is the safe one for `propened` per the
#     bias note above (an extra nag on a no-PR session, not a missing one).
#   - The `--help`/`-h` exclusion is scoped per matched invocation (up to the
#     next `;`/`&`/`|`), not per whole line, so `gh pr create --help | cat;
#     gh pr create --fill` still marks on the second, real invocation. It
#     cannot distinguish a real `-h`/`--help` flag from that exact substring
#     appearing inside a quoted argument on the SAME invocation (`gh pr create
#     --title "Add -h flag support"` will not mark) — a real parser would be
#     needed to close that, and it is judged rare enough next to the
#     sibling-invocation case (which real sessions running `--help` to check
#     usage before the real call would actually hit) not to be worth one.
#   - PostToolUse fires regardless of the command's exit status — a failed
#     `gh pr create` (bad auth, no repo) still marks `propened`. Same
#     asymmetry the plugin README's Known Limitations section already
#     documents for `slackposted`'s marker: a call that fires but errors still
#     marks state. Documented symmetrically here rather than parsing
#     `.tool_response`, which is not reliably shaped the same way across
#     harnesses.
#   - `slackposted` relies on the harness naming MCP tools `mcp__<server>__
#     <tool>` and the server itself being named with "slack" in it — a Slack
#     tool exposed under a differently-named server (`mcp__team-chat__
#     chat_postMessage`) will not match. Not fixed here; no tool inventory is
#     pinned anywhere in this repo to match against instead (verified by grep
#     at FULL review time).
#
# Fail open always: missing jq, missing session id, unreadable state dir all
# exit 0 silent.

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
DIR="$PROJECT_DIR/.agent/tmp/code-review"

# shellcheck source=lib/code-review-session.sh
. "$HOOK_DIR/lib/code-review-session.sh" 2>/dev/null || exit 0

command -v jq >/dev/null 2>&1 || exit 0

payload="$(cat)"
tool="$(printf '%s' "$payload" | jq -r '.tool_name // .toolName // .original_request_name // empty' 2>/dev/null)"
[ -z "$tool" ] && exit 0

sid="$(session_id_from "$payload")"
[ -z "$sid" ] && exit 0

mark_pr_opened() { mkdir -p "$DIR"; : > "$DIR/propened.$sid"; }
mark_slack_posted() { mkdir -p "$DIR"; : > "$DIR/slackposted.$sid"; }

if [ "$tool" = "Bash" ]; then
    cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // .toolInput.command // empty' 2>/dev/null)"
    [ -z "$cmd" ] && exit 0

    # Heredoc bodies are normally treated as DATA (stripped below) — correct
    # when the heredoc feeds a file-writer or a log (WORK-LOG.md append). It is
    # WRONG when the heredoc's own consumer is itself a shell/executor (`bash
    # <<EOF`, `cat <<EOF | bash`, `ssh host <<EOF`) — there the body IS the
    # command. Detect that shape first and skip stripping entirely when found,
    # so the invocation check below sees the real body. Ported verbatim
    # (reasoning and all) from destructive-command-guard.sh, which solves the
    # identical problem for its own gate — DELTA review verified this port
    # 6/6 against both the executed-heredoc and worklog-mention cases.
    heredoc_openers="$(grep -E '<<' <<< "$cmd" | sed -E 's/>>?[[:space:]]*[^[:space:]|;&]+//g')"
    if grep -Eqi '(^|[^A-Za-z0-9_])(bash|sh|zsh|ssh|docker|kubectl)([^A-Za-z0-9_]|$)' <<< "$heredoc_openers"; then
        scan="$cmd"
    else
        STRIPPER="$HOOK_DIR/strip-heredocs.awk"
        if [ -f "$STRIPPER" ]; then
            scan="$(printf '%s' "$cmd" | awk -f "$STRIPPER" 2>/dev/null || printf '%s' "$cmd")"
        else
            scan="$cmd"
        fi
    fi

    # Boundary class widened past the original start/;/&/|/space set to also
    # accept "(" and a backtick, so `$(gh pr create ...)` and a backtick
    # command substitution are caught, not just a bare top-level invocation.
    # Each match is extracted (up to the next separator) so the --help
    # exclusion below can be scoped per-invocation, not per-line — see the
    # KNOWN GAPS note above for what this does and does not close.
    matches="$(printf '%s' "$scan" | grep -oE '(^|[;&|(`]|[[:space:]])gh[[:space:]]+pr[[:space:]]+create[^;&|)`]*' 2>/dev/null)"
    if [ -n "$matches" ]; then
        while IFS= read -r seg; do
            [ -z "$seg" ] && continue
            case "$seg" in
                *--help*|*' -h'*|*' -h') ;;  # help invocation for this segment — skip
                *) mark_pr_opened; break ;;
            esac
        done <<< "$matches"
    fi
    exit 0
fi

# Any Slack MCP tool call counts as "posted" — deliberately permissive, not
# restricted to a specific verb. A FULL review measured the earlier
# `*slack*send_message*|*slack*schedule_message*` pattern against real Slack
# MCP server tool names and found it missed the community server's own
# `slack_post_message`, plus `chat_postMessage`/`conversations_add_message`
# variants from other servers — i.e. it produced a permanent false nag on a
# contractor who DID post, on whichever Slack MCP server they actually have
# installed. This plugin does not pin one server's tool names (none is
# pinned anywhere in this repo), so match on the service name instead of a
# guessed verb list. Excludes anything with "draft" in the name (a draft is
# not a post) and read-only lookups (list/get/history/search/channels/users/
# info) — a DELTA review found the broad match otherwise treats "enumerated
# #build-<project> to find the channel ID" as "posted," which silently
# defeats the nag on exactly the session it exists to catch.
lc_tool="$(printf '%s' "$tool" | tr '[:upper:]' '[:lower:]')"
case "$lc_tool" in
    *draft*) exit 0 ;;
    *slack*list*|*slack*get*|*slack*history*|*slack*search*|*slack*channels*|*slack*users*|*slack*info*) exit 0 ;;
    *slack*) mark_slack_posted ;;
esac

exit 0
