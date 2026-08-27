#!/usr/bin/env bash
# ANCHOR: code-review-session | role: Hook library | refs: ENGINEERING.md §17.10
#
# Shared session-id derivation for code-edit-tracker.sh and code-review-gate.sh.
# Both must agree exactly: if the tracker files an edit under one id and the gate
# looks under another, the gate reads an empty list and allows the turn. FAIL
# OPEN. That is why this lives in one file rather than being copy-pasted twice
# and left to drift.
#
# B-001 (security review, 2026-08-13): v2 filtered session_id with
# `tr -cd '[:alnum:]._-'` and fell back to the literal string "nosession" when
# the result was empty. Two sessions with unusable ids therefore SHARED one
# bucket, and either one's --reviewed cleared the other's unreviewed code.
# Verified live with ids "@#$%" and "^^^" — both landed in edits.nosession.
# The v2 comment two lines above that bug asserted it must not happen.
#
# Fallback order:
#   1. session_id, filtered to filesystem-safe characters
#   2. a hash of transcript_path — distinct per session, stable across a session,
#      which is exactly what is needed. Claude Code sends this on hook payloads.
#   3. "nosession" — a genuinely shared bucket, reached only when the payload
#      carries neither field. The gate treats it as UNISOLATED and refuses to
#      auto-resolve it, so clearing it requires naming it explicitly.

# session_id_from <payload-json>  -> prints a filesystem-safe session key
session_id_from() {
    local payload="${1:-}" sid tp

    sid="$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null | tr -cd '[:alnum:]._-')"
    # Reject ids that are only dots — "." and ".." are directory entries, not keys.
    case "$sid" in ''|'.'|'..') sid="" ;; esac
    if [ -n "$sid" ]; then printf '%s' "$sid"; return 0; fi

    tp="$(printf '%s' "$payload" | jq -r '.transcript_path // empty' 2>/dev/null)"
    if [ -n "$tp" ]; then
        local h=""
        if command -v shasum >/dev/null 2>&1; then
            h="$(printf '%s' "$tp" | shasum -a 256 2>/dev/null | cut -c1-16)"
        elif command -v sha256sum >/dev/null 2>&1; then
            h="$(printf '%s' "$tp" | sha256sum 2>/dev/null | cut -c1-16)"
        fi
        h="$(printf '%s' "$h" | tr -cd '[:alnum:]')"
        if [ -n "$h" ]; then printf 'tp-%s' "$h"; return 0; fi
    fi

    printf 'nosession'
}
