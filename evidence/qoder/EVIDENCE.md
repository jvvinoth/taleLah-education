# Qoder evidence trail — spec → quest plan → execution

TaleLah was built spec-first inside Qoder: specs authored before code, each
sprint executed as a quest, every feature landing as a conventional commit
that traces back to a spec section and an acceptance criterion.

## 1 · Specs (authored first)

| Spec | Governs |
|---|---|
| `docs/PRD.md` | Product scope, P0 checklist (§9.1), FR catalogue (§12), Qoder plan (§21) |
| `specs/product.md` | Product narrative + flows |
| `specs/story-package.md` | Story Package contract (AC-01/AC-02) |
| `specs/agents/` | Six-agent responsibilities + prompts |
| `specs/languages/` | Language-pack contract (F1, AC-08) |
| `specs/safety.md` | Safety gate, mission rules, forbidden copy (AC-09) |
| `specs/ui-states.md` | Parent/child mode states (AC-03) |
| `specs/acceptance.md` | AC-01…AC-10 + eval golden-set definition |

## 2 · Quest plan → sprints

`docs/SPRINT-PLAN.md` decomposes the PRD §21.2 quests into 5 sprints;
each sprint closed with verification before the next began.

| Sprint | Focus | Landed as |
|---|---|---|
| 1 | Six-agent pipeline + Story Package | `feat(f2)`… pipeline commits |
| 2 | Parent trust loop (review/edit/approve, packs, clarification) | `0efef9c`, `007e1a5`, `6d0dffa` |
| 3 | Capture + child speech (ASR/TTS, fallback ladder) | `744b292`, `dd29616` |
| 4 | Child & family experience (F7–F10) | `f1a2b50` |
| — | Neon persistence (restart-survivable state) | `c22da8f`, `e3a72d6` |
| 5 | Evidence & demo — evals, CI hardening, pack-swap proof | this commit |

## 3 · Execution evidence

- **Eval results**: `evidence/evals/eval-results-<date>.{json,md}` — golden set
  (6 ta + 3 zh + 3 ms + 2 ambiguous) run through the LIVE pipeline, graded
  automatically against `specs/acceptance.md` criteria, with git HEAD +
  clean-tree proof embedded.
- **Adversarial safety**: `backend/evals/adversarial_cases.json` (25 cases) run
  as pytest (`backend/tests/test_eval_safety.py`) on every CI push — the
  harness caught and fixed a real gate over-blocking bug (ta-02/ta-04) during
  Sprint 5.
- **Forbidden-copy audit**: `backend/tests/test_forbidden_copy.py` in CI.
- **Child-mode purity (AC-03)**: `flutter test` in `ci-app.yml`.
- **Pack-swap proof (AC-08)**: `evidence/demo/pack-swap-proof.md`.
- **Demo (AC-10)**: `docs/DEMO-SCRIPT.md` — 2–3 min shot list on the seeded
  profile (`backend/evals/seed_demo.py`).
- **Deployment**: push to `main` → Railway auto-deploy; `/api/v1/health`
  reports agents, packs, and `"persistence": "neon"`.

## 4 · Traceability inside the product

Every generated package carries a full agent trace (six agents, timestamps,
inputs/outputs) persisted to Neon (`traces` table) and visible in the parent
UI — the same evidence the judges see is what parents see.
