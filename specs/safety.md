# specs/safety.md — Safety & Parent Approval Gate

Safety is an **enforced policy layer + approval gate**, not a conversational agent. Any failed check blocks child mode.

## The gate verifies (all must pass before status = approved)
- source input moderation (moment media + text)
- factual confidence (Moment Lens above threshold or parent clarified)
- age appropriateness
- **mission physical safety** (see below)
- language validation passed (Agent 4)
- absence of diagnostic / identity / emotion inference
- absence of external links or commercial content
- explicit parent approval recorded

## Mission safety — reject any mission involving
leaving the home · strangers · climbing · sharp objects · heat/stove/cooking · medicine · known food-allergy risk · water hazards. Missions use household-safe actions and no special equipment. The mission screen reduces stimulation and waits for the child to return; parent can skip.

## Child-facing AI boundary
no open input · no open-domain generation at runtime · no outbound links · no ads · no purchases · no direct messages · no content feed · no personalised persuasion · no clinical/emotional-dependency language · never tell a child to keep secrets from adults.

## Privacy defaults
adult accounts only; child aliases; voice transcribed→intent→discarded; raw photo retention off after generation; explicit parent action to save any media; visible delete controls; encryption in transit + at rest; access scoped to parent account and audited.

## Compliance posture (commercial, not legal advice)
Review against Singapore PDPA + PDPC Advisory Guidelines on Children's Personal Data before commercialization.
