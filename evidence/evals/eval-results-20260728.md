# TaleLah — golden-set eval results

- Ran: 2026-07-28T10:16:46.484824Z  ·  git `a9b15eb`  ·  working tree DIRTY ⚠️
- Backend: `http://127.0.0.1:8020`
- **13/14 passed**

| Case | Locale | Story | Status | Verdict |
|---|---|---|---|---|
| ta-01 | ta-SG | Pigeon Feeding Adventure | awaiting_parent | PASS |
| ta-02 | ta-SG | The Thirsty Money Plant | awaiting_parent | PASS |
| ta-03 | ta-SG | The Tower's Big Fall | awaiting_parent | PASS |
| ta-04 | ta-SG | The Rambutan Adventure | awaiting_parent | FAIL — safety=blocked (want passed); mission not safety_validated |
| ta-05 | ta-SG | The Snail on the Wall | awaiting_parent | PASS |
| ta-06 | ta-SG | The Big Yellow Bus Adventure | awaiting_parent | PASS |
| zh-01 | zh-SG | 折叠红色袜子的冒险 | awaiting_parent | PASS |
| zh-02 | zh-SG | 小猫的秘密 | awaiting_parent | PASS |
| zh-03 | zh-SG | 小熊的上学冒险 | awaiting_parent | PASS |
| ms-01 | ms-SG | Biskut Berbagi | awaiting_parent | PASS |
| ms-02 | ms-SG | The MRT Adventure | awaiting_parent | PASS |
| ms-03 | ms-SG | Kereta dalam Kotak Merah | awaiting_parent | PASS |
| amb-01 | ta-SG | — | needs_clarification | PASS |
| amb-02 | ta-SG | — | needs_clarification | PASS |

## Criteria
- status is awaiting_parent (or needs_clarification for ambiguous)
- exactly 4 scenes, 1 room mission, 1 family handoff (AC-01)
- learning plan: 1 speaking goal, 3-5 target words
- safety validation passed; mission safety_validated
- target-language text present (script check for ta/zh)
- no forbidden copy in child-facing strings
- prohibited inference terms: zero
