# specs/product.md — Product behaviour spec

Load for: Q1 Foundation, and any Quest needing product context. Pairs with `AGENTS.md`.

## Purpose

Create **real mother-tongue use** between a child and family members, starting from the child's real daily moments. TaleLah is **not** an unlimited AI story generator and **not** a lesson app.

## Product promise

- **Parents:** Turn today's moment into tonight's mother-tongue conversation.
- **Children:** Tell it. Play it. Speak it.

## Golden-path outcome (within ~10 minutes a family can)

1. Capture one real child moment.
2. Approve one generated language goal + story.
3. Let the child complete a 4-scene interactive adventure.
4. Hear the child use one useful mother-tongue phrase.
5. Complete one activity away from the screen.
6. Involve one trusted family member.
7. Preserve the child's ending as a family memory.

## North-star metric

**Completed family language moments per active child per week.** A completed moment = a child speaking turn **and** (off-screen mission **or** family handoff). Opening or passively listening does not count.

## Users

- **Parent (buyer + operator):** English-dominant, wants more mother-tongue use, ≤2 min prep, needs confidence the language is right, control over what the child sees.
- **Child 4–8 (participant):** understands some MTL, answers mostly in English. Picture-first, one instruction at a time, no typing/reading dependency, celebration without grades.
- **Family Voice (speaker):** parent, grandparent, relative, sibling — in-room or remote. One-button entry, one prompt at a time. **Never assume a grandparent exists.**

## End-to-end journey (9 stages)

Adult gate → Language & family profile → Capture moment → Generate & approve → Child handover & choice → Interactive story + speech → Off-screen mission → Family handoff → Remember. (Full detail: PRD §10.)

## Confidence levels (plain language, not scores)

- **Beginning** — recognizes a few familiar words
- **Emerging** — understands common phrases, often answers in English
- **Growing** — answers with short phrases
- **Conversational** — can tell a short story with support

## Acceptance for "done" (hackathon)

One polished Tamil golden path end-to-end; Mandarin + Malay sample paths; six-agent trace visible; live language-pack swap with no code change; 2–3 min demo; 3 consented pilot sessions. Full criteria: `specs/acceptance.md`.
