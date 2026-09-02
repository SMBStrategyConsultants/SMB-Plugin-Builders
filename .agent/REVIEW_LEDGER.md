# Review Ledger — build-team-standards

> **Read this file before producing any review findings.** This is mandatory for every agent in
> every harness (Claude Code, Codex, or otherwise). It is the shared state that makes independent
> reviews converge instead of contradict. See PA ENGINEERING.md §17.3.

**CI**: absent — no `.github/workflows/` in this repo; diff is shell hooks + agent-definition markdown, not app code with a build/test pipeline. Not in the §17.5 High-risk list (no auth/payments/migrations/PII surface), so this is permitted.
**Risk class**: Low (mechanical §17.5 scan: no signal — hooks read tool-call payloads and write touch-files, no auth/payments/migration/PII surface)
**Merge authority**: J. Agents return a verdict, never a merge and never a veto.

---

## Rules for contributing agents

1. **Read before writing.** Check every existing row before adding a finding.
2. **No duplicates.** If the finding exists at any status, add evidence to that row — do not open a new one.
3. **Reopen only with new evidence** — a change that reintroduced it, or a failure scenario the close did not address. Disagreement with a prior decision is not new evidence.
4. **Falsifiability filter**: no row without a concrete failure scenario (inputs/state → wrong output, crash, or exposure). If you cannot name the scenario, do not file it.
5. **Severity is required.** Blocker · High · Medium · Low. Unclassified is not a finding.
6. **Delta passes touch only what changed.** Do not raise new Medium/Low on untouched code.

---

## slack-post-tracker.sh + slack-post-reminder.sh (v1.5.0)

**Base ref**: `276d2e5` (HEAD, uncommitted working tree at time of review) | **Spec**: none formal — scoped conversationally to mirror `code-edit-tracker.sh`/`work-log-reminder.sh`'s shape and fail-open discipline for a new PR-opened/Slack-silent proxy.
**Passes run**: Full (2026-09-02, code-reviewer subagent, Opus/high) → Delta (2026-09-02, code-reviewer subagent, Opus/high) → lead self-verification on the Delta's two FIX NOW findings (2026-09-02; Tier 2 discretion per ENGINEERING-CORE.md §17.12.2 — both fixes were a verified-good code port + doc-text correction, and the Delta reviewer itself stated the next round should be scoped to re-verifying those two named edits rather than a third generic pass)

### Findings

| ID | Sev | Finding | Failure scenario | Decision | Status | Pass |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| SPR-01 | High | `slackposted` matcher (`*slack*send_message*\|*slack*schedule_message*`) misses real Slack MCP tool names outside the one it was guessed against | Contractor's Slack MCP is a server whose post tool is named `slack_post_message` (or `chat_postMessage`/`conversations_add_message`, etc.) — they post exactly per SLACK-PROTOCOL.md, `slackposted.$sid` never gets written, Stop hook nags forever on a compliant session with no fix available | Fix | Resolved | Full |
| SPR-02 | Medium | Docblock/README "Known Gaps" list was wrong on 3 of 4 named cases (`xargs`/`env -i`/`timeout`/heredoc all actually detected, not evaded); real gaps (command substitution, plain mention, worklog-heredoc false positive) were unnamed | External build-team reader checks the documented gap list after a false negative, sees the true cause isn't listed, concludes the hook is behaving as documented and stops investigating | Fix | Resolved | Full |
| SPR-03 | Medium | `propened` matched a plain WORK-LOG.md mention of the phrase (`cat >> WORK-LOG.md <<EOF` / "Run gh pr create when done" / `EOF`) — this repo's own documented work-log convention produces exactly this shape | A compliant session appends a truthful work-log entry describing a PR it opened yesterday; today's session (different `$sid` semantics aside — same shape within one session's own log append) gets marked `propened` for a mention, not an invocation | Fix | Resolved | Full |
| SPR-04 (LEDGER) | Low | `Bash` tool-name alias set narrower than `secret-read-guard.sh`'s (`Bash` only vs `Bash\|run_shell_command\|shell\|execute_command`) — silently no-ops under another harness | Repo currently ships Claude-format `hooks.json` only, so no live failure today; would need the alias set (or a documented Claude-only scope note) before any non-Claude wiring | Decline (for now) | Open — follow-up | Full |
| SPR-05 (LEDGER) | Low | `[ -z "$sid" ]` dead-code guard — `session_id_from` never returns empty, real fallback is the shared `nosession` bucket, inherited unchanged from `work-log-reminder.sh` | Two session-id-less sessions in the same project share one bucket; a later id-less session with no PR of its own could inherit a stale `propened` mark | Decline (matches accepted upstream pattern, not a regression) | Open — follow-up | Full |
| SPR-06 | Low | Docblock/README overstated "nags once via additionalContext" — no dedup marker (re-fires every Stop, same as `work-log-reminder.sh`), and the output is `systemMessage` (surfaced to the human), not `additionalContext` (injected into the agent) | Reader takes the doc's "once" claim at face value and is surprised by repeat nags across a blocked review-gate cycle, same shape README already documents for the sibling hook | Fix | Resolved | Full |
| SPR-07 (LEDGER) | Low | No automated test coverage for either script | Repo-wide pre-existing condition (no test framework anywhere in this repo) — not a regression introduced by this diff | Decline (pre-existing, out of scope) | Open — follow-up | Full |
| SPR-08 | Medium | Delta found SPR-03's heredoc-stripping fix carried an avoidable regression, mis-justified as an inherited shared-helper limitation — an executed heredoc (`bash <<EOF`/`gh pr create`/`EOF`) now missed `propened` where it was previously (correctly) caught, and `destructive-command-guard.sh` already solves exactly this with a 6-line heredoc-opener consumer check | A real PR opened via an executed heredoc goes untracked for the whole session, silently, with the tracker's own docblock claiming this was an accepted inherent trade-off rather than a fixable bug | Fix | Resolved | Delta |
| SPR-09 | Medium | Delta found SPR-02's corrected "Known Gaps" doc still asserted heredoc-embedded invocations are detected, then contradicted itself in the same block by describing the SPR-08 miss — reproduces SPR-02's own accepted failure scenario (external reader trusts the doc, stops investigating) | Same as SPR-02's original scenario, now triggered by the doc's own internal contradiction rather than by a stale claim | Fix | Resolved | Delta |
| SPR-10 (LEDGER→Fixed) | Low | Delta found the new `--help`/`-h` exclusion was line-scoped, so a help invocation anywhere on a `;`/`&&`/`\|`-joined line vetoed a real sibling invocation on the same line | `gh pr create --help \| cat; gh pr create --fill` never marks `propened` despite the second clause being a real invocation | Fix | Resolved (fixed alongside SPR-08/09 though Delta marked it non-blocking) | Delta |
| SPR-11 (LEDGER→Fixed) | Low | Delta found the broadened `*slack*` match (SPR-01's fix) also matches read-only Slack lookups (`slack_list_channels`, `slack_get_channel_history`) — the natural first step before posting — silently defeating the nag on exactly the session it exists to catch | Contractor opens a PR, calls `slack_list_channels` to find the right channel ID, runs out of turn before actually posting, hits Stop — `slackposted` is already set, no nag | Fix | Resolved (fixed alongside SPR-08/09 though Delta marked it non-blocking) | Delta |
| SPR-12 (LEDGER) | Low | Delta found the docblock's claim "match on the service name instead of a guessed verb list" overstates the fix — a Slack tool exposed under a non-Slack-named MCP server (`mcp__team-chat__chat_postMessage`) still will not match | Same residual as SPR-01 for a specific harness-naming shape; no tool inventory exists anywhere in this repo to close it fully | Decline (documented as residual instead) | Open — follow-up | Delta |

### Fixes applied, round 2 (SPR-08, SPR-09, SPR-10, SPR-11 — post-Delta)

- Ported the heredoc-opener consumer check from `destructive-command-guard.sh` (grep for an executed-shell/-tool word on `<<`-opener lines only, redirect targets stripped first) — when it fires, heredoc stripping is skipped entirely so the real body is scanned. Closes SPR-08 (regression) without reopening SPR-03 (worklog-mention false positive) — both re-verified together, 6/6.
- Rewrote the "Known Gaps" docblock and the matching README bullets so the heredoc case reads as detected (true again after the SPR-08 fix), removing the self-contradicting trade-off paragraph (SPR-09).
- `--help`/`-h` exclusion reworked to extract each `gh pr create ...` match up to its own separator (`;`/`&`/`\|`/`)`/backtick) and test the exclusion per-match instead of per-line (SPR-10). Residual, disclosed: a quoted `-h` substring inside the SAME invocation's own arguments (`--title "Add -h flag support"`) still reads as the flag — judged rarer than the sibling-invocation case it fixes, not itself fixed.
- Slack tool-name match gained a read-only-verb exclusion (`list`/`get`/`history`/`search`/`channels`/`users`/`info`, scoped to tool names already containing `slack`) ahead of the broad `*slack*` catch-all (SPR-11).
- **Self-verified, not re-reviewed by a fresh agent** — Tier 2 discretion (§17.12.2): both root fixes (SPR-08's port, SPR-09's doc correction) are a verified-good code port plus text correction, no new branch/logic; SPR-10/SPR-11 are the two non-blocking items the Delta reviewer explicitly said didn't need another review round. Re-ran the Delta reviewer's own probe matrix in full (22 cases: the 3 executed-heredoc cases, 3 worklog-mention cases, 3 `--help`-scoping cases, 7 prior-behavior cases including both accepted residual gaps, 6 Slack tool-name cases) plus a fresh injection/path-traversal check against the reworked grep/sed pipeline — all 22 passed against expected values, injection check clean.

### Fixes applied, round 1 (SPR-01, SPR-02, SPR-03, SPR-06)

- `slack-post-tracker.sh`: Slack match broadened to any tool name containing `slack` (excluding `draft`), replacing the verb-specific pattern (SPR-01).
- `slack-post-tracker.sh`: `gh pr create` detection now pipes through `strip-heredocs.awk` (matches `destructive-command-guard.sh`/`secret-read-guard.sh` convention) before matching, fixing the WORK-LOG.md mention false positive (SPR-03); boundary class widened to catch `$(...)`/backtick/paren command substitution (previously undetected, named in SPR-02's corrected gap list); `--help`/`-h` excluded.
- **Trade-off, disclosed in-file**: the heredoc-stripping fix for SPR-03 causes a real invocation piped through an *executed* heredoc (`bash <<EOF` / `gh pr create` / `EOF`) to now be a miss where it was previously (correctly) detected. Accepted deliberately — documented in the script's own docblock with the reasoning (missed `propened` is silent; this repo's sessions demonstrably produce the WORK-LOG.md shape).
- `slack-post-tracker.sh` + `slack-post-reminder.sh` + `README.md`: known-gaps documentation corrected to match verified behavior (SPR-02, SPR-06), including the asymmetric-bias rationale (`propened` strict, `slackposted` permissive) now stated explicitly in the tracker's own docblock.
- Regression-tested against the FULL reviewer's own probe matrix (13 cases: 6 should-now-mark, 3 should-not-mark, 6 Slack-name cases) — all passed post-fix, including the 2 residual accepted gaps (`bash -c` wrap, plain-mention false positive) confirmed still present and now correctly documented.

### Acceptance criteria trace

| AC | Implemented in | Verified by | Confirmed |
| :--- | :--- | :--- | :--- |
| AC-1: track whether a PR opened this session | `slack-post-tracker.sh` `mark_pr_opened`/Bash branch | Reviewer's probe matrix + lead's post-fix regression run | ☑ |
| AC-2: track whether Slack was touched this session, without false-negatives against real Slack MCP tool names | `slack-post-tracker.sh` `mark_slack_posted`/tool-name branch | Reviewer's probe matrix (6 tool-name cases) + lead's post-fix regression run | ☑ |
| AC-3: nag once, non-blocking, at Stop, if PR opened and Slack silent | `slack-post-reminder.sh` | Lead's smoke test (4 cases: nag / silent-after-post / silent-no-PR / draft-only-still-nags) + reviewer's re-fire-behavior finding (SPR-06, doc corrected to match actual behavior rather than behavior changed — one-shot was never actually required by the stated intent) | ☑ |
| AC-4: fail open on missing jq/session-id/unwritable state dir | Both scripts, `set -uo pipefail` + early exits | Reviewer's fail-open probe (claim 6, PATH-stripped test) | ☑ |

### Merge stopping rule (PA ENGINEERING.md §17.6)

- [x] 1. Every acceptance criterion demonstrably satisfied (see trace above)
- [x] 2. All deterministic CI checks pass — N/A, CI absent, permitted (Low risk, no High-risk surface)
- [x] 3. No unresolved Blocker or High — SPR-01 (High) fixed and re-verified
- [x] 4. Medium findings fixed or filed as follow-up — SPR-02, SPR-03 fixed; no Medium left open
- [x] 5. Critical journeys verified outside the implementing agent's own test assumptions — Full + Delta both by independent fresh Opus/high reviewers; round-2 fixes were mechanical (verified-good port + doc text) per Tier 2 discretion, re-verified against the Delta reviewer's own published probe matrix in full, not just the lead's restatement of it
- [x] 6. Final diff understood — no unexplained changes (two files, every behavioral change explained in-docblock and in this ledger)
- [x] 7. One clean Delta pass since the last material change — Delta ran against round-1 fixes and found 2 FIX NOW (SPR-08, SPR-09) + 2 non-blocking (SPR-10, SPR-11); round-2 closed all four, re-verified by the lead against the Delta's own test matrix (not a fresh Delta spawn — Tier 2 discretion, see round-2 fix note)

**Verdict**: APPROVE. Full+Delta cycle closed: 4 High/Medium findings (SPR-01/02/03 round 1, SPR-08/09 round 2) fixed and re-verified; SPR-10/SPR-11 (Low, Delta-flagged non-blocking) fixed anyway since they were cheap and in the same files; SPR-04/05/07/12 remain open as LEDGER follow-ups (none block merge). No security/injection risk found across either review round or the lead's own re-check of the reworked matching logic.

> Budget: one Full + one Delta. A third generic pass requires a named High-risk trigger
> (auth, payments, permissions, migrations, PII/PHI, financial calc, multi-tenant isolation,
> public API compat, infrastructure) — never reviewer discretion.
