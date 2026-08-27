---
name: systematic-debugging
description: 4-phase systematic debugging methodology with root cause analysis and evidence-based verification. Use when debugging complex issues.
allowed-tools: Read, Glob, Grep
---

# Systematic Debugging

> Source: obra/superpowers

## Overview
This skill provides a structured approach to debugging that prevents random guessing and ensures problems are properly understood before solving.

## 4-Phase Debugging Process

### Phase 1: Reproduce
Before fixing, reliably reproduce the issue.

```markdown
## Reproduction Steps
1. [Exact step to reproduce]
2. [Next step]
3. [Expected vs actual result]

## Reproduction Rate
- [ ] Always (100%)
- [ ] Often (50-90%)
- [ ] Sometimes (10-50%)
- [ ] Rare (<10%)
```

### Phase 2: Isolate
Narrow down the source.

```markdown
## Isolation Questions
- When did this start happening?
- What changed recently?
- Does it happen in all environments?
- Can we reproduce with minimal code?
- What's the smallest change that triggers it?
```

### Phase 3: Understand
Find the root cause, not just symptoms.

```markdown
## Root Cause Analysis
### The 5 Whys
1. Why: [First observation]
2. Why: [Deeper reason]
3. Why: [Still deeper]
4. Why: [Getting closer]
5. Why: [Root cause]
```

### Phase 4: Fix & Verify
Fix and verify it's truly fixed.

```markdown
## Fix Verification
- [ ] Bug no longer reproduces
- [ ] Related functionality still works
- [ ] No new issues introduced
- [ ] Test added to prevent regression
```

## Debugging Checklist

```markdown
## Before Starting
- [ ] Can reproduce consistently
- [ ] Have minimal reproduction case
- [ ] Understand expected behavior

## During Investigation
- [ ] Check recent changes (git log)
- [ ] Check logs for errors
- [ ] Add logging if needed
- [ ] Use debugger/breakpoints

## After Fix
- [ ] Root cause documented
- [ ] Fix verified
- [ ] Regression test added
- [ ] Similar code checked
```

## Common Debugging Commands

```bash
# Recent changes
git log --oneline -20
git diff HEAD~5

# Search for pattern
grep -r "errorPattern" --include="*.ts"

# Check logs
pm2 logs app-name --err --lines 100
```

## Anti-Patterns

❌ **Random changes** - "Maybe if I change this..."
❌ **Ignoring evidence** - "That can't be the cause"
❌ **Assuming** - "It must be X" without proof
❌ **Not reproducing first** - Fixing blindly
❌ **Stopping at symptoms** - Not finding root cause

## 🧠 Hardened Guardrails: Silent Failure Detection (July 2026)

### The Silent Failure Problem
Silent failures are the dominant risk class in complex systems — a bug that produces no error signal, no exception, no warning. The absence of an error signal carries zero information about correctness.

**Common patterns (July 2026):**
- **Swallowed exceptions**: Error handler catches an exception, logs nothing, returns empty results → caller sees `[]` and continues as normal
- **Absent error signals**: Configuration is missing but has a fallback default (`HUME_WEBHOOK_SECRET || 'default-secret'`) → "works" whether correctly configured or not
- **Partial constraints**: Unique index is `PARTIAL` (e.g., `WHERE hash IS NOT NULL`) → NULL values never collide, dedup "silently doesn't happen"
- **Inert policies**: Security policy is defined and enabled but produces no-op due to missing grants → code assumes safety, policy silently doesn't enforce
- **Type coercion in comparisons**: Last-one-wins resolution with duplicate keys in env vars → scripts silently get the wrong account's credentials
- **Absent observability**: No logs, no test failures, no UI indicator → system quietly degraded until user-visible impact discovered weeks later

### Detection Strategies

**1. Query-and-verify, never assume-and-log**
When reporting "I checked for X and didn't find it", be specific about what patterns were checked:
- ❌ "No secrets in the code" (implies complete scan)
- ✅ "No matches for patterns: `sk-*`, `ghp_*`, `AKIA*`, `xox*`, `pit-*`, `ntn_*`" (transparent about limitations)

A negative result from a partial pattern scan overstates confidence. Explicitly list the patterns checked so gaps are auditable.

**2. Test acceptance criteria, not implementation**
For any fix claiming to solve a problem:
- Don't assume logs prove the fix works
- Don't assume a test suite passing means nothing broke
- Verify the exact acceptance criterion the fix was supposed to satisfy
  - "Does a user calling `/api/ingest` with a PDF produce a chunk?" (acceptance)
  - Not: "Did the POST succeed with a 200?" (implementation detail)

**3. Silent failures hide at every layer**
Absence of failure at one layer does not mean the system works end-to-end:
- Local dev server works but production key is wrong → "works locally"
- Unit tests pass but integration CI doesn't exist → red suite never blocks
- Function returns `[]` on error but caller doesn't check → downstream code proceeds on empty data, looks normal until user-visible wrong answer is spotted
- Table RLS policy is correctly defined but grants are missing → code reasoning assumes safety, policy is inert

**If you cannot see the failure in production, you do not know it is not happening.**

### Verification Protocol
When investigating a complex system issue:
1. **Distinguish observation from inference**: What did you actually test vs. what are you inferring?
2. **Isolate variable sets**: Two observers seeing different results may both be correct — they may be testing different entry points or environments
3. **Instrument for observability before declaring "fixed"**: Add visibility into the exact path the fix claims to take (logs, UI indicators, count rows, etc.) before closing

Revisit trigger: Whenever a "fixed" system issue is later discovered to have continued undetected in production.
