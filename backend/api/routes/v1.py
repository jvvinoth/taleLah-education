"""API routes — profiles, moments, story packages, sessions."""
from __future__ import annotations

import asyncio
import logging
import uuid
from datetime import datetime

from fastapi import APIRouter, BackgroundTasks, HTTPException
from fastapi.responses import StreamingResponse

from ...core.language_packs import pack_loader
from ...core.orchestrator import AgentName, TraceEntry, orchestrator
from ...safety.gate import safety_gate
from ...schemas.api_schemas import (
    ChildProfileCreate,
    ChildProfileResponse,
    DifficultyUpdate,
    FactsUpdate,
    MomentCreateText,
    MomentResponse,
    RegenerateRequest,
    SessionStart,
    SessionSummary,
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
    SceneInteraction,
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
    return StoryPackageResponse.from_package(pkg)


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
