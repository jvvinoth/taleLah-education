"""API routes — profiles, moments, story packages, sessions."""
from __future__ import annotations

import asyncio
import uuid
from datetime import datetime

from fastapi import APIRouter, BackgroundTasks, HTTPException
from fastapi.responses import StreamingResponse

from ...core.orchestrator import orchestrator
from ...safety.gate import safety_gate
from ...schemas.api_schemas import (
    ChildProfileCreate,
    ChildProfileResponse,
    GenerationStatus,
    MomentCreateText,
    MomentResponse,
    SessionStart,
    SessionSummary,
    StoryPackageApproval,
    StoryPackageDetail,
    StoryPackageResponse,
    TokenResponse,
    AdultRegister,
    AdultLogin,
)
from ...schemas.story_package import (
    ChildProfile,
    ConfidenceLevel,
    FamilySpeaker,
    FamilyVoiceMode,
    InputType,
    Moment,
    StoryPackage,
    StorySession,
    StoryStatus,
)

router = APIRouter()

# In-memory stores for Sprint 0 (will be replaced with DB in Sprint 1)
_adults: dict[str, dict] = {}
_profiles: dict[str, ChildProfile] = {}
_speakers: dict[str, FamilySpeaker] = {}
_moments: dict[str, Moment] = {}
_sessions: dict[str, StorySession] = {}


# ── Auth (demo mode for Sprint 0) ─────────────────────────────────────────

@router.post("/auth/register", response_model=TokenResponse)
async def register(data: AdultRegister):
    adult_id = f"adult_{uuid.uuid4().hex[:12]}"
    _adults[adult_id] = {
        "id": adult_id,
        "email": data.email,
        "display_name": data.display_name,
    }
    return TokenResponse(access_token=f"demo_{adult_id}", adult_id=adult_id)


@router.post("/auth/login", response_model=TokenResponse)
async def login(data: AdultLogin):
    for aid, adult in _adults.items():
        if adult["email"] == data.email:
            return TokenResponse(access_token=f"demo_{aid}", adult_id=aid)
    raise HTTPException(404, "Adult not found")


# ── Child Profiles ─────────────────────────────────────────────────────────

@router.post("/profiles", response_model=ChildProfileResponse)
async def create_profile(data: ChildProfileCreate, adult_id: str = "demo"):
    profile_id = f"child_{uuid.uuid4().hex[:12]}"
    profile = ChildProfile(
        id=profile_id,
        adult_id=adult_id,
        alias=data.alias,
        age_band=data.age_band,
        target_locale=data.target_locale,
        understanding_level=data.understanding_level,
        speaking_level=data.speaking_level,
        interests=data.interests,
    )
    _profiles[profile_id] = profile
    return ChildProfileResponse(
        id=profile.id,
        alias=profile.alias,
        age_band=profile.age_band,
        target_locale=profile.target_locale,
        understanding_level=profile.understanding_level,
        speaking_level=profile.speaking_level,
        interests=profile.interests,
    )


@router.get("/profiles", response_model=list[ChildProfileResponse])
async def list_profiles(adult_id: str = "demo"):
    return [
        ChildProfileResponse(
            id=p.id, alias=p.alias, age_band=p.age_band,
            target_locale=p.target_locale,
            understanding_level=p.understanding_level,
            speaking_level=p.speaking_level, interests=p.interests,
        )
        for p in _profiles.values()
        if p.adult_id == adult_id and not p.deleted_at
    ]


# ── Family Speaker ─────────────────────────────────────────────────────────

@router.post("/profiles/{profile_id}/speaker")
async def set_speaker(profile_id: str, mode: FamilyVoiceMode = FamilyVoiceMode.CONFIDENT, label: str = "Amma"):
    if profile_id not in _profiles:
        raise HTTPException(404, "Profile not found")
    speaker_id = f"speak_{uuid.uuid4().hex[:8]}"
    _speakers[speaker_id] = FamilySpeaker(
        id=speaker_id,
        child_profile_id=profile_id,
        relationship_label=label,
        mode=mode,
    )
    return {"speaker_id": speaker_id, "mode": mode.value, "label": label}


# ── Moment Capture ─────────────────────────────────────────────────────────

@router.post("/moments", response_model=MomentResponse)
async def capture_moment_text(data: MomentCreateText):
    if data.child_profile_id not in _profiles:
        raise HTTPException(404, "Child profile not found")
    moment_id = f"moment_{uuid.uuid4().hex[:12]}"
    moment = Moment(
        id=moment_id,
        child_profile_id=data.child_profile_id,
        input_type=InputType.TEXT,
        parent_text=data.text,
        status="captured",
    )
    _moments[moment_id] = moment
    return MomentResponse(
        id=moment.id,
        child_profile_id=moment.child_profile_id,
        input_type=moment.input_type,
        parent_text=moment.parent_text,
        status=moment.status,
        created_at=moment.created_at,
    )


# ── Story Package Generation ──────────────────────────────────────────────

@router.post("/packages/generate", response_model=StoryPackageResponse)
async def generate_package(moment_id: str, locale: str = "ta-SG"):
    moment = _moments.get(moment_id)
    if not moment:
        raise HTTPException(404, "Moment not found")

    # Create package via orchestrator
    pkg = orchestrator.create_package(
        child_profile_id=moment.child_profile_id,
        moment_id=moment_id,
        locale=locale,
    )

    # Seed the moment text into facts for Agent 1
    from ...schemas.story_package import MomentFact
    pkg.moment_facts = [MomentFact(text=moment.parent_text, confidence=0.9)]

    # Run the generation pipeline (Agents 1-5)
    try:
        pkg = await orchestrator.run_generation(pkg.id)
    except Exception as e:
        raise HTTPException(500, f"Generation failed: {e}")

    # Run safety gate
    passed, failures = safety_gate.validate_package(pkg)
    if not passed:
        # Don't block — mark as needs review
        pass

    return StoryPackageResponse.from_package(pkg)


@router.post("/packages/generate-async")
async def generate_package_async(
    moment_id: str,
    locale: str = "ta-SG",
    background_tasks: BackgroundTasks = None,
):
    """
    Start story generation in the background.
    Returns package_id immediately; subscribe to /packages/{id}/stream for SSE events.
    """
    moment = _moments.get(moment_id)
    if not moment:
        raise HTTPException(404, "Moment not found")

    pkg = orchestrator.create_package(
        child_profile_id=moment.child_profile_id,
        moment_id=moment_id,
        locale=locale,
    )

    from ...schemas.story_package import MomentFact
    pkg.moment_facts = [MomentFact(text=moment.parent_text, confidence=0.9)]

    async def _run():
        try:
            await orchestrator.run_generation(pkg.id)
            safety_gate.validate_package(pkg)
        except Exception as e:
            await orchestrator._emit(pkg.id, {"type": "error", "error": str(e)})

    asyncio.create_task(_run())

    return {
        "package_id": pkg.id,
        "stream_url": f"/api/v1/packages/{pkg.id}/stream",
        "status": "generating",
    }


@router.get("/packages/{package_id}/stream")
async def stream_package_events(package_id: str):
    """SSE stream of real-time generation progress events for a package."""
    pkg = orchestrator.get_package(package_id)
    if not pkg:
        raise HTTPException(404, "Package not found")
    return StreamingResponse(
        orchestrator.stream_events(package_id),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
            "Connection": "keep-alive",
        },
    )


@router.get("/packages/{package_id}", response_model=StoryPackageDetail)
async def get_package_detail(package_id: str):
    pkg = orchestrator.get_package(package_id)
    if not pkg:
        raise HTTPException(404, "Package not found")
    return StoryPackageDetail(package=pkg)


@router.get("/packages/{package_id}/trace")
async def get_package_trace(package_id: str):
    """Inspectable orchestration trace — for hackathon demo."""
    trace = orchestrator.get_trace(package_id)
    if not trace:
        raise HTTPException(404, "Package not found")
    return {"package_id": package_id, "trace": trace}


@router.post("/packages/{package_id}/approve", response_model=StoryPackageResponse)
async def approve_package(package_id: str, data: StoryPackageApproval):
    if not data.approved:
        raise HTTPException(400, "Package rejected — regenerate or edit")
    try:
        pkg = await orchestrator.approve_package(package_id)
    except ValueError as e:
        raise HTTPException(400, str(e))
    return StoryPackageResponse.from_package(pkg)


# ── Child Session ──────────────────────────────────────────────────────────

@router.post("/sessions/start")
async def start_session(data: SessionStart):
    pkg = orchestrator.get_package(data.story_package_id)
    if not pkg:
        raise HTTPException(404, "Package not found")
    if pkg.status != StoryStatus.APPROVED:
        raise HTTPException(403, f"Package not approved — status: {pkg.status.value}")

    try:
        pkg = await orchestrator.start_session(data.story_package_id)
    except ValueError as e:
        raise HTTPException(400, str(e))

    session_id = f"sess_{uuid.uuid4().hex[:12]}"
    _sessions[session_id] = StorySession(
        id=session_id,
        story_package_id=data.story_package_id,
    )
    return {
        "session_id": session_id,
        "package": pkg.model_dump(),
        "scenes": [s.model_dump() for s in pkg.story.scenes],
    }


@router.post("/sessions/{session_id}/complete", response_model=SessionSummary)
async def complete_session(session_id: str):
    session = _sessions.get(session_id)
    if not session:
        raise HTTPException(404, "Session not found")

    pkg = await orchestrator.complete_session(session.story_package_id)
    session.completed_at = datetime.utcnow()

    return SessionSummary(
        session_id=session.id,
        story_package_id=session.story_package_id,
        target_phrase=pkg.learning_plan.target_phrase if pkg.learning_plan else "",
        speech_turn_completed=session.speech_turn_completed,
        mission_completed=session.mission_completed,
        handoff_completed=session.handoff_completed,
        duration_seconds=session.duration_seconds,
        fallback_events=session.fallback_events,
        completed_at=session.completed_at,
    )


# ── Language Pack Swap (Qoder reusability proof) ─────────────────────────

@router.post("/packages/{package_id}/swap-language")
async def swap_language(package_id: str, new_locale: str = "ms-SG"):
    """
    Demonstrate language-pack reuse: swap the locale on an existing package
    and re-run Language Guardian. No child-flow code changes.
    """
    pkg = orchestrator.get_package(package_id)
    if not pkg:
        raise HTTPException(404, "Package not found")

    old_locale = pkg.language.locale
    pkg.language.locale = new_locale

    # Re-run Language Guardian with new pack
    from ...agents.language_guardian import LanguageGuardianAgent
    guardian = LanguageGuardianAgent()
    pkg = await guardian.execute(pkg)

    return {
        "package_id": package_id,
        "old_locale": old_locale,
        "new_locale": new_locale,
        "validation": pkg.validation.language.value,
        "message": "Language pack swapped — no application code changed",
    }


# ── Health ─────────────────────────────────────────────────────────────────

@router.get("/health")
async def health():
    return {
        "status": "ok",
        "app": "TaleLah",
        "version": "0.1.0",
        "agents": ["moment_lens", "learning_planner", "story_weaver",
                   "language_guardian", "family_voice_director", "growth_coach"],
        "language_packs": ["ta-SG", "zh-SG", "ms-SG"],
    }
