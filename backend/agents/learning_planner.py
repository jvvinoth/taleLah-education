"""
Agent 2: Learning Planner — specs/agents/2-learning-planner.md

Picks exactly ONE small speaking objective for the session.

Model: Qwen-Max.
Reads: verified momentFacts, understanding + speaking level, active language pack.
Writes: learningPlan.
"""
from __future__ import annotations

import logging

from ..schemas.story_package import (
    ConfidenceLevel,
    LearningPlan,
    StoryPackage,
)
from .base import BaseAgent

logger = logging.getLogger(__name__)

PLANNER_SYSTEM_PROMPT = """You are a language learning planner for a children's mother-tongue app.
Your job is to pick ONE small, achievable speaking objective based on what the child did.

Rules:
- One language win per session — not a lesson plan.
- Prefer everyday, reusable speech (colors, numbers, simple requests).
- Match speaking confidence level, not age alone.
- Avoid school/test/assessment framing.
- Target words must be 3-5 simple words the child can practice.
- The target phrase should naturally use the target words.
- Expected intents are categories like: names_a_color, counts, predicts_next, polite_request.

Respond with JSON:
{
  "speaking_goal": "brief goal description",
  "target_words": ["word1", "word2", "word3"],
  "target_phrase": "A complete sentence using the target words.",
  "level": "beginning|emerging|growing|conversational",
  "expected_intents": ["intent_category_1", "intent_category_2"]
}

No markdown. No explanation."""


class LearningPlannerAgent(BaseAgent):
    name = "learning_planner"
    spec_version = "1.1.0"

    async def execute(self, package: StoryPackage) -> StoryPackage:
        logger.info(f"[LearningPlanner] Planning for package {package.id}")

        if package.learning_plan:
            logger.info("[LearningPlanner] Plan already exists, skipping")
            self._record_provenance(package)
            return package

        if self.llm:
            try:
                facts_text = "\n".join([f"- {f.text} (confidence: {f.confidence})" for f in package.moment_facts])
                locale = package.language.locale

                result = await self.llm.generate_json(
                    prompt=(
                        f"Child's verified activity facts:\n{facts_text}\n\n"
                        f"Language: {locale}\n"
                        f"Speaking level: {package.child_profile_id and 'emerging' or 'emerging'}\n\n"
                        "Create ONE speaking objective with 3-5 target words."
                    ),
                    system=PLANNER_SYSTEM_PROMPT,
                )

                # Parse the response
                level_str = result.get("level", "emerging")
                level_map = {
                    "beginning": ConfidenceLevel.BEGINNING,
                    "emerging": ConfidenceLevel.EMERGING,
                    "growing": ConfidenceLevel.GROWING,
                    "conversational": ConfidenceLevel.CONVERSATIONAL,
                }

                words = result.get("target_words", ["red", "station", "next"])
                if len(words) < 3:
                    words = ["red", "station", "next"]
                if len(words) > 5:
                    words = words[:5]

                package.learning_plan = LearningPlan(
                    speaking_goal=result.get("speaking_goal", "Describe one color and predict the next stop."),
                    target_words=words,
                    target_phrase=result.get("target_phrase", "The red train goes to the next station."),
                    level=level_map.get(level_str, ConfidenceLevel.EMERGING),
                    expected_intents=result.get("expected_intents", ["names_a_color", "predicts_next"]),
                )
                self._set_model_version(package, "learning_planner", "qwen-max")
                logger.info(f"[LearningPlanner] Generated plan via Qwen-Max: {package.learning_plan.speaking_goal}")

            except Exception as e:
                logger.error(f"[LearningPlanner] Qwen call failed, using fallback: {e}")
                package.learning_plan = self._fallback_plan()
                self._set_model_version(package, "learning_planner", "fallback")
        else:
            package.learning_plan = self._fallback_plan()
            self._set_model_version(package, "learning_planner", "fallback")

        self._record_provenance(package)
        return package

    def _fallback_plan(self) -> LearningPlan:
        return LearningPlan(
            speaking_goal="Describe one color and predict the next stop.",
            target_words=["red", "station", "next"],
            target_phrase="The red train goes to the next station.",
            level=ConfidenceLevel.EMERGING,
            expected_intents=["names_a_color", "predicts_next"],
        )
