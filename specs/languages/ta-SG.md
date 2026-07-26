# specs/languages/ta-SG.md — Tamil language pack (Singapore)

The **golden path**. This pack must be native-verified before the demo. It is the template every other pack copies. Adding/revising a pack must not change child-flow application code (Rule 7).

## Identity
- `locale`: `ta-SG`  ·  `script`: Tamil  ·  `packVersion`: `1.0.0`  ·  `status`: `in_review`
- `verifier`: <fluent Tamil speaker name>  ·  `verifiedAt`: <date>

## Providers (resolved by the adapter layer)
- **ASR:** Sarvam **Saarika** (`ta-IN`). Fallback: Google STT `ta-IN`.
- **TTS:** Sarvam **Bulbul** (`ta`). Fallback: ElevenLabs multilingual.
- Bounded-intent matching is mandatory (Rule 9). ASR output is fuzzy-matched to `expectedIntents`, not required to be a perfect transcript.

## Parent support format (shown in parent/family mode, never dominant in child view)
Each target-language line renders three fields:
1. **Tamil script** — e.g. `இது என்ன நிறம்?`
2. **Romanisation** — one consistent convention across the whole pack — e.g. `Idhu enna niram?`
3. **English gloss** — e.g. "What colour is this?"

## Register & style
- Warm, everyday **spoken** Singapore Tamil — not literary/written Tamil, not classroom-test tone.
- Child lines: short, one idea, concrete nouns the child knows.
- Family/grandparent register: respectful, unhurried; use natural spoken numbers and phrasing.
- Permit **code-switching** as a bridge (a stray English word is fine; don't correct it).

## Speech rules
- Model the phrase (TTS) **before** asking the child to speak.
- Max **two** audio retries, then offer a picture/non-speech fallback.
- Never require accent imitation. A meaningful partial answer beats exact repetition.
- Never display "wrong".

## Cultural safeguards
- Do not assume religion, diet, housing type, or family structure.
- Do not stereotype. Use Singapore-relevant settings naturally (void deck, wet market, MRT) — not as a checklist.

## Expected-intent vocabulary (extend per story theme)
- `names_a_color`: நிறம் words — சிவப்பு (red), நீலம் (blue), பச்சை (green), மஞ்சள் (yellow)…
- `counts`: ஒன்று, இரண்டு, மூன்று, நான்கு, ஐந்து
- `predicts_next`: அடுத்து (next), பிறகு (after)
- `polite_request`: தயவு செய்து (please), கொடு (give)

## Sample verified lines (ILLUSTRATIVE — replace with native-verified content)
| Intent | Tamil | Romanisation | English |
|---|---|---|---|
| ask colour | இது என்ன நிறம்? | Idhu enna niram? | What colour is this? |
| count together | சேர்ந்து எண்ணுவோம் | Sernthu ennuvom | Let's count together |
| praise | நல்லா சொன்னே! | Nalla sonne! | You said it well! |
| predict next | அடுத்து எது வரும்? | Aduthu edhu varum? | What comes next? |

## Test cases (for `specs/acceptance.md` eval set)
- ≥6 Tamil moments produce natural, level-appropriate, culturally safe Story Packages.
- Every generated Tamil line passes Language Guardian.
- Romanisation is internally consistent across a whole package.
- TTS output is warm and intelligible (day-one risk test decides Bulbul vs fallback).

> ⚠️ All Tamil in this file is a starting sample. A fluent Tamil speaker must verify every child-facing line before it appears in the demo.
