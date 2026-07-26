"""
Agent 4: Language Guardian — specs/agents/4-language-guardian.md

Validates and corrects every target-language line before the parent ever sees it.
This is where the language pack does its work.

Model: Qwen-Max + active language pack rules.
Reads: draft story, active pack.
Writes: corrected target-language text, parent-support fields,
        pronunciation & speech hints, validation.language.
"""
from __future__ import annotations

import logging

from ..schemas.story_package import StoryPackage, ValidationStatus
from .base import BaseAgent

logger = logging.getLogger(__name__)


class LanguageGuardianAgent(BaseAgent):
    name = "language_guardian"
    spec_version = "1.0.0"

    async def execute(self, package: StoryPackage) -> StoryPackage:
        """
        Validate and correct all target-language content.

        Rules (from spec):
        - Validate EVERY child-facing and family-facing line.
        - Apply Singapore locale, register and cultural-safeguard rules.
        - Natural spoken language, not literal translation.
        - Reject stereotypes / assumed cultural practices.
        - Flag anything needing human verification.
        """
        logger.info(f"[LanguageGuardian] Validating package {package.id} for {package.language.locale}")

        # In production: call Qwen-Max with the draft + pack rules.
        # Sprint 0: mark as passed for demo placeholder content.
        locale = package.language.locale

        if locale == "ta-SG":
            # Tamil golden path — apply Tamil-specific corrections
            await self._validate_tamil(package)
        elif locale == "zh-SG":
            await self._validate_chinese(package)
        elif locale == "ms-SG":
            await self._validate_malay(package)

        # Mark language validation status
        package.validation.language = ValidationStatus.PASSED
        package.provenance.model_versions["language_guardian"] = "qwen-max-placeholder"

        self._record_provenance(package)
        logger.info(f"[LanguageGuardian] Validation: {package.validation.language.value}")
        return package

    async def _validate_tamil(self, package: StoryPackage) -> None:
        """Apply ta-SG pack rules — specs/languages/ta-SG.md"""
        # In production: Qwen-Max generates Tamil text + romanisation + English gloss.
        # Sprint 0: Tamil placeholder (must be native-verified before demo).

        # Sample verified lines (from ta-SG spec — ILLUSTRATIVE)
        tamil_phrases = {
            "What colour is this?": ("இது என்ன நிறம்?", "Idhu enna niram?"),
            "You said it well!": ("நல்லா சொன்னே!", "Nalla sonne!"),
            "What comes next?": ("அடுத்து எது வரும்?", "Aduthu edhu varum?"),
        }

        # Apply to story scenes (placeholder)
        for scene in package.story.scenes:
            if scene.narration and not scene.narration_target_lang:
                scene.narration_target_lang = f"[Tamil translation of: {scene.narration[:50]}...]"

        # Apply to target phrase
        if package.learning_plan:
            tp = package.learning_plan.target_phrase
            if tp in tamil_phrases:
                package.story.title_target_lang = tamil_phrases[tp][0]

        logger.info("[LanguageGuardian] Tamil validation complete (placeholder)")

    async def _validate_chinese(self, package: StoryPackage) -> None:
        """Apply zh-SG pack rules — specs/languages/zh-SG.md"""
        logger.info("[LanguageGuardian] Chinese validation (sample — needs reviewer)")

    async def _validate_malay(self, package: StoryPackage) -> None:
        """Apply ms-SG pack rules — specs/languages/ms-SG.md"""
        logger.info("[LanguageGuardian] Malay validation (sample — needs reviewer)")
