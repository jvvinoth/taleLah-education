"""
Language Pack loader — the F1 contract (AC-08).

All locale behaviour lives in versioned JSON packs under `backend/packs/`.
Agents and adapters read ONLY from the loaded pack — no locale literals in
application code. Adding or revising a language means editing a pack file,
never this module or any agent.
"""
from __future__ import annotations

import json
import logging
from pathlib import Path
from typing import Optional

from pydantic import BaseModel, Field

logger = logging.getLogger(__name__)

PACKS_DIR = Path(__file__).resolve().parent.parent / "packs"


# ── Pack schema ────────────────────────────────────────────────────────────

class SpeechProviderConfig(BaseModel):
    provider: str
    language: str
    voice_id: str = ""
    # Narration speed — children need a slower, storyteller pace. 1.0 is
    # the provider default; packs set ~0.85 (Sarvam pace / Google
    # speaking_rate / CosyVoice speech_rate all accept 0.5–2.0).
    pace: float = Field(default=1.0, ge=0.5, le=2.0)


class PackProviders(BaseModel):
    llm: str = "qwen"
    vision: str = "qwen"
    asr: SpeechProviderConfig
    tts: SpeechProviderConfig
    # Optional resilience chain — used when the primary provider errors at
    # call time (e.g. quota exhausted). Same shape as the primary entries.
    asr_fallback: Optional[SpeechProviderConfig] = None
    tts_fallback: Optional[SpeechProviderConfig] = None


class GuardianConfig(BaseModel):
    spoken_language: str
    register_notes: str = ""
    cultural_notes: str = ""


class WordBankEntry(BaseModel):
    word: str
    romanised: str
    english: str


class SpeechConfig(BaseModel):
    keyword_floor: float = Field(default=0.7, ge=0.0, le=1.0)
    max_attempts: int = 2
    normalization: str = "NFC"


class ChildCopy(BaseModel):
    celebration: list[str] = []
    encourage_retry: list[str] = []
    listen_prompt: str = ""
    # Constructive-feedback copy (AC-04 — always warm, never "wrong"):
    # gentle_correction teaches the expected word on a miss ({word} slot);
    # praise_reading celebrates the child reading a scene by themself;
    # reading_practice invites saying one missed word together ({word} slot).
    gentle_correction: str = ""
    praise_reading: list[str] = []
    reading_practice: str = ""
    # Word-practice tutoring (✨ Words to learn). Mina listens to the child
    # repeat one word and answers what she actually heard:
    #   word_perfect  — said it right ({word})
    #   word_close    — nearly there; names the syllable to fix ({word}, {part})
    #   word_retry    — quite different; models the word again ({word})
    #   word_unclear  — nothing audible; not the child's fault, ask again
    word_perfect: list[str] = []
    word_close: str = ""
    word_retry: str = ""
    word_unclear: str = ""


class FamilyCopy(BaseModel):
    """F9 — parent-facing handoff copy. Lives in the pack so no locale
    (or language-name) literal ever appears in application code."""
    say_together: str = ""
    confident_hint: str = ""
    learning_intro: str = ""
    coach_tip: str = ""
    response_label: str = ""


class LanguagePack(BaseModel):
    """A versioned language pack — the single source of locale behaviour."""
    pack_version: str
    locale: str
    language_name: str
    script: str
    providers: PackProviders
    guardian: GuardianConfig
    word_bank: list[WordBankEntry] = []
    expected_intents: dict[str, list[str]] = {}
    speech: SpeechConfig = SpeechConfig()
    child_copy: ChildCopy = ChildCopy()
    family_copy: FamilyCopy = FamilyCopy()
    placeholder_phrases: dict[str, str] = {}


# ── Loader ─────────────────────────────────────────────────────────────────

class PackLoader:
    """Loads and caches language packs from `backend/packs/*.json`."""

    def __init__(self, packs_dir: Path = PACKS_DIR):
        self.packs_dir = packs_dir
        self._packs: dict[str, LanguagePack] = {}

    def load_all(self) -> dict[str, LanguagePack]:
        """Load every pack file. Called once at startup; safe to re-call."""
        self._packs.clear()
        for path in sorted(self.packs_dir.glob("*.json")):
            try:
                data = json.loads(path.read_text(encoding="utf-8"))
                pack = LanguagePack(**data)
                self._packs[pack.locale] = pack
                logger.info(
                    f"📦 Loaded language pack {pack.locale} v{pack.pack_version} ({path.name})"
                )
            except Exception as e:
                logger.error(f"Failed to load pack {path.name}: {e}")
        return self._packs

    def get(self, locale: str) -> Optional[LanguagePack]:
        """Get the pack for a locale (lazy-loads on first access)."""
        if not self._packs:
            self.load_all()
        return self._packs.get(locale)

    def require(self, locale: str) -> LanguagePack:
        """Get the pack for a locale or raise — use inside the pipeline."""
        pack = self.get(locale)
        if pack is None:
            raise ValueError(
                f"No language pack for locale '{locale}'. "
                f"Available: {self.available_locales()}"
            )
        return pack

    def available_locales(self) -> list[str]:
        if not self._packs:
            self.load_all()
        return sorted(self._packs.keys())


# Singleton used across the backend
pack_loader = PackLoader()
