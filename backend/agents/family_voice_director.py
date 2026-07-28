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
from ..core.language_packs import pack_loader
from ..schemas.story_package import (
    MediaAsset,
    NarrationSegment,
    StoryPackage,
)
from .base import BaseAgent

logger = logging.getLogger(__name__)


def _wav_duration_ms(data: bytes) -> int:
    """Duration of a PCM WAV from its header byte rate; 0 if unknown."""
    if len(data) > 44 and data[:4] == b"RIFF":
        try:
            byte_rate = int.from_bytes(data[28:32], "little")
            if byte_rate:
                return int((len(data) - 44) * 1000 / byte_rate)
        except Exception:
            pass
    return 0


class FamilyVoiceDirectorAgent(BaseAgent):
    name = "family_voice_director"
    spec_version = "1.2.0"

    def __init__(
        self,
        tts: Optional[TTSProvider] = None,
        tts_registry: Optional[dict[str, TTSProvider]] = None,
        **kwargs,
    ):
        super().__init__(**kwargs)
        self.tts = tts
        # provider name (from pack) → concrete TTS adapter
        self.tts_registry = tts_registry or {}

    def _resolve_tts(self, locale: str) -> tuple[Optional[TTSProvider], str, str]:
        """Resolve the TTS provider + language + voice from the active pack (AC-08)."""
        pack = pack_loader.get(locale)
        if pack:
            cfg = pack.providers.tts
            provider = self.tts_registry.get(cfg.provider)
            if provider:
                return provider, cfg.language, cfg.voice_id
            logger.warning(
                f"[FamilyVoiceDirector] Pack {locale} wants TTS '{cfg.provider}' "
                f"but it is not registered — falling back"
            )
        return self.tts, "", ""

    async def execute(self, package: StoryPackage) -> StoryPackage:
        logger.info(f"[FamilyVoiceDirector] Preparing audio for package {package.id}")

        tts, tts_language, tts_voice = self._resolve_tts(package.language.locale)

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
            if tts and text_to_speak:
                try:
                    if tts_language:
                        audio_url = await tts.get_audio_url(
                            text_to_speak, language=tts_language, voice_id=tts_voice
                        )
                    else:
                        audio_url = await tts.get_audio_url(text_to_speak)
                    segment.audio_url = audio_url
                    segment.tts_provider = tts.__class__.__name__.replace("Provider", "").lower()
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

    # ── F4 · TTS pre-generation on approval ──────────────────────────────

    async def pregenerate_manifest(self, package: StoryPackage) -> dict[str, bytes]:
        """Synthesize ALL scene/mission/handoff audio and attach a media manifest.

        Returns {filename: audio bytes} for the caller to store/serve.
        Assets that fail TTS keep url="" — the parent-read fallback.
        """
        tts, tts_language, tts_voice = self._resolve_tts(package.language.locale)
        provider_name = (
            tts.__class__.__name__.replace("Provider", "").lower() if tts else "text_only"
        )

        items: list[tuple[str, str, int, str, str]] = []
        for scene in package.story.scenes:
            items.append(
                (f"scene_{scene.index}", "scene", scene.index,
                 scene.narration, scene.narration_target_lang)
            )
        mission = package.story.room_mission
        if mission.instruction or mission.instruction_target_lang:
            items.append(("mission", "mission", -1,
                          mission.instruction, mission.instruction_target_lang))
        handoff = package.story.family_handoff
        if handoff.prompt or handoff.prompt_target_lang:
            items.append(("handoff", "handoff", -1,
                          handoff.prompt, handoff.prompt_target_lang))

        blobs: dict[str, bytes] = {}
        manifest: list[MediaAsset] = []
        for asset_id, kind, idx, text, text_tl in items:
            asset = MediaAsset(
                id=asset_id, kind=kind, scene_index=idx,
                text=text, text_target_lang=text_tl,
            )
            speak = text_tl or text
            if tts and speak:
                try:
                    if tts_language:
                        audio = await tts.synthesize(
                            speak, language=tts_language, voice_id=tts_voice
                        )
                    else:
                        audio = await tts.synthesize(speak)
                    ext = "wav" if audio[:4] == b"RIFF" else "mp3"
                    filename = f"{asset_id}.{ext}"
                    blobs[filename] = audio
                    asset.url = f"media/{package.id}/{filename}"
                    asset.duration_ms = _wav_duration_ms(audio)
                    asset.tts_provider = provider_name
                except Exception as e:
                    logger.error(
                        f"[FamilyVoiceDirector] Pre-gen TTS failed for {asset_id}: {e}"
                    )
            manifest.append(asset)

        package.media.manifest = manifest
        package.media.manifest_ready = True
        audio_count = sum(1 for a in manifest if a.url)
        logger.info(
            f"[FamilyVoiceDirector] Pre-generated manifest for {package.id}: "
            f"{audio_count}/{len(manifest)} assets with audio ({provider_name})"
        )
        return blobs
