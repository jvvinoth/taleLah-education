# Pack-swap proof — F1 / AC-08

> **AC-08**: change language pack → app + child-flow code unchanged,
> language output + speech assets update.

## Git-clean proof

- HEAD: `3e0a85b` (`feat(evals): Sprint 5 evidence harness …`)
- `git status --porcelain` → **empty** before and after the swap
  (packs were copied to a scratch dir; the repo tree was never touched)

## Zero locale literals in application code

```
$ grep -rn "ta-SG\|zh-SG\|ms-SG" backend/agents backend/adapters backend/safety
(no matches — exit 1)
```

All locale behaviour lives in `backend/packs/*.json`; agents, adapters and
the safety gate resolve everything through `pack_loader` (`backend/core/language_packs.py`).

## Swap executed (unchanged `PackLoader`, edited JSON only)

Two edits, both pure data:
1. **Revise** `ta-SG.json` — bump `pack_version` → `1.3.0-demo`, add word
   `புறா / puraa / pigeon` to the word bank.
2. **Add a locale** — copy the file to `ta-DEMO.json` with `locale: "ta-DEMO"`.

Output of the unchanged loader against the edited pack dir:

```
locales: ['ms-SG', 'ta-DEMO', 'ta-SG', 'zh-SG']
ta-SG version: 1.3.0-demo | word_bank: 8
new word served: ['pigeon']
new locale pack: ta-DEMO 0.1.0-demo
```

The new locale appears, the revised word bank is served — no application
code changed, no restart-time special-casing.

## Three locales through the same unchanged pipeline

`evidence/evals/eval-results-20260728.md` — the golden set runs
**6 ta-SG + 3 zh-SG + 3 ms-SG** moments through the identical 6-agent
pipeline (14/14 pass), with git HEAD + clean-tree flag embedded in the
results JSON. Speech assets follow the pack too: each pack names its own
ASR/TTS provider, language and voice (`providers.tts.voice_id`).

## Live-demo procedure (shot 8 in `docs/DEMO-SCRIPT.md`)

1. `git status` on camera → clean.
2. Edit `backend/packs/ta-SG.json`: add a word-bank entry, bump version.
3. Restart backend (`uvicorn backend.main:app`) — startup log prints
   `📦 Loaded language pack ta-SG v<new>`.
4. `GET /api/v1/packs/ta-SG/word-bank` → new word present.
5. `git status` again → only the pack JSON changed. Revert with `git checkout -- backend/packs/ta-SG.json`.
