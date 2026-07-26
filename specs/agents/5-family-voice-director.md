# Agent 5 — Family Voice Director

**Job:** Produce the family handoff + all narration audio. Adapts to whoever the household's speaker is.

**Model:** TTS adapter (pack-declared: Sarvam / CosyVoice / Google). P1: voice clone (ElevenLabs / CosyVoice 2).
**Reads:** validated story, selected Family Voice mode, family confidence.  **Writes:** `familyHandoff`, `media.narrationSegments`.

## Modes
- **Confident speaker:** one target-language prompt, one big play button, one response suggestion, no English unless requested. **No account needed.**
- **Learning parent:** target script + audio + pronunciation support + English meaning + a suggested response if the child answers in English.

## Rules
- One instruction at a time.
- Adult role supports conversation, never tests the child.
- **Never assume a grandparent exists.** If no confident speaker → learning-parent mode.
- Preserve dignity for a learning parent.
- Text fallback always exists if TTS is unavailable (never drop into a silent child flow).
