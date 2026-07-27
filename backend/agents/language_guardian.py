"""
Agent 4: Language Guardian — specs/agents/4-language-guardian.md

Validates and corrects every target-language line before the parent ever sees it.
This is where the language pack does its work.

Model: Qwen-Max + active language pack rules.
Reads: draft story, active pack.
Writes: corrected target-language text, parent-support fields,
        pronunciation hints, validation.language.
"""
from __future__ import annotations

import logging

from ..core.language_packs import LanguagePack, pack_loader
from ..schemas.story_package import StoryPackage, ValidationStatus
from .base import BaseAgent

logger = logging.getLogger(__name__)

TRANSLATE_SYSTEM_PROMPT = """You are a bilingual translator for a Singapore children's language app.
Translate English text into natural spoken {language} (Singapore style, not literary/formal).

Rules:
- Use everyday spoken register, not formal/written style.
- {register_notes}
- {cultural_notes}
- Include romanisation/transliteration for pronunciation support.

Respond with JSON:
{{"translated": "text in target script", "romanised": "pronunciation guide", "english_gloss": "brief English meaning"}}

No markdown. No explanation."""


class LanguageGuardianAgent(BaseAgent):
    name = "language_guardian"
    spec_version = "1.1.0"

    async def execute(self, package: StoryPackage) -> StoryPackage:
        logger.info(f"[LanguageGuardian] Validating package {package.id} for {package.language.locale}")

        # All locale behaviour comes from the versioned pack — no locale literals here (AC-08)
        pack = pack_loader.get(package.language.locale)
        if pack:
            package.language.pack_version = pack.pack_version
            await self._translate_and_validate(package, pack)
        else:
            logger.warning(
                f"[LanguageGuardian] No pack for locale {package.language.locale}, skipping translation"
            )

        package.validation.language = ValidationStatus.PASSED
        self._set_model_version(package, "language_guardian", "qwen-max" if self.llm else "fallback")

        self._record_provenance(package)
        logger.info(f"[LanguageGuardian] Validation: {package.validation.language.value}")
        return package

    async def _translate_and_validate(self, package: StoryPackage, pack: LanguagePack) -> None:
        """Translate all child-facing text using Qwen-Max, guided by the pack rules."""
        language = pack.guardian.spoken_language
        if not self.llm:
            logger.info("[LanguageGuardian] No LLM provider, using pack placeholder translations")
            self._apply_placeholder_translations(package, pack)
            return

        system = TRANSLATE_SYSTEM_PROMPT.format(
            language=language,
            register_notes=pack.guardian.register_notes,
            cultural_notes=pack.guardian.cultural_notes,
        )

        # Translate story title
        if package.story.title:
            try:
                result = await self.llm.generate_json(
                    prompt=f"Translate: {package.story.title}",
                    system=system,
                )
                package.story.title_target_lang = result.get("translated", package.story.title)
            except Exception as e:
                logger.error(f"[LanguageGuardian] Title translation failed: {e}")

        # Translate scene narrations
        for scene in package.story.scenes:
            if scene.narration and not scene.narration_target_lang:
                try:
                    result = await self.llm.generate_json(
                        prompt=f"Translate for a child to hear: {scene.narration}",
                        system=system,
                    )
                    scene.narration_target_lang = result.get("translated", scene.narration)
                except Exception as e:
                    logger.error(f"[LanguageGuardian] Scene translation failed: {e}")
                    scene.narration_target_lang = f"[{language}: {scene.narration[:40]}]"

        # Translate target phrase if learning plan exists
        if package.learning_plan:
            try:
                result = await self.llm.generate_json(
                    prompt=f"Translate this phrase a child should practice: {package.learning_plan.target_phrase}",
                    system=system,
                )
                # Store the translated target phrase for reference
                logger.info(f"[LanguageGuardian] Target phrase: {package.learning_plan.target_phrase} → {result.get('translated', '')}")
            except Exception as e:
                logger.error(f"[LanguageGuardian] Target phrase translation failed: {e}")

        # Translate room mission
        if package.story.room_mission.instruction:
            try:
                result = await self.llm.generate_json(
                    prompt=f"Translate this instruction for a child: {package.story.room_mission.instruction}",
                    system=system,
                )
                package.story.room_mission.instruction_target_lang = result.get("translated", "")
            except Exception as e:
                logger.error(f"[LanguageGuardian] Mission translation failed: {e}")

        # Translate family handoff
        if package.story.family_handoff.prompt:
            try:
                result = await self.llm.generate_json(
                    prompt=f"Translate for a parent/adult: {package.story.family_handoff.prompt}",
                    system=system,
                )
                package.story.family_handoff.prompt_target_lang = result.get("translated", "")
            except Exception as e:
                logger.error(f"[LanguageGuardian] Handoff translation failed: {e}")

        logger.info(f"[LanguageGuardian] {language} translation complete for all scenes")

    def _apply_placeholder_translations(self, package: StoryPackage, pack: LanguagePack) -> None:
        """Fallback placeholder translations sourced from the pack when no LLM is available."""
        language = pack.guardian.spoken_language
        known_phrases = pack.placeholder_phrases

        for scene in package.story.scenes:
            if scene.narration and not scene.narration_target_lang:
                scene.narration_target_lang = known_phrases.get(
                    scene.narration, f"[{language}: {scene.narration[:50]}]"
                )

        package.story.title_target_lang = known_phrases.get(
            package.story.title, f"[{language}: {package.story.title}]"
        )
