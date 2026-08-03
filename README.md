<div align="center">

# 🐦 TaleLah

### Everyday moments. Mother-tongue magic.

**TaleLah turns something your child really did today into a five-minute story in Tamil, Chinese or Malay — and ends it off the screen, with your family.**

Built for the **Qoder × Alibaba Cloud Singapore 2026 Hackathon**

[**Try the app**](https://app.talelah.com) · [**Website**](https://talelah.com) · [**Pitch deck**](https://deck.talelah.com) · [**API docs**](https://api.talelah.com/docs)

</div>

---

## The problem

Singapore families are losing their mother tongue at home, one generation at a time. Parents want their children to speak Tamil, Mandarin or Malay — but the language lives in a weekly tuition class, not in the house.

The apps that exist teach *vocabulary*. A child learns the word for "elephant" and never says it to anyone. Screen time replaces family time instead of starting it.

## What TaleLah does differently

A parent captures **one real moment** from the day — a photo, a voice note, or a sentence. Six AI agents turn it into a short mother-tongue picture book starring that child's actual afternoon.

The child reads it with Mina the Myna, speaks **one bounded phrase** out loud, and then the screen deliberately sends them away:

> **Room mission** — "Stretch your arm out like Anbu's trunk, and gently move your softest toy onto the sofa."
>
> **Family handoff** — "Ask your grown-up: who helped you today?"

The story ends *off* the device, in a conversation with a real person. **That handoff is the product.**

**North-star metric:** completed family language moments per active child per week — not minutes of screen time.

---

## Live deployments

| Surface | URL | Hosted on |
|---|---|---|
| Product — Flutter PWA | [app.talelah.com](https://app.talelah.com) | Railway |
| API — FastAPI | [api.talelah.com/docs](https://api.talelah.com/docs) | Railway |
| Website — 4 languages | [talelah.com](https://talelah.com) | Cloudflare Pages |
| Pitch deck | [deck.talelah.com](https://deck.talelah.com) | Cloudflare Pages |

**Demo account:** `demo@talelah.app` / `demo1234` — preloaded with six authored stories across all three languages.

---

## How it works

```
   Parent captures a moment            Six agents, one pipeline          Child, then family
  ┌────────────────────────┐       ┌──────────────────────────────┐   ┌──────────────────┐
  │  📷  photo             │       │  1. Moment Lens      (vision)│   │  Mina reads      │
  │  🎙️  voice note   ─────┼──────▶│  2. Learning Planner         │──▶│  Child chooses   │
  │  ⌨️   one sentence     │       │  3. Story Weaver             │   │  Child speaks    │
  └────────────────────────┘       │  4. Language Guardian        │   │  Room mission    │
                                   │  5. Family Voice Director    │   │  Family handoff  │
        ┌─────────────────┐        │  6. Growth Coach             │   └──────────────────┘
        │ Parent approves │◀───────┤                              │
        │  (safety gate)  │        │  Safety gate blocks anything │
        └─────────────────┘        │  that fails a single check   │
                                   └──────────────────────────────┘
```

Nothing reaches a child without a parent tapping approve — and nothing reaches the parent without passing the safety gate.

### The six agents

| # | Agent | Job |
|---|---|---|
| 1 | **Moment Lens** | Reads the photo, voice note or text and extracts structured facts about what actually happened |
| 2 | **Learning Planner** | Picks 3–5 target words and one target phrase, pitched at the child's level |
| 3 | **Story Weaver** | Writes the picture book — title, pages, refrain, room mission, family handoff |
| 4 | **Language Guardian** | Translates and checks the mother-tongue text reads naturally, not machine-stiff |
| 5 | **Family Voice Director** | Generates narration audio per language and prepares the family handoff |
| 6 | **Growth Coach** | After the session, seeds the next moment and writes an encouraging note for the parent |

Plus a **Community Scout** that refreshes nearby language events, and a **deterministic orchestrator** — the agents are AI, the state machine that runs them is not.

### Two story engines

- **Classic** — the six agents run in sequence and the finished story arrives at once.
- **Book-first** (default) — an outline lands in about **6 seconds** so the parent can start reading, then each page expands and streams in independently. One failed page retries on its own without losing the book.

Progress streams to the client over **Server-Sent Events** with buffered replay, so a phone that reconnects never misses an event.

---

## Tools, platforms and models

### Built with Qoder

**[Qoder](https://qoder.com) is the IDE this product was built in**, and the reason a six-agent system across three languages and two clients shipped inside a hackathon window.

- **Spec-driven development.** The repo carries its own constitution in [`AGENTS.md`](AGENTS.md), plus one spec per concern under [`specs/`](specs/) — [`story-package.md`](specs/story-package.md) (the shared contract every agent reads and writes), [`safety.md`](specs/safety.md), [`ui-states.md`](specs/ui-states.md), one file per agent, one per language. Qoder is pointed at the constitution plus only the specs a task needs — never the whole PRD.
- **Quest Mode** planned and executed each feature slice against those specs, which is what kept six agents and three languages coherent instead of drifting apart.
- **Spec-swap proof** — adding a language is a data change, not a code change: [`evidence/demo/pack-swap-proof.md`](evidence/demo/pack-swap-proof.md).
- Session evidence lives in [`evidence/qoder/`](evidence/qoder/).

Which specs each Quest loads (always on top of `AGENTS.md`):

| Quest | Specs |
|---|---|
| Q1 Foundation | `product.md`, `story-package.md` |
| Q2 Capture | `story-package.md`, `safety.md` |
| Q3 Generation | `story-package.md`, `agents/1–4`, `languages/ta-SG.md` |
| Q4 Child session | `story-package.md`, `ui-states.md`, `agents/5–6` |
| Q5 Mission & family | `agents/5`, `safety.md`, `ui-states.md` |
| Q6 Safety & data | `safety.md`, `acceptance.md` |
| Q7 Language reuse | `story-package.md`, `languages/*` |
| Q8 Polish & evidence | `acceptance.md` |

### Alibaba Cloud — the AI core

| Model | Used for |
|---|---|
| **Qwen-Max** | Story authoring, planning and translation checking, via DashScope / Model Studio |
| **Qwen-VL-Max** | Vision — reading the photo a parent uploads |
| **Paraformer** | Mandarin speech recognition |
| **CosyVoice** | Mandarin narration voice |
| **Wanx** `wan2.1-t2i-turbo` | Scene illustrations, character-locked across pages |

### Per-language model routing

Every locale is a **language pack** — a JSON file declaring which providers serve it. Nothing in the pipeline hardcodes a language.

| Capability | Tamil `ta-SG` | Chinese `zh-SG` | Malay `ms-SG` |
|---|---|---|---|
| Story LLM | Sarvam 105B | **Qwen-Max** | **Qwen-Max** |
| Vision | **Qwen-VL-Max** | **Qwen-VL-Max** | **Qwen-VL-Max** |
| Speech recognition | Sarvam Saarika | **Alibaba Paraformer** | Google STT `ms-MY` |
| Narration voice | Sarvam Bulbul · `kavitha` | **Alibaba CosyVoice** · `longxiaochun` | Google TTS `ms-MY` |
| Fallback voice | Google `ta-IN` | Google `cmn-CN` | — |

Each pack declares a fallback, so a provider outage degrades the *voice* rather than breaking the *story*.

### Infrastructure

| Layer | Choice | Why |
|---|---|---|
| **App + API hosting** | **Railway** | Two services from one repo, deploy on push to `main`, managed TLS on custom domains |
| **Static hosting** | **Cloudflare Pages** | Website and pitch deck at the edge, preview build per branch |
| **Database** | **Neon** — serverless PostgreSQL | Write-through JSONB document store; state survives every redeploy |
| **Object storage** | **Cloudflare R2** | Story illustrations and narration audio, no egress fees |
| **Email** | **Resend** | Signup verification and password reset |
| **CI/CD** | **GitHub Actions** | Test every PR, deploy on merge to `main` |

### Client and server

- **Flutter 3.35** — one Dart codebase → installable PWA and mobile web, with three distinct modes: `parent/`, `child/`, `family/`
- **Python 3.11 / FastAPI** — async throughout, Pydantic schemas as the single source of truth
- **Astro + TypeScript** — the website, statically rendered in four locales

---

## Safety

Safety is an enforced policy layer, not a prompt instruction. Every story passes [`backend/safety/gate.py`](backend/safety/gate.py) before a parent ever sees it.

- **Room missions** are keyword-screened against anything sharp, hot, electrical, chokeable, height-related or water-related — and anything that would send a child out of the room.
- **Child-facing text** may contain no external links, no diagnostic or clinical language, no commercial phrasing, and nothing asking a child to keep a secret from an adult.
- **Child mode has no open input.** No text box, no open-domain chat, no feeds, no ads, no purchases. Interactions are bounded: at most three tappable choices, or one spoken phrase.
- **No model API keys ever reach the client.** Flutter records and uploads; the backend makes every model call.

The gate applies to the hand-authored seed library too — authored stories are validated by exactly the same code as generated ones, with no exemption.

---

## Repository layout

```
talelah/
├── AGENTS.md              # Build constitution — the always-loaded spec
├── specs/                 # One spec per concern (agents, languages, safety, UI states)
├── docs/                  # PRD, sprint plan, demo script
├── evidence/              # Qoder sessions, eval results, pack-swap proof
│
├── backend/               # Python / FastAPI  (~10,700 lines)
│   ├── agents/            # The six agents + community scout
│   ├── core/              # Orchestrator, book engine, language packs, persistence
│   ├── adapters/          # One module per provider — DashScope, Sarvam, Google, R2…
│   ├── packs/             # ta-SG / zh-SG / ms-SG language packs (JSON, not code)
│   ├── safety/            # The gate
│   ├── schemas/           # Pydantic contracts — StoryPackage is the shared spine
│   ├── seed/              # Hand-authored starter library (6 stories, 3 languages)
│   └── tests/             # 130 tests
│
├── app/                   # Flutter PWA  (~13,400 lines)
│   └── lib/
│       ├── screens/       # parent home, child session, family mode, library
│       ├── widgets/       # adventure deck, live mic, story reader
│       ├── providers/     # app state, SSE pipeline handling
│       └── services/      # API client
│
├── marketing/             # Astro website, 4 locales (en / ta / zh / ms)
└── deck/                  # Pitch deck (self-contained HTML)
```

---

## Running it locally

**Backend**

```bash
cd backend && pip install -r requirements.txt
cp ../.env.example ../.env      # then fill in your keys
uvicorn backend.main:app --reload --port 8000
```

Without any API keys the app still runs — agents fall back to deterministic sample data, so the whole flow is explorable offline.

**App**

```bash
cd app && flutter pub get && flutter run -d chrome
```

**Website**

```bash
cd marketing && npm install && npm run dev
```

**Tests**

```bash
python3 -m pytest backend/tests -q      # 130 tests
cd app && flutter test && flutter analyze
```

---

## Environment variables

| Variable | Purpose |
|---|---|
| `DASHSCOPE_API_KEY` | Qwen-Max, Qwen-VL-Max, Paraformer, CosyVoice, Wanx |
| `SARVAM_API_KEY` | Tamil LLM, speech recognition and narration |
| `GOOGLE_CREDENTIALS_JSON` | Malay speech + multilingual transcription (inline JSON, for hosts without a filesystem) |
| `DATABASE_URL` | Neon PostgreSQL — omit to run memory-only |
| `R2_*` | Cloudflare R2 bucket credentials |
| `RESEND_API_KEY` | Transactional email — without it, codes are logged instead of sent |
| `ADMIN_TOKEN` | Enables the demo reseed endpoint; unset means the route does not exist |

Full list in [`.env.example`](.env.example).

---

## Design decisions worth knowing

**Language packs, not language branches.** Adding Malay meant adding `ms-SG.json` and a spec — no pipeline code changed. That reusability is the architectural claim this project makes.

**Memory is the read path, Postgres is a write-through mirror.** Requests never wait on the database; every mutation is mirrored fire-and-forget, and startup hydrates the stores back, so state survives redeploys.

**Degradation ladders everywhere.** No database → memory-only. No Pillow → original photo bytes pass through. No TTS provider → the pack's fallback voice. No API keys at all → sample data. The demo never dies on a missing dependency.

**Progressive generation.** The book-first engine publishes the outline early so a parent can read while the rest is still being written, and every page carries its own status, so one failure never costs the whole story.

---

## Roadmap

- **Parent voice cloning** — narration in the child's own parent's voice, for families where a grandparent lives overseas
- **Pronunciation coaching** — per-word feedback on the child's spoken turn
- **Illustrated seed library** — character-locked art across every page
- **School pilot** — mother-tongue teachers assigning moments as homework

---

<div align="center">

**Made in Singapore** 🇸🇬 · Built with [Qoder](https://qoder.com) and [Alibaba Cloud](https://alibabacloud.com)

*Mina the Myna is waiting.*

</div>
