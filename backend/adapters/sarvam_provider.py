"""
Sarvam AI provider adapters — Tamil ASR (Saarika) + TTS (Bulbul).
"""
from __future__ import annotations

import base64
import logging

import httpx

from .interfaces import ASRProvider, TTSProvider

logger = logging.getLogger(__name__)

SARVAM_API_URL = "https://api.sarvam.ai"

# Bulbul v2 compatible voices
SARVAM_TTS_VOICES = {
    "ta-female": "anushka",
    "ta-male": "abhilash",
    "default": "anushka",
}


class SarvamTTSProvider(TTSProvider):
    """Sarvam Bulbul v2 — Tamil text-to-speech."""

    def __init__(self, api_key: str):
        self.api_key = api_key
        self._client = httpx.AsyncClient(timeout=30.0)

    async def synthesize(
        self,
        text: str,
        language: str = "ta-IN",
        voice_id: str = "",
        speed: float = 1.0,
    ) -> bytes:
        speaker = voice_id or SARVAM_TTS_VOICES["default"]
        if speaker not in ("anushka", "abhilash", "manisha", "vidya", "arya", "karun", "hitesh"):
            speaker = "anushka"

        resp = await self._client.post(
            f"{SARVAM_API_URL}/text-to-speech",
            headers={"api-subscription-key": self.api_key},
            json={
                "inputs": [text],
                "target_language_code": language,
                "speaker": speaker,
            },
        )
        resp.raise_for_status()
        data = resp.json()

        if "audios" in data and data["audios"]:
            audio_bytes = base64.b64decode(data["audios"][0])
            logger.info(f"[Sarvam TTS] Generated {len(audio_bytes)} bytes for {speaker}")
            return audio_bytes

        raise ValueError(f"Sarvam TTS failed: {data}")

    async def get_audio_url(
        self,
        text: str,
        language: str = "ta-IN",
        voice_id: str = "",
    ) -> str:
        # Sarvam returns base64, not a URL. Synthesize and save locally.
        audio = await self.synthesize(text, language, voice_id)
        # For now, return base64 data URI
        b64 = base64.b64encode(audio).decode()
        return f"data:audio/wav;base64,{b64}"

    async def close(self):
        await self._client.aclose()


class SarvamASRProvider(ASRProvider):
    """Sarvam Saarika v2 — Tamil speech-to-text."""

    def __init__(self, api_key: str):
        self.api_key = api_key
        self._client = httpx.AsyncClient(timeout=30.0)

    async def transcribe(
        self,
        audio_bytes: bytes,
        language: str = "ta-IN",
        sample_rate: int = 16000,
    ) -> str:
        # Sarvam expects file upload as multipart
        resp = await self._client.post(
            f"{SARVAM_API_URL}/speech-to-text",
            headers={"api-subscription-key": self.api_key},
            data={
                "model": "saarika:v2",
                "language_code": language,
            },
            files={"file": ("audio.wav", audio_bytes, "audio/wav")},
        )
        resp.raise_for_status()
        data = resp.json()

        transcript = data.get("transcript", "")
        logger.info(f"[Sarvam ASR] Transcribed: {transcript[:50]}...")
        return transcript

    async def close(self):
        await self._client.aclose()


class SarvamTranslateProvider:
    """Sarvam Translate — English ↔ Indian language translation."""

    def __init__(self, api_key: str):
        self.api_key = api_key
        self._client = httpx.AsyncClient(timeout=15.0)

    async def translate(
        self,
        text: str,
        source_lang: str = "en-IN",
        target_lang: str = "ta-IN",
    ) -> str:
        resp = await self._client.post(
            f"{SARVAM_API_URL}/translate",
            headers={"api-subscription-key": self.api_key},
            json={
                "input": text,
                "source_language_code": source_lang,
                "target_language_code": target_lang,
            },
        )
        resp.raise_for_status()
        data = resp.json()
        return data.get("translated_text", "")

    async def close(self):
        await self._client.aclose()
