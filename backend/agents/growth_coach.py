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
from datetime import datetime

from ..schemas.story_package import SessionOutcome, StoryPackage
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

        next_moment_suggestion = ""
        encouragement = ""
        coach_source = "fallback"

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
                next_moment_suggestion = (result.get("next_moment_suggestion") or "").strip()
                encouragement = (result.get("encouragement") or "").strip()
                coach_source = "qwen-max"
                self._set_model_version(package, "growth_coach", "qwen-max")
                logger.info(f"[GrowthCoach] Next suggestion: {next_moment_suggestion}")
            except Exception as e:
                logger.error(f"[GrowthCoach] Qwen call failed: {e}")
                self._set_model_version(package, "growth_coach", "fallback")
        else:
            self._set_model_version(package, "growth_coach", "fallback")

        # Persist the session record + next-moment seed on the package (F11).
        # A non-empty fallback keeps the parent journey moving even without an LLM.
        if not next_moment_suggestion:
            next_moment_suggestion = (
                "Capture another everyday moment together — mealtime, play, or a walk "
                "outside — and we'll turn it into the next little story."
            )
        if not encouragement:
            encouragement = "Lovely work showing up together today. Every moment counts. 🐦"

        package.session_outcome = SessionOutcome(
            completed_at=datetime.utcnow(),
            next_moment_suggestion=next_moment_suggestion,
            encouragement=encouragement,
            coach_source=coach_source,
        )

        self._record_provenance(package)
        return package
