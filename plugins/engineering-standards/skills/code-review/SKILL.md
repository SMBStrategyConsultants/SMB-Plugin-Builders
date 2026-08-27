---
name: code-review
description: Review a non-empty diff against repository standards and its originating spec, keeping the two result sets separate. Enforces the PR Review Convergence Protocol — ledger-first, severity-classified, falsifiable findings with a defined stopping rule.
keywords: [code review, review diff, review branch, review since, pr review, verify code, delta review, review ledger]
allowed-tools: Read, Glob, Grep, Bash
---

# Code Review

Review a diff against a fixed comparison point on two independent axes. This skill coordinates the existing `code-review-checklist`; it does not replace security or automated validation.

**Governing protocol**: [ENGINEERING-CORE.md §17 — PR Review Convergence](../../ENGINEERING-CORE.md). That file is authoritative; this skill executes it.

The purpose of the rules below is convergence. An AI reviewer can always generate another possibility — that capability is not defect evidence. Stop when the PR meets its acceptance criteria and carries no unresolved material risk, not when no agent can find anything else.

## 0. Read the Ledger First — MANDATORY

Before producing any finding, read `.agent/REVIEW_LEDGER.md` in the project root.

- If it exists: every existing row is binding context. Do not duplicate a finding at any status. Reopen a closed finding **only with new evidence** — a change that reintroduced it, or a failure scenario the close did not address. Disagreement with a prior decision is not new evidence.
- If it is missing and this PR has already had one agent review, create it from the workspace template before reviewing.
- Note whether the header records `CI: absent`. If so, weight deterministic-class defects (types, lint-catchable errors, broken builds) higher — nothing else caught them.

Skipping this step is what causes each agent to review as if from zero. It is the single largest source of review loops.

## 1. Pin the Diff

Require a base ref (commit, branch, tag, merge-base, or explicit range). Confirm it resolves and that the diff is non-empty before reviewing. Default to `git diff <base>...HEAD` only when the user has supplied `<base>`.

**Declare the mode**:

| Mode | When | Scope |
| :--- | :--- | :--- |
| **Full** | First review of a complete implementation · architecture materially changed · major logic rewritten · new requirement added | Whole diff against the base ref |
| **Delta** | After review fixes | Only changes since the last review. Verify each accepted finding was resolved and no regression was introduced. Do **not** reopen accepted areas or raise new Medium/Low on untouched code. |

Budget is **one Full + one Delta**. A third generic pass requires a named high-risk trigger (auth, payments, permissions, migrations, PII/PHI, financial calculations, multi-tenant isolation, public API compatibility, infrastructure) — never reviewer discretion. Past two meaningful cycles, generic review yields speculation faster than defects.

## 2. Locate Evidence

- **Standards:** repository instructions, `AGENTS.md`, coding standards, CONTRIBUTING files, and `code-review-checklist`.
- **Spec:** for Tier 2 work, the project `.agent/SPEC.md` is authoritative; otherwise use a linked issue/PRD/spec, commit references, or a user-supplied path. If none exists, explicitly report that the Spec axis was unavailable rather than inventing requirements.
- **Anchor set:** the tracked edited-file list for the session (`EDITS`, from `code-edit-tracker.sh`, part of this same `engineering-standards` plugin) is the boundary a reviewer subagent traces "follow the consumer mechanism" from — expand outward only along a cited grep/import trail from one of those files, never a free roam of the workspace. Missing this list is an incomplete brief.

## 3. Review Separately

Run these passes in order. Ordering matters — spec compliance first, because a correct implementation of the wrong requirement is still wrong.

| Pass | Axis | Checks |
| :--- | :--- | :--- |
| **A** | Spec compliance | Every acceptance criterion met? Anything missing? Behavior introduced outside the spec? Any declared non-goal accidentally implemented? |
| **B** | Correctness | Logic defects, unhandled failure states, boundary conditions, concurrency/state/lifecycle issues, behavior on invalid or partial data |
| **C** | Security & data integrity | Authn/authz, permission boundaries, input validation, injection, secret exposure, data leakage, destructive operations, tenant isolation, migration safety |
| **D** | Maintainability | Unnecessary complexity, duplicated logic, misleading names, tight coupling, code that will be hard to change safely |
| **E** | Test sufficiency | Are important behaviors tested? Do tests assert outcomes rather than implementation details? Negative cases? **Could the implementation be broken while the tests still pass?** |

### Standards

Check correctness, maintainability, security, tests, performance, and documented repository rules. Treat code smells as judgment calls, not hard violations, unless a repository rule makes them one. Route security-sensitive changes through `vulnerability-scanner`.

### Spec

Check for missing requirements, incorrect behavior, and scope creep using direct evidence from the originating artifact.

For Tier 2, also verify that the diff traces to the locked entities, flow, mutations, and acceptance criteria in `.agent/SPEC.md`; flag unexplained scope changes, missing amendments, or behavior that introduces new state/flows without a spec update.

**Ontology conformance**: if `SPEC.md` has an `## Ontology` section, it is the naming authority. A finding proposing different naming or a new entity is admissible only if it cites an ontology conflict. Otherwise it is a spec-amendment request — file it Low, not as a code finding.

## 4. Filter Before Writing

### Falsifiability test — every finding must pass

A finding is admissible **only** if it names a concrete failure scenario: specific inputs or state → specific wrong output, crash, or exposure. If you cannot name the scenario, do not write it down.

- ✅ *"`ingestChunk()` omits `hash`, so re-uploading the same PDF inserts duplicate rows and double-weights that content in retrieval."*
- ❌ *"Consider adding more validation here."*

In Claude Code, report via the built-in `ReportFindings` tool — it makes `failure_scenario` a required field, which enforces this structurally.

### Do not report

- Purely stylistic preferences
- Optional refactors with no concrete risk
- Speculative edge cases with no plausible failure scenario
- Anything already settled in the ledger, absent new evidence

### Severity — required on every finding

| Severity | Merge effect |
| :--- | :--- |
| **Blocker** | Must fix before merge — security hole, data-loss path, unimplemented acceptance criterion, broken migration, critical flow down |
| **High** | Fix before merge unless the risk is explicitly accepted and recorded in the ledger |
| **Medium** | Fix if cheap, else file as follow-up with a ticket reference |
| **Low** | Never blocks |

Unclassified findings are not findings. Without severity, every observation reads as equally urgent — which is what produces endless back-and-forth.

## 5. Report

Keep `## Standards` and `## Spec` findings separate. Every finding includes severity, location, evidence, a concrete failure scenario, impact, and the **smallest safe fix**. State a clean pass explicitly.

**Write findings to `.agent/REVIEW_LEDGER.md`** — new rows for new findings, status updates for resolved ones. The ledger is the durable artifact; the chat response is a view of it.

**End with exactly one verdict**:

- `APPROVE` — acceptance criteria met, CI green, no Blocker or High outstanding
- `APPROVE WITH FOLLOW-UP` — as above, with Medium findings recorded as follow-up work
- `REQUEST CHANGES` — one or more Blocker or High findings remain

A verdict is a recommendation. **Merge authority belongs to the user, not this skill.** Never merge, never claim a veto, and never treat your own prior output as clearance.

### Stopping rule

Merge-eligible when all seven hold ([§17.6](../../ENGINEERING-CORE.md)): acceptance criteria demonstrably satisfied · CI green · no unresolved Blocker/High · Mediums fixed or filed · critical journeys verified outside the implementing agent's own test assumptions · final diff understood · **one clean Delta pass since the last material change**.

If the Delta comes back clean, **stop**. Do not open a new line of inquiry.

Do not commit, amend, publish reviews, or spawn reviewers unless the user requests it. If the user explicitly requests a release and the required validation is green, hand the reviewed diff to `deployment-procedures`. Review approval never authorizes a deployment by itself.

## Related Skills

| When | Use |
|---|---|
| Baseline checklist | `code-review-checklist` |
| Static validation | `lint-and-validate` |
| Security-sensitive diff | `vulnerability-scanner` |
| Requirements are unclear | `architecture` or `to-spec` |
| A defect is found | `diagnosing-bugs` |
| Explicit release request after a clean review | `deployment-procedures` |

## Attribution

Adapted from Matt Pocock’s `code-review` skill. Source: https://github.com/mattpocock/skills. License: [`licenses/matt-pocock-skills-MIT.txt`](../licenses/matt-pocock-skills-MIT.txt).
