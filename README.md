# build-team-standards

Claude Code plugin marketplace for SMB Strategy Consultants' external build teams (Spot2Bee and whatever comes after it). One plugin today: **`engineering-standards`**.

## What this is, and why it's a separate marketplace

The engineering-standards package for build teams originally shipped as a static zip (`builder-team-core.zip`, distributed via a Google Drive folder) — `CLAUDE.md` + skills + docs, unzipped into the workspace root above each cloned repo. That still works and still ships that way for the parts that are pure workspace-root overlay (`CLAUDE.md`, `ENGINEERING-CORE.md`, `ENGINEERING-WORKSPACE.md`, `REVIEW.md`, `WORK-LOG-PROTOCOL.md`, `CONTEXT-WINDOW-CONTROL.md`, `documentation-templates/`).

What the zip **cannot** carry is enforcement — hooks. `REVIEW.md` and `CONTEXT-WINDOW-CONTROL.md` were advisory prose only: nothing stopped a session from ending with unreviewed code, and nothing nagged before the context window filled. This marketplace exists to ship that enforcement, auto-updating, without asking every build-team member to manually re-download and re-unzip a file every time a hook changes.

It is **not** part of `smb-skills-marketplace` (the other SMB Strategy Consultants marketplace) on purpose: that marketplace's own README explicitly forbids hooks, because it also serves Claude chat/Desktop/Cowork, where hooks silently do nothing. This one is Code-only, and says so.

## Installing

Add this marketplace and enable the plugin the same way you'd enable any Claude Code plugin — via `extraKnownMarketplaces` and `enabledPlugins` in your `.claude/settings.json`, or via the in-app plugin browser once this repo has a remote.

**Add `.agent/tmp/` to your project's own `.gitignore`.** The review-gate and context-nag hooks write session state (an audit log of review clears/waivers, per-session edit tracking) to `<your project>/.agent/tmp/code-review/` — inside the repo you're building, not inside this plugin. Without an ignore rule, `git add -A` picks it up and reviewer verdict text/waiver reasons end up committed.

## What `engineering-standards` ships

- **Skills** (12 dirs, mirrored from `builder-team-core/skills/`): karpathy-coding, clean-code, code-review, code-review-checklist, testing-patterns, tdd-workflow, systematic-debugging, python-patterns, nodejs-best-practices, database-design, api-patterns, architecture.
- **Hooks**:
  - `code-edit-tracker.sh` + `code-review-gate.sh` (paired) — turns `REVIEW.md`/`ENGINEERING-CORE.md §17`'s review protocol into an enforced Stop-hook gate. Ending a turn with unreviewed code blocks until the gate is cleared (reviewed, waived with a reason, or risk explicitly accepted) — every clear is durably logged.
  - `code-review-reminder.sh` — fires on a review-shaped prompt, restates the §17.9 contract (fresh agent, minimal unbiased brief, edited-file anchor set).
  - `secret-read-guard.sh` — denies shell commands that would print secret *values* (not names) to the transcript.
  - `context-gate.py` — nags before the harness auto-compacts, so open state gets noted first. Same mechanism as `CONTEXT-WINDOW-CONTROL.md` describes, now enforced instead of just documented.
- **Documentation templates**, mirrored from `builder-team-core/documentation-templates/`.

## Versioning

Bump `plugins/engineering-standards/.claude-plugin/plugin.json`'s `version` (and the matching entry in `.claude-plugin/marketplace.json`) on any change to what ships. Installed clients pick up the new version on their next plugin sync.
