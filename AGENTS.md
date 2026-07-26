# AGENTS.md — TaleLah build constitution

> **Always load this file.** It is the single source of truth for how TaleLah is built.
> For any Quest, load this + `specs/story-package.md` + only the specs that Quest needs.
> Full detail lives in `docs/PRD.md` (reference only — do not paste it wholesale into prompts).

---

## What we are building (in one paragraph)

TaleLah turns something a child really did today into a **five-minute mother-tongue adventure** that continues off-screen with the family. A parent captures one moment (photo / voice / text). Six agents produce a **parent-approved Story Package** in Tamil, Chinese or Malay. Mina the Myna guides the child through a 4-scene story, listens for one bounded spoken response, sends an off-screen mission, then hands off to a family speaker. North-star metric: **completed family language moments per active child per week.**

**Golden path (the only must-have):** capture → approve → child chooses → child speaks → off-screen mission → family handoff → save memory. Tamil is the fully tested path; Mandarin + Malay prove reusability.

---

## Tech stack (do not deviate without updating this file)

- **Client:** Flutter, one codebase → installable **PWA + mobile web**. Three modes: `parent/`, `child/`, `family/`.
- **Backend:** **Python / FastAPI**, PostgreSQL, object storage, Server-Sent Events for pipeline progress.
- **AI core:** **Qwen-Max** (LLM) + **Qwen-VL-Max** (vision) via Alibaba Cloud Model Studio / DashScope.
- **Speech = per-language, behind adapters** (see matrix below). Never call a model SDK from Flutter.
- **Orchestrator:** deterministic state machine at runtime (Qoder Quest Mode is for building, not runtime).

### Model/provider matrix (resolved by the active language pack)
| Capability | ta-SG | zh-SG | ms-SG |
|---|---|---|---|
| LLM + Vision | Qwen-Max / Qwen-VL | Qwen-Max / Qwen-VL | Qwen-Max / Qwen-VL |
| ASR | Sarvam Saarika | Alibaba Paraformer | Google STT ms-MY |
| TTS | Sarvam Bulbul | Alibaba CosyVoice | Google TTS ms-MY |
| Voice clone (P1) | ElevenLabs IVC | CosyVoice 2 | ElevenLabs IVC |

---

## Hard rules (never violate — these are the trust product)

1. **No model API keys in the client.** Flutter records audio/photo and POSTs to FastAPI; the backend calls all models.
2. **Speech runs on the backend only.** Flutter web must not embed ASR/TTS SDKs.
3. **Child mode has no open input** — no text box, no open-domain chat, no external links, no ads, no purchases, no feeds.
4. **Nothing reaches child mode without the Safety + Parent Approval Gate passing.**
5. **No raw child audio stored by default.** Child speech → bounded intent → discarded. Saving a memory requires explicit parent action.
6. **No scores, grades, rankings, proficiency claims, or emotion/confidence inference about the child.** (See Non-goals.)
7. **Language behaviour lives in `/specs/languages/*`, not in code.** Adding/revising a language must not change child-flow application code. This is the reusability proof.
8. **Every child-facing and family-facing line passes Language Guardian (Agent 4) before parent review.**
9. **Bounded speech:** transcribe, then fuzzy-match against the pack's expected words/intents. Never require perfect open ASR. Weak match → replay / slower / picture fallback. Never mark the child "wrong."
10. **Data minimization:** child alias only — no legal name, DOB, school, address, ethnicity or face profile required.

---

## Locked decisions (PRD §31 — do not re-litigate in code)

Product name **TaleLah**; **Mina the Myna** is a functional guide, not decoration; parent is the account holder + approval authority; every session has **one** speaking goal, **one** off-screen mission, **one** family handoff; progress measures family language moments, not proficiency; **six logical agents + one orchestrator** is final; stable pre-approved child visuals for the hackathon (no runtime image generation).

## Non-goals (PRD §4.3 — if a task drifts here, stop and flag)

Open child chatbot · infinite story generation · teacher/documentation dashboard · developmental or clinical assessment · **language proficiency scoring** · **emotion/confidence analysis of the child** · school-syllabus replacement · social feed / child-to-child messaging · ads to children · native iOS/Android apps · smart-speaker/hardware · runtime dynamic image or video generation.

---

## Repo layout

```
app/          Flutter — parent/ child/ family/ shared/
backend/      FastAPI — api/ orchestration/ agents/ adapters/ safety/ schemas/ analytics/
specs/        product · story-package · agents/ · languages/ · safety · ui-states · acceptance
docs/         PRD.md (full reference)
evidence/     qoder/ (specs, quest plans) · pilot/ · demo/
marketing/    separate static site (Astro/Framer/HTML) — NOT Flutter
```

## Conventions

- All agents read/write the **structured Story Package schema** (`specs/story-package.md`). Free-form agent prose never passes directly into child mode.
- Each Story Package records `agentSpecVersions` + `modelVersions` for provenance.
- Adapter interfaces: `LLMProvider`, `VisionProvider`, `ASRProvider`, `TTSProvider`. Language pack declares which concrete provider to use.
- Every generation step is idempotent and retryable without re-uploading the moment.
- Capture Qoder evidence as you build (spec → quest plan → execution) in `evidence/qoder/`.

## P1 stretch (only after P0 golden path is polished)

- **Parent voice narration** — gated go/no-go on Aug 1. Preset TTS is the P0 guarantee.
- **Family Growth Reflection** — descriptive parent view: words used, stories spoken in, participation over time. **No scores, no emotion inference, no raw audio.** (This is the safe reframe of the "speech report" idea.)
- Pre-recorded family voice · remote handoff link · multiple child profiles · weekly recap.
