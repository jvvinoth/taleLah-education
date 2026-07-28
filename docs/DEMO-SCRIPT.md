# TaleLah — demo script (AC-10)

Target: **2–3 minutes edited**, seeded profile, capture → summary in one take.
Rehearse the golden path twice before recording; the ladder in
`docs/SPRINT-PLAN.md` (degradation ladder) covers every failure mode.

## Setup (before recording)

- Frontend: `https://talelah-education-production.up.railway.app`
- Backend: `https://web-production-52ebab.up.railway.app` (`/api/v1/health` → `"persistence": "neon"`)
- Seeded: `python3 -m backend.evals.seed_demo --base-url <backend>` — profile **Aru** (4-5, ta-SG) + moment ready
- Browser at 100 % zoom, mobile viewport for child-mode shots, notifications off
- Pack-swap terminal ready on `backend/packs/ta-SG.json` (see `evidence/demo/pack-swap-proof.md`)

## Shot list

| # | ~Time | Shot | Beat / spoken line |
|---|---|---|---|
| 1 | 0:00–0:15 | Title card → parent home | "A real moment from your child's day becomes tonight's Tamil story. This is TaleLah." |
| 2 | 0:15–0:30 | Capture moment (text): *"We fed the pigeons at the void deck after breakfast"* | "Parents capture one everyday moment — text, voice or photo." |
| 3 | 0:30–0:55 | Generate → **agent trace panel** while pipeline runs | "Six Qwen agents plan, write, and safety-check the story. Every step is traced." |
| 4 | 0:55–1:20 | Parent review: 4 scenes, learning plan, target words; edit one word; **approve** | "Nothing reaches the child unapproved. Parents can edit words, facts, difficulty." |
| 5 | 1:20–1:50 | Child mode (mobile frame): scene narration + TTS, tap a choice, speak a Tamil word → celebration | "Child mode is pure — no menus, no text input, no ads. She speaks Tamil back to the story." |
| 6 | 1:50–2:05 | Room mission card + family handoff | "The story ends off-screen: a safe room mission, and a one-button handoff so Paati hears her say it." |
| 7 | 2:05–2:20 | Session summary → saved memory in parent progress view | "The moment is now a memory — phrases spoken, family moments, all parent-controlled." |
| 8 | 2:20–2:45 | **Pack-swap** (AC-08): `git status` clean → edit `ta-SG.json` word bank → restart → same flow shows new word | "One JSON pack per language. Swap the pack, zero code changes — Mandarin and Malay run the same pipeline." |
| 9 | 2:45–3:00 | Eval results card (`evidence/evals/`) + close | "14/14 golden-set evals, 25 adversarial safety cases blocked. Built spec-first with Qoder." |

## B-roll / backups

- Safety block (AC-09): generate from an unsafe seeded moment → approval blocked banner
- zh-SG and ms-SG packages from the eval run (titles on screen) for shot 8
- If live generation is slow on camera, cut to the pre-generated package
  `story_7e4e44a2dd6c` ("Pigeon Feeding Adventure") — already in Neon

## Recording notes

- Record backend logs in a corner terminal during shot 3 (agent trace credibility)
- Keep child-mode audio audible — the Tamil TTS is the emotional peak
- End card: repo + `evidence/` folder path for judges
