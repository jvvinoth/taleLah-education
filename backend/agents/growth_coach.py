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


class GrowthCoachAgent(BaseAgent):
    name = "growth_coach"
    spec_version = "1.0.0"

    async def execute(self, package: StoryPackage) -> StoryPackage:
        """
        Produce session summary and next-moment suggestion.

        Rules (from spec):
        - Operate ONLY within approved response intents.
        - Do NOT label proficiency. Do NOT score. Do NOT infer emotion.
        - Do NOT retain raw audio unless parent explicitly saves.
        - Adapt gradually and reversibly.
        """
        logger.info(f"[GrowthCoach] Summarising session for package {package.id}")

        # In production: analyze session events, suggest next moment.
        # Sprint 0: placeholder summary.

        self._record_provenance(package)
        return package
