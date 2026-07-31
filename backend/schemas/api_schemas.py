"""API request/response schemas."""
from __future__ import annotations

from datetime import datetime
from typing import Literal, Optional

from pydantic import BaseModel, Field

from .story_package import (
    ConfidenceLevel,
    FamilyVoiceMode,
    InputType,
    StoryPackage,
    StoryStatus,
)


# ── Auth ───────────────────────────────────────────────────────────────────

class AdultRegister(BaseModel):
    email: str
    display_name: str
    preferred_ui_language: str = "en"


class AdultSignup(BaseModel):
    email: str = Field(
        min_length=5, max_length=254, pattern=r"^[^@\s]+@[^@\s]+\.[^@\s]+$"
    )
    password: str = Field(min_length=8, max_length=128)
    display_name: str = Field(min_length=1, max_length=60)
    preferred_ui_language: str = "en"


class EmailVerify(BaseModel):
    email: str
    code: str = Field(min_length=6, max_length=6, pattern=r"^\d{6}$")


class AdultLogin(BaseModel):
    email: str
    password: str = Field(min_length=1, max_length=128)


class ForgotPassword(BaseModel):
    email: str


class ResetPassword(BaseModel):
    email: str
    code: str = Field(min_length=6, max_length=6, pattern=r"^\d{6}$")
    new_password: str = Field(min_length=8, max_length=128)


class ChangePassword(BaseModel):
    current_password: str = Field(min_length=1, max_length=128)
    new_password: str = Field(min_length=8, max_length=128)


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    adult_id: str


class MeResponse(BaseModel):
    id: str
    email: str
    display_name: str
    email_verified: bool


# ── Child Profile ──────────────────────────────────────────────────────────

class ChildProfileCreate(BaseModel):
    alias: str = Field(min_length=1, max_length=50)
    age_band: str = Field(pattern=r"^[4-8](-[5-8])?$")
    target_locale: str = "ta-SG"
    home_language: str = "en"
    understanding_level: ConfidenceLevel = ConfidenceLevel.EMERGING
    speaking_level: ConfidenceLevel = ConfidenceLevel.EMERGING
    interests: list[str] = []


class ChildProfileUpdate(BaseModel):
    alias: Optional[str] = Field(default=None, min_length=1, max_length=50)
    age_band: Optional[str] = Field(default=None, pattern=r"^[4-8](-[5-8])?$")
    home_language: Optional[str] = None
    target_locale: Optional[str] = None


class ChildProfileResponse(BaseModel):
    id: str
    alias: str
    age_band: str
    target_locale: str
    home_language: str = "en"
    photo_url: Optional[str] = None
    understanding_level: ConfidenceLevel
    speaking_level: ConfidenceLevel
    interests: list[str]


# ── Community Events ───────────────────────────────────────────────────────

class CommunityEvent(BaseModel):
    """One language-based kids event a family can join."""
    id: str
    title: str
    description: str = ""
    language: str = "en"  # ta / zh / ms / en
    date: str = ""        # ISO date, e.g. "2026-08-01"
    time: str = ""        # e.g. "10:30 AM"
    venue: str = ""
    age_range: str = ""   # e.g. "4-8"
    organizer: str = ""
    registration_url: str = ""
    is_free: bool = True


# ── Family Speaker ─────────────────────────────────────────────────────────

class FamilySpeakerCreate(BaseModel):
    relationship_label: str
    mode: FamilyVoiceMode = FamilyVoiceMode.CONFIDENT
    language_confidence: str = ""
    is_remote: bool = False


# ── Moment Capture ─────────────────────────────────────────────────────────

class MomentCreateText(BaseModel):
    child_profile_id: str
    text: str = Field(max_length=500)


class MomentResponse(BaseModel):
    id: str
    child_profile_id: str
    input_type: InputType
    parent_text: str = ""
    status: str
    created_at: datetime


# ── Story Package ──────────────────────────────────────────────────────────

class StoryPackageResponse(BaseModel):
    id: str
    status: StoryStatus
    child_profile_id: str
    language_locale: str
    title: str = ""
    speaking_goal: str = ""
    target_phrase: str = ""
    scene_count: int = 0
    has_mission: bool = False
    has_handoff: bool = False
    validation_language: str = "pending"
    validation_safety: str = "pending"
    regeneration_count: int = 0
    created_at: datetime

    @classmethod
    def from_package(cls, pkg: StoryPackage) -> StoryPackageResponse:
        return cls(
            id=pkg.id,
            status=pkg.status,
            child_profile_id=pkg.child_profile_id,
            language_locale=pkg.language.locale,
            title=pkg.story.title,
            speaking_goal=pkg.learning_plan.speaking_goal if pkg.learning_plan else "",
            target_phrase=pkg.learning_plan.target_phrase if pkg.learning_plan else "",
            scene_count=len(pkg.story.scenes),
            has_mission=bool(pkg.story.room_mission.instruction),
            has_handoff=bool(pkg.story.family_handoff.prompt),
            validation_language=pkg.validation.language.value,
            validation_safety=pkg.validation.safety.value,
            regeneration_count=pkg.regeneration_count,
            created_at=pkg.created_at,
        )


class StoryPackageDetail(BaseModel):
    """Full package for parent review."""
    package: StoryPackage


class StoryPackageApproval(BaseModel):
    approved: bool = True
    edited_facts: Optional[list[dict]] = None
    edited_target_words: Optional[list[str]] = None
    notes: str = ""


# ── Parent Review & Edit (F2) ──────────────────────────────────────────────

class FactsUpdate(BaseModel):
    """Parent-corrected moment facts — replaces the extracted set."""
    facts: list[str] = Field(min_length=1, max_length=10)


class TargetWordSwap(BaseModel):
    """Swap one target word for another from the pack word bank."""
    old_word: str
    new_word: str


class DifficultyUpdate(BaseModel):
    """Adjust the learning plan difficulty level."""
    level: ConfidenceLevel


class RegenerateRequest(BaseModel):
    """Regenerate a single story component — hard cap 5 per package."""
    component: Literal["scene", "mission", "handoff"]
    scene_index: int = Field(default=0, ge=0, le=3)


class ClarifyRequest(BaseModel):
    """F3 — parent's answer to the one clarification question."""
    answer: str = Field(min_length=1, max_length=500)


class SpeechFallbackChoice(BaseModel):
    """F6 — picture-choice fallback tap (any choice celebrates)."""
    selected_word: str = ""


class SpeakRequest(BaseModel):
    """On-demand TTS for feedback Mina composes live (word tutoring).
    Length-bounded — a session speaks one short sentence, never an essay."""
    text: str = Field(min_length=1, max_length=200)


# ── Session ────────────────────────────────────────────────────────────────

class SessionStart(BaseModel):
    story_package_id: str


class SessionEvent(BaseModel):
    session_id: str
    event_type: str
    scene_index: int = 0
    metadata: dict = {}


class SessionSummary(BaseModel):
    session_id: str
    story_package_id: str
    target_phrase: str = ""
    speech_turn_completed: bool = False
    mission_completed: bool = False
    handoff_completed: bool = False
    duration_seconds: int = 0
    fallback_events: int = 0
    completed_at: Optional[datetime] = None
    # F11 — Growth Coach next-moment seed + parent encouragement
    next_moment_suggestion: str = ""
    encouragement: str = ""


class MemorySaveRequest(BaseModel):
    """F10 — saving a memory requires an explicit consent tick (default off)."""
    session_id: str
    consent: bool = False
    note: str = ""


# ── Generation ─────────────────────────────────────────────────────────────

class GenerationStatus(BaseModel):
    story_package_id: str
    status: StoryStatus
    current_agent: str = ""
    progress_pct: float = 0.0
    error: str = ""
