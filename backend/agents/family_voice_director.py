"""
Agent 5: Family Voice Director — specs/agents/5-family-voice-director.md

Produces the family handoff + all narration audio.
Adapts to whoever the household's speaker is.

Model: TTS adapter (pack-declared: Sarvam / CosyVoice / Google).
Reads: validated story, selected Family Voice mode, family confidence.
Writes: familyHandoff, media.narrationSegments.
"""
from __future__ import annotations

import base64
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
        """Resolve the primary TTS provider + language + voice (AC-08)."""
        chain = self._resolve_tts_chain(locale)
        return chain[0] if chain else (self.tts, "", "")

    def _resolve_tts_chain(
        self, locale: str
    ) -> list[tuple[TTSProvider, str, str]]:
        """Ordered (provider, language, voice) candidates from the pack —
        primary first, then the pack's declared fallback (AC-08). A provider
        that errors at call time (e.g. quota 402) hands over to the next."""
        chain: list[tuple[TTSProvider, str, str]] = []
        pack = pack_loader.get(locale)
        if pack:
            for cfg in (pack.providers.tts, pack.providers.tts_fallback):
                if cfg is None:
                    continue
                provider = self.tts_registry.get(cfg.provider)
                if provider:
                    chain.append((provider, cfg.language, cfg.voice_id))
                else:
                    logger.warning(
                        f"[FamilyVoiceDirector] Pack {locale} wants TTS "
                        f"'{cfg.provider}' but it is not registered — skipping"
                    )
        if not chain and self.tts:
            chain.append((self.tts, "", ""))
        return chain

    @staticmethod
    async def _synthesize_with(
        chain: list[tuple[TTSProvider, str, str]], text: str
    ) -> tuple[bytes, TTSProvider]:
        """Try each TTS candidate in order; return (audio, provider used)."""
        last_error: Exception = RuntimeError("no TTS provider available")
        for provider, language, voice in chain:
            try:
                if language:
                    audio = await provider.synthesize(
                        text, language=language, voice_id=voice
                    )
                else:
                    audio = await provider.synthesize(text)
                return audio, provider
            except Exception as e:
                logger.warning(
                    f"[FamilyVoiceDirector] TTS "
                    f"{provider.__class__.__name__} failed ({e}) — "
                    f"trying next provider"
                )
                last_error = e
        raise last_error

    async def execute(self, package: StoryPackage) -> StoryPackage:
        logger.info(f"[FamilyVoiceDirector] Preparing audio for package {package.id}")

        chain = self._resolve_tts_chain(package.language.locale)

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

            # Generate TTS audio if a provider is available
            if chain and text_to_speak:
                try:
                    audio, used = await self._synthesize_with(chain, text_to_speak)
                    mime = "audio/wav" if audio[:4] == b"RIFF" else "audio/mp3"
                    segment.audio_url = (
                        f"data:{mime};base64,{base64.b64encode(audio).decode()}"
                    )
                    segment.tts_provider = used.__class__.__name__.replace("Provider", "").lower()
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
        chain = self._resolve_tts_chain(package.language.locale)
        provider_name = "text_only"

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

        # Spoken feedback — Mina praises and gently corrects OUT LOUD, like a
        # parent would. Copy comes from the pack (AC-08); corrections teach
        # the scene's expected word without ever saying "wrong" (AC-04).
        pack = pack_loader.get(package.language.locale)
        if pack:
            copy = pack.child_copy
            if copy.celebration:
                items.append(("celebrate", "feedback", -1, "", copy.celebration[0]))
            if copy.encourage_retry:
                items.append(("encourage", "feedback", -1, "", copy.encourage_retry[0]))
            if copy.praise_reading:
                items.append(
                    ("praise_reading", "feedback", -1, "", copy.praise_reading[0])
                )
            if copy.gentle_correction:
                for scene in package.story.scenes:
                    intent = scene.interaction.expected_intent
                    words = pack.expected_intents.get(intent) or []
                    if scene.interaction.type == "speak" and words:
                        items.append((
                            f"correction_{scene.index}", "feedback", scene.index,
                            "", copy.gentle_correction.format(word=words[0]),
                        ))

        blobs: dict[str, bytes] = {}
        manifest: list[MediaAsset] = []
        for asset_id, kind, idx, text, text_tl in items:
            asset = MediaAsset(
                id=asset_id, kind=kind, scene_index=idx,
                text=text, text_target_lang=text_tl,
            )
            speak = text_tl or text
            if chain and speak:
                try:
                    audio, used = await self._synthesize_with(chain, speak)
                    provider_name = used.__class__.__name__.replace("Provider", "").lower()
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
