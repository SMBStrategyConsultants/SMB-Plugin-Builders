---
name: architecture
description: Architectural decision-making framework. Requirements analysis, trade-off evaluation, ADR documentation. Use when making architecture decisions or analyzing system design.
allowed-tools: Read, Glob, Grep
---

# Architecture Decision Framework

> "Requirements drive architecture. Trade-offs inform decisions. ADRs capture rationale."

## 🎯 Selective Reading Rule

**Read ONLY files relevant to the request!** Check the content map, find what you need.

| File | Description | When to Read |
|------|-------------|--------------|
| `context-discovery.md` | Questions to ask, project classification | Starting architecture design |
| `trade-off-analysis.md` | ADR templates, trade-off framework | Documenting decisions |
| `pattern-selection.md` | Decision trees, anti-patterns | Choosing patterns |
| `examples.md` | MVP, SaaS, Enterprise examples | Reference implementations |
| `patterns-reference.md` | Quick lookup for patterns | Pattern comparison |

---

## 🔗 Related Skills

| Skill | Use For |
|-------|---------|
| `@[skills/database-design]` | Database schema design |
| `@[skills/api-patterns]` | API design patterns |
| `@[skills/deployment-procedures]` | Deployment architecture |

---

## Core Principle

**"Simplicity is the ultimate sophistication."**

- Start simple
- Add complexity ONLY when proven necessary
- You can always add patterns later
- Removing complexity is MUCH harder than adding it

---

## Validation Checklist

Before finalizing architecture:

- [ ] Requirements clearly understood
- [ ] Constraints identified
- [ ] Each decision has trade-off analysis
- [ ] Simpler alternatives considered
- [ ] ADRs written for significant decisions
- [ ] Team expertise matches chosen patterns


## 🧠 Hardened Guardrails (Lessons — Spot2Bee-relevant subset)
<!-- lessons_start -->
* **2026-06-23 [Strategy]**: OAuth-only auth (Apple/Google 1-tap) is the correct Spot2Bee auth strategy — SMS OTP removed permanently (Rationale: SMS OTP hit toll fraud in a prior version of the app. At scale: $0.01–$0.05 per SMS, 30% sign-up abandonment when users must type a code. OAuth binds accounts to verified Apple/Google identities + device IDs, making bot rating manipulation structurally harder. No phone number collected at sign-up. Strengthens LBM data integrity by eliminating unverified device associations.)
* **2026-06-21 [Strategy]**: LBM runtime token cost is negligible because core intelligence is pure Python math, not LLM (Rationale: Operator Nightly Brief = $0.0042/venue/night. User Recommendations = $0.0026/user/trigger (Thu+Fri only). All CEM, PAW, VM, KEI, WMI, persona clustering runs as deterministic Python — zero LLM calls. Haiku 4.5 only at narrative synthesis (Tier 3). This architecture should be the model for any behavioral intelligence platform at scale.)
* **2026-06-11 [Strategy]**: Direct ingest architecture — app calls LBM endpoint, bypasses Go monolith (Rationale: `POST /lbm/v1/ingest` fired directly from React Native. Go monolith never knows LBM exists at runtime. Eliminates inter-team runtime dependency, simplest possible integration surface.)
* **2026-06-11 [Strategy]**: LBM 3-Tier Processing Architecture (Rationale: Separates Edge Capture (React Native) from Inference (Go Monolith) and LLM Translation to keep cloud hosting costs low and prevent API bottlenecks.)
* **2026-06-23 [Rejection]**: SMS Phone OTP as primary consumer auth method (Why: Toll fraud hit prior version of the app. $0.01–$0.05 per SMS at scale. 30% sign-up abandonment when users must type a code. Carrier-dependent reliability.. Alternative: Apple/Google 1-tap OAuth only — faster sign-up, no phone number stored, stronger device identity binding for LBM)
* **2026-06-23 [Rejection]**: `hashed_password` storage in users schema (Why: Eliminated as a direct consequence of OAuth-only decision. No password auth = no password storage. Adds attack surface with zero value if OAuth is the only path.. Alternative: `oauth_provider` + `oauth_provider_id` fields in users table; auth fully delegated to Apple/Google)
<!-- lessons_end -->

> Trimmed from our full internal lessons log — removed entries belonged to other clients/projects and aren't relevant here.
