#!/usr/bin/env bash
# ANCHOR: code-review-gate | role: Hook | refs: ENGINEERING-CORE.md §17.10, REVIEW.md
#
# Stop hook. Blocks the agent from ending a turn while code it wrote this session
# has not been through BOTH reviews §17.10 requires: a full code review by an
# independent subagent, and a security review by a SEPARATE independent subagent.
#
# Adapted from an internal PersonalAssistant hook of the same shape. The state
# machine, the audit-log durability checks, and the fail-closed behavior on a
# missing/broken jq are kept faithfully — those are genuine correctness properties
# of the gate, not internal-workspace ceremony. What changed for this plugin: no
# hardcoded repo path (state lives under CLAUDE_PROJECT_DIR, wherever this plugin
# is installed), and no "engineering codebases only" scope carve-out — every repo
# you build for us is shipped product code, so the gate fires everywhere, always.
#
# Why a Stop hook and not a PreToolUse push guard: the failure mode is not "pushed
# unreviewed code", it is "said the work was done". Code can be finished, reported
# complete, and never pushed at all. Stop is where "done" actually happens, so
# Stop is where the claim gets checked.
#
# ---------------------------------------------------------------------------
# DATA MODEL. Outstanding files ARE the contents of edits.<session_id> — no
# separate "reviewed" set to fall out of sync with it. Clearing a round ARCHIVES
# (to an audit log) and TRUNCATES that file. Any later edit re-appends, so
# re-arming after a post-review fix is automatic and needs no temporal
# bookkeeping — the common failure mode this avoids: a fix to an
# ALREADY-REVIEWED file not re-arming the gate because a "reviewed" set still
# contained it.
#
# State is keyed by session_id, so one session's clear cannot silence another
# session's outstanding files — a real failure mode when concurrent sessions (or
# review subagents exercising this same hook) share one bucket.
# ---------------------------------------------------------------------------
#
# Why blocking and not advisory: an advisory-only reminder that fires on prompt
# vocabulary (code-review-reminder.sh) never fires on the ACT of writing code — an
# agent that writes code and never says "review" triggers nothing. A rule with no
# consumer is not a rule.
#
# CLEARING THE GATE (the lead runs these, after the reviews actually return —
# use the shell-quoted absolute path this script computes into $SELF; a plugin
# install lives outside the project directory and can itself contain spaces, so
# neither a bare relative "code-review-gate.sh" nor an unquoted absolute path
# reliably resolves from the agent's cwd):
#   $SELF --reviewed "<full-verdict>" "<security-verdict>" [--session ID]
#   $SELF --waive "<reason>" [--session ID]
#   $SELF --status [--session ID]
# The Stop block message prints the exact command with this session's ID filled
# in. --session may be omitted only when exactly one session has pending state.
#
# Exit codes: 0 = allow, for every path INCLUDING errors — except that a missing
# jq now blocks rather than allowing silently (see below). Blocking is expressed
# as JSON on stdout, not via exit status.

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Shell-quoted, not just absolute — a plugin install path can contain spaces
# (this repo's own parent, "Antigravity Projects", is one), and an unquoted
# absolute path word-splits exactly as badly as a relative one when pasted into
# a shell. Every printed clear-command site below uses $SELF, never a raw
# unquoted interpolation of $HOOK_DIR.
SELF="$(printf '%q' "$HOOK_DIR/code-review-gate.sh")"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
DIR="$PROJECT_DIR/.agent/tmp/code-review"
LOG_FILE="$DIR/history.log"
HARNESS="claude"

if [ "${1:-}" = "--harness" ]; then
    HARNESS="${2:-claude}"
    shift 2
fi

# shellcheck source=lib/code-review-session.sh
. "$HOOK_DIR/lib/code-review-session.sh" 2>/dev/null || true

mkdir -p "$DIR" 2>/dev/null || true

# Resolve which session's state a CLI invocation refers to. Never guess between
# two candidates — guessing wrong silences a real session's outstanding files.
resolve_sid() {
    local want="${1:-}"
    if [ -n "$want" ]; then printf '%s' "$want"; return 0; fi
    local files=("$DIR"/edits.*)
    local live=()
    for f in "${files[@]}"; do [ -s "$f" ] && live+=("$f"); done
    case "${#live[@]}" in
        1) basename "${live[0]}" | sed 's/^edits\.//' ;;
        0) printf '' ;;
        *) echo "ERROR: ${#live[@]} sessions have pending state. Pass --session ID explicitly:" >&2
           for f in "${live[@]}"; do echo "  --session $(basename "$f" | sed 's/^edits\.//')" >&2; done
           return 1 ;;
    esac
}

# Collapse newlines/CR so a multi-line argument cannot forge additional log lines.
# Verdict strings are pasted from AGENT OUTPUT, which routinely contains
# newlines, so this is reachable by accident and not only by malice.
oneline() { printf '%s' "${1:-}" | tr '\n\r' '  ' | tr -s ' '; }

clear_state() {  # $1=sid $2=logline -> prints file count, non-zero on audit failure
    local sid="$1" line="$2" f="$DIR/edits.$sid"
    local n=0

    if [ -f "$f" ]; then
        n="$(grep -c . "$f" 2>/dev/null)" || n=0
    fi
    n="$(printf '%s' "$n" | tr -cd '0-9')"; [ -z "$n" ] && n=0

    # The audit record is the only evidence a clear/waiver happened. An
    # unwritable log must refuse the clear, not silently truncate state with no
    # durable record — that is the same fail-open class as the gate not firing.
    if ! printf '' >> "$LOG_FILE" 2>/dev/null; then
        echo "ERROR: cannot write the audit log at $LOG_FILE." >&2
        echo "Refusing to clear the gate — a clear with no durable record is not a clear." >&2
        echo "Fix permissions on that path, then re-run." >&2
        return 1
    fi

    local before after
    before="$(wc -c < "$LOG_FILE" 2>/dev/null | tr -cd '0-9')"; [ -z "$before" ] && before=0
    {
        printf '%s session=%s %s files=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$sid" "$line" "$n"
        [ -f "$f" ] && sed 's/^/    /' "$f"
    } >> "$LOG_FILE" 2>/dev/null
    after="$(wc -c < "$LOG_FILE" 2>/dev/null | tr -cd '0-9')"; [ -z "$after" ] && after=0

    if [ "$after" -le "$before" ]; then
        echo "ERROR: the audit log did not grow — the record was not durably written." >&2
        echo "Refusing to clear the gate." >&2
        return 1
    fi

    : > "$f"
    printf '%s' "$n"
}

append_audit() { # $1=line; non-zero unless the record is durably appended
    local line="$1" before after
    if ! printf '' >> "$LOG_FILE" 2>/dev/null; then
        echo "ERROR: cannot write the audit log at $LOG_FILE." >&2
        return 1
    fi
    before="$(wc -c < "$LOG_FILE" 2>/dev/null | tr -cd '0-9')"; [ -z "$before" ] && before=0
    printf '%s\n' "$line" >> "$LOG_FILE" 2>/dev/null
    after="$(wc -c < "$LOG_FILE" 2>/dev/null | tr -cd '0-9')"; [ -z "$after" ] && after=0
    [ "$after" -gt "$before" ] || { echo "ERROR: audit record was not durably written." >&2; return 1; }
}

# scan_high_risk <newline-separated absolute paths> -> prints one matched trigger
# name and returns 0, or returns 1 with no output.
#
# Mechanical ENGINEERING-CORE.md §17.5 High-risk classifier. This does NOT let the
# writing agent judge its own risk — it is a fixed, objective grep against §17.5's
# own High-risk list (auth, payments, permissions, migrations, PII/PHI,
# multi-tenant isolation, public API, infrastructure), deliberately keyword-broad
# and false-positive-prone by design: a false positive costs one extra security
# pass; a false negative skips one that was owed. When it hits nothing, the
# security pass becomes optional (NOT_WARRANTED, no reviewer spawned) — the
# FULL/DELTA code-correctness review is untouched and still always runs.
scan_high_risk() {
    local files="$1" f real
    local kw='(\bauth(entication|orization)?\b|\bjwt\b|\boauth\b|session[_-]?token|\bpassword\b|\bpermission(s)?\b|\brbac\b|\bpayment(s)?\b|\bstripe\b|\bpaypal\b|\bbilling\b|\binvoice\b|\bmigration(s)?\b|\balembic\b|\bpii\b|\bphi\b|\bpatient\b|medical[_-]?record|\bssn\b|date[_-]?of[_-]?birth|tenant[_-]?id|org(anization)?[_-]?id|multi-?tenant|\bopenapi\b|\bswagger\b|public[_-]?api)'
    local infra='(^|/)(Dockerfile|docker-compose.*\.ya?ml|.*\.tf|wrangler\.toml|.*\.tfvars)$'
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        # $f is printf '%q'-quoted (code-edit-tracker.sh writes it that way so an
        # embedded newline can't forge a second entry), so it is a SHELL WORD, not
        # a real path — a space in the directory name (this repo's own parent,
        # "Antigravity Projects", is exactly such a path) round-trips as a literal
        # backslash-space and never matches a real file. Unquote before using it
        # as a path; the escaped form is fine for the string-only infra grep and
        # for display, since it's our own %q output, not attacker-controlled shape.
        real="$f"
        eval "real=$f" 2>/dev/null || real="$f"
        if printf '%s' "$f" | grep -qiE "$infra" 2>/dev/null; then
            printf 'infrastructure (%s)' "$(basename "$real")"; return 0
        fi
        if [ -f "$real" ] && grep -qiE "$kw" "$real" 2>/dev/null; then
            printf 'high-risk keyword match (%s)' "$(basename "$real")"; return 0
        fi
    done <<< "$files"
    return 1
}

phase_file() { printf '%s/phase.%s' "$DIR" "$1"; }
policy_file() { printf '%s/policy.%s' "$DIR" "$1"; }
phase_of() {
    local f; f="$(phase_file "$1")"
    [ -s "$f" ] && head -n 1 "$f" || printf 'full'
}
policy_of() {
    local f; f="$(policy_file "$1")"
    [ -s "$f" ] && head -n 1 "$f" || printf 'auto'
}
set_phase() { printf '%s\n' "$2" > "$(phase_file "$1")"; }
lastblock_file() { printf '%s/lastblock.%s' "$DIR" "$1"; }
reset_cycle() { rm -f "$(phase_file "$1")" "$(policy_file "$1")" "$(lastblock_file "$1")"; }
valid_next() { [ "$1" = "REQUIRED" ] || [ "$1" = "NOT_WARRANTED" ]; }

# Refuses an explicit --session that this DIR has never heard of, instead of
# clear_state() silently treating "no edits file" as "0 files, success". Without
# this, a CLAUDE_PROJECT_DIR/cwd mismatch between where the tracker wrote state
# and where a CLI clear runs from produces a phantom clear: the command reports
# success, a durable log entry is written into the WRONG (possibly newly
# created) directory, and the real outstanding files in the real directory are
# untouched — the Stop hook then blocks again with no visible explanation for
# why "clearing" it did nothing. Only applies when --session was given
# explicitly; resolve_sid's own single-live-session auto-pick is already tied to
# a real file by construction.
require_known_session() {
    local sid="$1" explicit="$2"
    [ "$explicit" != "1" ] && return 0
    # edits.$sid ALONE, not phase/policy too: clear_state() truncates but never
    # removes it, so a completed session's file persists — checking it, and only
    # it, is what lets a legitimate delta/third clear pass while still refusing
    # a session this DIR has no record of at all. phase.*/policy.* were tried
    # and found to widen, not narrow, what a bare directory listing can forge.
    if [ ! -e "$DIR/edits.$sid" ]; then
        echo "ERROR: no review state for session $sid was found at $DIR." >&2
        echo "This usually means the gate is resolving a different project directory than the one" >&2
        echo "code-edit-tracker.sh wrote to (CLAUDE_PROJECT_DIR unset and cwd differs from the tracked" >&2
        echo "session's project root). Refusing to report success for a clear that would clear nothing." >&2
        echo "cd to the project root the edits were made in, or re-run with the correct --session, then retry." >&2
        return 1
    fi
    return 0
}
emit_block() {
    local reason="$1"
    if [ "$HARNESS" = "gemini" ]; then
        jq -n --arg r "$reason" '{decision:"deny", reason:$r}'
    else
        jq -n --arg r "$reason" '{decision:"block", reason:$r}'
    fi
}

cmd="${1:-}"; shift 2>/dev/null || true
args=(); want_sid=""
while [ $# -gt 0 ]; do
    case "$1" in
        --session) want_sid="${2:-}"; shift 2 ;;
        *) args+=("$1"); shift ;;
    esac
done

case "$cmd" in
    --reviewed)
        mode="${args[0]:-}"
        case "$mode" in full|delta|third) ;; *) echo "ERROR: invalid review mode: $mode" >&2; exit 1 ;; esac
        sid="$(resolve_sid "$want_sid")" || exit 1
        [ -z "$sid" ] && { echo "Nothing outstanding."; exit 0; }
        require_known_session "$sid" "$([ -n "$want_sid" ] && echo 1 || echo 0)" || exit 1
        expected="$(phase_of "$sid")"
        [ "$mode" = "$expected" ] || { echo "ERROR: session $sid expects $expected review, not $mode." >&2; exit 1; }
        policy="$(policy_of "$sid")"

        if [ "$mode" = "third" ]; then
            role="${args[1]:-}"; verdict="${args[2]:-}"; next="${args[3]:-}"; trigger="${args[4]:-}"
            case "$role" in code|security|migration) ;; *) echo "ERROR: third-pass role must be code, security, or migration." >&2; exit 1 ;; esac
            [ -n "$verdict" ] && [ -n "$trigger" ] && valid_next "$next" || {
                echo "ERROR: third review requires role, verdict, NEXT ROUND, and the authorized trigger." >&2
                echo "usage: $SELF --reviewed third <code|security|migration> '<verdict>' <REQUIRED|NOT_WARRANTED> '<authorized trigger>' [--session ID]" >&2
                exit 1
            }
            n="$(clear_state "$sid" "REVIEWED mode=third role=$role verdict=$(oneline "$verdict") next=$next trigger=$(oneline "$trigger") policy=$policy")" || exit 1
            if [ "$next" = "NOT_WARRANTED" ]; then
                reset_cycle "$sid"
                echo "Targeted third pass complete for session $sid ($n file(s)); role=$role."
            else
                set_phase "$sid" escalate
                echo "Third pass exhausted for session $sid; unresolved material risk requires the client (J)."
            fi
            exit 0
        fi

        full="${args[1]:-}"; sec="${args[2]:-}"
        full_next="${args[3]:-}"; sec_next="${args[4]:-}"; trigger="${args[5]:-}"
        if [ -z "$full" ] || [ -z "$sec" ] || [ -z "$full_next" ] || [ -z "$sec_next" ]; then
            echo "ERROR: paired review requires both verdicts and both NEXT ROUND values." >&2
            echo "usage: $SELF --reviewed <full|delta> '<full>' '<security>' <REQUIRED|NOT_WARRANTED> <REQUIRED|NOT_WARRANTED> ['named trigger'] [--session ID]" >&2
            exit 1
        fi
        valid_next "$full_next" && valid_next "$sec_next" || { echo "ERROR: NEXT ROUND must be REQUIRED or NOT_WARRANTED." >&2; exit 1; }
        n="$(clear_state "$sid" "REVIEWED mode=$mode full=$(oneline "$full") security=$(oneline "$sec") full_next=$full_next security_next=$sec_next trigger=$(oneline "$trigger") policy=$policy")" || exit 1

        if [ "$full_next" = "NOT_WARRANTED" ] && [ "$sec_next" = "NOT_WARRANTED" ]; then
            reset_cycle "$sid"
            echo "Review cycle complete for session $sid ($n file(s)); mode=$mode."
            exit 0
        fi

        case "$mode" in
            full)
                set_phase "$sid" delta
                echo "Full round recorded for session $sid ($n file(s)); batch all fixes, then run one paired DELTA."
                ;;
            delta)
                if [ "$policy" = "auto" ] && [ -n "$trigger" ]; then
                    set_phase "$sid" third
                    echo "AUTO authorized one fresh-implementer fix plus narrow THIRD verification for session $sid: $trigger"
                else
                    set_phase "$sid" escalate
                    echo "Delta exhausted the normal budget for session $sid; escalation required."
                fi
                ;;
        esac
        exit 0
        ;;
    --policy)
        policy="${args[0]:-}"
        case "$policy" in auto|ask) ;; *) echo "ERROR: policy must be auto or ask." >&2; exit 1 ;; esac
        sid="$(resolve_sid "$want_sid")" || exit 1
        [ -z "$sid" ] && { echo "ERROR: no pending review session." >&2; exit 1; }
        require_known_session "$sid" "$([ -n "$want_sid" ] && echo 1 || echo 0)" || exit 1
        printf '%s\n' "$policy" > "$(policy_file "$sid")"
        echo "Review escalation policy for session $sid: $policy"
        exit 0
        ;;
    --authorize-third)
        trigger="${args[0]:-}"
        [ -z "$trigger" ] && { echo "ERROR: a named High-risk trigger is required." >&2; exit 1; }
        sid="$(resolve_sid "$want_sid")" || exit 1
        require_known_session "$sid" "$([ -n "$want_sid" ] && echo 1 || echo 0)" || exit 1
        [ "$(phase_of "$sid")" = "escalate" ] || { echo "ERROR: session $sid is not awaiting escalation." >&2; exit 1; }
        append_audit "$(date -u +%Y-%m-%dT%H:%M:%SZ) session=$sid THIRD_AUTHORIZED trigger=$(oneline "$trigger")" || exit 1
        set_phase "$sid" third
        echo "One fresh-implementer fix plus narrow third verification authorized for session $sid: $trigger"
        exit 0
        ;;
    --accept-risk)
        reason="${args[0]:-}"
        [ -z "$reason" ] && { echo "ERROR: accepted risk needs a stated reason." >&2; exit 1; }
        sid="$(resolve_sid "$want_sid")" || exit 1
        [ -z "$sid" ] && { echo "Nothing outstanding."; exit 0; }
        require_known_session "$sid" "$([ -n "$want_sid" ] && echo 1 || echo 0)" || exit 1
        n="$(clear_state "$sid" "RISK_ACCEPTED reason=$(oneline "$reason")")" || exit 1
        reset_cycle "$sid"
        echo "Risk accepted and review cycle closed for session $sid ($n file(s)): $reason"
        exit 0
        ;;
    --waive)
        reason="${args[0]:-}"
        [ -z "$reason" ] && { echo "ERROR: a waiver needs a stated reason. usage: --waive '<reason>'" >&2; exit 1; }
        sid="$(resolve_sid "$want_sid")" || exit 1
        [ -z "$sid" ] && { echo "Nothing outstanding."; exit 0; }
        require_known_session "$sid" "$([ -n "$want_sid" ] && echo 1 || echo 0)" || exit 1
        n="$(clear_state "$sid" "WAIVED reason=$(oneline "$reason")")" || exit 1
        reset_cycle "$sid"
        echo "Gate waived for session $sid ($n file(s)) and logged: $reason"
        exit 0
        ;;
    --status)
        sid="$(resolve_sid "$want_sid")" || exit 1
        if [ -z "$sid" ]; then
            echo "outstanding unreviewed code files: 0"; exit 0
        fi
        phase="$(phase_of "$sid")"; policy="$(policy_of "$sid")"
        count=0; [ -s "$DIR/edits.$sid" ] && count="$(sort -u "$DIR/edits.$sid" | grep -c .)"
        echo "session $sid — phase=$phase policy=$policy outstanding=$count"
        [ "$count" -gt 0 ] && sort -u "$DIR/edits.$sid" | sed 's/^/  /'
        exit 0
        ;;
esac

# ---- Stop-hook path ----
payload="$(cat 2>/dev/null || true)"

# jq absent OR BROKEN must FAIL CLOSED — this is a FUNCTIONAL probe, not
# `command -v`: a jq that exists on PATH but exits non-zero passes a presence
# check, then the block-emitting `jq -n` below fails, nothing is written to
# stdout, and the gate silently allows.
if ! printf '{}' | jq -e . >/dev/null 2>&1; then
    printf '{"decision":"block","reason":"code-review-gate: jq is not on PATH, so review state cannot be read. Blocking rather than assuming the code was reviewed. Install jq or clear the gate explicitly."}\n'
    exit 0
fi

# MANDATORY loop guard. When this hook blocks, the agent continues and will hit
# Stop again; without this check it blocks forever and the session cannot end.
active="$(printf '%s' "$payload" | jq -r '.stop_hook_active // false' 2>/dev/null)"
[ "$active" = "true" ] && exit 0

# A missing/unsourceable lib must FAIL CLOSED, same class as the jq check above.
if ! command -v session_id_from >/dev/null 2>&1; then
    emit_block "code-review-gate: hooks/lib/code-review-session.sh could not be sourced, so review session state cannot be located. Blocking rather than assuming the code was reviewed. Reinstall the engineering-standards plugin."
    exit 0
fi

sid="$(session_id_from "$payload")"

EDITS="$DIR/edits.$sid"
pending=""
[ -s "$EDITS" ] && pending="$(sort -u "$EDITS" | grep . || true)"
phase="$(phase_of "$sid")"
policy="$(policy_of "$sid")"

# A pending phase still blocks when the edit list is temporarily empty. After a
# Full review that says REQUIRED, the list is deliberately cleared so the next
# batch contains only fixes; allowing Stop in that gap would erase the Delta.
if [ -z "$pending" ] && [ "$phase" = "full" ]; then exit 0; fi

count=0; files="  - [no fix batch recorded yet]"
if [ -n "$pending" ]; then
    count="$(printf '%s' "$pending" | grep -c .)"
    files="$(printf '%s' "$pending" | sed 's/^/  - /')"
fi

risk_trigger=""
if [ -n "$pending" ]; then
    risk_trigger="$(scan_high_risk "$pending")" || risk_trigger=""
fi
security_note=""

case "$phase" in
    full)
        mode_label="FULL"
        action="Run the initial FULL code review and separate FULL security review."
        command="$SELF --reviewed full \"<full-verdict>\" \"<security-verdict>\" <REQUIRED|NOT_WARRANTED> <REQUIRED|NOT_WARRANTED> \"<named trigger if required>\" --session $sid"
        if [ -n "$risk_trigger" ]; then
            security_note="Mechanical §17.5 High-risk scan matched: $risk_trigger. Security pass is MANDATORY — spawn it."
        else
            security_note="Mechanical §17.5 High-risk scan found NO signal (auth/payments/migrations/PII-PHI/multi-tenant/public-API/infra) in this batch. The security pass is OPTIONAL for this round: you may still spawn it, or clear the security verdict as NOT_WARRANTED with reason \"no high-risk signal (auto)\" WITHOUT spawning a security reviewer. The code-correctness FULL review is NOT optional and always runs."
        fi
        ;;
    delta)
        mode_label="DELTA"
        action="Batch every accepted finding, prove the consumer mechanism and both controls, then run ONE paired DELTA. Do not restart a Full review."
        command="$SELF --reviewed delta \"<full-verdict>\" \"<security-verdict>\" <REQUIRED|NOT_WARRANTED> <REQUIRED|NOT_WARRANTED> \"<named Blocker/High FIX NOW trigger if required>\" --session $sid"
        if [ -n "$risk_trigger" ]; then
            security_note="Mechanical §17.5 High-risk scan matched: $risk_trigger. Security pass is MANDATORY — spawn it."
        else
            security_note="Mechanical §17.5 High-risk scan found NO signal in this batch. Security pass is OPTIONAL — NOT_WARRANTED with reason \"no high-risk signal (auto)\" is acceptable without spawning a security reviewer, unless the round-1 security reviewer's own findings say otherwise."
        fi
        ;;
    third)
        mode_label="THIRD"
        action="Assign the one named trigger to a FRESH IMPLEMENTER, batch that exact fix, then run ONE narrowly scoped verifier with fresh context. Do not reopen generic discovery."
        command="$SELF --reviewed third <code|security|migration> \"<verdict>\" <REQUIRED|NOT_WARRANTED> \"<authorized trigger>\" --session $sid"
        ;;
    escalate)
        read -r -d '' REASON <<EOF || true
🛑 ENGINEERING-CORE.md §17 — normal review budget exhausted.

The narrow verification after the fresh-implementer pass still reported material work. No
further generic review is automatic, and PR authority remains with the client — remember,
you and your agents never merge (top of CLAUDE.md).

AUTO mode interrupts the client only here: unresolved Blocker/High FIX NOW after the
fresh-implementer + narrow-verification pass, material reviewer disagreement, or
explicit risk acceptance.

Authorize one named High-risk pass:
  $SELF --authorize-third "<named trigger>" --session $sid

Or explicitly accept and document the residual risk:
  $SELF --accept-risk "<reason>" --session $sid

The automatic changed-implementer exception is already exhausted; do not start a
fourth review or silently accept the remaining risk.
EOF
        emit_block "$REASON"
        exit 0
        ;;
    *)
        emit_block "code-review-gate: invalid phase '$phase' for session $sid. Refusing to guess."
        exit 0
        ;;
esac

# Repeat-suppression: does NOT change whether the gate blocks — emit_block still
# fires unconditionally below either way. It only shortens the TEXT on a Stop
# event that repeats an already-announced state verbatim, which is common when a
# background review agent is in flight. The fingerprint covers everything that
# would change the guidance, so any real change reprints the full explanation.
marker="$(lastblock_file "$sid")"
fingerprint="$(printf 'phase=%s policy=%s risk=%s\n%s' "$phase" "$policy" "$risk_trigger" "$pending")"
if [ -f "$marker" ] && [ "$(cat "$marker" 2>/dev/null)" = "$fingerprint" ]; then
    read -r -d '' REASON <<EOF || true
🛑 Still blocked — same $mode_label batch already explained this cycle. Session $sid, $count file(s), policy=$policy.

Nothing has changed since the full explanation was last printed. Do the review work, then clear it:
  $command

(Full instructions reprint automatically once the batch changes — a new file, a phase transition, or a High-risk trigger appearing. To force it now: rm "$marker")
EOF
    emit_block "$REASON"
    exit 0
fi
printf '%s' "$fingerprint" > "$marker" 2>/dev/null

read -r -d '' REASON <<EOF || true
🛑 ENGINEERING-CORE.md §17.10 — coding work is not done until it is reviewed.

Review phase: $mode_label · escalation policy: $policy

$count code file(s) are in the current review batch:

$files

Do this now, in order. Do NOT report the work complete first.

SPAWNING THE REVIEWERS IS PRE-AUTHORIZED — DO NOT ASK FIRST. When §17.9/§17.10
owes a review, spawn the reviewers WITHOUT asking. Stopping to ask costs a round
trip and is itself the error. (This is about spawning REVIEW subagents, not
about merging — merge authority stays with the client, always.)

1. $action
2. For FULL/DELTA, spawn fresh independent code and security reviewers. For
   THIRD, spawn only the specialist named by the trigger. Brief with MODE:
   $mode_label, pinned base/head SHAs, the spec, decision record, and the
   review ledger. Include the pending file list above as the reviewer's anchor
   set. Give no verdicts or conclusions of your own.
$([ -n "$security_note" ] && printf '   %s\n' "$security_note")
3. CONSOLIDATE — you allocate finding IDs into the review ledger. Reviewers are
   read-only. Re-run their falsifiable claims; test counts and "verified" are
   hypotheses, not evidence.
4. CLEAR THE GATE:
     $command
5. THEN report completion in the §17.10 form — implementation, self-verification,
   full review by an independent subagent, security review by a separate one,
   ledger location.

Genuinely trivial and §17.5 Low-risk (a comment, a typo, nothing on the
High-risk list)? Waive it explicitly — it gets logged, never skipped silently:
  $SELF --waive "<reason>" --session $sid

Paths are shown shell-quoted. AUTO is the default. To require the client before
any third pass: $SELF --policy ask --session $sid

Only if a harness restriction forbids spawning subagents: say so plainly, cite
this clause, and ask once. Do not quietly proceed as if the reviews happened.
EOF

emit_block "$REASON"
exit 0
