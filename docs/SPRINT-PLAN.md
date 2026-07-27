# TaleLah — Sprint Plan (reconciled)

> Our stack stays locked per `AGENTS.md`: **Flutter (Provider) + Python FastAPI + Qwen via DashScope + SSE**.
> This plan folds in the 10 adopted features from the team plan review. Sprints are ordered by
> dependency, not calendar days — we build full-agentic, one sprint at a time, demo-green after each.

---

## Status

| Sprint | Theme | Status |
|---|---|---|
| Sprint 0 | Foundation — repo, specs, FastAPI shell, Flutter shell, accounts | ✅ Done |
| Sprint 1 | Real pipeline — 6 Qwen agents, SSE progress, Sarvam/Google TTS, premium UI + mobile frame | ✅ Done |
| Sprint 2 | Parent trust loop — language packs, review/edit, clarification, TTS pre-gen | 🔜 Next |
| Sprint 3 | Child voice loop — voice/photo capture, bounded speech turn | Pending |
| Sprint 4 | Child & family experience — lockdown, mission, handoff modes, memory | Pending |
| Sprint 5 | Evidence & demo — pack-swap showpiece, eval passes, demo cut | Pending |

---

## Sprint 2 — Parent trust loop

### F1 · Language-pack contract (zero-code locale swap) — AC-08
Versioned JSON packs are the single source of locale behaviour.
- `backend/packs/ta-SG.json`, `zh-SG.json`, `ms-SG.json` — `packVersion`, prompts, target-word
  banks, phonetics/romanization, expected child intents, provider matrix (ASR/TTS per AGENTS.md).
- Agents + adapters read **only** from the loaded pack; no locale literals in agent code or Flutter child flow.
- Story Package records `packVersion` for provenance (alongside `agentSpecVersions`).
- **Judge showpiece:** swap the active pack → language output + speech assets change,
  `git status` clean on `app/` and `backend/agents/` — record this for `evidence/demo/`.

### F2 · Parent review & edit workflow — AC-01, AC-02
Between "generated" and "approved", the parent is in control.
- Review screen: edit extracted facts, swap the target word (from pack word bank), difficulty control
  (Beginning → Conversational levels from `specs/product.md`).
- **Single-component regeneration** — regenerate one scene / mission / handoff without re-running the
  whole pipeline; hard cap **5 regenerations** per package.
- **Immutable after approval** — backend flips `approved` flag; all mutation endpoints reject afterwards.

### F3 · needs_clarification flow
- Moment Lens emits per-fact `confidence`; below threshold → pipeline pauses, SSE emits
  `needs_clarification` with **one** question for the parent.
- Parent answers in a dialog → pipeline resumes from the paused step (idempotent, no re-upload).

### F4 · TTS pre-generation on approval
- On approve: backend generates **all** scene/mission/handoff audio via the pack's TTS provider and
  returns a **media manifest** (URLs + durations) on the Story Package.
- Flutter preloads every asset before child mode opens → offline-tolerant playback, <500 ms scene transitions.
- **Parent-read fallback:** any missing audio → scene renders text + romanization for the adult to read aloud.

---

## Sprint 3 — Child voice loop

### F5 · Voice + photo moment capture
Text capture (shipped) stays as the always-works path; add:
- **Voice ≤45 s** — Flutter records, POSTs to FastAPI; backend transcribes via the pack's ASR provider
  (Paraformer / Sarvam / Google STT) → feeds the existing text pipeline. Enforce duration server-side.
- **Photo ≤10 MB** — upload to object storage; **Qwen-VL-Max** interprets the image into moment facts.
  Size/type validation server-side; ambiguous photo → routes into F3 clarification.
- No model SDKs in Flutter — capture only, per hard rule 1/2.

### F6 · Bounded child speech turn — AC-04, AC-07
ASR never free-transcribes into the app.
- Backend transcribes the child clip, then a **fuzzy intent matcher** scores against the pack's expected
  intents only: **Dice + Levenshtein blend, keyword floor 0.7, Tamil NFC normalization** before compare.
- Fallback ladder: attempt 1 miss → replay slower; attempt 2 miss → **picture-choice fallback**; story
  always continues. The app **never says "wrong"** — celebration copy only.
- **Forbidden-copy audit:** automated test scans every child-facing string (all packs) for
  wrong/incorrect/try-again-or-fail phrasing — CI-red if found.
- Raw child audio discarded after intent extraction (hard rule 5); nothing retained without F10 consent.

---

## Sprint 4 — Child & family experience

### F7 · Child-mode lockdown — AC-03
- **Press-and-hold 3 s** to exit child mode; system back-navigation blocked.
- **No-text-input purity assertion** — widget test walks the child-mode tree: zero `TextField`s,
  keyboards, external links, settings entry points.
- Touch targets **≥56 dp**; respects `MediaQuery.disableAnimations` (reduced motion).
- **Mina the Myna — exactly 8 states:** idle · listening · encouraging · celebrating · thinking ·
  demonstrating · waiting · goodbye. Emoji/shape placeholders first; art upgrade only after Sprint 5 is green.

### F8 · Mission screen — AC-05
- Dimmed, **animation-free** waiting screen once the mission starts — the screen gets out of the way.
- Single **"I'm back"** button to resume; parent-skip available from the hold-to-exit gate.

### F9 · Two family-handoff modes — AC-06
- Profile flag per family voice: `confident_speaker` | `learning_parent`.
- Confident: phrase + prompt, minimal chrome. Learning parent: **coach screen** — script, audio playback,
  romanization/pronunciation, meaning — all on one screen.
- Copy comes from the pack (F1); never assumes a grandparent exists.

### F10 · Memory consent + session summary & progress
- Save-memory requires an **explicit consent checkbox** (default off); saved memories have a delete
  action that removes media + rows.
- Session summary after handoff: what the child said, mission done, family moment — celebration, no grades.
- Progress screen shows the **north-star metric only** (completed family language moments / week) —
  no scores, no streaks, no proficiency claims (hard rule 6).

---

## Sprint 5 — Evidence & demo

- Record the **pack-swap demo** (F1) with git-clean proof → `evidence/demo/`.
- Run the eval golden set + 25 adversarial safety cases from `specs/acceptance.md`; capture results.
- Forbidden-copy audit + child-mode purity assertion wired into the test run.
- Seeded demo profile → capture-to-summary **AC-10** rehearsal; cut the 2–3 min video.
- Qoder evidence trail (spec → quest plan → execution) refreshed in `evidence/qoder/`.

---

## Degradation ladder (demo never dies)

| If this slips… | The demo path is… |
|---|---|
| Voice/photo capture (F5) | Text capture (shipped, Sprint 1) |
| Child ASR live match (F6) | Picture-choice fallback — a spec'd feature, not a hack |
| TTS pre-gen manifest (F4) | Parent-read fallback (text + romanization) |
| Mina art | 8 emoji/shape states — behaviour identical |
| zh-SG / ms-SG polish | Tamil golden path + pack-swap proof carries AC-08 |

## AC coverage map

| AC | Covered by |
|---|---|
| AC-01 | Sprint 1 pipeline + F2 |
| AC-02 | F2 (immutability + draft block) |
| AC-03 | F7 |
| AC-04 | F6 |
| AC-05 | F8 |
| AC-06 | F9 |
| AC-07 | F6 + F10 |
| AC-08 | F1 |
| AC-09 | Sprint 1 safety gate + F2 regeneration |
| AC-10 | Sprint 5 |
