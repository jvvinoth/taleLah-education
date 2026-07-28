# TaleLah — golden-set eval results

- Ran: 2026-07-28T09:07:05.297819Z  ·  git `3e0a85b`  ·  working tree DIRTY ⚠️
- Backend: `http://127.0.0.1:8020`
- **12/14 passed**

| Case | Locale | Story | Status | Verdict |
|---|---|---|---|---|
| ta-01 | ta-SG | Feeding the Pigeons | awaiting_parent | PASS |
| ta-02 | ta-SG | The Thirsty Money Plant | awaiting_parent | PASS |
| ta-03 | ta-SG | The Tower's Adventure | awaiting_parent | PASS |
| ta-04 | ta-SG | The Rambutan Adventure | awaiting_parent | PASS |
| ta-05 | ta-SG | The Snail and the Rain | awaiting_parent | PASS |
| ta-06 | ta-SG | The Big Yellow Bus Adventure | awaiting_parent | PASS |
| zh-01 | zh-SG | The Sock Matching Adventure | awaiting_parent | PASS |
| zh-02 | zh-SG | 小猫的午睡冒险 | awaiting_parent | PASS |
| zh-03 | zh-SG | 小明的上学准备 | awaiting_parent | PASS |
| ms-01 | ms-SG | Mina and the Missing MRT Color | awaiting_parent | PASS |
| ms-02 | ms-SG | Mina and the Missing MRT Color | awaiting_parent | PASS |
| ms-03 | ms-SG | Mina and the Missing MRT Color | awaiting_parent | PASS |
| amb-01 | ta-SG | Mina and the Missing MRT Color | awaiting_parent | FAIL — status=awaiting_parent (want needs_clarification + question) |
| amb-02 | ta-SG | Mina and the Missing MRT Color | awaiting_parent | FAIL — status=awaiting_parent (want needs_clarification + question) |

## Criteria
- status is awaiting_parent (or needs_clarification for ambiguous)
- exactly 4 scenes, 1 room mission, 1 family handoff (AC-01)
- learning plan: 1 speaking goal, 3-5 target words
- safety validation passed; mission safety_validated
- target-language text present (script check for ta/zh)
- no forbidden copy in child-facing strings
- prohibited inference terms: zero
