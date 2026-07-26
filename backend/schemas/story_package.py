"""
Story Package Schema — The shared contract (specs/story-package.md).

Every agent reads and writes these structured objects.
Free-form agent prose must never pass directly into child mode.
"""
from __future__ import annotations

from datetime import datetime
from enum import Enum
from typing import List, Optional

from pydantic import BaseModel, Field


# ── Lifecycle ──────────────────────────────────────────────────────────────

class StoryStatus(str, Enum):
    CAPTURED = "captured"
    INTERPRETING = "interpreving"
    PLANNING = "planning"
    WRITING = "writing"
    VALIDATING = "validating"
    AWAITING_PARENT = "awaiting_parent"
    APPROVED = "approved"
    IN_SESSION = "in_session"
    COMPLETED = "completed"


class ValidationStatus(str, Enum):
    PENDING = "pending"
    PASSED = "passed"
    REVISE = "revise"
    BLOCKED = "blocked"


class FamilyVoiceMode(str, Enum):
    CONFIDENT = "confident"
    LEARNING = "learning"
    PRERECORDED = "prerecorded"


class InteractionType(str, Enum):
    CHOICE = "choice"
    SPEAK = "speak"


class InputType(str, Enum):
    TEXT = "text"
    VOICE = "voice"
    PHOTO = "photo"


class ConfidenceLevel(str, Enum):
    BEGINNING = "beginning"
    EMERGING = "emerging"
    GROWING = "growing"
    CONVERSATIONAL = "conversational"


# ── Sub-schemas ────────────────────────────────────────────────────────────

class MomentFact(BaseModel):
    text: str
    confidence: float = Field(ge=0.0, le=1.0)


class LanguageInfo(BaseModel):
    locale: str  # ta-SG, zh-SG, ms-SG
    pack_version: str = "1.0.0"


class LearningPlan(BaseModel):
    speaking_goal: str
    target_words: list[str] = Field(min_length=3, max_length=5)
    target_phrase: str
    level: ConfidenceLevel
    expected_intents: list[str] = []


class SceneInteraction(BaseModel):
    type: InteractionType
    options: list[str] = []
    expected_intent: str = ""


class StoryScene(BaseModel):
    index: int
    narration: str = ""
    narration_target_lang: str = ""
    visual_id: str = ""
    interaction: SceneInteraction = SceneInteraction(type=InteractionType.CHOICE)


class RoomMission(BaseModel):
    instruction: str = ""
    instruction_target_lang: str = ""
    safety_validated: bool = False


class FamilyHandoff(BaseModel):
    mode: FamilyVoiceMode = FamilyVoiceMode.CONFIDENT
    prompt: str = ""
    prompt_target_lang: str = ""
    response_suggestion: str = ""
    parent_support: Optional[dict] = None


class EndingPrompt(BaseModel):
    text: str = ""


class Story(BaseModel):
    title: str = ""
    title_target_lang: str = ""
    opening_choices: list[str] = Field(default_factory=list, max_length=3)
    scenes: list[StoryScene] = Field(default_factory=list)
    room_mission: RoomMission = RoomMission()
    family_handoff: FamilyHandoff = FamilyHandoff()
    ending_prompt: EndingPrompt = EndingPrompt()


class NarrationSegment(BaseModel):
    scene_index: int
    tts_provider: str = ""
    audio_url: str = ""
    text: str = ""
    text_target_lang: str = ""


class SceneAsset(BaseModel):
    visual_id: str = ""
    asset_url: str = ""


class Media(BaseModel):
    narration_segments: list[NarrationSegment] = []
    scene_assets: list[SceneAsset] = []


class FamilyVoiceConfig(BaseModel):
    mode: FamilyVoiceMode = FamilyVoiceMode.CONFIDENT
    speaker_label: str = ""
    is_remote: bool = False


class Validation(BaseModel):
    language: ValidationStatus = ValidationStatus.PENDING
    safety: ValidationStatus = ValidationStatus.PENDING
    parent_approved_at: Optional[datetime] = None


class Provenance(BaseModel):
    agent_spec_versions: dict[str, str] = {}
    model_versions: dict[str, str] = {}


# ── The Story Package ─────────────────────────────────────────────────────

class StoryPackage(BaseModel):
    """The central shared contract — specs/story-package.md."""
    id: str
    status: StoryStatus = StoryStatus.CAPTURED
    child_profile_id: str = ""
    moment_id: str = ""
    language: LanguageInfo = LanguageInfo(locale="ta-SG")

    moment_facts: list[MomentFact] = []
    learning_plan: Optional[LearningPlan] = None
    story: Story = Story()
    media: Media = Media()
    family_voice: FamilyVoiceConfig = FamilyVoiceConfig()
    validation: Validation = Validation()
    provenance: Provenance = Provenance()

    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)


# ── Child Profile ──────────────────────────────────────────────────────────

class ChildProfile(BaseModel):
    id: str
    adult_id: str
    alias: str
    age_band: str  # "4-5", "6-7", "7-8"
    target_locale: str = "ta-SG"
    understanding_level: ConfidenceLevel = ConfidenceLevel.EMERGING
    speaking_level: ConfidenceLevel = ConfidenceLevel.EMERGING
    interests: list[str] = []
    created_at: datetime = Field(default_factory=datetime.utcnow)
    deleted_at: Optional[datetime] = None


# ── Family Speaker ─────────────────────────────────────────────────────────

class FamilySpeaker(BaseModel):
    id: str
    child_profile_id: str
    relationship_label: str = ""  # "Amma", "Appa", "Thatha" — not "grandparent"
    mode: FamilyVoiceMode = FamilyVoiceMode.CONFIDENT
    language_confidence: str = ""
    is_remote: bool = False


# ── Moment ─────────────────────────────────────────────────────────────────

class Moment(BaseModel):
    id: str
    child_profile_id: str
    input_type: InputType
    parent_text: str = ""
    transcript: str = ""
    source_media_url: str = ""
    source_media_retention: str = "discard_after_generation"
    structured_facts: list[MomentFact] = []
    status: str = "captured"
    created_at: datetime = Field(default_factory=datetime.utcnow)


# ── Story Session ──────────────────────────────────────────────────────────

class StorySession(BaseModel):
    id: str
    story_package_id: str
    started_at: datetime = Field(default_factory=datetime.utcnow)
    completed_at: Optional[datetime] = None
    last_scene: int = 0
    speech_turn_completed: bool = False
    mission_completed: bool = False
    handoff_completed: bool = False
    duration_seconds: int = 0
    fallback_events: int = 0


# ── Analytics Events ───────────────────────────────────────────────────────

class AnalyticsEvent(BaseModel):
    event_type: str
    child_profile_id: str = ""
    story_package_id: str = ""
    session_id: str = ""
    metadata: dict = {}
    created_at: datetime = Field(default_factory=datetime.utcnow)
