# SPEC: {Project or Feature Name}

**Created**: {YYYY-MM-DD} | **Tier**: 2 | **Status**: Locked
**Risk class**: Low | Standard | High  ← sets the review budget (PA ENGINEERING.md §17.5)

> **Lock instruction**: Follow this exact spec. Do not introduce new entities, state, or flows
> without an explicit amendment recorded in §6 below.

---

## 1. Problem

{What are we solving? One paragraph. Why it matters before how it works.}

## 2. Ontology

> Canonical naming authority. Code, tests, tickets, and review findings use these exact names.
> A rename is an amendment (§6), never an inline refactor. See PA ENGINEERING.md §16.

### {EntityName}
- **Purpose**: {one line — what it represents in the domain}
- **Key fields**: `id: uuid`, `status: JobStatus`, `{field}: {type}`
- **Relationships**: belongs to `{Entity}` · has many `{Entity}`
- **States**: `pending → processing → complete | failed`
- **Invariants**:
  - {What must always be true. These become test assertions and review checks.}

### {NextEntity}
- **Purpose**:
- **Key fields**:
- **Relationships**:
- **States**: {omit if not stateful}
- **Invariants**:

## 3. Flow

`{A} → {B} → {C} → {D}`

**Mutations per step**:
| Step | Creates | Updates | Triggers / Emits |
| :--- | :--- | :--- | :--- |
| {A} | | | |
| {B} | | | |

## 4. Acceptance Criteria

> Observable definitions of correct completion. The reviewer checks against these, not against
> what it imagines the system should do. Each one must be independently verifiable.

| ID | Criterion | Implemented in | Verified by |
| :--- | :--- | :--- | :--- |
| AC-1 | {Given X, when Y, then Z} | {file:line — filled at implementation} | {test name / manual step} |
| AC-2 | | | |

## 5. Out of Scope

> Explicit non-goals. A reviewer flagging a non-goal as "missing" is filing an invalid finding.

- {Non-goal}

## 6. Amendments

| Date | Change | Reason | Files touched |
| :--- | :--- | :--- | :--- |
| | | | |

## 7. Open Questions & Assumptions

- **[ASSUMPTION]** {Label inferences explicitly — never state an assumption as settled fact.}
- **[OPEN]** {Unresolved decision that materially affects scope, safety, or user behavior.}

---

> **Post-ship**: on first production release, freeze this file and archive it as
> `.agent/adrs/ADR-{YYYY-MM-DD}-{slug}.md`. Code becomes the sole source of truth.
> Do not maintain a live spec beside shipped code (PA ENGINEERING.md §6, §15).
