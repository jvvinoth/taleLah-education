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


class LearningPlannerAgent(BaseAgent):
    name = "learning_planner"
    spec_version = "1.0.0"

    async def execute(self, package: StoryPackage) -> StoryPackage:
        """
        Generate a learning plan from verified facts.

        Rules (from spec):
        - One language win per session — not a lesson plan.
        - Prefer everyday, reusable speech.
        - Match speaking confidence, not age alone.
        - Avoid school/test framing.
        """
        logger.info(f"[LearningPlanner] Planning for package {package.id}")

        # In production: call Qwen-Max with the facts + level + pack rules.
        # Sprint 0: deterministic placeholder.
        if not package.learning_plan:
            package.learning_plan = LearningPlan(
                speaking_goal="Describe one color and predict the next stop.",
                target_words=["red", "station", "next"],
                target_phrase="The red train goes to the next station.",
                level=package.child_profile_id and ConfidenceLevel.EMERGING or ConfidenceLevel.EMERGING,
                expected_intents=["names_a_color", "predicts_next"],
            )
            logger.info("[LearningPlanner] Generated learning plan")

        self._record_provenance(package)
        return package
