"""
Story Package Schema — The shared contract (specs/story-package.md).

Every agent reads and writes these structured objects.
Free-form agent prose must never pass directly into child mode.
"""
from __future__ import annotations

from datetime import datetime
from enum import Enum
from typing import Optional

from pydantic import BaseModel, Field, field_validator


# ── Lifecycle ──────────────────────────────────────────────────────────────

class StoryStatus(str, Enum):
    CAPTURED = "captured"
    INTERPRETING = "interpreting"
    NEEDS_CLARIFICATION = "needs_clarification"  # F3 — paused for one parent answer
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


class Clarification(BaseModel):
    """F3 — one follow-up question when the moment is too vague."""
    needed: bool = False
    question: str = ""
    answer: str = ""


class LanguageInfo(BaseModel):
    locale: str  # ta-SG, zh-SG, ms-SG
    pack_version: str = "1.0.0"


class LearningPlan(BaseModel):
    speaking_goal: str
    target_words: list[str] = Field(min_length=3, max_length=5)
    target_phrase: str
    level: ConfidenceLevel
    expected_intents: list[str] = []


# Child mode must never present more than 3 tappable choices at once
# (specs/story-package.md · bounded interactions).
MAX_CHOICES = 3


class SceneInteraction(BaseModel):
    type: InteractionType
    options: list[str] = []
    expected_intent: str = ""

    @field_validator("options")
    @classmethod
    def _cap_options(cls, v: list[str]) -> list[str]:
        # Hard cap — protects the child UI even if an agent/LLM over-produces.
        return v[:MAX_CHOICES]


class StoryScene(BaseModel):
    index: int
    # A chapter name the way a storybook has one — "The Slipper in the Bushes",
    # not "Scene 2". Shown above the page in child mode.
    title: str = ""
    title_target_lang: str = ""
    # One picture for this beat of the story, chosen by the writer so it
    # matches what actually happens here.
    emoji: str = ""
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


class VocabWord(BaseModel):
    """One "word to learn" from the story — spoken by Mina, repeated by the
    child. Native script is what the child sees; romanised helps the parent."""
    word: str  # English
    word_target_lang: str = ""
    romanised: str = ""


class Story(BaseModel):
    title: str = ""
    title_target_lang: str = ""
    opening_choices: list[str] = Field(default_factory=list, max_length=MAX_CHOICES)
    scenes: list[StoryScene] = Field(default_factory=list)
    room_mission: RoomMission = RoomMission()
    family_handoff: FamilyHandoff = FamilyHandoff()
    ending_prompt: EndingPrompt = EndingPrompt()
    # Words to learn — the learning plan's target words in the home language
    vocabulary: list[VocabWord] = Field(default_factory=list)
    # The sing-song line that comes back scene after scene, word for word, so
    # the child can chant it along with Mina — what makes four scenes feel
    # like one story instead of four sentences.
    refrain: str = ""
    refrain_target_lang: str = ""
    # The one hero, named once. Translated a single time and then spelled that
    # same way in every scene — a child who hears three names hears three
    # different stories.
    hero_name: str = ""
    hero_name_target_lang: str = ""


class NarrationSegment(BaseModel):
    scene_index: int
    tts_provider: str = ""
    audio_url: str = ""
    text: str = ""
    text_target_lang: str = ""


class SceneAsset(BaseModel):
    visual_id: str = ""
    asset_url: str = ""


class MediaAsset(BaseModel):
    """F4 — one pre-generated audio asset in the media manifest.
    url is relative to the API prefix (e.g. media/{pkg}/{id}.wav);
    empty url == parent-read fallback (text + romanization)."""
    id: str
    kind: str  # scene | mission | handoff | feedback | vocab
    scene_index: int = -1
    url: str = ""
    duration_ms: int = 0
    tts_provider: str = "text_only"
    text: str = ""
    text_target_lang: str = ""


class Media(BaseModel):
    narration_segments: list[NarrationSegment] = []
    scene_assets: list[SceneAsset] = []
    # F4 — TTS pre-generation on approval
    manifest: list[MediaAsset] = []
    manifest_ready: bool = False


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


class SessionOutcome(BaseModel):
    """Growth Coach output persisted on session completion (F11).
    Non-judgmental: no scores, no proficiency labels — just a forward-looking
    seed for the next moment plus an encouraging note for the parent."""
    completed_at: Optional[datetime] = None
    next_moment_suggestion: str = ""
    encouragement: str = ""
    coach_source: str = ""  # qwen-max | fallback


# ── The Story Package ─────────────────────────────────────────────────────

class StoryPackage(BaseModel):
    """The central shared contract — specs/story-package.md."""
    id: str
    status: StoryStatus = StoryStatus.CAPTURED
    child_profile_id: str = ""
    moment_id: str = ""
    language: LanguageInfo = LanguageInfo(locale="ta-SG")

    # Raw parent description of the moment (input to Moment Lens)
    moment_text: str = ""
    moment_facts: list[MomentFact] = []
    # F3 — needs_clarification pause state
    clarification: Clarification = Clarification()
    learning_plan: Optional[LearningPlan] = None
    story: Story = Story()
    media: Media = Media()
    family_voice: FamilyVoiceConfig = FamilyVoiceConfig()
    validation: Validation = Validation()
    provenance: Provenance = Provenance()
    # F11 — Growth Coach session record + next-moment seed
    session_outcome: Optional[SessionOutcome] = None

    # Parent review & edit (F2): single-component regenerations, hard cap 5
    regeneration_count: int = 0

    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)


# ── Child Profile ──────────────────────────────────────────────────────────

class ChildProfile(BaseModel):
    id: str
    adult_id: str
    alias: str
    age_band: str  # "4-5", "6-7", "7-8"
    target_locale: str = "ta-SG"
    home_language: str = "en"  # language spoken at home (en/ta/zh/ms)
    photo_url: Optional[str] = None  # API path served by the backend
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


# ── Saved Memory (F10) ───────────────────────────────────────────────────────

class SavedMemory(BaseModel):
    """A family memory saved with explicit consent (F10, AC-07).
    Deleting it removes this row AND the package's media files."""
    id: str
    session_id: str
    story_package_id: str
    child_profile_id: str = ""
    title: str = ""
    target_phrase: str = ""
    note: str = ""
    created_at: datetime = Field(default_factory=datetime.utcnow)


# ── Analytics Events ───────────────────────────────────────────────────────

class AnalyticsEvent(BaseModel):
    event_type: str
    child_profile_id: str = ""
    story_package_id: str = ""
    session_id: str = ""
    metadata: dict = {}
    created_at: datetime = Field(default_factory=datetime.utcnow)
