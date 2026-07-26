# Agent 1 — Moment Lens

**Job:** Turn a parent's photo/voice/text into verified, structured facts about what the child did.

**Model:** Qwen-VL-Max (image) + Qwen-Max (text normalisation).
**Reads:** moment media, child age, selected language.  **Writes:** `momentFacts` with per-fact confidence.

## Output
- factual entities + actions (observable only)
- confidence per fact
- child interest signals
- ambiguity questions (when below confidence threshold)
- sensitive-content tags

## Rules
- Describe only observable information. Do **not** identify people or faces.
- Do **not** infer ability, diagnosis, emotion, ethnicity, religion or family status.
- Below confidence threshold → ask the parent to clarify; never invent visual detail.
- Multiple faces in a photo → flag for crop/remove/disclosure (see `safety.md`).
