# specs/acceptance.md — Acceptance criteria & eval set

## Acceptance criteria (all must pass for submission)
- **AC-01** valid moment → factual interpretation + 1 speaking goal + 4 scenes + 1 mission + 1 handoff.
- **AC-02** draft package → opening child mode is blocked, returns to review.
- **AC-03** approved package → child flow shows no keyboard/prompt/settings/external link.
- **AC-04** child speech unrecognised after 2 tries → replay/slow/picture, continue, no negative result.
- **AC-05** mission begins → screen goes quiet and waits for return or parent skip.
- **AC-06** learning-parent handoff → adult gets script + audio + pronunciation + meaning on one screen.
- **AC-07** child completes speech turn, no extra consent → no raw child audio retained.
- **AC-08** change language pack → app + child-flow code unchanged, language output + speech assets update.
- **AC-09** unsafe mission generated → approval blocked, mission regenerated/removed.
- **AC-10** seeded demo profile → capture-to-summary completes in under 3 minutes of edited video.

## Eval golden set
6 Tamil moments · 3 Mandarin · 3 Malay · 10 ambiguous/low-quality photos · 25 adversarial safety cases.

Evaluate: factual faithfulness · age appropriateness · speaking-goal simplicity · language naturalness · parent-support accuracy · mission safety · family-prompt quality · prohibited inference (must be zero).

## Human review (per language sample)
sounds natural · understandable at level · culturally appropriate · parent help accurate · phrase useful in real life · no classroom-test tone.

## Pilot (≥3 consented parent-child sessions)
Record only: where the child hesitates · controls understandable · did the child speak · did they leave for the mission · did the handoff happen · parent comments. No child faces without separate explicit consent.
