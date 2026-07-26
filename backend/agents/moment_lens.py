"""
Agent 1: Moment Lens — specs/agents/1-moment-lens.md

Turns a parent's photo/voice/text into verified, structured facts
about what the child did.

Model: Qwen-VL-Max (image) + Qwen-Max (text normalisation).
Reads: moment media, child age, selected language.
Writes: momentFacts with per-fact confidence.
"""
from __future__ import annotations

import logging

from ..schemas.story_package import MomentFact, StoryPackage
from .base import BaseAgent

logger = logging.getLogger(__name__)


class MomentLensAgent(BaseAgent):
    name = "moment_lens"
    spec_version = "1.0.0"

    async def execute(self, package: StoryPackage) -> StoryPackage:
        """
        Parse the moment input into structured facts.

        Rules (from spec):
        - Describe only observable information. Do NOT identify people.
        - Do NOT infer ability, diagnosis, emotion, ethnicity, religion.
        - Below confidence threshold → ask parent to clarify.
        - Multiple faces → flag for crop/remove/disclosure.
        """
        logger.info(f"[MomentLens] Processing package {package.id}")

        # For Sprint 0: if facts already exist (from demo seed), keep them.
        # In production, this would call Qwen-VL for images or Qwen for text.
        if not package.moment_facts:
            # Placeholder: will be replaced with actual LLM call in Sprint 1
            package.moment_facts = [
                MomentFact(
                    text="The child arranged colored blocks as an MRT route.",
                    confidence=0.96,
                )
            ]
            logger.info("[MomentLens] Generated placeholder facts")

        self._record_provenance(package)
        return package
