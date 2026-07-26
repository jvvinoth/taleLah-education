# specs/story-package.md — The shared contract

**The most-referenced file in the repo.** Every agent reads and writes this structured object. Free-form agent prose must never pass directly into child mode — only validated structured fields.

## Lifecycle status

`captured → interpreting → planning → writing → validating → awaiting_parent → approved → in_session → completed`

Child mode is reachable **only** at `approved` (after the Safety + Parent Approval Gate passes).

## Schema (illustrative — keep field names stable)

```json
{
  "id": "story_123",
  "status": "approved",
  "childProfileId": "child_123",
  "momentId": "moment_123",
  "language": { "locale": "ta-SG", "packVersion": "1.0.0" },

  "momentFacts": [
    { "text": "The child arranged colored blocks as an MRT route.", "confidence": 0.96 }
  ],

  "learningPlan": {
    "speakingGoal": "Describe one color and predict the next stop.",
    "targetWords": ["red", "station", "next"],
    "targetPhrase": "The red train goes to the next station.",
    "level": "emerging",
    "expectedIntents": ["names_a_color", "predicts_next"]
  },

  "story": {
    "title": "Mina and the Missing MRT Color",
    "openingChoices": ["Find the missing color", "Repair the secret station", "Follow Mina's route"],
    "scenes": [
      { "index": 0, "narration": "", "visualId": "", "interaction": { "type": "choice|speak", "options": [], "expectedIntent": "" } }
    ],
    "roomMission": { "instruction": "", "safetyValidated": true },
    "familyHandoff": { "mode": "confident|learning", "prompt": "", "responseSuggestion": "" },
    "endingPrompt": { "text": "" }
  },

  "media": {
    "narrationSegments": [ { "sceneIndex": 0, "ttsProvider": "", "audioUrl": "", "text": "" } ],
    "sceneAssets": [ { "visualId": "", "assetUrl": "" } ]
  },

  "familyVoice": { "mode": "confident|learning|prerecorded", "speakerLabel": "", "isRemote": false },

  "validation": {
    "language": "passed|revise|blocked",
    "safety": "passed|blocked",
    "parentApprovedAt": "2026-07-30T12:00:00Z"
  },

  "provenance": { "agentSpecVersions": {}, "modelVersions": {} }
}
```

## Invariants (enforce in code + Approval Gate)

- Exactly **one** `speakingGoal`; **3–5** `targetWords`; **one** `targetPhrase`.
- Exactly **4** scenes; **one** `roomMission`; **one** `familyHandoff`; **≤3** `openingChoices`.
- At least **one** scene has `interaction.type == "speak"` with an `expectedIntent`.
- `roomMission.safetyValidated` must be `true` before `approved`.
- Every child-facing / family-facing string has passed Language Guardian.
- `provenance` populated for every generation.

## Agent I/O boundaries

| Agent | Reads | Writes |
|---|---|---|
| 1 Moment Lens | moment media, profile | `momentFacts` (+confidence) |
| 2 Learning Planner | `momentFacts`, level, pack | `learningPlan` |
| 3 Story Weaver | facts, plan, interests, templates | `story` (draft), `openingChoices`, `roomMission`, `endingPrompt` |
| 4 Language Guardian | draft `story`, pack | corrected target-language text, parent-support fields, `validation.language` |
| 5 Family Voice Director | validated story, family mode | `familyHandoff`, `media.narrationSegments` (TTS) |
| 6 Growth Coach | approved package, session events | session record, next-moment seed (no proficiency labels) |
