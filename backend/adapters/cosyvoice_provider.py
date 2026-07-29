"""
DashScope (Alibaba Cloud) speech adapters for Mandarin — zh-SG pack.

- CosyVoice  → TTS  (Family Voice Director narration)
- Paraformer → ASR  (bounded child speech + parent voice-note capture)

Both use the official `dashscope` SDK (a declared dependency). The SDK is
imported lazily inside methods so the rest of the backend still boots if the
package or an API key is absent — the pipeline then falls back to text-only /
picture-choice, exactly as it does for the other locales.
"""
from __future__ import annotations

import asyncio
import logging
import os
import tempfile

from .audio_format import sniff_audio_format as _sniff_audio_format
from .interfaces import ASRProvider, TTSProvider

logger = logging.getLogger(__name__)

# International vs China endpoints — mirror whatever region the LLM base_url
# points at so a single account/key works for text, vision AND speech.
_INTL_HTTP = "https://dashscope-intl.aliyuncs.com/api/v1"
_INTL_WS = "wss://dashscope-intl.aliyuncs.com/api-ws/v1/inference"

# CosyVoice voice options (Mandarin). longxiaochun is a warm, child-friendly voice.
COSYVOICE_VOICES = {
    "zh-female": "longxiaochun",
    "zh-male": "longshu",
    "default": "longxiaochun",
}


def _configure_region(api_key: str, base_url: str) -> None:
    """Point the dashscope SDK at the same region as the configured base_url."""
    import dashscope

    dashscope.api_key = api_key
    if "intl" in (base_url or ""):
        dashscope.base_http_api_url = _INTL_HTTP
        dashscope.base_websocket_api_url = _INTL_WS


class CosyVoiceTTSProvider(TTSProvider):
    """CosyVoice text-to-speech via DashScope — Mandarin narration."""

    def __init__(self, api_key: str, base_url: str = "", model: str = "cosyvoice-v1"):
        self.api_key = api_key
        self.base_url = base_url
        self.model = model

    async def synthesize(
        self,
        text: str,
        language: str = "zh",
        voice_id: str = "",
        speed: float = 1.0,
    ) -> bytes:
        loop = asyncio.get_event_loop()
        return await loop.run_in_executor(
            None, self._synthesize_sync, text, voice_id, speed
        )

    def _synthesize_sync(self, text: str, voice_id: str, speed: float) -> bytes:
        _configure_region(self.api_key, self.base_url)
        from dashscope.audio.tts_v2 import AudioFormat, SpeechSynthesizer

        voice = voice_id or COSYVOICE_VOICES["default"]
        synthesizer = SpeechSynthesizer(
            model=self.model,
            voice=voice,
            format=AudioFormat.WAV_16000HZ_MONO_16BIT,
            speech_rate=speed,
        )
        audio = synthesizer.call(text)
        if not audio:
            raise ValueError("CosyVoice returned no audio")
        logger.info(f"[CosyVoice TTS] Generated {len(audio)} bytes for {voice}")
        return audio

    async def get_audio_url(
        self,
        text: str,
        language: str = "zh",
        voice_id: str = "",
    ) -> str:
        import base64

        audio = await self.synthesize(text, language, voice_id)
        b64 = base64.b64encode(audio).decode()
        return f"data:audio/wav;base64,{b64}"


class ParaformerASRProvider(ASRProvider):
    """Paraformer speech-to-text via DashScope — Mandarin transcription."""

    def __init__(self, api_key: str, base_url: str = "", model: str = "paraformer-realtime-v2"):
        self.api_key = api_key
        self.base_url = base_url
        self.model = model

    async def transcribe(
        self,
        audio_bytes: bytes,
        language: str = "zh",
        sample_rate: int = 16000,
    ) -> str:
        loop = asyncio.get_event_loop()
        return await loop.run_in_executor(
            None, self._transcribe_sync, audio_bytes, language, sample_rate
        )

    def _transcribe_sync(self, audio_bytes: bytes, language: str, sample_rate: int) -> str:
        _configure_region(self.api_key, self.base_url)
        from dashscope.audio.asr import Recognition

        # Recognition.call reads a file path — persist the clip briefly, then
        # remove it (raw audio is never retained beyond intent extraction).
        fmt = _sniff_audio_format(audio_bytes)
        tmp = tempfile.NamedTemporaryFile(suffix=f".{fmt}", delete=False)
        try:
            tmp.write(audio_bytes)
            tmp.flush()
            tmp.close()
            recognition = Recognition(
                model=self.model,
                format=fmt,
                sample_rate=sample_rate,
                language_hints=[language.split("-")[0] or "zh"],
                callback=None,
            )
            result = recognition.call(tmp.name)
        finally:
            try:
                os.unlink(tmp.name)
            except OSError:
                pass

        sentences = []
        try:
            for sentence in result.get_sentence() or []:
                text = sentence.get("text", "") if isinstance(sentence, dict) else ""
                if text:
                    sentences.append(text)
        except Exception as e:  # noqa: BLE001 — defensive over SDK result shape
            logger.warning(f"[Paraformer ASR] Could not read result: {e}")
        transcript = "".join(sentences)
        logger.info(f"[Paraformer ASR] Transcribed: {transcript[:50]}...")
        return transcript

