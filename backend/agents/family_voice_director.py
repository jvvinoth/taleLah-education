"""
Agent 5: Family Voice Director — specs/agents/5-family-voice-director.md

Produces the family handoff + all narration audio.
Adapts to whoever the household's speaker is.

Model: TTS adapter (pack-declared: Sarvam / CosyVoice / Google).
Reads: validated story, selected Family Voice mode, family confidence.
Writes: familyHandoff, media.narrationSegments.
"""
from __future__ import annotations

import logging
from typing import Optional

from ..adapters.interfaces import TTSProvider
from ..schemas.story_package import (
    FamilyVoiceConfig,
    NarrationSegment,
    StoryPackage,
)
from .base import BaseAgent

logger = logging.getLogger(__name__)


class FamilyVoiceDirectorAgent(BaseAgent):
    name = "family_voice_director"
    spec_version = "1.1.0"

    def __init__(self, tts: Optional[TTSProvider] = None, **kwargs):
        super().__init__(**kwargs)
        self.tts = tts

    async def execute(self, package: StoryPackage) -> StoryPackage:
        logger.info(f"[FamilyVoiceDirector] Preparing audio for package {package.id}")

        segments = []
        tts_provider_name = "none"

        for scene in package.story.scenes:
            text_to_speak = scene.narration_target_lang or scene.narration

            segment = NarrationSegment(
                scene_index=scene.index,
                tts_provider="pending",
                audio_url="",
                text=scene.narration,
                text_target_lang=scene.narration_target_lang,
            )

            # Generate TTS audio if provider is available
            if self.tts and text_to_speak:
                try:
                    audio_url = await self.tts.get_audio_url(text_to_speak)
                    segment.audio_url = audio_url
                    segment.tts_provider = self.tts.__class__.__name__.replace("Provider", "").lower()
                    tts_provider_name = segment.tts_provider
                    logger.debug(f"[FamilyVoiceDirector] Generated audio for scene {scene.index}")
                except Exception as e:
                    logger.error(f"[FamilyVoiceDirector] TTS failed for scene {scene.index}: {e}")
                    segment.tts_provider = "text_only"
            else:
                segment.tts_provider = "text_only"

            segments.append(segment)

        package.media.narration_segments = segments
        self._set_model_version(package, "tts", tts_provider_name)

        self._record_provenance(package)
        logger.info(f"[FamilyVoiceDirector] Generated {len(segments)} narration segments")
        return package
