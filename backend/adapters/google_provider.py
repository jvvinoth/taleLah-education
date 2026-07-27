"""
Google Cloud provider adapters — Malay ASR + TTS.
"""
from __future__ import annotations

import logging
from typing import Optional

from .interfaces import ASRProvider, TTSProvider

logger = logging.getLogger(__name__)

# Malay voice options
GOOGLE_MALAY_VOICES = {
    "ms-female": "ms-MY-Wavenet-A",
    "ms-male": "ms-MY-Wavenet-B",
    "default": "ms-MY-Wavenet-A",
}


class GoogleTTSProvider(TTSProvider):
    """Google Cloud Text-to-Speech — Malay narration."""

    def __init__(self, credentials_path: str = "", project_id: str = ""):
        self.credentials_path = credentials_path
        self.project_id = project_id
        self._client = None

    def _get_client(self):
        if self._client is None:
            import os
            if self.credentials_path:
                os.environ["GOOGLE_APPLICATION_CREDENTIALS"] = self.credentials_path
            from google.cloud import texttospeech
            self._client = texttospeech.TextToSpeechClient()
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

    def __init__(self, credentials_path: str = "", project_id: str = ""):
        self.credentials_path = credentials_path
        self.project_id = project_id
        self._client = None

    def _get_client(self):
        if self._client is None:
            import os
            if self.credentials_path:
                os.environ["GOOGLE_APPLICATION_CREDENTIALS"] = self.credentials_path
            from google.cloud import speech
            self._client = speech.SpeechClient()
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

        audio = speech_mod.RecognitionAudio(content=audio_bytes)
        config = speech_mod.RecognitionConfig(
            encoding=speech_mod.RecognitionConfig.AudioEncoding.LINEAR16,
            sample_rate_hertz=sample_rate,
            language_code=language,
        )

        response = client.recognize(config=config, audio=audio)
        transcript = ""
        for result in response.results:
            transcript += result.alternatives[0].transcript

        logger.info(f"[Google ASR] Transcribed: {transcript[:50]}...")
        return transcript
