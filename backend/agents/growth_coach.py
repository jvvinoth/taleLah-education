"""
Agent 6: Session & Growth Coach — specs/agents/6-growth-coach.md

Runs adaptive help during the session and produces the
(non-judgmental) memory + next-moment seed.

Model: Qwen-Max, bounded to approved response intents.
Reads: approved package, bounded child responses, session events, parent feedback.
Writes: adaptive hint/fallback, session completion record,
        next-moment suggestion, gentle reversible difficulty adjustment.
"""
from __future__ import annotations

import logging

from ..schemas.story_package import StoryPackage
from .base import BaseAgent

logger = logging.getLogger(__name__)

COACH_SYSTEM_PROMPT = """You are a gentle, non-judgmental growth coach for a children's language app.
Analyse the session and suggest the next activity moment.

Rules:
- Do NOT label proficiency or score the child.
- Do NOT infer emotion or ability.
- Do NOT retain raw audio.
- Adapt gradually and reversibly.
- Suggest one concrete next moment the parent can capture.

Respond with JSON:
{"next_moment_suggestion": "Brief suggestion for next activity to capture", "encouragement": "Brief positive note for the parent"}

No markdown. No explanation."""


class GrowthCoachAgent(BaseAgent):
    name = "growth_coach"
    spec_version = "1.1.0"

    async def execute(self, package: StoryPackage) -> StoryPackage:
        logger.info(f"[GrowthCoach] Summarising session for package {package.id}")

        if self.llm:
            try:
                target_phrase = ""
                if package.learning_plan:
                    target_phrase = package.learning_plan.target_phrase

                result = await self.llm.generate_json(
                    prompt=(
                        f"Session completed. Target phrase practiced: '{target_phrase}'. "
                        f"Story: '{package.story.title}'. "
                        "Suggest the next moment for the parent to capture."
                    ),
                    system=COACH_SYSTEM_PROMPT,
                )
                self._set_model_version(package, "growth_coach", "qwen-max")
                logger.info(f"[GrowthCoach] Next suggestion: {result.get('next_moment_suggestion', '')}")
            except Exception as e:
                logger.error(f"[GrowthCoach] Qwen call failed: {e}")
                self._set_model_version(package, "growth_coach", "fallback")
        else:
            self._set_model_version(package, "growth_coach", "fallback")

        self._record_provenance(package)
        return package
