"""
Provider adapter interfaces — AGENTS.md rule: "Adapter interfaces:
LLMProvider, VisionProvider, ASRProvider, TTSProvider.
Language pack declares which concrete provider to use."

Language packs themselves live in `backend/packs/*.json` and are loaded by
`core.language_packs.pack_loader` (F1 / AC-08) — never hardcode locale
behaviour in this module.
"""
from __future__ import annotations

from abc import ABC, abstractmethod
from enum import Enum
from typing import Optional


class ProviderType(str, Enum):
    QWEN = "qwen"
    SARVAM = "sarvam"
    GOOGLE = "google"
    GEMINI = "gemini"
    COSYVOICE = "cosyvoice"
    ELEVENLABS = "elevenlabs"
    MOCK = "mock"


# ── LLM ────────────────────────────────────────────────────────────────────

class LLMProvider(ABC):
    """Text generation provider."""

    @abstractmethod
    async def generate(
        self,
        prompt: str,
        system: str = "",
        temperature: float = 0.7,
        max_tokens: int = 2000,
        response_format: Optional[dict] = None,
    ) -> str:
        """Generate text from a prompt."""
        ...

    @abstractmethod
    async def generate_json(
        self,
        prompt: str,
        system: str = "",
        schema: Optional[dict] = None,
    ) -> dict:
        """Generate structured JSON from a prompt."""
        ...


# ── Vision ─────────────────────────────────────────────────────────────────

class VisionProvider(ABC):
    """Image understanding provider."""

    @abstractmethod
    async def analyze_image(
        self,
        image_url: str,
        prompt: str = "Describe what you see.",
    ) -> str:
        """Analyze an image and return description."""
        ...

    @abstractmethod
    async def extract_facts(
        self,
        image_url: str,
        child_age: str = "",
    ) -> list[dict]:
        """Extract structured facts from an image."""
        ...


# ── Image Generation ────────────────────────────────────────────────────────

class ImageProvider(ABC):
    """Text-to-image generation provider."""

    @abstractmethod
    async def generate_image(
        self,
        prompt: str,
        negative_prompt: str = "",
        size: str = "1280*1280",
    ) -> str:
        """Generate an image from a text prompt. Returns the image URL."""
        ...


# ── ASR ────────────────────────────────────────────────────────────────────

class ASRProvider(ABC):
    """Speech-to-text provider for bounded child speech."""

    @abstractmethod
    async def transcribe(
        self,
        audio_bytes: bytes,
        language: str = "ta",
        sample_rate: int = 16000,
    ) -> str:
        """Transcribe audio to text."""
        ...


# ── TTS ────────────────────────────────────────────────────────────────────

class TTSProvider(ABC):
    """Text-to-speech provider for narration."""

    @abstractmethod
    async def synthesize(
        self,
        text: str,
        language: str = "ta",
        voice_id: str = "",
        speed: float = 1.0,
    ) -> bytes:
        """Synthesize text to audio bytes."""
        ...

    @abstractmethod
    async def get_audio_url(
        self,
        text: str,
        language: str = "ta",
        voice_id: str = "",
    ) -> str:
        """Get a URL for synthesized audio."""
        ...


# ── Fuzzy Intent Matcher ──────────────────────────────────────────────────

class IntentMatcher:
    """
    Bounded intent matching — AGENTS.md rule 9:
    'transcribe, then fuzzy-match against the pack's expected words/intents.
    Never require perfect open ASR.'
    """

    def __init__(self, expected_intents: dict[str, list[str]]):
        """
        Args:
            expected_intents: mapping of intent_name → list of keyword phrases
        """
        self.expected_intents = expected_intents

    def match(self, transcript: str, threshold: float = 0.4) -> tuple[str, float]:
        """
        Match a transcript against expected intents.
        Returns (intent_name, confidence).
        """
        transcript_lower = transcript.lower().strip()
        best_intent = ""
        best_score = 0.0

        for intent, keywords in self.expected_intents.items():
            for keyword in keywords:
                keyword_lower = keyword.lower().strip()
                # Simple substring match
                if keyword_lower in transcript_lower or transcript_lower in keyword_lower:
                    score = len(keyword_lower) / max(len(transcript_lower), 1)
                    score = min(score, 1.0)
                    if score > best_score:
                        best_score = score
                        best_intent = intent

        return best_intent, best_score

    def is_match(self, transcript: str, threshold: float = 0.4) -> bool:
        """Check if transcript matches any expected intent."""
        _, score = self.match(transcript, threshold)
        return score >= threshold


# ── Language Pack Config ──────────────────────────────────────────────────

# Language packs live in backend/packs/*.json, loaded by core.language_packs
# (F1 / AC-08). The old hardcoded LanguagePackConfig registry was removed.
