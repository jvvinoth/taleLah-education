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
from ..schemas.story_package import StoryPackage, ValidationStatus, VocabWord
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

        # The hero's name, settled once. Left to each scene, a transliterated
        # name comes back spelled differently every time.
        if package.story.hero_name and not package.story.hero_name_target_lang:
            try:
                result = await self._translate(
                    llm,
                    f"Write this child's name in {language} script, the way it "
                    f"would be said at home: {package.story.hero_name}",
                    system,
                    locale,
                    language,
                )
                package.story.hero_name_target_lang = str(
                    result.get("translated", "")
                ).strip()
            except Exception as e:
                logger.error(f"[LanguageGuardian] Hero name translation failed: {e}")

        # The refrain is the line the child chants along with, so it must be
        # translated ONCE and then reused word for word in every scene.
        if package.story.refrain and not package.story.refrain_target_lang:
            try:
                result = await self._translate(
                    llm,
                    f"Translate this sing-song line a child will chant along with. "
                    f"Keep it short and easy to say: {package.story.refrain}",
                    system,
                    locale,
                    language,
                )
                package.story.refrain_target_lang = result.get("translated", "")
            except Exception as e:
                logger.error(f"[LanguageGuardian] Refrain translation failed: {e}")

        # Translate the scenes in order, each call carrying the story so far.
        # One isolated call per scene cannot see the hero's name or the refrain
        # it chose last time, so the home-language story drifts apart even when
        # the English holds together.
        try:
            await self._translate_scenes(package, llm, system, locale, language)
        except Exception as e:
            logger.error(f"[LanguageGuardian] Scene translation failed: {e}")

        # Chapter titles — nice to have, never a reason to block the story.
        try:
            await self._translate_scene_titles(package, llm, system, locale, language)
        except Exception as e:
            logger.error(f"[LanguageGuardian] Chapter titles failed: {e}")

        # Any scene the pass could not render must still not reach a child as
        # English — mark it so validation catches it and the parent regenerates.
        for scene in package.story.scenes:
            if scene.narration and not scene.narration_target_lang:
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

        # Words to learn — translate the plan's target words so Mina can teach
        # them one by one (child taps a word chip → hears it → repeats it).
        if package.learning_plan and not package.story.vocabulary:
            try:
                package.story.vocabulary = await self._translate_vocabulary(
                    llm, package.learning_plan.target_words, system, locale, language
                )
            except Exception as e:
                logger.error(f"[LanguageGuardian] Vocabulary translation failed: {e}")

        logger.info(f"[LanguageGuardian] {language} translation complete for all scenes")

    async def _translate_scenes(
        self, package: StoryPackage, llm, system: str, locale: str, language: str
    ) -> None:
        """Translate the scenes one at a time, in order, handing each call the
        story so far: the hero's name as already spelled, the refrain word for
        word, and how the previous scene ended. A small native-language model
        renders one scene beautifully but cannot hold a whole story in a single
        JSON answer — so the continuity is carried in, not asked for."""
        scenes = [s for s in package.story.scenes if s.narration]
        if not scenes:
            return

        story = package.story
        refrain = story.refrain_target_lang or story.refrain
        done = 0
        for i, scene in enumerate(scenes):
            if scene.narration_target_lang:
                continue

            lines = [f"This is scene {i + 1} of {len(scenes)} of one story for a "
                     f"young child, told out loud by a grandmother."]
            if story.hero_name and story.hero_name_target_lang:
                lines.append(
                    f"The child in the story is called {story.hero_name}. Write "
                    f"that name as exactly {story.hero_name_target_lang} every "
                    f"time it appears — never a different spelling."
                )
            if i > 0 and scenes[i - 1].narration_target_lang:
                lines.append(
                    f"The scene before it ended like this — keep the same voice, "
                    f"and spell every name exactly the same way:\n"
                    f"{scenes[i - 1].narration_target_lang}"
                )
            if story.refrain and story.refrain.lower() in scene.narration.lower():
                lines.append(
                    f"This scene repeats the story's chant. Write it with exactly "
                    f"these words, unchanged: {refrain}"
                )
            lines.append(
                "Keep the warm spoken voice, the sound words, and the questions "
                "asked straight to the child. Keep it the same length — do not "
                "shorten it to one sentence."
            )
            lines.append(f"Translate for a child to hear:\n{scene.narration}")

            try:
                result = await self._translate(
                    llm, "\n\n".join(lines), system, locale, language
                )
            except Exception as e:
                logger.error(f"[LanguageGuardian] Scene {i} translation failed: {e}")
                continue

            translated = str(result.get("translated", "")).strip()
            if not translated or not self._in_native_script(translated, locale):
                continue
            scene.narration_target_lang = translated
            done += 1

        logger.info(
            f"[LanguageGuardian] Scenes: {done}/{len(scenes)} rendered in {language}"
        )

    async def _translate_scene_titles(
        self, package: StoryPackage, llm, system: str, locale: str, language: str
    ) -> None:
        """Chapter titles in one short batch call — they are a handful of words
        each, so they fit in one answer where whole scenes do not. A title that
        comes back romanised or empty is dropped; child mode then shows the
        story's own title instead of bad script."""
        scenes = [s for s in package.story.scenes if s.title and not s.title_target_lang]
        if not scenes:
            return
        numbered = "\n".join(f"{i + 1}. {s.title}" for i, s in enumerate(scenes))
        result = await llm.generate_json(
            prompt=(
                f"These are the chapter titles of one children's story called "
                f"\"{package.story.title}\". Translate each one as a short, "
                f"storybook chapter name a child could read:\n{numbered}\n\n"
                'Respond with JSON: {"titles": ["<native script>", ...]} '
                "in the same order."
            ),
            system=system,
        )
        titles = result.get("titles") or []
        for scene, title in zip(scenes, titles):
            text = str(title).strip()
            if self._is_clean_label(text, locale):
                scene.title_target_lang = text

    def _is_clean_label(self, text: str, locale: str) -> bool:
        """Stricter than _in_native_script, for the short things a child reads on
        its own: a chapter title or a word chip. Narration may carry the English
        words a Singapore family really says, but a two-word label that comes
        back half-transliterated ("ஓத்த கீழ்லukku") is just broken text on
        the page, so any Latin letter disqualifies it."""
        if not text:
            return False
        if any("a" <= c.lower() <= "z" for c in text):
            return False
        return self._in_native_script(text, locale)

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
        romanised/Latin text (unreadable for a child learning the script), or
        does not answer usably at all, retry once. A scene that comes back empty
        would otherwise reach the parent as a bracketed placeholder."""
        result = await llm.generate_json(prompt=prompt, system=system)
        translated = result.get("translated", "")
        if not translated:
            logger.warning("[LanguageGuardian] Empty translation, retrying")
            note = (
                "IMPORTANT: your previous answer could not be read. Reply with "
                'ONLY the JSON object {"translated": ..., "romanised": ..., '
                '"english_gloss": ...} and nothing else.'
            )
        elif not self._in_native_script(translated, locale):
            logger.warning(
                f"[LanguageGuardian] Romanised output detected, retrying in script: "
                f"{translated[:50]!r}"
            )
            note = (
                f"IMPORTANT: your previous answer used Latin letters. "
                f'Write "translated" ONLY in {language} script characters.'
            )
        else:
            return result
        return await llm.generate_json(prompt=f"{prompt}\n\n{note}", system=system)

    async def _translate_vocabulary(
        self, llm, words: list[str], system: str, locale: str, language: str
    ) -> list[VocabWord]:
        """Translate the target words in one batch call → VocabWord list.
        Words that come back romanised or empty are dropped — a bad chip
        teaches the child the wrong thing. The prompt stays deliberately short:
        asked for the "everyday spoken form, not the dictionary form", the
        native model returned தாழ்ச்சி (humiliation) for "clean"."""
        if not words:
            return []
        numbered = "\n".join(f"{i + 1}. {w}" for i, w in enumerate(words))
        result = await llm.generate_json(
            prompt=(
                f"Translate each word for a child to learn:\n{numbered}\n\n"
                'Respond with JSON: {"words": [{"word": "<English>", '
                '"translated": "<native script>", "romanised": "<pronunciation>"}]} '
                "in the same order."
            ),
            system=system,
        )
        vocab: list[VocabWord] = []
        for i, item in enumerate((result.get("words") or [])[: len(words)]):
            if not isinstance(item, dict):
                continue
            translated = str(item.get("translated", "")).strip()
            if not self._is_clean_label(translated, locale):
                continue
            vocab.append(VocabWord(
                word=str(item.get("word", "")).strip() or words[i],
                word_target_lang=translated,
                romanised=str(item.get("romanised", "")).strip(),
            ))
        logger.info(
            f"[LanguageGuardian] Vocabulary: {len(vocab)}/{len(words)} words in {language}"
        )
        return vocab

    async def ensure_vocabulary(self, package: StoryPackage) -> bool:
        """Backfill Words-to-learn for stories approved before vocabulary
        existed (session-start self-heal). Returns True when words were added
        — the caller should then regenerate the media manifest."""
        if package.story.vocabulary or not package.learning_plan:
            return False
        pack = pack_loader.get(package.language.locale)
        llm, _ = self._llm_for(package)
        if not pack or not llm:
            return False
        system = TRANSLATE_SYSTEM_PROMPT.format(
            language=pack.guardian.spoken_language,
            register_notes=pack.guardian.register_notes,
            cultural_notes=pack.guardian.cultural_notes,
        )
        try:
            package.story.vocabulary = await self._translate_vocabulary(
                llm,
                package.learning_plan.target_words,
                system,
                package.language.locale,
                pack.guardian.spoken_language,
            )
        except Exception as e:
            logger.error(f"[LanguageGuardian] Vocabulary backfill failed: {e}")
            return False
        return bool(package.story.vocabulary)

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
