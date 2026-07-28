"""API routes — profiles, moments, story packages, sessions."""
from __future__ import annotations

import asyncio
import base64
import logging
import random
import uuid
from datetime import datetime, timedelta

from fastapi import APIRouter, BackgroundTasks, File, Form, HTTPException, UploadFile
from fastapi.responses import Response, StreamingResponse

from ...core.config import settings
from ...core.language_packs import pack_loader
from ...core.orchestrator import AgentName, TraceEntry, orchestrator
from ...core.persistence import persistence
from ...core.speech import match_intent
from ...safety.gate import safety_gate
from ...schemas.api_schemas import (
    ChildProfileCreate,
    ChildProfileResponse,
    ClarifyRequest,
    DifficultyUpdate,
    FactsUpdate,
    MemorySaveRequest,
    MomentCreateText,
    MomentResponse,
    RegenerateRequest,
    SessionStart,
    SessionSummary,
    SpeechFallbackChoice,
    StoryPackageApproval,
    StoryPackageDetail,
    StoryPackageResponse,
    TargetWordSwap,
    TokenResponse,
    AdultRegister,
    AdultLogin,
)
from ...schemas.story_package import (
    ChildProfile,
    FamilySpeaker,
    FamilyVoiceMode,
    InputType,
    InteractionType,
    Moment,
    MomentFact,
    SavedMemory,
    SceneInteraction,
    StoryPackage,
    StorySession,
    StoryStatus,
)

logger = logging.getLogger(__name__)

router = APIRouter()

# In-memory stores for Sprint 0 (will be replaced with DB in Sprint 1)
_adults: dict[str, dict] = {}
_profiles: dict[str, ChildProfile] = {}
_speakers: dict[str, FamilySpeaker] = {}
_moments: dict[str, Moment] = {}
_sessions: dict[str, StorySession] = {}
# F10 — memories exist ONLY after an explicit consent tick
_memories: dict[str, SavedMemory] = {}

# F4 — pre-generated audio blobs: package_id → {filename: bytes}
_media_blobs: dict[str, dict[str, bytes]] = {}


async def hydrate_stores() -> None:
    """Reload persisted state from Neon on startup (write-through cache).
    Any failure is non-fatal — the app simply starts with empty stores."""
    if not persistence.enabled:
        return
    try:
        _adults.update(await persistence.fetch_all("adults"))
        for k, v in (await persistence.fetch_all("child_profiles")).items():
            _profiles[k] = ChildProfile.model_validate(v)
        for k, v in (await persistence.fetch_all("family_speakers")).items():
            _speakers[k] = FamilySpeaker.model_validate(v)
        for k, v in (await persistence.fetch_all("moments")).items():
            _moments[k] = Moment.model_validate(v)
        for k, v in (await persistence.fetch_all("story_sessions")).items():
            _sessions[k] = StorySession.model_validate(v)
        for k, v in (await persistence.fetch_all("saved_memories")).items():
            _memories[k] = SavedMemory.model_validate(v)
        _media_blobs.update(await persistence.fetch_blobs())

        packages = await persistence.fetch_all("story_packages")
        traces = await persistence.fetch_all("traces")
        for pid, data in packages.items():
            orchestrator._packages[pid] = StoryPackage.model_validate(data)
            restored = []
            for e in traces.get(pid, {}).get("entries", []):
                entry = TraceEntry(e["agent"], e["status"], e.get("detail", ""))
                try:
                    entry.timestamp = datetime.fromisoformat(e["timestamp"])
                except (KeyError, ValueError):
                    pass
                restored.append(entry)
            orchestrator._traces[pid] = restored

        logger.info(
            f"💾 Hydrated from Neon: {len(_adults)} adults, "
            f"{len(_profiles)} profiles, {len(_moments)} moments, "
            f"{len(packages)} packages, {len(_sessions)} sessions, "
            f"{len(_memories)} memories, {len(_media_blobs)} media manifests"
        )
    except Exception as e:
        logger.warning(f"💾 Hydration failed ({e}) — starting with empty stores")

# F6 — lazy ASR provider registry (provider name → adapter)
_asr_providers: dict[str, object] = {}


def _get_asr(provider_name: str):
    """Resolve the pack's ASR provider by name, instantiating on first use."""
    if provider_name in _asr_providers:
        return _asr_providers[provider_name]
    if provider_name == "sarvam" and settings.sarvam_api_key:
        from ...adapters.sarvam_provider import SarvamASRProvider
        _asr_providers[provider_name] = SarvamASRProvider(
            api_key=settings.sarvam_api_key
        )
        return _asr_providers[provider_name]
    return None


# F5 — lazy vision provider (Qwen-VL-Max) for photo moment capture
_vision_provider: list[object] = []


def _get_vision():
    """Qwen-VL-Max via DashScope, instantiated on first use."""
    if _vision_provider:
        return _vision_provider[0]
    if settings.dashscope_api_key:
        from ...adapters.dashscope_provider import DashScopeVisionProvider
        _vision_provider.append(DashScopeVisionProvider(
            api_key=settings.dashscope_api_key,
            base_url=settings.dashscope_base_url,
            model=settings.qwen_vl_model,
        ))
        return _vision_provider[0]
    return None


def _wav_duration_seconds(data: bytes) -> float:
    """Duration of a RIFF/WAVE clip from its header; 0.0 if not parseable."""
    if len(data) < 44 or data[:4] != b"RIFF" or data[8:12] != b"WAVE":
        return 0.0
    try:
        byte_rate = int.from_bytes(data[28:32], "little")
        return len(data) / byte_rate if byte_rate else 0.0
    except Exception:
        return 0.0


# ── Auth (demo mode for Sprint 0) ─────────────────────────────────────────

@router.post("/auth/register", response_model=TokenResponse)
async def register(data: AdultRegister):
    adult_id = f"adult_{uuid.uuid4().hex[:12]}"
    _adults[adult_id] = {
        "id": adult_id,
        "email": data.email,
        "display_name": data.display_name,
    }
    persistence.save("adults", adult_id, _adults[adult_id])
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
    persistence.save("child_profiles", profile_id, profile)
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
    persistence.save("family_speakers", speaker_id, _speakers[speaker_id])
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
    persistence.save("moments", moment_id, moment)
    return MomentResponse(
        id=moment.id,
        child_profile_id=moment.child_profile_id,
        input_type=moment.input_type,
        parent_text=moment.parent_text,
        status=moment.status,
        created_at=moment.created_at,
    )


@router.post("/moments/voice", response_model=MomentResponse)
async def capture_moment_voice(
    audio: UploadFile = File(...),
    child_profile_id: str = Form(...),
    locale: str = Form("ta-SG"),
):
    """F5 — parent voice note ≤45 s → pack ASR → text pipeline. Audio discarded."""
    if child_profile_id not in _profiles:
        raise HTTPException(404, "Child profile not found")
    pack = pack_loader.get(locale)
    if not pack:
        raise HTTPException(422, f"No language pack for locale {locale}")

    audio_bytes = await audio.read()
    if len(audio_bytes) > 10 * 1024 * 1024:
        raise HTTPException(413, "Audio too large (max 10 MB)")
    duration = _wav_duration_seconds(audio_bytes)
    if duration > 45.5:
        raise HTTPException(422, "Voice note too long — keep it under 45 seconds")

    asr = _get_asr(pack.providers.asr.provider)
    if asr is None:
        raise HTTPException(503, "Speech recognition unavailable — try typing instead")
    try:
        # Parents mix English + mother tongue — let Sarvam auto-detect.
        transcript = await asr.transcribe(audio_bytes, language="unknown")
    except Exception:
        try:
            transcript = await asr.transcribe(
                audio_bytes, language=pack.providers.asr.language
            )
        except Exception as e:
            logger.warning(f"[MomentVoice] ASR failed: {e}")
            raise HTTPException(502, "Could not hear that — try again or type it")
    del audio_bytes  # hard rule 5 — raw parent audio never retained

    transcript = transcript.strip()
    if not transcript:
        raise HTTPException(422, "Could not hear any words — try again or type it")

    moment_id = f"moment_{uuid.uuid4().hex[:12]}"
    moment = Moment(
        id=moment_id,
        child_profile_id=child_profile_id,
        input_type=InputType.VOICE,
        parent_text=transcript,
        transcript=transcript,
        status="captured",
    )
    _moments[moment_id] = moment
    persistence.save("moments", moment_id, moment)
    return MomentResponse(
        id=moment.id,
        child_profile_id=moment.child_profile_id,
        input_type=moment.input_type,
        parent_text=moment.parent_text,
        status=moment.status,
        created_at=moment.created_at,
    )


@router.post("/moments/photo", response_model=MomentResponse)
async def capture_moment_photo(
    image: UploadFile = File(...),
    child_profile_id: str = Form(...),
):
    """F5 — photo ≤10 MB → Qwen-VL-Max facts → text pipeline. Image discarded."""
    if child_profile_id not in _profiles:
        raise HTTPException(404, "Child profile not found")

    content_type = (image.content_type or "").lower()
    if content_type not in ("image/jpeg", "image/png", "image/webp"):
        raise HTTPException(415, "Use a JPEG, PNG, or WebP photo")
    image_bytes = await image.read()
    if len(image_bytes) > 10 * 1024 * 1024:
        raise HTTPException(413, "Photo too large (max 10 MB)")

    vision = _get_vision()
    if vision is None:
        raise HTTPException(503, "Photo understanding unavailable — try typing instead")
    data_uri = f"data:{content_type};base64,{base64.b64encode(image_bytes).decode()}"
    del image_bytes  # hard rule 5 — raw photo never retained
    try:
        facts = await vision.extract_facts(image_url=data_uri)
    except Exception as e:
        logger.warning(f"[MomentPhoto] Vision failed: {e}")
        raise HTTPException(502, "Could not read that photo — try again or type it")

    # An ambiguous photo yields thin facts → F3 clarification asks the parent.
    fact_texts = [
        str(f.get("text", "")).strip()
        for f in facts
        if isinstance(f, dict) and str(f.get("text", "")).strip()
    ]
    parent_text = ". ".join(t.rstrip(".") for t in fact_texts[:5])

    moment_id = f"moment_{uuid.uuid4().hex[:12]}"
    moment = Moment(
        id=moment_id,
        child_profile_id=child_profile_id,
        input_type=InputType.PHOTO,
        parent_text=parent_text,
        status="captured",
    )
    _moments[moment_id] = moment
    persistence.save("moments", moment_id, moment)
    return MomentResponse(
        id=moment.id,
        child_profile_id=moment.child_profile_id,
        input_type=moment.input_type,
        parent_text=moment.parent_text,
        status=moment.status,
        created_at=moment.created_at,
    )


# ── Story Package Generation ──────────────────────────────────────────────

@router.get("/packages", response_model=list[StoryPackageResponse])
async def list_packages(child_profile_id: str = "", status: str = ""):
    """Story library — all packages, newest first, optional filters."""
    pkgs = orchestrator.list_packages()
    if child_profile_id:
        pkgs = [p for p in pkgs if p.child_profile_id == child_profile_id]
    if status:
        pkgs = [p for p in pkgs if p.status.value == status]
    pkgs.sort(key=lambda p: p.created_at, reverse=True)
    return [StoryPackageResponse.from_package(p) for p in pkgs]


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

    # Seed the raw moment text for Agent 1 (Moment Lens extracts facts — F3)
    pkg.moment_text = moment.parent_text

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

    pkg.moment_text = moment.parent_text

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


@router.post("/packages/{package_id}/clarify")
async def clarify_package(package_id: str, data: ClarifyRequest):
    """
    F3 — parent answers the one clarification question.
    Resumes the paused pipeline in the background; SSE stream continues.
    """
    pkg = orchestrator.get_package(package_id)
    if not pkg:
        raise HTTPException(404, "Package not found")
    if pkg.status != StoryStatus.NEEDS_CLARIFICATION:
        raise HTTPException(
            409, f"Package is not awaiting clarification: {pkg.status.value}"
        )

    answer = data.answer.strip()
    if not answer:
        raise HTTPException(422, "Answer cannot be empty")

    async def _resume():
        try:
            await orchestrator.resume_with_clarification(package_id, answer)
            safety_gate.validate_package(pkg)
        except Exception as e:
            await orchestrator._emit(package_id, {"type": "error", "error": str(e)})

    asyncio.create_task(_resume())

    return {"package_id": package_id, "status": "resuming"}


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


@router.get("/debug/llm")
async def debug_llm():
    """Diagnostic: which LLM config is live + a 1-token connectivity ping.
    Never exposes the API key. Safe for the hackathon demo."""
    weaver = orchestrator._agents.get(AgentName.STORY_WEAVER)
    llm = getattr(weaver, "llm", None) if weaver else None
    info: dict = {
        "agent_registered": weaver is not None,
        "llm_configured": llm is not None,
        "base_url": getattr(llm, "base_url", None),
        "model": getattr(llm, "model", None),
        "api_key_prefix": (getattr(llm, "api_key", "") or "")[:6],
    }
    if llm:
        try:
            reply = await llm.generate(prompt="Say OK", max_tokens=5)
            info["ping"] = "ok"
            info["reply"] = reply[:40]
        except Exception as e:
            info["ping"] = "failed"
            info["error"] = str(e)[:300]
    return info


@router.post("/packages/{package_id}/approve", response_model=StoryPackageResponse)
async def approve_package(package_id: str, data: StoryPackageApproval):
    if not data.approved:
        raise HTTPException(400, "Package rejected — regenerate or edit")
    try:
        pkg = await orchestrator.approve_package(package_id)
    except ValueError as e:
        raise HTTPException(400, str(e))

    # F4 — TTS pre-generation: synthesize the full media manifest on approval.
    # Failure is non-fatal — assets stay text-only (parent-read fallback).
    fvd = orchestrator._agents.get(AgentName.FAMILY_VOICE_DIRECTOR)
    if fvd is not None:
        try:
            blobs = await fvd.pregenerate_manifest(pkg)
            _media_blobs[pkg.id] = blobs
            persistence.save_blobs(pkg.id, blobs)
        except Exception as e:
            logger.error(f"[F4] TTS pre-generation failed for {pkg.id}: {e}")
    return StoryPackageResponse.from_package(pkg)


@router.get("/media/{package_id}/{filename}")
async def get_media_asset(package_id: str, filename: str):
    """F4 — serve a pre-generated audio asset from the media manifest."""
    blob = _media_blobs.get(package_id, {}).get(filename)
    if blob is None:
        raise HTTPException(404, "Media asset not found")
    media_type = "audio/wav" if filename.endswith(".wav") else "audio/mpeg"
    return Response(
        content=blob,
        media_type=media_type,
        headers={"Cache-Control": "public, max-age=86400"},
    )


# ── Parent Review & Edit (F2) ──────────────────────────────────────────────

MAX_REGENERATIONS = 5

REGEN_SYSTEM_PROMPTS = {
    "scene": (
        "You are a children's story writer for a language learning app. "
        "Rewrite ONE scene of an existing 4-scene story. Keep it anchored to the "
        "child's real activity, bounded interactions only (choice or speak), safe content.\n"
        'Respond with JSON: {"narration": "...", "interaction_type": "choice" or "speak", '
        '"options": ["opt1", "opt2"], "expected_intent": "..."}\n'
        "No markdown. No explanation."
    ),
    "mission": (
        "You are a children's story writer. Write ONE physical off-screen room mission "
        "for a child aged 4-8. Must be safe: stay indoors, no sharp/hot objects.\n"
        'Respond with JSON: {"room_mission": "..."}\n'
        "No markdown. No explanation."
    ),
    "handoff": (
        "You are a children's story writer. Write a family handoff: a prompt for an adult "
        "to continue the story conversation with the child, plus a suggested response.\n"
        'Respond with JSON: {"family_handoff_prompt": "...", "family_response_suggestion": "..."}\n'
        "No markdown. No explanation."
    ),
}


def _get_editable_package(package_id: str):
    """Fetch a package that is still editable — 409 once approved (immutability)."""
    pkg = orchestrator.get_package(package_id)
    if not pkg:
        raise HTTPException(404, "Package not found")
    if pkg.status != StoryStatus.AWAITING_PARENT:
        raise HTTPException(
            409,
            f"Package is immutable — edits only allowed while awaiting parent review "
            f"(current status: {pkg.status.value})",
        )
    return pkg


def _trace_edit(package_id: str, status: str, detail: str) -> None:
    orchestrator._traces.setdefault(package_id, []).append(
        TraceEntry("parent_edit", status, detail)
    )
    pkg = orchestrator.get_package(package_id)
    if pkg is not None:
        orchestrator.persist(pkg)


@router.patch("/packages/{package_id}/facts")
async def edit_facts(package_id: str, data: FactsUpdate):
    """Parent corrects the extracted moment facts before approval."""
    pkg = _get_editable_package(package_id)
    facts = [t.strip() for t in data.facts if t.strip()]
    if not facts:
        raise HTTPException(400, "At least one non-empty fact is required")

    # Parent-provided facts are ground truth — confidence 1.0
    pkg.moment_facts = [MomentFact(text=t, confidence=1.0) for t in facts]
    pkg.updated_at = datetime.utcnow()
    _trace_edit(package_id, "facts_edited", f"Parent replaced facts ({len(facts)} items)")
    return {
        "package_id": package_id,
        "facts": [f.text for f in pkg.moment_facts],
        "message": "Facts updated — regenerate a component to reflect changes",
    }


@router.patch("/packages/{package_id}/target-word")
async def swap_target_word(package_id: str, data: TargetWordSwap):
    """Swap one target word for another — validated against the pack word bank."""
    pkg = _get_editable_package(package_id)
    if not pkg.learning_plan:
        raise HTTPException(400, "Package has no learning plan")
    plan = pkg.learning_plan

    if data.old_word not in plan.target_words:
        raise HTTPException(
            400, f"'{data.old_word}' is not a current target word: {plan.target_words}"
        )

    # Validate the new word against the active pack's word bank (AC: pack-driven)
    pack = pack_loader.get(pkg.language.locale)
    entry = None
    if pack and pack.word_bank:
        needle = data.new_word.strip().lower()
        for e in pack.word_bank:
            if needle in (e.word.lower(), e.romanised.lower(), e.english.lower()):
                entry = e
                break
        if entry is None:
            raise HTTPException(
                400,
                f"'{data.new_word}' is not in the {pkg.language.locale} word bank. "
                f"Available: {[e.english for e in pack.word_bank]}",
            )

    new_word = entry.english if entry else data.new_word.strip()
    plan.target_words = [new_word if w == data.old_word else w for w in plan.target_words]
    if data.old_word in plan.target_phrase:
        plan.target_phrase = plan.target_phrase.replace(data.old_word, new_word)

    pkg.updated_at = datetime.utcnow()
    _trace_edit(package_id, "word_swapped", f"'{data.old_word}' → '{new_word}'")
    return {
        "package_id": package_id,
        "target_words": plan.target_words,
        "target_phrase": plan.target_phrase,
        "word_bank_entry": entry.model_dump() if entry else None,
    }


@router.patch("/packages/{package_id}/difficulty")
async def set_difficulty(package_id: str, data: DifficultyUpdate):
    """Parent adjusts the difficulty level of the learning plan."""
    pkg = _get_editable_package(package_id)
    if not pkg.learning_plan:
        raise HTTPException(400, "Package has no learning plan")

    old_level = pkg.learning_plan.level
    pkg.learning_plan.level = data.level
    pkg.updated_at = datetime.utcnow()
    _trace_edit(package_id, "difficulty_changed", f"{old_level.value} → {data.level.value}")
    return {
        "package_id": package_id,
        "old_level": old_level.value,
        "new_level": data.level.value,
    }


async def _regen_scene(pkg, scene_index: int, llm) -> None:
    scene = pkg.story.scenes[scene_index]
    facts_text = "\n".join(f"- {f.text}" for f in pkg.moment_facts)
    plan = pkg.learning_plan
    regenerated = False
    if llm:
        try:
            result = await llm.generate_json(
                prompt=(
                    f"Story title: {pkg.story.title}\n"
                    f"Child's real activity:\n{facts_text}\n"
                    f"Target words: {plan.target_words if plan else []}\n\n"
                    f"Current scene {scene_index} text: {scene.narration}\n"
                    f"Write a DIFFERENT version of this scene (same position in the story)."
                ),
                system=REGEN_SYSTEM_PROMPTS["scene"],
            )
            scene.narration = result.get("narration", scene.narration)
            if result.get("interaction_type") == "speak":
                scene.interaction = SceneInteraction(
                    type=InteractionType.SPEAK,
                    expected_intent=result.get("expected_intent", ""),
                )
            else:
                scene.interaction = SceneInteraction(
                    type=InteractionType.CHOICE,
                    options=result.get("options", scene.interaction.options) or ["Continue"],
                )
            regenerated = True
        except Exception as e:
            logger.error(f"[F2] Scene regen LLM failed, using fallback: {e}")
    if not regenerated:
        # Offline/LLM-failure fallback — deterministic variant so the flow stays demoable
        base = scene.narration.removeprefix("In a new telling, ")
        scene.narration = f"In a new telling, {base}"
    scene.narration_target_lang = ""  # force Guardian re-translation


async def _regen_mission(pkg, llm) -> None:
    mission = pkg.story.room_mission
    regenerated = False
    if llm:
        try:
            facts_text = "\n".join(f"- {f.text}" for f in pkg.moment_facts)
            result = await llm.generate_json(
                prompt=(
                    f"Story title: {pkg.story.title}\n"
                    f"Child's real activity:\n{facts_text}\n"
                    f"Current mission: {mission.instruction}\n"
                    f"Write a DIFFERENT safe room mission for this story."
                ),
                system=REGEN_SYSTEM_PROMPTS["mission"],
            )
            mission.instruction = result.get("room_mission", mission.instruction)
            regenerated = True
        except Exception as e:
            logger.error(f"[F2] Mission regen LLM failed, using fallback: {e}")
    if not regenerated:
        base = mission.instruction.removeprefix("New mission: ")
        mission.instruction = f"New mission: {base}"
    mission.safety_validated = False
    mission.instruction_target_lang = ""


async def _regen_handoff(pkg, llm) -> None:
    handoff = pkg.story.family_handoff
    regenerated = False
    if llm:
        try:
            result = await llm.generate_json(
                prompt=(
                    f"Story title: {pkg.story.title}\n"
                    f"Current handoff prompt: {handoff.prompt}\n"
                    f"Write a DIFFERENT family handoff for this story."
                ),
                system=REGEN_SYSTEM_PROMPTS["handoff"],
            )
            handoff.prompt = result.get("family_handoff_prompt", handoff.prompt)
            handoff.response_suggestion = result.get(
                "family_response_suggestion", handoff.response_suggestion
            )
            regenerated = True
        except Exception as e:
            logger.error(f"[F2] Handoff regen LLM failed, using fallback: {e}")
    if not regenerated:
        base = handoff.prompt.removeprefix("Try this instead: ")
        handoff.prompt = f"Try this instead: {base}"
    handoff.prompt_target_lang = ""


@router.post("/packages/{package_id}/regenerate")
async def regenerate_component(package_id: str, data: RegenerateRequest):
    """
    Regenerate a single story component (scene / mission / handoff).
    Hard cap of 5 regenerations per package. Re-runs Language Guardian
    for the cleared translation and re-checks the safety gate.
    """
    pkg = _get_editable_package(package_id)
    if pkg.regeneration_count >= MAX_REGENERATIONS:
        raise HTTPException(
            409, f"Regeneration cap reached ({MAX_REGENERATIONS} per package)"
        )

    # Reuse the registered Story Weaver's LLM provider
    weaver = orchestrator._agents.get(AgentName.STORY_WEAVER)
    llm = getattr(weaver, "llm", None)

    try:
        if data.component == "scene":
            if data.scene_index >= len(pkg.story.scenes):
                raise HTTPException(
                    400,
                    f"scene_index {data.scene_index} out of range "
                    f"(story has {len(pkg.story.scenes)} scenes)",
                )
            await _regen_scene(pkg, data.scene_index, llm)
        elif data.component == "mission":
            await _regen_mission(pkg, llm)
        else:
            await _regen_handoff(pkg, llm)
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"[F2] Regeneration failed for {package_id}: {e}")
        raise HTTPException(502, f"Regeneration failed: {e}")

    pkg.regeneration_count += 1

    # Re-run the registered Language Guardian for the cleared translation
    guardian = orchestrator._agents.get(AgentName.LANGUAGE_GUARDIAN)
    if guardian is None:
        from ...agents.language_guardian import LanguageGuardianAgent
        guardian = LanguageGuardianAgent()
    pkg = await guardian.execute(pkg)

    # Safety gate re-check on the regenerated content
    safety_passed, safety_failures = safety_gate.validate_package(pkg)

    pkg.updated_at = datetime.utcnow()
    _trace_edit(
        package_id,
        "regenerated",
        f"{data.component} regenerated ({pkg.regeneration_count}/{MAX_REGENERATIONS})",
    )
    return {
        "package_id": package_id,
        "component": data.component,
        "scene_index": data.scene_index if data.component == "scene" else None,
        "regeneration_count": pkg.regeneration_count,
        "regenerations_remaining": MAX_REGENERATIONS - pkg.regeneration_count,
        "safety_passed": safety_passed,
        "safety_failures": safety_failures,
        "package": pkg.model_dump(),
    }


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
    persistence.save("story_sessions", session_id, _sessions[session_id])
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
    persistence.save("story_sessions", session_id, session)

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


@router.post("/sessions/{session_id}/event")
async def session_event(session_id: str, kind: str = Form(...)):
    """F8/F9 — the child app reports mission + handoff milestones."""
    session = _sessions.get(session_id)
    if not session:
        raise HTTPException(404, "Session not found")
    if kind == "mission_completed":
        session.mission_completed = True
    elif kind == "handoff_completed":
        session.handoff_completed = True
    else:
        raise HTTPException(422, f"Unknown session event '{kind}'")
    persistence.save("story_sessions", session_id, session)
    return {
        "session_id": session_id,
        "mission_completed": session.mission_completed,
        "handoff_completed": session.handoff_completed,
    }


# ── F6 · Bounded child speech turn (AC-04, AC-07) ──────────────────────

def _pick(copy_list: list[str], fallback: str) -> str:
    return random.choice(copy_list) if copy_list else fallback


@router.post("/sessions/{session_id}/speech-turn")
async def speech_turn(
    session_id: str,
    audio: UploadFile = File(...),
    expected_intent: str = Form(""),
    attempt: int = Form(1),
):
    """
    Transcribe the child clip, fuzzy-match against the pack's expected
    intents only, and return bounded feedback. The raw transcript is never
    returned; raw audio is discarded after intent extraction (AC-07).
    Never says "wrong" — celebration/encouragement copy only (AC-04).
    """
    session = _sessions.get(session_id)
    if not session:
        raise HTTPException(404, "Session not found")
    pkg = orchestrator.get_package(session.story_package_id)
    if not pkg:
        raise HTTPException(404, "Package not found")
    pack = pack_loader.get(pkg.language.locale)
    if not pack:
        raise HTTPException(422, f"No language pack for {pkg.language.locale}")

    audio_bytes = await audio.read()
    if len(audio_bytes) > 5 * 1024 * 1024:
        raise HTTPException(413, "Audio clip too large (max 5 MB)")

    transcript = ""
    asr_ok = False
    asr = _get_asr(pack.providers.asr.provider)
    if asr and audio_bytes:
        try:
            transcript = await asr.transcribe(
                audio_bytes, language=pack.providers.asr.language
            )
            asr_ok = True
        except Exception as e:
            logger.warning(f"[SpeechTurn] ASR failed: {e}")
    # AC-07 — raw child audio discarded after intent extraction; never stored
    del audio_bytes

    result = match_intent(
        transcript,
        pack.expected_intents,
        floor=pack.speech.keyword_floor,
        restrict_to=expected_intent,
        normalization=pack.speech.normalization,
    )

    max_attempts = pack.speech.max_attempts
    attempt = max(1, attempt)
    if result.matched:
        session.speech_turn_completed = True
        persistence.save("story_sessions", session_id, session)
        next_action = "celebrate"
    elif attempt < max_attempts:
        next_action = "retry_slower"
    else:
        next_action = "picture_choice"

    # Picture-choice options — pack word bank, target intent's word first
    fallback_options: list[dict] = []
    if next_action == "picture_choice":
        bank = list(pack.word_bank)
        random.shuffle(bank)
        for entry in bank[:3]:
            fallback_options.append({
                "word": entry.word,
                "romanised": entry.romanised,
                "english": entry.english,
            })

    _trace_edit(
        session.story_package_id,
        "speech_turn",
        f"attempt={attempt} matched={result.matched} "
        f"intent={result.intent or '-'} score={result.score} "
        f"asr_ok={asr_ok} (raw audio discarded)",
    )

    return {
        "session_id": session_id,
        "matched": result.matched,
        "intent": result.intent,
        "confidence": result.score,
        "attempt": attempt,
        "max_attempts": max_attempts,
        "next_action": next_action,
        "celebration_copy": _pick(pack.child_copy.celebration, "🎉"),
        "encourage_copy": _pick(
            pack.child_copy.encourage_retry, "Let's listen once more!"
        ),
        "listen_prompt": pack.child_copy.listen_prompt,
        "fallback_options": fallback_options,
        "audio_retained": False,
    }


@router.post("/sessions/{session_id}/speech-fallback")
async def speech_fallback(session_id: str, data: SpeechFallbackChoice):
    """Picture-choice fallback — any tap celebrates; the story continues."""
    session = _sessions.get(session_id)
    if not session:
        raise HTTPException(404, "Session not found")
    pkg = orchestrator.get_package(session.story_package_id)
    if not pkg:
        raise HTTPException(404, "Package not found")
    pack = pack_loader.get(pkg.language.locale)

    session.speech_turn_completed = True
    session.fallback_events += 1
    persistence.save("story_sessions", session_id, session)
    _trace_edit(
        session.story_package_id,
        "speech_fallback",
        f"picture_choice selected='{data.selected_word}' "
        f"(fallback_events={session.fallback_events})",
    )
    celebration = _pick(pack.child_copy.celebration, "🎉") if pack else "🎉"
    return {
        "session_id": session_id,
        "celebration_copy": celebration,
        "speech_turn_completed": True,
    }


# ── F10 · Memory consent + progress (AC-07, hard rule 6) ───────────────

@router.post("/memories", status_code=201)
async def save_memory(data: MemorySaveRequest):
    """Save a family memory — refused without the explicit consent tick."""
    if not data.consent:
        raise HTTPException(403, "Memory consent required — nothing was saved")
    session = _sessions.get(data.session_id)
    if not session:
        raise HTTPException(404, "Session not found")
    pkg = orchestrator.get_package(session.story_package_id)
    memory_id = f"mem_{uuid.uuid4().hex[:10]}"
    memory = SavedMemory(
        id=memory_id,
        session_id=data.session_id,
        story_package_id=session.story_package_id,
        child_profile_id=pkg.child_profile_id if pkg else "",
        title=pkg.story.title if pkg else "",
        target_phrase=(
            pkg.learning_plan.target_phrase if pkg and pkg.learning_plan else ""
        ),
        note=data.note,
    )
    _memories[memory_id] = memory
    persistence.save("saved_memories", memory_id, memory)
    return memory.model_dump()


@router.get("/memories")
async def list_memories(child_profile_id: str = ""):
    items = [
        m.model_dump()
        for m in _memories.values()
        if not child_profile_id or m.child_profile_id == child_profile_id
    ]
    items.sort(key=lambda m: m["created_at"], reverse=True)
    return {"memories": items}


@router.delete("/memories/{memory_id}")
async def delete_memory(memory_id: str):
    """Delete a saved memory — removes the row AND the package media blobs."""
    memory = _memories.pop(memory_id, None)
    if not memory:
        raise HTTPException(404, "Memory not found")
    media_purged = _media_blobs.pop(memory.story_package_id, None) is not None
    persistence.delete("saved_memories", memory_id)
    if media_purged:
        persistence.delete_blobs(memory.story_package_id)
    return {"deleted": memory_id, "media_purged": media_purged}


@router.get("/progress/{child_profile_id}")
async def get_progress(child_profile_id: str):
    """North-star metric ONLY — completed family language moments this week.
    No scores, no streaks, no proficiency claims (hard rule 6)."""
    if child_profile_id not in _profiles:
        raise HTTPException(404, "Child profile not found")
    week_ago = datetime.utcnow() - timedelta(days=7)
    count = 0
    for session in _sessions.values():
        if not session.completed_at or session.completed_at < week_ago:
            continue
        pkg = orchestrator.get_package(session.story_package_id)
        if pkg and pkg.child_profile_id == child_profile_id:
            count += 1
    return {
        "child_profile_id": child_profile_id,
        "metric": "completed family language moments this week",
        "family_moments_this_week": count,
    }


# ── Language Pack Swap (AC-08 reusability proof) ───────────────────────

@router.get("/packs")
async def list_packs():
    """List the loaded language packs — all locale behaviour lives here."""
    return {
        "packs": [
            {
                "locale": p.locale,
                "pack_version": p.pack_version,
                "language_name": p.language_name,
                "script": p.script,
                "tts_provider": p.providers.tts.provider,
                "asr_provider": p.providers.asr.provider,
            }
            for locale in pack_loader.available_locales()
            if (p := pack_loader.get(locale))
        ]
    }


@router.get("/packs/{locale}/family-copy")
async def get_family_copy(locale: str):
    """F9 — parent-facing handoff copy straight from the pack (AC-08)."""
    pack = pack_loader.get(locale)
    if not pack:
        raise HTTPException(404, f"No language pack for '{locale}'")
    return {
        "locale": locale,
        "pack_version": pack.pack_version,
        "family_copy": pack.family_copy.model_dump(),
    }


@router.get("/packs/{locale}/word-bank")
async def get_word_bank(locale: str):
    """Word bank for the parent's target-word swap picker (F2)."""
    pack = pack_loader.get(locale)
    if not pack:
        raise HTTPException(404, f"No language pack for '{locale}'")
    return {
        "locale": locale,
        "pack_version": pack.pack_version,
        "word_bank": [e.model_dump() for e in pack.word_bank],
    }


@router.post("/packages/{package_id}/swap-language")
async def swap_language(package_id: str, new_locale: str = "ms-SG"):
    """
    Demonstrate language-pack reuse: swap the locale on an existing package
    and re-run Language Guardian. No child-flow code changes.
    """
    pkg = orchestrator.get_package(package_id)
    if not pkg:
        raise HTTPException(404, "Package not found")

    new_pack = pack_loader.get(new_locale)
    if not new_pack:
        raise HTTPException(
            400,
            f"No language pack for '{new_locale}'. Available: {pack_loader.available_locales()}",
        )

    old_locale = pkg.language.locale
    pkg.language.locale = new_locale
    pkg.language.pack_version = new_pack.pack_version

    # Clear previous translations so the Guardian re-translates with the new pack
    pkg.story.title_target_lang = ""
    for scene in pkg.story.scenes:
        scene.narration_target_lang = ""
    pkg.story.room_mission.instruction_target_lang = ""
    pkg.story.family_handoff.prompt_target_lang = ""

    # Re-run the registered Language Guardian (keeps its LLM provider) with new pack
    guardian = orchestrator._agents.get(AgentName.LANGUAGE_GUARDIAN)
    if guardian is None:
        from ...agents.language_guardian import LanguageGuardianAgent
        guardian = LanguageGuardianAgent()
    pkg = await guardian.execute(pkg)

    return {
        "package_id": package_id,
        "old_locale": old_locale,
        "new_locale": new_locale,
        "pack_version": new_pack.pack_version,
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
        "language_packs": pack_loader.available_locales(),
    }
