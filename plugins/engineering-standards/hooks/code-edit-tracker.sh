#!/usr/bin/env bash
# ANCHOR: code-edit-tracker | role: Hook | refs: ENGINEERING-CORE.md §17.10, REVIEW.md
#
# Records every CODE file this session writes, so code-review-gate.sh can tell at
# Stop time whether unreviewed code exists. PostToolUse on Write|Edit|MultiEdit.
#
# Adapted from an internal PersonalAssistant hook of the same shape. Two changes
# from that original, both because this ships as a plugin to an external team
# rather than living inside one fixed repo:
#   1. No hardcoded repo path — state is written under the CURRENT project
#      directory (CLAUDE_PROJECT_DIR, falling back to cwd), not a fixed location.
#   2. No "engineering codebases only" scope carve-out. PersonalAssistant's own
#      copy of this hook excludes its own operational tooling (.sh/.py scripts
#      that aren't shipped product); that carve-out does not apply here — every
#      repo you build for us is shipped product code, so everything is in scope.
#
# Why this exists at all: a prompt-matching reminder (code-review-reminder.sh)
# fires on REVIEW VOCABULARY IN A PROMPT, not the ACT of writing code — so an
# agent that writes code and never says the word "review" triggers nothing. This
# hook closes that gap by tracking the act directly.
#
# STATE IS PER-SESSION. The file is keyed by session_id from the hook payload, so
# one session's clear can never silence another session's outstanding files.
#
# PATHS ARE WRITTEN SHELL-QUOTED via printf %q, so a path containing a newline
# occupies exactly one line and cannot forge a second entry.
#
# Exit codes: 0 always. A tracker that blocks work is worse than no tracker.

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
DIR="$PROJECT_DIR/.agent/tmp/code-review"
HARNESS="claude"
if [ "${1:-}" = "--harness" ]; then
    HARNESS="${2:-claude}"
    shift 2
fi

# shellcheck source=lib/code-review-session.sh
. "$HOOK_DIR/lib/code-review-session.sh" 2>/dev/null || exit 0

command -v jq >/dev/null 2>&1 || exit 0

# Claude/Codex use Write/Edit/MultiEdit/NotebookEdit/apply_patch. Gemini uses
# write_to_file/replace_file_content. The payload field names are otherwise
# compatible. Codex's apply_patch carries one patch string, so paths are
# extracted from its explicit *** Add/Update/Delete File headers.
payload="$(cat)"
tool="$(printf '%s' "$payload" | jq -r '.tool_name // .toolName // .original_request_name // empty' 2>/dev/null)"
case "$tool" in
    Write|Edit|MultiEdit|NotebookEdit|apply_patch|write_to_file|replace_file_content) ;;
    *) exit 0 ;;
esac

sid="$(session_id_from "$payload")"
project_dir="$(printf '%s' "$payload" | jq -r '.cwd // .project_dir // .projectDir // empty' 2>/dev/null)"
[ -z "$project_dir" ] && project_dir="$PROJECT_DIR"
tracked=0

# WORK-LOG.md tracking markers (WORK-LOG-PROTOCOL.md), independent of the
# code-review edits list above and NOT cleared by code-review-gate.sh — a
# review clear must not erase "did this session touch code" or "was the work
# log updated", since work-log-reminder.sh needs both to survive to Stop.
# Touch-file existence only; content doesn't matter, so a truncate-on-clear
# collision (the review gate's own DIR) is a non-issue — these two live beside
# edits.$sid but neither gate nor lead ever writes to them.
mark_code_changed() { mkdir -p "$DIR"; : > "$DIR/codechanged.$sid"; }
mark_worklog_touched() { mkdir -p "$DIR"; : > "$DIR/worklogged.$sid"; }

record_path() {
    local path="${1:-}"
    [ -z "$path" ] && return 0
    case "$path" in /*) ;; *) path="$project_dir/$path" ;; esac

    # WORK-LOG.md itself, at any depth — checked before the code-extension
    # filter below, since .md is deliberately excluded from that filter.
    case "$path" in
        */WORK-LOG.md|WORK-LOG.md) mark_worklog_touched ;;
    esac

    # Code, by extension. Deliberately NOT matched: .md, .txt, .json, .lock, .csv.
    # Config-as-code (.tf, .yml under .github/workflows) IS code.
    case "$path" in
        *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs|*.py|*.go|*.rb|*.rs|*.java|*.kt|*.swift) ;;
        *.c|*.h|*.cc|*.cpp|*.hpp|*.cs|*.php|*.sh|*.bash|*.zsh|*.sql|*.vue|*.svelte|*.tf|*.ipynb) ;;
        */.github/workflows/*.yml|*/.github/workflows/*.yaml) ;;
        *) return 0 ;;
    esac

    # Vendored / generated trees are not authored code.
    case "$path" in
        */node_modules/*|*/dist/*|*/build/*|*/.next/*|*/vendor/*|*/__pycache__/*|*/.venv/*) return 0 ;;
    esac

    mkdir -p "$DIR"
    printf '%q\n' "$path" >> "$DIR/edits.$sid"
    mark_code_changed
    tracked=1
}

if [ "$tool" = "apply_patch" ]; then
    patch="$(printf '%s' "$payload" | jq -r '.tool_input as $t | if ($t | type) == "string" then $t else ($t.patch // $t.input // "") end' 2>/dev/null)"
    while IFS= read -r path; do record_path "$path"; done <<EOF
$(printf '%s\n' "$patch" | sed -nE 's/^\*\*\* (Add|Update|Delete) File: (.*)$/\2/p')
EOF
else
    path="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // .tool_input.notebook_path // .tool_input.path // .toolInput.filePath // .toolInput.file_path // empty' 2>/dev/null)"
    record_path "$path"
fi

# Codex and Gemini receive an immediate in-loop reminder as defense in depth.
# Their lifecycle Stop/AfterAgent hook remains authoritative; this context keeps
# the agent aligned even if a harness version delays or drops the final hook.
if [ "$tracked" -eq 1 ] && [ "$HARNESS" != "claude" ]; then
    ctx="Review state recorded for session $sid (ENGINEERING-CORE.md §17 / REVIEW.md). Before your final response, run the review this batch owes and clear the gate. Spawning reviewers is pre-authorized — do not stop to ask."
    jq -n --arg ctx "$ctx" '{hookSpecificOutput:{additionalContext:$ctx}}'
fi
exit 0
