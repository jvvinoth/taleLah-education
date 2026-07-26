# TaleLah — repo & spec set

Everyday moments. Mother-tongue magic. Built for the Qoder × Alibaba Cloud SG 2026 hackathon.

## How to feed Qoder (layered context — don't paste the whole PRD)

**Tier 1 — always load:** [`AGENTS.md`](AGENTS.md) — the constitution (stack, hard rules, locked decisions, non-goals).

**Tier 2 — load per Quest:** files under [`specs/`](specs/) — one purpose each.

**Tier 3 — reference only:** [`docs/PRD.md`](docs/PRD.md) — full source of truth. Do not paste wholesale.

## Which specs per Qoder Quest

| Quest | Load these specs (+ always `AGENTS.md`) |
|---|---|
| Q1 Foundation | `specs/product.md`, `specs/story-package.md` |
| Q2 Capture | `specs/story-package.md`, `specs/safety.md` |
| Q3 Generation | `specs/story-package.md`, `specs/agents/1..4`, `specs/languages/ta-SG.md` |
| Q4 Child Session | `specs/story-package.md`, `specs/ui-states.md`, `specs/agents/5,6` |
| Q5 Mission & Family | `specs/agents/5`, `specs/safety.md`, `specs/ui-states.md` |
| Q6 Safety & Data | `specs/safety.md`, `specs/acceptance.md` |
| Q7 Language Reuse | `specs/story-package.md`, `specs/languages/*` |
| Q8 Polish & Evidence | `specs/acceptance.md` |

## Build order (Sprint 0 → today)
1. Read `AGENTS.md`.
2. Confirm stack + accounts (see the Build Blueprint).
3. **Run the Tamil TTS + child ASR risk test before writing features.**
4. Start Quest 1 pointing Qoder at `AGENTS.md` + `specs/product.md` + `specs/story-package.md`.

## Folders to create as you build
`app/` (Flutter) · `backend/` (FastAPI) · `evidence/` (Qoder specs, quest plans, spec-swap recording) · `marketing/` (separate static site — not Flutter).
