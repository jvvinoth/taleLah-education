# Agent 2 — Learning Planner

**Job:** Pick exactly ONE small speaking objective for the session.

**Model:** Qwen-Max.
**Reads:** verified `momentFacts`, understanding + speaking level, active language pack.  **Writes:** `learningPlan`.

## Output
- one `speakingGoal`
- 3–5 `targetWords`
- one `targetPhrase`
- interaction difficulty
- `expectedIntents`

## Rules
- One language win per session — not a lesson plan.
- Prefer everyday, reusable speech over vocabulary lists.
- Match **speaking confidence**, not age alone.
- Avoid school/test framing.
