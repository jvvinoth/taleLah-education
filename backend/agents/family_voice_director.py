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

from ..schemas.story_package import (
    FamilyVoiceConfig,
    NarrationSegment,
    StoryPackage,
)
from .base import BaseAgent

logger = logging.getLogger(__name__)


class FamilyVoiceDirectorAgent(BaseAgent):
    name = "family_voice_director"
    spec_version = "1.0.0"

    async def execute(self, package: StoryPackage) -> StoryPackage:
        """
        Generate TTS narration segments and family handoff content.

        Rules (from spec):
        - One instruction at a time.
        - Adult role supports conversation, never tests the child.
        - Never assume a grandparent exists.
        - Preserve dignity for a learning parent.
        - Text fallback always exists if TTS is unavailable.
        """
        logger.info(f"[FamilyVoiceDirector] Preparing audio for package {package.id}")

        # Generate narration segments for each scene
        segments = []
        for scene in package.story.scenes:
            segment = NarrationSegment(
                scene_index=scene.index,
                tts_provider="placeholder",  # Will be resolved by adapter
                audio_url="",  # Will be filled by TTS adapter
                text=scene.narration,
                text_target_lang=scene.narration_target_lang,
            )
            segments.append(segment)

        package.media.narration_segments = segments

        # Record the TTS provider in provenance
        package.provenance.model_versions["tts"] = "placeholder"

        self._record_provenance(package)
        logger.info(f"[FamilyVoiceDirector] Generated {len(segments)} narration segments")
        return package
