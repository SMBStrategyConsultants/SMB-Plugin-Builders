# Review Ledger — {Project Name}

> **Read this file before producing any review findings.** This is mandatory for every agent in
> every harness (Claude Code, Codex, or otherwise). It is the shared state that makes independent
> reviews converge instead of contradict. See PA ENGINEERING.md §17.3.

**CI**: present | absent — {if absent, state why; not permitted for auth/payments/migrations/PII diffs}
**Risk class**: Low | Standard | High
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

## PR #{N} — {title}

**Base ref**: `{commit-or-branch}` | **Spec**: `.agent/SPEC.md`
**Passes run**: Full ({date}, {agent}) → Delta ({date}, {agent})

### Findings

| ID | Sev | Finding | Failure scenario | Decision | Status | Pass |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| R-01 | | | | Fix \| Follow-up \| Decline \| Accept-risk | Open \| Resolved \| Closed | Full |

### Acceptance criteria trace

| AC | Implemented in | Verified by | Confirmed |
| :--- | :--- | :--- | :--- |
| AC-1 | | | ☐ |

### Merge stopping rule (PA ENGINEERING.md §17.6)

- [ ] 1. Every acceptance criterion demonstrably satisfied
- [ ] 2. All deterministic CI checks pass
- [ ] 3. No unresolved Blocker or High
- [ ] 4. Medium findings fixed or filed as follow-up with ticket ref
- [ ] 5. Critical journeys verified outside the implementing agent's own test assumptions
- [ ] 6. Final diff understood — no unexplained changes
- [ ] 7. One clean Delta pass since the last material change

**Verdict**: APPROVE | APPROVE WITH FOLLOW-UP | REQUEST CHANGES

> Budget: one Full + one Delta. A third generic pass requires a named High-risk trigger
> (auth, payments, permissions, migrations, PII/PHI, financial calc, multi-tenant isolation,
> public API compat, infrastructure) — never reviewer discretion.
