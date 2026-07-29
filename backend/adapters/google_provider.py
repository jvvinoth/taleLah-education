"""
Google Cloud provider adapters — Malay ASR + TTS.
"""
from __future__ import annotations

import logging

from .audio_format import sniff_audio_format
from .interfaces import ASRProvider, TTSProvider

logger = logging.getLogger(__name__)


def _google_credentials(credentials_json: str = "", credentials_path: str = ""):
    """Build service-account credentials from inline JSON (Railway env var) or a
    file path (local dev). Returns None to fall back to Application Default
    Credentials. Never logs or persists the secret material."""
    from google.oauth2 import service_account

    if credentials_json:
        import json
        return service_account.Credentials.from_service_account_info(
            json.loads(credentials_json)
        )
    if credentials_path:
        import os
        if os.path.exists(credentials_path):
            return service_account.Credentials.from_service_account_file(
                credentials_path
            )
    return None


# Malay voice options
GOOGLE_MALAY_VOICES = {
    "ms-female": "ms-MY-Wavenet-A",
    "ms-male": "ms-MY-Wavenet-B",
    "default": "ms-MY-Wavenet-A",
}


class GoogleTTSProvider(TTSProvider):
    """Google Cloud Text-to-Speech — Malay narration."""

    def __init__(self, credentials_path: str = "", project_id: str = "",
                 credentials_json: str = ""):
        self.credentials_path = credentials_path
        self.credentials_json = credentials_json
        self.project_id = project_id
        self._client = None

    def _get_client(self):
        if self._client is None:
            from google.cloud import texttospeech
            self._client = texttospeech.TextToSpeechClient(
                credentials=_google_credentials(self.credentials_json, self.credentials_path)
            )
            self._module = texttospeech
        return self._client

    async def synthesize(
        self,
        text: str,
        language: str = "ms-MY",
        voice_id: str = "",
        speed: float = 1.0,
    ) -> bytes:
        import asyncio
        loop = asyncio.get_event_loop()
        return await loop.run_in_executor(None, self._synthesize_sync, text, language, voice_id, speed)

    def _synthesize_sync(self, text: str, language: str, voice_id: str, speed: float) -> bytes:
        client = self._get_client()
        tts = self._module

        voice_name = voice_id or GOOGLE_MALAY_VOICES.get("default", "ms-MY-Wavenet-A")

        synthesis_input = tts.SynthesisInput(text=text)
        voice = tts.VoiceSelectionParams(
            language_code=language,
            name=voice_name,
            ssml_gender=tts.SsmlVoiceGender.FEMALE,
        )
        audio_config = tts.AudioConfig(
            audio_encoding=tts.AudioEncoding.MP3,
            speaking_rate=speed,
        )

        response = client.synthesize_speech(
            input=synthesis_input,
            voice=voice,
            audio_config=audio_config,
        )
        logger.info(f"[Google TTS] Generated {len(response.audio_content)} bytes for {voice_name}")
        return response.audio_content

    async def get_audio_url(
        self,
        text: str,
        language: str = "ms-MY",
        voice_id: str = "",
    ) -> str:
        import base64
        audio = await self.synthesize(text, language, voice_id)
        b64 = base64.b64encode(audio).decode()
        return f"data:audio/mp3;base64,{b64}"


class GoogleASRProvider(ASRProvider):
    """Google Cloud Speech-to-Text — Malay transcription."""

    def __init__(self, credentials_path: str = "", project_id: str = "",
                 credentials_json: str = ""):
        self.credentials_path = credentials_path
        self.credentials_json = credentials_json
        self.project_id = project_id
        self._client = None

    def _get_client(self):
        if self._client is None:
            from google.cloud import speech
            self._client = speech.SpeechClient(
                credentials=_google_credentials(self.credentials_json, self.credentials_path)
            )
            self._module = speech
        return self._client

    async def transcribe(
        self,
        audio_bytes: bytes,
        language: str = "ms-MY",
        sample_rate: int = 16000,
    ) -> str:
        import asyncio
        loop = asyncio.get_event_loop()
        return await loop.run_in_executor(None, self._transcribe_sync, audio_bytes, language, sample_rate)

    def _transcribe_sync(self, audio_bytes: bytes, language: str, sample_rate: int) -> str:
        client = self._get_client()
        speech_mod = self._module
        enc = speech_mod.RecognitionConfig.AudioEncoding

        # Browser mic clips are webm/ogg-opus, not raw LINEAR16 wav — sniff the
        # real container and pick the matching encoding so recognition works.
        fmt = sniff_audio_format(audio_bytes)
        encoding_map = {
            "webm": enc.WEBM_OPUS,
            "ogg": enc.OGG_OPUS,
            "flac": enc.FLAC,
            "mp3": enc.MP3,
            "wav": enc.LINEAR16,
        }
        encoding = encoding_map.get(fmt, enc.ENCODING_UNSPECIFIED)

        audio = speech_mod.RecognitionAudio(content=audio_bytes)
        config_kwargs = {
            "encoding": encoding,
            "language_code": language,
        }
        # Opus/WAV carry sample rate in the header; only send an explicit rate
        # for raw LINEAR16 where Google cannot infer it.
        if fmt == "wav":
            config_kwargs["sample_rate_hertz"] = sample_rate
        config = speech_mod.RecognitionConfig(**config_kwargs)

        response = client.recognize(config=config, audio=audio)
        transcript = ""
        for result in response.results:
            transcript += result.alternatives[0].transcript

        logger.info(f"[Google ASR] Transcribed: {transcript[:50]}...")
        return transcript

    async def transcribe_multilingual(
        self,
        audio_bytes: bytes,
        primary: str = "en-SG",
        alternates: list[str] | None = None,
    ) -> tuple[str, str]:
        """Auto-detect across `primary` + up to 3 `alternates` (Google's cap).
        Returns (transcript, detected_language). Used for parent moment capture
        where the spoken language is independent of the child's learning pack."""
        import asyncio
        loop = asyncio.get_event_loop()
        return await loop.run_in_executor(
            None, self._multi_sync, audio_bytes, primary, alternates or []
        )

    def _multi_sync(
        self, audio_bytes: bytes, primary: str, alternates: list[str]
    ) -> tuple[str, str]:
        client = self._get_client()
        speech_mod = self._module
        enc = speech_mod.RecognitionConfig.AudioEncoding

        fmt = sniff_audio_format(audio_bytes)
        encoding_map = {
            "webm": enc.WEBM_OPUS,
            "ogg": enc.OGG_OPUS,
            "flac": enc.FLAC,
            "mp3": enc.MP3,
            "wav": enc.LINEAR16,
        }
        encoding = encoding_map.get(fmt, enc.ENCODING_UNSPECIFIED)

        config_kwargs = {
            "encoding": encoding,
            "language_code": primary,
            "alternative_language_codes": alternates,
        }
        if fmt == "wav":
            config_kwargs["sample_rate_hertz"] = 16000
        config = speech_mod.RecognitionConfig(**config_kwargs)

        response = client.recognize(
            config=config,
            audio=speech_mod.RecognitionAudio(content=audio_bytes),
        )
        transcript = ""
        detected = primary
        for result in response.results:
            transcript += result.alternatives[0].transcript
            lang = getattr(result, "language_code", "")
            if lang:
                detected = lang
        logger.info(f"[Google ASR·multi] {detected}: {transcript[:50]}...")
        return transcript, detected
