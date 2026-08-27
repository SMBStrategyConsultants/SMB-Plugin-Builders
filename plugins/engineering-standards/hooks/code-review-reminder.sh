#!/usr/bin/env bash
# ANCHOR: code-review-reminder | role: Hook | refs: ENGINEERING-CORE.md §17
#
# Fires when a user prompt asks for a code review, and injects the §17.9 contract
# for how a review must be run — the skill, a fresh unbiased agent, minimal
# context, and the areas to cover. Advisory only.
#
# Adapted from an internal PersonalAssistant hook of the same shape (matcher
# logic unchanged — it was already harness-agnostic); only the injected content
# changed, to point at ENGINEERING-CORE.md/REVIEW.md instead of an internal doc
# you don't have.
#
# Registered via this plugin's hooks.json (UserPromptSubmit).
set -uo pipefail

payload="$(cat)"
prompt="$(printf '%s' "$payload" | jq -r '[.prompt?, .user_prompt?, .input?, .request?] | map(select(type=="string")) | first // empty' 2>/dev/null)"
[ -z "$prompt" ] && exit 0

# Machine-generated turns are not review requests.
printf '%s' "$prompt" | grep -qF 'SYSTEM NOTIFICATION - NOT USER INPUT' && exit 0
printf '%s' "$prompt" | grep -qF '<task-notification>' && exit 0

norm=" $(printf '%s' "$prompt" | tr '[:upper:]' '[:lower:]' | tr -d "'\342\200\231" | tr -cs '[:alnum:]' ' ') "

matched=0

REVIEW=' (code review|review (this |that |the )?(pr|pull request|diff|branch|change|changes|code)|pr review|security review|review pr [0-9]+|do a review|run a review|review it|needs? (a )?(code )?review|another review|re review|spawn (an? )?(agent|subagent)[a-z ]{0,20}review|agent to review) '
printf '%s' "$norm" | grep -qE "$REVIEW" && matched=1

if [ "$matched" -eq 0 ]; then
  printf '%s' "$prompt" | grep -qE '(^|[[:space:]])/(code-)?review([[:space:]]|$)|(^|[[:space:]])/security-review([[:space:]]|$)' && matched=1
fi

[ "$matched" -eq 0 ] && exit 0

CTX='CODE-REVIEW REQUEST DETECTED (advisory — hook pattern match). ENGINEERING-CORE.md §17 is binding on how this runs; read it before briefing anyone. Non-negotiables:

(1) USE THE SKILL. Invoke `code-review` for a working diff, `security-review` for a specialized security pass. Never hand-roll a prose review. The skill supplies ReportFindings, which structurally enforces §17.2 falsifiability (`failure_scenario` is required).

(2) SPAWN A FRESH AGENT. One new reviewing agent per review. NEVER the implementing agent, and never an agent that authored any part of the diff — including you. If you wrote any of it, say so in the brief and instruct that it gets the same scrutiny; do not review it yourself. You are PRE-AUTHORIZED to spawn it — do not stop to ask; §17.6 cannot be satisfied without a review, so permission is implied the moment a PR exists. (This is about spawning REVIEW subagents only — merge authority stays with the client, always; see the top of CLAUDE.md.)

(3) MINIMAL, UNBIASED CONTEXT — PLUS THE EDITED-FILE LIST. Give the reviewer the authoritative sources only: the spec, the task brief, the decision record, the review ledger, and the tracked edited-file list for this session (from `code-edit-tracker.sh`, where installed). That list is the anchor set the reviewer traces "follow the consumer mechanism" from, not a free roam of the workspace. Do NOT pass your own findings, verdicts, severity guesses, or a curated "this part is fine" list. Accepted trade-offs belong in the decision record, where the reviewer reads them independently.

(4) TREAT COMMIT CLAIMS AS HYPOTHESES. Test counts, mutation results and "verified" in commit messages or agent reports are claims to re-run, never evidence.

(5) AREAS TO COVER — spec conformance, correctness, security and data integrity, integration contracts (both sides of any seam, error paths included), test sufficiency, regression risk (shared/consumer code paths).

(6) READ-ONLY AND NO LEDGER WRITES. Reviewers report; you consolidate into the ledger and allocate finding IDs. Verdict is APPROVE / APPROVE WITH FOLLOW-UP / REQUEST CHANGES — a recommendation only. You open the PR; you never merge it.

Budget (§17.5): one paired Full + one paired Delta. Brief reviewers with MODE: FULL or DELTA and pinned SHAs. AUTO is the default: after a Delta, one targeted THIRD reviewer (not another pair) may be authorized without the client only for a named Blocker/High FIX NOW trigger; otherwise stop. A THIRD that still says REQUIRED, material reviewer disagreement, or acceptance of unresolved Blocker/High risk escalates to the client. If the request is not actually about reviewing code, ignore this reminder.'

jq -n --arg ctx "$CTX" '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$ctx}}'
