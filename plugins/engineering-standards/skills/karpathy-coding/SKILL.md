---
name: karpathy-coding
description: Pre-implementation coding discipline derived from Andrej Karpathy's observations on LLM coding pitfalls. MANDATORY for all coding agents.
keywords: [karpathy, coding discipline, technical implementation]
applies_to:
  - frontend-specialist
  - backend-specialist
  - mobile-developer
  - game-developer
  - debugger
---

# Karpathy Coding Protocol

> **Authority**: This skill is P1 — it overrides default coding behavior for ALL agents.
> Run these 4 checks before writing or modifying any code.

**Tradeoff:** These guidelines bias toward caution over speed. For truly trivial tasks (e.g., single-character typo fix), use judgment. For anything non-trivial, this protocol is mandatory.

---

## ✅ Check 1: Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before writing a single line of code:

- **State assumptions explicitly.** If you are uncertain about scope, intent, or behavior — ASK rather than guess.
- **If multiple interpretations exist, present them.** Do NOT silently pick one. Show the options and let J decide.
- **If a simpler approach exists, say so.** Push back when the request seems overcomplicated for the goal.
- **If something is unclear, STOP.** Name exactly what is confusing. Ask for clarification.

> ❌ WRONG: "I'll assume you want X and implement it."
> ✅ CORRECT: "I see two ways to do this: A or B. A is simpler if [assumption]. Which do you want?"

---

## ✅ Check 2: Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was explicitly asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50 — rewrite it.

**Self-check before submitting:** *"Would a senior engineer say this is overcomplicated?"*
If yes → simplify before responding.

---

## ✅ Check 3: Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Do NOT "improve" adjacent code, comments, or formatting unless explicitly asked.
- Do NOT refactor things that aren't broken.
- Match the existing code style, even if you'd personally do it differently.
- If you notice unrelated dead code or obvious tech debt — **mention it**, but don't delete it unless it's in the direct path of your change.

**Exception:** Minor, obvious tech-debt cleanup is permitted if it is immediately adjacent to your targeted change and does not change behavior.

When your changes create orphans:
- Remove imports, variables, or functions that **YOUR changes** made unused.
- Do NOT remove pre-existing dead code unless J asks.

**Self-check:** *Every changed line should trace directly to J's request.*

---

## ✅ Check 4: Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform imperative tasks into verifiable goals before coding:

| Instead of... | Write it as... |
| :--- | :--- |
| "Add validation" | "Write tests for invalid inputs, then make them pass." |
| "Fix the bug" | "Write a test that reproduces it, then make it pass." |
| "Refactor X" | "Ensure tests pass before and after." |

For multi-step tasks, state a brief plan **before** executing:

```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria enable autonomous looping. Weak criteria ("make it work") require constant clarification.

---

## 📋 Pre-Code Checklist (Run Every Time)

| # | Check | Pass? |
|---|-------|-------|
| 1 | Did I state my assumptions explicitly? | ✅ / ❌ |
| 2 | Is this the simplest solution that solves the request? | ✅ / ❌ |
| 3 | Am I only touching what I need to touch? | ✅ / ❌ |
| 4 | Have I defined verifiable success criteria? | ✅ / ❌ |

If any check is ❌ → Resolve it before proceeding.

---

*Source: Derived from [Andrej Karpathy's observations](https://x.com/karpathy/status/2015883857489522876) on LLM coding pitfalls, adapted for the AOS by Botman.*
