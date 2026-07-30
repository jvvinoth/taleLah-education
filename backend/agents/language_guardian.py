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

# Native script ranges — a translation that comes back romanised ("Tanglish")
# is unreadable for a child learning the script. Latin-script locales skip this.
NATIVE_SCRIPT_RANGES = {
    "ta": (0x0B80, 0x0BFF),  # Tamil
    "zh": (0x4E00, 0x9FFF),  # CJK Unified Ideographs
}

TRANSLATE_SYSTEM_PROMPT = """You are a bilingual translator for a Singapore children's language app.
Translate English text into natural spoken {language} (Singapore style, not literary/formal).

Rules:
- Use everyday spoken register, not formal/written style.
- {register_notes}
- {cultural_notes}
- Include romanisation/transliteration for pronunciation support.
- "translated" MUST be written entirely in the native {language} script —
  children read it on screen. Romanised/Latin spellings go ONLY in "romanised".

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
        if not pack:
            # No pack means we cannot produce or verify the target language at
            # all — the story must NOT reach a child untranslated.
            logger.warning(
                f"[LanguageGuardian] No pack for locale {package.language.locale} — blocking"
            )
            package.validation.language = ValidationStatus.BLOCKED
            self._set_model_version(package, "language_guardian", "no-pack")
            self._record_provenance(package)
            return package

        package.language.pack_version = pack.pack_version
        # Pack-declared LLM — e.g. Tamil translations via Sarvam for quality
        llm, llm_name = self._llm_for(package)
        await self._translate_and_validate(package, pack, llm)

        # Only PASS if every child-facing line actually carries a real target
        # translation. Empty text or a bracketed `[language: ...]` placeholder
        # is a translation failure, not a pass — surface it as REVISE so the
        # parent regenerates instead of the child hearing English/gibberish.
        language = pack.guardian.spoken_language
        untranslated = self._untranslated_fields(package, language)
        if untranslated:
            package.validation.language = ValidationStatus.REVISE
            logger.warning(
                f"[LanguageGuardian] {len(untranslated)} field(s) not translated: "
                f"{untranslated} — marking REVISE"
            )
        else:
            package.validation.language = ValidationStatus.PASSED

        self._set_model_version(package, "language_guardian", llm_name if llm else "fallback")
        self._record_provenance(package)
        logger.info(f"[LanguageGuardian] Validation: {package.validation.language.value}")
        return package

    def _is_untranslated(self, text: str, language: str) -> bool:
        """A field is untranslated if it is empty or still a bracket placeholder."""
        if not text or not text.strip():
            return True
        return text.lstrip().startswith(f"[{language}:")

    def _untranslated_fields(self, package: StoryPackage, language: str) -> list[str]:
        """Names of the child-facing fields that lack a real target translation."""
        missing: list[str] = []
        if package.story.title and self._is_untranslated(
            package.story.title_target_lang, language
        ):
            missing.append("title")
        for scene in package.story.scenes:
            if scene.narration and self._is_untranslated(
                scene.narration_target_lang, language
            ):
                missing.append(f"scene[{scene.index}]")
        if package.story.room_mission.instruction and self._is_untranslated(
            package.story.room_mission.instruction_target_lang, language
        ):
            missing.append("room_mission")
        return missing

    async def _translate_and_validate(
        self, package: StoryPackage, pack: LanguagePack, llm
    ) -> None:
        """Translate all child-facing text with the pack's LLM, guided by the pack rules."""
        language = pack.guardian.spoken_language
        locale = package.language.locale
        if not llm:
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
                result = await self._translate(
                    llm, f"Translate: {package.story.title}", system, locale, language
                )
                package.story.title_target_lang = result.get("translated", package.story.title)
            except Exception as e:
                logger.error(f"[LanguageGuardian] Title translation failed: {e}")

        # Translate scene narrations
        for scene in package.story.scenes:
            if scene.narration and not scene.narration_target_lang:
                try:
                    result = await self._translate(
                        llm,
                        f"Translate for a child to hear: {scene.narration}",
                        system,
                        locale,
                        language,
                    )
                    scene.narration_target_lang = result.get("translated", scene.narration)
                except Exception as e:
                    logger.error(f"[LanguageGuardian] Scene translation failed: {e}")
                    scene.narration_target_lang = f"[{language}: {scene.narration[:40]}]"

        # Translate target phrase if learning plan exists
        if package.learning_plan:
            try:
                result = await self._translate(
                    llm,
                    f"Translate this phrase a child should practice: {package.learning_plan.target_phrase}",
                    system,
                    locale,
                    language,
                )
                # Store the translated target phrase for reference
                logger.info(f"[LanguageGuardian] Target phrase: {package.learning_plan.target_phrase} → {result.get('translated', '')}")
            except Exception as e:
                logger.error(f"[LanguageGuardian] Target phrase translation failed: {e}")

        # Translate room mission
        if package.story.room_mission.instruction:
            try:
                result = await self._translate(
                    llm,
                    f"Translate this instruction for a child: {package.story.room_mission.instruction}",
                    system,
                    locale,
                    language,
                )
                package.story.room_mission.instruction_target_lang = result.get("translated", "")
            except Exception as e:
                logger.error(f"[LanguageGuardian] Mission translation failed: {e}")

        # Translate family handoff
        if package.story.family_handoff.prompt:
            try:
                result = await self._translate(
                    llm,
                    f"Translate for a parent/adult: {package.story.family_handoff.prompt}",
                    system,
                    locale,
                    language,
                )
                package.story.family_handoff.prompt_target_lang = result.get("translated", "")
            except Exception as e:
                logger.error(f"[LanguageGuardian] Handoff translation failed: {e}")

        logger.info(f"[LanguageGuardian] {language} translation complete for all scenes")

    def _in_native_script(self, text: str, locale: str) -> bool:
        """True when the text is mostly written in the locale's native script."""
        rng = NATIVE_SCRIPT_RANGES.get(locale.split("-")[0])
        if rng is None:
            return True
        letters = [c for c in text if c.isalpha()]
        if not letters:
            return False
        native = sum(1 for c in letters if rng[0] <= ord(c) <= rng[1])
        return native / len(letters) >= 0.5

    async def _translate(
        self, llm, prompt: str, system: str, locale: str, language: str
    ) -> dict:
        """One translation call with a script guard — if the model answers in
        romanised/Latin text (unreadable for a child learning the script),
        retry once demanding the native script."""
        result = await llm.generate_json(prompt=prompt, system=system)
        translated = result.get("translated", "")
        if translated and not self._in_native_script(translated, locale):
            logger.warning(
                f"[LanguageGuardian] Romanised output detected, retrying in script: "
                f"{translated[:50]!r}"
            )
            result = await llm.generate_json(
                prompt=(
                    f"{prompt}\n\nIMPORTANT: your previous answer used Latin letters. "
                    f"Write \"translated\" ONLY in {language} script characters."
                ),
                system=system,
            )
        return result

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
