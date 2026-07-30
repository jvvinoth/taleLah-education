"""
Sarvam AI provider adapters — Tamil ASR (Saarika) + TTS (Bulbul) + LLM.
"""
from __future__ import annotations

import base64
import json
import logging
from typing import Optional

import httpx

from .audio_format import extension_for, mime_for, sniff_audio_format
from .interfaces import ASRProvider, LLMProvider, TTSProvider

logger = logging.getLogger(__name__)

SARVAM_API_URL = "https://api.sarvam.ai"

# Bulbul speakers — the model version must match the speaker generation.
BULBUL_V2_SPEAKERS = {
    "anushka", "manisha", "vidya", "arya", "abhilash", "karun", "hitesh",
}
BULBUL_V3_SPEAKERS = {
    "shubh", "aditya", "ritu", "priya", "neha", "rahul", "pooja", "rohan",
    "simran", "kavya", "amit", "dev", "ishita", "shreya", "ratan", "varun",
    "manan", "sumit", "roopa", "kabir", "aayan", "ashutosh", "advait",
    "anand", "tanya", "tarun", "sunny", "mani", "gokul", "vijay", "shruti",
    "suhani", "mohit", "kavitha", "rehan", "soham", "rupali",
}
DEFAULT_SPEAKER = "kavitha"  # warm storyteller voice (bulbul:v3)


class SarvamTTSProvider(TTSProvider):
    """Sarvam Bulbul — Tamil text-to-speech (v2/v3 auto-picked per speaker)."""

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
        speaker = voice_id or DEFAULT_SPEAKER
        if speaker not in BULBUL_V2_SPEAKERS | BULBUL_V3_SPEAKERS:
            speaker = DEFAULT_SPEAKER
        model = "bulbul:v2" if speaker in BULBUL_V2_SPEAKERS else "bulbul:v3"

        resp = await self._client.post(
            f"{SARVAM_API_URL}/text-to-speech",
            headers={"api-subscription-key": self.api_key},
            json={
                "inputs": [text],
                "target_language_code": language,
                "speaker": speaker,
                "model": model,
                # Storyteller pace for children (Sarvam range 0.5–2.0)
                "pace": max(0.5, min(2.0, speed)),
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
    """Sarvam Saarika v2.5 — Tamil speech-to-text."""

    def __init__(self, api_key: str):
        self.api_key = api_key
        self._client = httpx.AsyncClient(timeout=30.0)

    async def transcribe(
        self,
        audio_bytes: bytes,
        language: str = "ta-IN",
        sample_rate: int = 16000,
    ) -> str:
        # Don't trust the client's filename — sniff the real container so
        # webm/ogg mic recordings aren't mislabelled as wav (would 400/garble).
        fmt = sniff_audio_format(audio_bytes)
        filename = f"audio.{extension_for(fmt)}"
        # Sarvam expects file upload as multipart
        resp = await self._client.post(
            f"{SARVAM_API_URL}/speech-to-text",
            headers={"api-subscription-key": self.api_key},
            data={
                "model": "saarika:v2.5",
                "language_code": language,
            },
            files={"file": (filename, audio_bytes, mime_for(fmt))},
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


class SarvamLLMProvider(LLMProvider):
    """Sarvam-105B chat completions — native-quality Indic story text.

    The model is a reasoner: content arrives alongside reasoning_content,
    so the token budget must cover both and reasoning is kept low. Any
    failure is delegated to the fallback LLM (Qwen) so a story never
    degrades to static copy.
    """

    # Starter-tier hard cap — requests above this are rejected with 400.
    MAX_TOKENS_CAP = 4096

    def __init__(
        self,
        api_key: str,
        model: str = "sarvam-105b",
        fallback: Optional[LLMProvider] = None,
    ):
        self.api_key = api_key
        self.model = model
        self.fallback = fallback
        self._client = httpx.AsyncClient(timeout=90.0)

    async def generate(
        self,
        prompt: str,
        system: str = "",
        temperature: float = 0.7,
        max_tokens: int = 2000,
        response_format: Optional[dict] = None,
    ) -> str:
        try:
            return await self._generate_sarvam(
                prompt, system, temperature, max_tokens, response_format
            )
        except Exception as e:
            if self.fallback:
                logger.warning(f"[Sarvam LLM] Falling back to default LLM: {e}")
                return await self.fallback.generate(
                    prompt=prompt,
                    system=system,
                    temperature=temperature,
                    max_tokens=max_tokens,
                    response_format=response_format,
                )
            raise

    async def _generate_sarvam(
        self,
        prompt: str,
        system: str,
        temperature: float,
        max_tokens: int,
        response_format: Optional[dict],
    ) -> str:
        messages = []
        if system:
            messages.append({"role": "system", "content": system})
        messages.append({"role": "user", "content": prompt})

        body = {
            "model": self.model,
            "messages": messages,
            "temperature": temperature,
            # Reasoning tokens count against the budget — leave headroom so
            # the answer itself never gets truncated (finish_reason=length),
            # but stay under the subscription-tier ceiling.
            "max_tokens": min(max_tokens + 2000, self.MAX_TOKENS_CAP),
            "reasoning_effort": "low",
        }
        if response_format:
            body["response_format"] = response_format

        resp = await self._client.post(
            f"{SARVAM_API_URL}/v1/chat/completions",
            headers={"Authorization": f"Bearer {self.api_key}"},
            json=body,
        )
        resp.raise_for_status()
        data = resp.json()
        content = data["choices"][0]["message"].get("content") or ""
        if not content:
            raise ValueError("Sarvam LLM returned empty content")
        logger.info(f"[Sarvam LLM] Generated {len(content)} chars with {self.model}")
        return content

    async def generate_json(
        self,
        prompt: str,
        system: str = "",
        schema: Optional[dict] = None,
    ) -> dict:
        """Generate JSON — parses from response, handling markdown fences."""
        raw = await self.generate(
            prompt=prompt,
            system=system + "\n\nRespond ONLY with valid JSON. No markdown fences. No explanation.",
            temperature=0.3,
            max_tokens=3000,
        )

        text = raw.strip()
        if text.startswith("```"):
            lines = text.split("\n")
            lines = [ln for ln in lines[1:] if not ln.strip().startswith("```")]
            text = "\n".join(lines)

        try:
            result = json.loads(text)
            return result if isinstance(result, dict) else {"data": result}
        except json.JSONDecodeError:
            logger.warning("[Sarvam LLM] Failed to parse JSON, returning raw")
            return {"raw": text}

    async def close(self):
        await self._client.aclose()
