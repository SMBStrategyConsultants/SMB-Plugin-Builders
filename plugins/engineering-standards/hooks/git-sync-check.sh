#!/usr/bin/env bash
# ANCHOR: git-sync-check | role: Hook | refs: ENGINEERING-CORE.md, SETUP-INSTRUCTIONS.md §4a
#
# SessionStart hook. Advisory only — never blocks, never pulls anything itself.
# Fetches the current branch's upstream and tells the agent up front if the
# local checkout is behind origin, so a session doesn't spend an hour building
# against code someone already replaced (real incident: a builder missed
# merged F9a/F9b build-plan updates because their clone was stale).
#
# Fail open always: no git repo, no network, no upstream configured, missing
# jq — every one of these exits 0 silent. A sync check that blocks session
# start on a flaky network is worse than no check.
set -uo pipefail

command -v git >/dev/null 2>&1 || exit 0
command -v jq >/dev/null 2>&1 || exit 0

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$PROJECT_DIR" 2>/dev/null || exit 0

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
if [ -z "$branch" ] || [ "$branch" = "HEAD" ]; then
  exit 0
fi

upstream="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)"
if [ -z "$upstream" ]; then
  git rev-parse --verify origin/main >/dev/null 2>&1 && upstream="origin/main"
fi
[ -z "$upstream" ] && exit 0

remote="${upstream%%/*}"
git remote get-url "$remote" >/dev/null 2>&1 || exit 0

# Quiet fetch, capped so a dead network doesn't hang session start beyond the
# hook's own harness-enforced timeout (set in hooks.json).
git fetch --quiet "$remote" >/dev/null 2>&1 || exit 0

behind="$(git rev-list --count "HEAD..$upstream" 2>/dev/null)"
case "$behind" in
  ''|*[!0-9]*) exit 0 ;;
esac
[ "$behind" -eq 0 ] && exit 0

recent="$(git log --oneline "HEAD..$upstream" 2>/dev/null | head -5)"
dirty=""
git diff --quiet 2>/dev/null && git diff --cached --quiet 2>/dev/null || dirty=" Working tree has uncommitted changes — stash or commit before pulling/rebasing."

CTX="GIT SYNC CHECK: local '$branch' is $behind commit(s) behind '$upstream'. Recent commits you don't have yet:
$recent

Tell the operator before doing any build work off this checkout — a stale clone silently misses merged plan/spec updates. Suggested fix: on '$branch' tracking '$upstream' directly, 'git pull'; on a feature branch, 'git fetch' (already done) then 'git rebase $upstream' (or merge if rebase gets messy).$dirty"

jq -n --arg ctx "$CTX" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$ctx}}'
exit 0
